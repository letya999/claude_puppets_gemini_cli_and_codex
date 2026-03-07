#Requires -Version 5.1
<#
.SYNOPSIS
    Unified agent runner — routes --Model to the correct CLI automatically.
.DESCRIPTION
    PowerShell equivalent of orchestrate's run-agent.sh.
    "A run is model + role + prompt."

    Model routing (auto-detected from model name):
      claude-*  →  claude -p     (YOLO: --dangerously-skip-permissions)
      gemini-*  →  gemini        (no sandbox concept — always unrestricted)
      codex-*, gpt-* → codex exec (YOLO: --dangerously-bypass-approvals-and-sandbox)
      mods      →  mods pipe

    Run artifacts saved to: .orchestrate\runs\agent-runs\<run-id>\
    Run index appended to:  .orchestrate\index\runs.jsonl

.PARAMETER Model
    Model identifier. Routes to correct CLI:
      claude-sonnet-4-6, claude-opus-4-6, claude-haiku-4-5  → claude
      gemini-2.5-pro, gemini-2.0-flash                      → gemini
      codex, gpt-5.3-codex, gpt-4o, o3                      → codex
      mods                                                   → mods

.PARAMETER Prompt
    Task prompt text. Can also pipe via stdin.

.PARAMETER Role
    Role name from .claude/roles/<role>.md — loaded as system prompt prefix.

.PARAMETER Agent
    Claude agent profile from .claude/agents/<agent>.md (claude harness only).

.PARAMETER Session
    Session ID for grouping related runs.

.PARAMETER Yolo
    UNSAFE unrestricted mode:
      claude:  --dangerously-skip-permissions    (skips all tool confirmations)
      codex:   --dangerously-bypass-approvals-and-sandbox  (no sandbox)
      gemini:  no-op (already a text interface, no sandboxing)

.PARAMETER DryRun
    Show CLI command and composed prompt without executing.

.PARAMETER Detail
    Report detail level: brief | standard | detailed

.PARAMETER WorkDir
    Working directory for the subprocess. Default: current directory.

.PARAMETER Timeout
    Timeout in seconds. Default: 1800 (30 min).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$Model,
    [Parameter()]          [string]$Prompt = "",
    [Parameter()]          [string]$Role = "",
    [Parameter()]          [string]$Agent = "",
    [Parameter()]          [string]$Session = "",
    [Parameter()]          [hashtable]$Labels = @{},
    [Parameter()]          [switch]$Yolo,
    [Parameter()]          [switch]$DryRun,
    [Parameter()]          [string]$Detail = "standard",
    [Parameter()]          [string]$WorkDir = "",
    [Parameter()]          [int]$Timeout = 1800,
    [Parameter()]          [string]$Variant = "high",
    [Parameter()]          [string]$OutputDir = "",
    [Parameter()]          [string]$RolesDir = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir   = $PSScriptRoot
$projectRoot = Split-Path $scriptDir -Parent

if (-not $RolesDir) { $RolesDir = Join-Path $projectRoot ".claude\roles" }
if (-not $WorkDir)  { $WorkDir  = (Get-Location).Path }

# ════════════════════════════════════════════════════════════════
# MODEL ROUTING
# ════════════════════════════════════════════════════════════════

function Route-Model([string]$model) {
    $m = $model.ToLower()
    switch -Regex ($m) {
        '^claude-|^opus|^sonnet|^haiku' { return 'claude' }
        '^gemini'                        { return 'gemini' }
        '^codex|^gpt-|^o1|^o3|^o4'     { return 'codex'  }
        '^mods'                          { return 'mods'   }
        default { throw "Unknown model family: $model. Supported prefixes: claude-, gemini-, codex/gpt-/o*, mods" }
    }
}

$harness = Route-Model $Model
Write-Host "  [Run-Agent] Model: $Model  Harness: $harness  Yolo: $($Yolo.IsPresent)" -ForegroundColor DarkCyan

# ════════════════════════════════════════════════════════════════
# RUN ARTIFACTS SETUP
# ════════════════════════════════════════════════════════════════

$timestamp = Get-Date -Format 'yyyyMMddTHHmmssZ'
$pid_hex   = '{0:x4}' -f $PID
$runId     = "${timestamp}__${pid_hex}"
$sessionId = if ($Session) { $Session } else { $runId }

$orchestrateRoot = Join-Path $projectRoot ".orchestrate"
$runsDir         = Join-Path $orchestrateRoot "runs\agent-runs"
$indexDir        = Join-Path $orchestrateRoot "index"
$indexFile       = Join-Path $indexDir "runs.jsonl"
$logDir          = if ($OutputDir) { $OutputDir } else { Join-Path $runsDir $runId }

New-Item -ItemType Directory -Force -Path $logDir  | Out-Null
New-Item -ItemType Directory -Force -Path $indexDir | Out-Null

$inputFile  = Join-Path $logDir "input.md"
$outputFile = Join-Path $logDir "output.txt"
$reportFile = Join-Path $logDir "report.md"
$paramsFile = Join-Path $logDir "params.json"

