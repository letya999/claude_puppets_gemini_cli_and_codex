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

    This is the key to making the pipeline automatic:
    the user writes any task → Claude sees the instruction → Claude plans + calls chain.
#>

# ── Read chain config ──────────────────────────────────────────
$configPath = ".claude\dispatcher.config.json"
$chain = @("gemini")  # default if config missing

try {
    if (Test-Path $configPath) {
        $config = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $chain = $config.chain
    }
} catch { }

$chainStr = $chain -join " → "

# ── Read user prompt from stdin (Claude Code passes it as JSON) ──
$prompt = ""
try {
    $raw = [Console]::In.ReadToEnd()
    if ($raw.Trim()) {
        $parsed = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
        $prompt = $parsed.prompt ?? $parsed.message ?? ""
    }
} catch { }

if (-not $prompt -and $env:CLAUDE_USER_PROMPT) {
    $prompt = $env:CLAUDE_USER_PROMPT
}

# ── Detect if this is a simple question (skip chain for those) ──
$isSimpleQuestion = $false
$questionPatterns = @(
    '^\s*что такое ', '^\s*what is ', '^\s*как работает ', '^\s*how does ',
    '^\s*объясни ', '^\s*explain ', '^\s*почему ', '^\s*why ',
    '^\s*привет', '^\s*hello', '^\s*hi ', '^\s*помоги понять'
)
$promptLower = $prompt.ToLower()
foreach ($p in $questionPatterns) {
    if ($promptLower -match $p) { $isSimpleQuestion = $true; break }
}

# Short prompts without action verbs are likely questions
if ($prompt.Length -lt 60 -and $promptLower -notmatch 'напиши|реализуй|сделай|создай|implement|write|build|create|fix|review|analyze') {
    $isSimpleQuestion = $true
}

# ── Output mandatory instruction (goes into Claude's context) ────
if (-not $isSimpleQuestion) {
    $instruction = @"

════════════════════════════════════════════════════
  DISPATCHER — ОБЯЗАТЕЛЬНАЯ ИНСТРУКЦИЯ
════════════════════════════════════════════════════
Активная цепочка: Claude (план) → $chainStr

ТЫ ОБЯЗАН выполнить ДВА ШАГА:

ШАГ 1 — напиши ПЛАН (5-10 строк):
  ## ПЛАН
  Задача: [краткое описание]
  Цепочка: $chainStr
  Шаги: ...

ШАГ 2 — запусти цепочку НЕМЕДЛЕННО (без вопросов):
  pwsh -NoProfile -File scripts\Invoke-Chain.ps1 -Task "[задача дословно]"

НЕ ПИШИ КОД. НЕ СПРАШИВАЙ РАЗРЕШЕНИЯ. ПРОСТО ВЫПОЛНИ.
════════════════════════════════════════════════════

"@
    Write-Output $instruction
}

exit 0
