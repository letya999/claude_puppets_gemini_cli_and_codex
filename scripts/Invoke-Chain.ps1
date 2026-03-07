#Requires -Version 5.1
<#
.SYNOPSIS
    Chain executor — reads dispatcher.config.json and runs the configured tool chain.
.DESCRIPTION
    This is the single script Claude calls for EVERY task.
    It reads the chain from .claude/dispatcher.config.json and executes
    each step in order, passing Claude's plan + user task through the chain.

    Chain examples:
      ["gemini"]                  → Gemini implements
      ["gemini", "codex-review"]  → Gemini implements → Codex reviews
      ["codex", "mods-review"]    → Codex implements → Mods reviews
      ["gemini", "codex", "mods-review"] → full pipeline

.PARAMETER Task
    The user's original task (passed verbatim from Claude).
.PARAMETER Plan
    Claude's plan text (optional, passed as context to first tool in chain).
.PARAMETER ContextFile
    Optional file to include as context (source file to modify, etc.)
.PARAMETER ConfigPath
    Path to dispatcher.config.json. Default: .claude\dispatcher.config.json
.EXAMPLE
    pwsh -NoProfile -File scripts\Invoke-Chain.ps1 -Task "Напиши FastAPI endpoint для регистрации"
    pwsh -NoProfile -File scripts\Invoke-Chain.ps1 -Task "Рефактори auth.py" -ContextFile "src\auth.py"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Task,

    [Parameter()]
    [string]$Plan = "",

    [Parameter()]
    [string]$ContextFile = "",

    [Parameter()]
    [string]$ConfigPath = ".claude\dispatcher.config.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot

# ════════════════════════════════════════════════════════════
# 1. LOAD CONFIG
# ════════════════════════════════════════════════════════════
$config = $null
$chain = @("gemini")  # safe default

try {
    if (Test-Path $ConfigPath) {
        $config = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $chain = $config.chain
    } else {
        Write-Host "[WARN] Config not found: $ConfigPath — using default chain: gemini" -ForegroundColor Yellow
    }
} catch {
    Write-Host "[WARN] Config parse error: $_ — using default chain: gemini" -ForegroundColor Yellow
}

# ════════════════════════════════════════════════════════════
# 2. SESSION SETUP
# ════════════════════════════════════════════════════════════
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$sessionDir = Join-Path $env:TEMP "chain-session-$timestamp"
New-Item -ItemType Directory -Path $sessionDir -Force | Out-Null

$log = Join-Path $sessionDir "chain.log"

function Log([string]$msg, [string]$color = 'White') {
    $entry = "[$(Get-Date -Format 'HH:mm:ss')] $msg"
    Write-Host $entry -ForegroundColor $color
    $entry | Out-File -FilePath $log -Append -Encoding UTF8
}

function Banner([string]$text, [string]$color = 'Cyan') {
    $line = "═" * 56
    Write-Host ""
    Write-Host "  $line" -ForegroundColor $color
    Write-Host "  $text" -ForegroundColor $color
    Write-Host "  $line" -ForegroundColor $color
    Write-Host ""
}

Banner "CHAIN EXECUTOR  ·  $(($chain -join ' → ').ToUpper())"
Log "Task: $Task"
Log "Chain: $($chain -join ' → ')"
if ($ContextFile) { Log "Context: $ContextFile" }

# ════════════════════════════════════════════════════════════
# 3. CHECK TOOLS
# ════════════════════════════════════════════════════════════
$tools = @{ Gemini = $false; Codex = $false; Mods = $false }
try { $tools = & "$scriptDir\Test-Tools.ps1" 2>$null } catch {}

# ════════════════════════════════════════════════════════════
# 4. BUILD INITIAL CONTEXT
# ════════════════════════════════════════════════════════════
# Start with Claude's plan (if provided) + original task
$currentContext = ""
if ($Plan) {
    $currentContext = "## Claude's Plan`n$Plan`n`n"
}
$currentContext += "## Task`n$Task"

$currentOutputFile = ""  # path to last step's output file