# ════════════════════════════════════════════════════════════════
# LOAD ROLE SYSTEM PROMPT
# ════════════════════════════════════════════════════════════════

$rolePrompt = ""
if ($Role) {
    $rolePath = Join-Path $RolesDir "$Role.md"
    if (Test-Path $rolePath) {
        $rolePrompt = Get-Content $rolePath -Raw -Encoding UTF8
        Write-Host "  [Run-Agent] Role: $Role ($rolePath)" -ForegroundColor DarkGray
    } else {
        Write-Host "  [Run-Agent] WARN: Role '$Role' not found: $rolePath" -ForegroundColor Yellow
    }
}

# Read prompt from stdin if not provided
if (-not $Prompt -and -not [Console]::IsInputRedirected -eq $false) {
    try {
        $piped = [Console]::In.ReadToEnd()
        if ($piped.Trim()) { $Prompt = $piped }
    } catch { }
}

# ════════════════════════════════════════════════════════════════
# COMPOSE PROMPT
# ════════════════════════════════════════════════════════════════

$composed = ""
if ($rolePrompt) {
    $composed += $rolePrompt + "`n`n---`n`n"
}
$composed += $Prompt

# Append report instruction (like orchestrate's build_report_instruction)
$reportInstruction = switch ($Detail) {
    'brief'    { "Keep the report concise: what was done, pass/fail, any blockers." }
    'detailed' { "Be thorough: all decisions, all files touched, full verification results, recommendations." }
    default    { "Include: what was done, key decisions, files created/modified, any issues." }
}
$composed += @"

---
## REPORT INSTRUCTION
As your FINAL action, write a brief report of your work to: ``$reportFile``
$reportInstruction
Use plain markdown.
"@

# ════════════════════════════════════════════════════════════════
# BUILD CLI COMMAND
# ════════════════════════════════════════════════════════════════

function Get-ClaudeCmd {
    $args_list = @('claude', '-p', '-', '--model', $Model, '--output-format', 'stream-json', '--verbose')
    if ($Agent) {
        $args_list += @('--agent', $Agent)
    } elseif ($Yolo) {
        $args_list += '--dangerously-skip-permissions'
    }
    return $args_list
}

function Get-GeminiCmd {
    # Gemini CLI: no sandbox, no YOLO needed — it's a text interface
    # YOLO note: Gemini CLI has no tool execution, so no sandboxing applies
    $args_list = @('gemini', '--model', $Model)
    if ($Yolo) {
        Write-Host "  [Run-Agent] Gemini YOLO: Gemini CLI has no sandbox — already unrestricted" -ForegroundColor DarkGray
    }
    return $args_list
}

function Get-CodexCmd {
    # YOLO mode uses --dangerously-bypass-approvals-and-sandbox
    # This is UNSAFE: unrestricted filesystem + network + no confirmations
    $perm = if ($Yolo) {
        Write-Host "  [Run-Agent] Codex YOLO: --dangerously-bypass-approvals-and-sandbox (UNSAFE)" -ForegroundColor Red
        '--dangerously-bypass-approvals-and-sandbox'
    } else {
        '--sandbox workspace-write'
    }
    return @('codex', 'exec', '-m', $Model, '--json', '-') + ($perm -split ' ')
}

function Get-ModsCmd {
    return @('mods')
}

$cliArgs = switch ($harness) {
    'claude' { Get-ClaudeCmd }
    'gemini' { Get-GeminiCmd }
    'codex'  { Get-CodexCmd  }
    'mods'   { Get-ModsCmd   }
}

$cliDisplay = $cliArgs -join ' '

# ════════════════════════════════════════════════════════════════
# SAVE PARAMS
# ════════════════════════════════════════════════════════════════

$labelsJson = ($Labels.GetEnumerator() | ForEach-Object { '"' + $_.Key + '":"' + $_.Value + '"' }) -join ','
@"
{
  "run_id": "$runId",
  "session_id": "$sessionId",
  "model": "$Model",
  "harness": "$harness",
  "variant": "$Variant",
  "role": "$Role",
  "agent": "$Agent",
  "yolo": $($Yolo.IsPresent.ToString().ToLower()),
  "detail": "$Detail",
  "cwd": "$($WorkDir -replace '\\','\\')",
  "log_dir": "$($logDir -replace '\\','\\')",
  "cli": "$($cliDisplay -replace '"','\"')",
  "created_at_utc": "$(Get-Date -Format 'o')",
  "labels": {$labelsJson}
}
"@ | Out-File $paramsFile -Encoding UTF8

# ════════════════════════════════════════════════════════════════
# DRY RUN
# ════════════════════════════════════════════════════════════════

