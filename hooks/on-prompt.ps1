#Requires -Version 5.1
<#
.SYNOPSIS
    UserPromptSubmit hook — injects mandatory chain instruction into EVERY prompt.
.DESCRIPTION
    Runs before Claude processes each user message.
    Config resolution order (first found wins):
      1. Local project:  <CWD>\.claude\dispatcher.config.json
      2. Global profile: <this script's parent>\dispatcher.config.json

    Works from ~/.claude/hooks/ (global install) and from .claude/hooks/ (local project).
#>

# ── Resolve config path: local project wins, then global profile ──
$globalDir        = Split-Path $PSScriptRoot -Parent
$globalConfigPath = Join-Path $globalDir "dispatcher.config.json"
$localConfigPath  = Join-Path $PWD ".claude\dispatcher.config.json"

if (Test-Path $localConfigPath) {
    $configPath = $localConfigPath
} elseif (Test-Path $globalConfigPath) {
    $configPath = $globalConfigPath
} else {
    $configPath = ""
}

# ── Absolute path to Invoke-Chain.ps1 (sibling scripts/ folder) ──
$invokeChain = Join-Path $globalDir "scripts\Invoke-Chain.ps1"

$chain = @()
$chainStr = "gemini (default)"

try {
    if ($configPath -and (Test-Path $configPath)) {
        $config = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($config.chain) {
            $parts = @()
            foreach ($step in $config.chain) {
                if ($step.agent -and $step.role) {
                    $parts += "$($step.agent):$($step.role)"
                } elseif ($step -is [string]) {
                    $parts += $step
                }
            }
            $chainStr = $parts -join " -> "
        }
    }
} catch { }

# ── Read user prompt from stdin (Claude Code passes it as JSON) ──
$prompt = ""
try {
    $raw = [Console]::In.ReadToEnd()
    if ($raw.Trim()) {
        $parsed = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($parsed) {
            # PS 5.1 compatible: no ?? or ?. operators
            if ($parsed.prompt)  { $prompt = $parsed.prompt }
            elseif ($parsed.message) { $prompt = $parsed.message }
            elseif ($parsed.content) { $prompt = $parsed.content }
        }
    }
} catch { }

if (-not $prompt -and $env:CLAUDE_USER_PROMPT) {
    $prompt = $env:CLAUDE_USER_PROMPT
}

# ── Detect simple questions — skip chain for those ────────────
$isSimpleQuestion = $false
$questionPatterns = @(
    '^\s*что такое ', '^\s*what is ', '^\s*как работает ', '^\s*how does ',
    '^\s*объясни ', '^\s*explain ', '^\s*почему ', '^\s*why ',
    '^\s*привет', '^\s*hello', '^\s*hi ', '^\s*помоги понять',
    '^\s*покажи ', '^\s*show me '
)
$promptLower = $prompt.ToLower()

foreach ($p in $questionPatterns) {
    if ($promptLower -match $p) { $isSimpleQuestion = $true; break }
}

# Short prompts without action verbs are likely questions
$actionVerbs = 'напиши|реализуй|сделай|создай|implement|write|build|create|fix|review|analyze|рефактор|добавь|add|generate|запусти'
if ($prompt.Length -lt 60 -and $promptLower -notmatch $actionVerbs) {
    $isSimpleQuestion = $true
}

# ── Output mandatory instruction ───────────────────────────────
if (-not $isSimpleQuestion) {
    $instruction = @"

================================================================================
  DISPATCHER - MANDATORY INSTRUCTION
================================================================================
Active chain: $chainStr

YOU MUST perform exactly TWO steps:

STEP 1 - Write a PLAN (5-10 lines):
  ## PLAN
  Task: [brief description]
  Chain: $chainStr
  Steps: [list each agent:role and what it will do]

STEP 2 - Run the chain IMMEDIATELY (no questions, no waiting):
  pwsh -NoProfile -File "$invokeChain" -Task "[user task verbatim]"

DO NOT WRITE CODE. DO NOT ASK PERMISSION. EXECUTE THE CHAIN NOW.
================================================================================

"@
    Write-Output $instruction
}

exit 0
