#Requires -Version 5.1
<#
.SYNOPSIS
    UserPromptSubmit hook — injects mandatory chain instruction into EVERY prompt.
.DESCRIPTION
    Runs before Claude processes each user message.
    Reads dispatcher.config.json to know the current chain,
    then outputs a MANDATORY INSTRUCTION to stdout.
    Claude Code shows this output to Claude before it responds —
    forcing Claude to always plan first, then execute the chain.
#>

# ── Read chain config ──────────────────────────────────────────
$configPath = ".claude\dispatcher.config.json"
$chain = @()
$chainStr = "gemini (default)"

try {
    if (Test-Path $configPath) {
        $config = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($config.chain) {
            # chain is array of {agent, role} objects — build readable summary
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
  pwsh -NoProfile -File scripts\Invoke-Chain.ps1 -Task "[user task verbatim]"

DO NOT WRITE CODE. DO NOT ASK PERMISSION. EXECUTE THE CHAIN NOW.
================================================================================

"@
    Write-Output $instruction
}

exit 0