# ════════════════════════════════════════════════════════════
# 5. EXECUTE CHAIN STEPS
# ════════════════════════════════════════════════════════════
$stepNum = 0
foreach ($step in $chain) {
    $stepNum++
    $stepOutputFile = Join-Path $sessionDir "step-$stepNum-$step-output.txt"

    Banner "STEP $stepNum / $($chain.Count)  ·  $($step.ToUpper())" 'Yellow'
    Log "Executing step: $step" 'Cyan'

    switch ($step) {

        # ── GEMINI — research + implementation ──────────────────
        "gemini" {
            if (-not $tools.Gemini) {
                Log "Gemini not in PATH — skipping, falling to next step" 'Yellow'
                continue
            }

            $geminiModel = if ($config?.gemini?.model) { $config.gemini.model } else { "gemini-2.5-pro" }
            $geminiRetries = if ($config?.gemini?.retries) { $config.gemini.retries } else { 1 }

            # Build prompt with chain context
            $geminiTask = if ($currentOutputFile -and (Test-Path $currentOutputFile)) {
                "Previous step output:`n$(Get-Content $currentOutputFile -Raw)`n`nNow: $Task"
            } else {
                $Task
            }

            $result = & "$scriptDir\Invoke-GeminiDelegate.ps1" `
                -Task $geminiTask `
                -Context $currentContext `
                -ContextFile $ContextFile `
                -Model $geminiModel `
                -MaxRetries $geminiRetries `
                -OutputFile $stepOutputFile

            $currentOutputFile = $result.OutputFile
            $currentContext = Get-Content $currentOutputFile -Raw -Encoding UTF8
            Log "Gemini done → $stepOutputFile" 'Green'
        }

        # ── CODEX — code generation ──────────────────────────────
        "codex" {
            if (-not $tools.Codex) {
                Log "Codex not in PATH — skipping" 'Yellow'
                continue
            }

            $lang = if ($config?.codex?.language) { $config.codex.language } else { "python" }

            $codexTask = if ($currentOutputFile -and (Test-Path $currentOutputFile)) {
                "Based on this context, implement:`n$(Get-Content $currentOutputFile -Raw -ErrorAction SilentlyContinue | Select-Object -First 200)`n`nTask: $Task"
            } else {
                $Task
            }

            $result = & "$scriptDir\Invoke-CodexDelegate.ps1" `
                -Task $codexTask `
                -ContextFile $ContextFile `
                -Language $lang `
                -OutputFile $stepOutputFile

            $currentOutputFile = $result.OutputFile
            $currentContext = Get-Content $currentOutputFile -Raw -Encoding UTF8
            Log "Codex done → $stepOutputFile" 'Green'
        }

        # ── MODS-REVIEW — full review + fixes ───────────────────
        "mods-review" {
            if (-not $tools.Mods) {
                Log "Mods not in PATH — skipping review" 'Yellow'
                continue
            }
            if (-not $currentOutputFile -or -not (Test-Path $currentOutputFile)) {
                Log "No previous output to review — skipping mods" 'Yellow'
                continue
            }

            $reviewType = if ($config?.'mods-review'?.type) { $config.'mods-review'.type } else { "full" }
            $applyFixes = if ($config?.'mods-review'?.applyFixes) { $config.'mods-review'.applyFixes } else { $true }

            $modsParams = @{
                InputFile  = $currentOutputFile
                ReviewType = $reviewType
                OutputFile = $stepOutputFile
            }
            if ($applyFixes) { $modsParams['ApplyFixes'] = $true }

            $result = & "$scriptDir\Invoke-ModsReview.ps1" @modsParams
            $currentOutputFile = $result.OutputFile
            $currentContext = Get-Content $currentOutputFile -Raw -Encoding UTF8
            Log "Mods review done → $stepOutputFile" 'Green'
        }

        # ── CODEX-REVIEW — code review via codex/mods ───────────
        "codex-review" {
            if (-not $currentOutputFile -or -not (Test-Path $currentOutputFile)) {
                Log "No output to review — skipping codex-review" 'Yellow'
                continue
            }

            # Use mods if available, otherwise skip
            if ($tools.Mods) {
                $reviewType = if ($config?.'codex-review'?.type) { $config.'codex-review'.type } else { "security" }
                $result = & "$scriptDir\Invoke-ModsReview.ps1" `
                    -InputFile $currentOutputFile `
                    -ReviewType $reviewType `
                    -OutputFile $stepOutputFile `
                    -ApplyFixes
                $currentOutputFile = $result.OutputFile
                Log "Codex-review (mods) done → $stepOutputFile" 'Green'
            } else {
                Log "Mods not available for codex-review — skipping" 'Yellow'
            }
        }

        default {
            Log "Unknown chain step: '$step' — skipping" 'Yellow'
        }
    }
}

# ════════════════════════════════════════════════════════════
# 6. FINAL OUTPUT — print for Claude to consume
# ════════════════════════════════════════════════════════════
Banner "CHAIN COMPLETE  ·  RESULT FOR CLAUDE" 'Green'

if ($currentOutputFile -and (Test-Path $currentOutputFile)) {
    Log "Final output file: $currentOutputFile" 'Cyan'
    Write-Host ""
    Write-Host "━━━ OUTPUT START (Claude: read and apply via Edit tool) ━━━" -ForegroundColor DarkCyan

    $outputLines = Get-Content $currentOutputFile -Encoding UTF8
    $outputLines | Select-Object -First 150 | Write-Host
    if ($outputLines.Count -gt 150) {
        Write-Host "  ... [+$($outputLines.Count - 150) lines — full output at: $currentOutputFile]" -ForegroundColor DarkGray
    }

    Write-Host "━━━ OUTPUT END ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "  CLAUDE: Apply the above to the target file using Edit tool." -ForegroundColor Yellow
    Write-Host "  Full file: $currentOutputFile" -ForegroundColor DarkGray
    Write-Host "  Session:   $sessionDir" -ForegroundColor DarkGray
} else {
    Write-Host "[WARN] No output was generated. Check logs at: $log" -ForegroundColor Red
}

Write-Host ""

return @{
    Success        = $true
    Chain          = $chain
    FinalOutput    = $currentOutputFile
    SessionDir     = $sessionDir
    Log            = $log
}
