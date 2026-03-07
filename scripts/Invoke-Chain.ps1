#Requires -Version 5.1
<#
.SYNOPSIS
    Role-aware chain executor — reads config and runs agent steps in sequence.
.DESCRIPTION
    Reads .claude/dispatcher.config.json, iterates over the chain steps,
    and for each step calls Invoke-Agent.ps1 with the configured agent+role.
    Output of each step becomes context for the next step.

    Chain format in config:
      "chain": [
        { "agent": "claude",  "role": "global-planner" },
        { "agent": "gemini",  "role": "researcher" },
        { "agent": "claude",  "role": "implementation-planner" },
        { "agent": "codex",   "role": "implementer" },
        { "agent": "gemini",  "role": "reviewer" }
      ]

    To add a new agent: drop Invoke-<Name>Agent.ps1 into scripts/agents/
    To add a new role: drop <role>.md into .claude/roles/

.PARAMETER Task
    The user's task (passed verbatim from Claude's plan step).
.PARAMETER ContextFile
    Optional file to include as context for the chain.
.PARAMETER ConfigPath
    Path to dispatcher config. If omitted, resolved automatically:
      1. Local project:  <CWD>\.claude\dispatcher.config.json
      2. Global profile: <this script's parent>\dispatcher.config.json
.PARAMETER DryRun
    Print what would run without executing API calls.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$Task,
    [Parameter()]          [string]$ContextFile = "",
    [Parameter()]          [string]$ConfigPath = "",
    [Parameter()]          [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir  = $PSScriptRoot
$profileDir = Split-Path $scriptDir -Parent
$rolesDir   = Join-Path $profileDir "roles"
$agentsDir  = Join-Path $scriptDir "agents"

# ════════════════════════════════════════════════════════════════
# LOAD CONFIG  (local project overrides global profile)
# ════════════════════════════════════════════════════════════════
if (-not $ConfigPath) {
    $localConfig  = Join-Path $PWD ".claude\dispatcher.config.json"
    $globalConfig = Join-Path $profileDir "dispatcher.config.json"
    if (Test-Path $localConfig) {
        $ConfigPath = $localConfig
    } elseif (Test-Path $globalConfig) {
        $ConfigPath = $globalConfig
    } else {
        throw "dispatcher.config.json not found (checked: $localConfig, $globalConfig)"
    }
}

if (-not (Test-Path $ConfigPath)) {
    throw "Config not found: $ConfigPath"
}

$rawConfig = Get-Content $ConfigPath -Raw -Encoding UTF8
try {
    $config = $rawConfig | ConvertFrom-Json
} catch {
    throw "Invalid JSON in ${ConfigPath}: $_"
}

$chainSteps = $config.chain
if (-not $chainSteps -or $chainSteps.Count -eq 0) {
    throw "No chain steps defined in $ConfigPath"
}

# ════════════════════════════════════════════════════════════════
# SESSION SETUP
# ════════════════════════════════════════════════════════════════
$timestamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
$sessionDir = Join-Path $env:TEMP "chain-$timestamp"
New-Item -ItemType Directory -Path $sessionDir -Force | Out-Null
$logFile    = Join-Path $sessionDir "chain.log"

function Log ([string]$msg, [string]$color = 'White') {
    $entry = "[$(Get-Date -Format 'HH:mm:ss')] $msg"
    Write-Host $entry -ForegroundColor $color
    Add-Content -Path $logFile -Value $entry -Encoding UTF8
}

function Banner ([string]$text, [string]$color = 'Cyan') {
    $line = "═" * 60
    Write-Host ""
    Write-Host "  $line" -ForegroundColor $color
    Write-Host "  $text" -ForegroundColor $color
    Write-Host "  $line" -ForegroundColor $color
    Write-Host ""
}

# ════════════════════════════════════════════════════════════════
# HEADER
# ════════════════════════════════════════════════════════════════
$chainSummary = ($chainSteps | ForEach-Object { "$($_.agent):$($_.role)" }) -join " -> "
Banner "CHAIN: $chainSummary"
Log "Task: $Task"
Log "Steps: $($chainSteps.Count)"
Log "Session: $sessionDir"
if ($DryRun) { Log "DRY RUN — no API calls" 'Yellow' }

@{
    task      = $Task
    chain     = $chainSteps
    startedAt = (Get-Date -Format 'o')
    sessionDir= $sessionDir
    dryRun    = $DryRun.IsPresent
} | ConvertTo-Json -Depth 5 | Out-File (Join-Path $sessionDir "manifest.json") -Encoding UTF8

# ════════════════════════════════════════════════════════════════
# EXECUTE CHAIN
# ════════════════════════════════════════════════════════════════
$accumulatedContext = ""
$lastOutputFile     = ""
$stepResults        = [System.Collections.Generic.List[hashtable]]::new()

for ($i = 0; $i -lt $chainSteps.Count; $i++) {
    $step    = $chainSteps[$i]
    $stepNum = $i + 1
    $agent   = $step.agent
    $role    = $step.role
    $desc    = if ($step.description) { $step.description } else { "$agent performing $role" }

    $safeName       = $role -replace '[^a-zA-Z0-9\-]', '-'
    $stepOutputFile = Join-Path $sessionDir "step-${stepNum}-${agent}-${safeName}.txt"

    Banner "STEP $stepNum / $($chainSteps.Count)  |  [$($agent.ToUpper())]  $role" 'Yellow'
    Log "Step $stepNum: $agent -> $role  ($desc)"

    # Resolve per-agent config
    $stepConfig = @{}
    $agentCfgObj = $config.$agent
    if ($agentCfgObj) {
        $agentCfgObj.PSObject.Properties | ForEach-Object { $stepConfig[$_.Name] = $_.Value }
    }
    # Step-level inline config overrides agent-level config
    if ($step.config) {
        $step.config.PSObject.Properties | ForEach-Object { $stepConfig[$_.Name] = $_.Value }
    }

    if ($DryRun) {
        Log "  [DRY RUN] Agent=$agent Role=$role Config=$($stepConfig | ConvertTo-Json -Compress)" 'DarkCyan'
        $dryOut = "[DRY RUN] Placeholder output for step $stepNum ($agent:$role)"
        $dryOut | Out-File $stepOutputFile -Encoding UTF8
        $accumulatedContext += "`n--- Step $stepNum ($agent:$role) [DRY RUN] ---`n$dryOut`n"
        $lastOutputFile = $stepOutputFile
        $stepResults.Add(@{ step=$stepNum; agent=$agent; role=$role; success=$true; dryRun=$true })
        continue
    }

    # Execute agent
    $stepSuccess = $false
    try {
        $result = & "$scriptDir\Invoke-Agent.ps1" `
            -Agent       $agent `
            -Role        $role `
            -Task        $Task `
            -Context     $accumulatedContext `
            -ContextFile $ContextFile `
            -OutputFile  $stepOutputFile `
            -StepConfig  $stepConfig `
            -RolesDir    $rolesDir `
            -AgentsDir   $agentsDir

        $lastOutputFile = $result.OutputFile
        $stepOutput = Get-Content $lastOutputFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        $accumulatedContext += "`n=== Step $stepNum: $agent -> $role ===`n$stepOutput`n"
        $stepSuccess = $true
        Log "Step $stepNum done: $lastOutputFile" 'Green'

    } catch {
        Log "Step $stepNum FAILED ($agent:$role): $_" 'Red'

        # Try fallback if defined in chain step
        if ($step.fallback) {
            $fbAgent = $step.fallback.agent
            $fbRole  = $step.fallback.role
            Log "  Fallback: $fbAgent -> $fbRole" 'Yellow'
            try {
                $result = & "$scriptDir\Invoke-Agent.ps1" `
                    -Agent      $fbAgent `
                    -Role       $fbRole `
                    -Task       $Task `
                    -Context    $accumulatedContext `
                    -OutputFile $stepOutputFile `
                    -StepConfig $stepConfig `
                    -RolesDir   $rolesDir `
                    -AgentsDir  $agentsDir

                $lastOutputFile = $result.OutputFile
                $stepOutput = Get-Content $lastOutputFile -Raw -Encoding UTF8
                $accumulatedContext += "`n=== Step $stepNum FALLBACK ($fbAgent:$fbRole) ===`n$stepOutput`n"
                $stepSuccess = $true
                Log "  Fallback OK: $lastOutputFile" 'Green'
            } catch {
                Log "  Fallback failed: $_" 'Red'
            }
        }
    }

    $stepResults.Add(@{
        step       = $stepNum
        agent      = $agent
        role       = $role
        outputFile = $lastOutputFile
        success    = $stepSuccess
    })

    if (-not $stepSuccess -and -not $step.optional) {
        Log "Non-optional step failed — stopping chain" 'Red'
        break
    }
}

# ════════════════════════════════════════════════════════════════
# FINAL OUTPUT
# ════════════════════════════════════════════════════════════════
Banner "CHAIN COMPLETE" 'Green'

Write-Host "  Results:" -ForegroundColor Cyan
foreach ($r in $stepResults) {
    $icon  = if ($r.success) { "[OK]  " } else { "[FAIL]" }
    $color = if ($r.success) { 'Green' } else { 'Red' }
    Write-Host ("  $icon  Step {0}: {1} -> {2}" -f $r.step, $r.agent, $r.role) -ForegroundColor $color
}

Write-Host ""

if ($lastOutputFile -and (Test-Path $lastOutputFile)) {
    Write-Host "  Final output file:" -ForegroundColor Yellow
    Write-Host "  $lastOutputFile" -ForegroundColor White
    Write-Host ""
    Write-Host "--- OUTPUT START (Claude: read and apply via Edit tool) ---" -ForegroundColor DarkCyan

    $lines = Get-Content $lastOutputFile -Encoding UTF8
    $lines | Select-Object -First 200 | ForEach-Object { Write-Host $_ }
    if ($lines.Count -gt 200) {
        Write-Host "  ... [+$($lines.Count - 200) lines — full: $lastOutputFile]" -ForegroundColor DarkGray
    }

    Write-Host "--- OUTPUT END ----" -ForegroundColor DarkCyan
}

Write-Host ""
Write-Host "  Session: $sessionDir" -ForegroundColor DarkGray
Write-Host "  Log:     $logFile" -ForegroundColor DarkGray
Write-Host ""

$allOk = ($stepResults | Where-Object { -not $_.success }).Count -eq 0
return @{
    Success     = $allOk
    Chain       = $chainSummary
    FinalOutput = $lastOutputFile
    SessionDir  = $sessionDir
    Log         = $logFile
    StepResults = $stepResults
}