if ($DryRun) {
    Write-Host ""
    Write-Host "  ═══ DRY RUN ═══════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  Run ID:   $runId" -ForegroundColor White
    Write-Host "  Model:    $Model  ($harness)" -ForegroundColor White
    Write-Host "  Role:     $(if ($Role) { $Role } else { '(none)' })" -ForegroundColor White
    Write-Host "  Agent:    $(if ($Agent) { $Agent } else { '(none)' })" -ForegroundColor White
    Write-Host "  YOLO:     $($Yolo.IsPresent)" -ForegroundColor $(if ($Yolo) { 'Red' } else { 'White' })
    Write-Host "  Session:  $sessionId" -ForegroundColor White
    Write-Host "  CLI:      $cliDisplay" -ForegroundColor Yellow
    Write-Host "  Log dir:  $logDir" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  ── Composed Prompt (first 20 lines):" -ForegroundColor DarkCyan
    $composed -split "`n" | Select-Object -First 20 | ForEach-Object { Write-Host "  $_" }
    Write-Host "  ═══════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""

    $composed | Out-File $inputFile -Encoding UTF8
    "[DRY RUN] No execution" | Out-File $outputFile -Encoding UTF8
    "# Report (Dry Run)`n`nRun ID: $runId`nNo execution performed." | Out-File $reportFile -Encoding UTF8

    return @{ Success=$true; RunId=$runId; LogDir=$logDir; DryRun=$true; Harness=$harness }
}

# ════════════════════════════════════════════════════════════════
# WRITE RUN INDEX (start row)
# ════════════════════════════════════════════════════════════════

$startRow = '{"run_id":"' + $runId + '","status":"running","created_at_utc":"' + (Get-Date -Format 'o') + '","session_id":"' + $sessionId + '","model":"' + $Model + '","harness":"' + $harness + '","role":"' + $Role + '","yolo":' + $Yolo.IsPresent.ToString().ToLower() + ',"log_dir":"' + ($logDir -replace '\\','\\\\') + '"}'
Add-Content -Path $indexFile -Value $startRow -Encoding UTF8

$composed | Out-File $inputFile -Encoding UTF8

# ════════════════════════════════════════════════════════════════
# EXECUTE
# ════════════════════════════════════════════════════════════════

Write-Host "  [Run-Agent] Starting: $cliDisplay" -ForegroundColor Cyan
$startTime = Get-Date

$exitCode = 0
$output   = ""
$success  = $false

try {
    $cli = $cliArgs[0]
    $cliRest = if ($cliArgs.Count -gt 1) { $cliArgs[1..($cliArgs.Count-1)] } else { @() }

    if (-not (Get-Command $cli -ErrorAction SilentlyContinue)) {
        throw "$cli not found in PATH"
    }

    $errorFile = Join-Path $logDir "stderr.log"
    $output = $composed | & $cli @cliRest 2>$errorFile
    $exitCode = $LASTEXITCODE

    if ($exitCode -eq 0 -and $output) {
        $success = $true
    } elseif (-not $output) {
        $errContent = Get-Content $errorFile -Raw -ErrorAction SilentlyContinue
        throw "No output from $cli (exit $exitCode). Stderr: $errContent"
    } else {
        $success = $true  # some tools use non-zero exit even on success
    }

} catch {
    $exitCode = 1
    $errMsg = "$_"
    Write-Host "  [Run-Agent] FAILED: $errMsg" -ForegroundColor Red
    "# Report`n`n**Status**: failed`n`n**Error**: $errMsg" | Out-File $reportFile -Encoding UTF8
}

$duration = [int](((Get-Date) - $startTime).TotalSeconds)
$status   = if ($success) { 'completed' } else { 'failed' }

# Save output
$output | Out-File $outputFile -Encoding UTF8

# Extract report.md from output if not already written by subagent
if (-not (Test-Path $reportFile) -or (Get-Item $reportFile).Length -lt 10) {
    # Simple extraction: take everything after last markdown heading
    $reportContent = if ($output) {
        "# Report`n`n$($output | Select-Object -Last 100 | Out-String)"
    } else {
        "# Report`n`n**Status**: $status`n**Duration**: ${duration}s`n**Exit code**: $exitCode"
    }
    $reportContent | Out-File $reportFile -Encoding UTF8
}

# ════════════════════════════════════════════════════════════════
# WRITE RUN INDEX (finalize row)
# ════════════════════════════════════════════════════════════════

$finalRow = '{"run_id":"' + $runId + '","status":"' + $status + '","finished_at_utc":"' + (Get-Date -Format 'o') + '","duration_seconds":' + $duration + ',"exit_code":' + $exitCode + ',"report_path":"' + ($reportFile -replace '\\','\\\\') + '"}'
Add-Content -Path $indexFile -Value $finalRow -Encoding UTF8

Write-Host "  [Run-Agent] $status (${duration}s) → $logDir" -ForegroundColor $(if ($success) { 'Green' } else { 'Red' })

return @{
    Success    = $success
    RunId      = $runId
    SessionId  = $sessionId
    Harness    = $harness
    Model      = $Model
    LogDir     = $logDir
    OutputFile = $outputFile
    ReportFile = $reportFile
    Duration   = $duration
    ExitCode   = $exitCode
}
