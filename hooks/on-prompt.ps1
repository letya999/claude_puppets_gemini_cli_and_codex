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

# ── Resolve config path ──
$globalDir        = Split-Path $PSScriptRoot -Parent
$localConfigPath  = Join-Path $PWD ".claude\dispatcher.config.json"
$globalConfigPath = Join-Path $globalDir "dispatcher.config.json"

if (Test-Path $localConfigPath) { $configPath = $localConfigPath }
elseif (Test-Path $globalConfigPath) { $configPath = $globalConfigPath }
else { $configPath = "" }

# ── Absolute path to Invoke-Flow.ps1 (the new universal executor) ──
$invokeFlow = Join-Path $PWD "scripts\Invoke-Flow.ps1"
if (-not (Test-Path $invokeFlow)) {
    $invokeFlow = Join-Path $globalDir "scripts\Invoke-Flow.ps1"
}

# ── Detect simple questions — skip chain for those ────────────
$raw = ""
try { $raw = [Console]::In.ReadToEnd() } catch { }
$prompt = ""
if ($raw.Trim()) {
    $parsed = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
    if ($parsed.prompt) { $prompt = $parsed.prompt }
    elseif ($parsed.message) { $prompt = $parsed.message }
}
if (-not $prompt -and $env:CLAUDE_USER_PROMPT) { $prompt = $env:CLAUDE_USER_PROMPT }

$isSimpleQuestion = $false
$questionPatterns = @('^\s*что такое ', '^\s*what is ', '^\s*как работает ', '^\s*how does ', '^\s*объясни ', '^\s*explain ', '^\s*почему ', '^\s*why ', '^\s*привет', '^\s*hello', '^\s*hi ')
$promptLower = $prompt.ToLower()
foreach ($p in $questionPatterns) { if ($promptLower -match $p) { $isSimpleQuestion = $true; break } }

# ── Output mandatory instruction ───────────────────────────────
if (-not $isSimpleQuestion -and $prompt.Length -gt 10) {
    $instruction = @"

================================================================================
  DISPATCHER - MANDATORY DELEGATION RULES
================================================================================
YOU ARE STRICTLY PROHIBITED FROM DIRECT FILE EDITING (write_file, edit_file, replace).
You MUST delegate all implementation tasks to Gemini/Codex via the Flow Executor.

NO IN-CHAT IMPLEMENTATION: Do NOT write implementation code or provide complete scripts directly in the chat. Even if the user asks 'Show me a script', treat it as a request to CREATE a file. Immediately provide a plan and use Invoke-Flow.ps1. Your role is a Planner, not a Coder.

STEP 1 - Write a detailed PLAN:
  - Describe what files will be created or modified.
  - Specify the flow name from flow.config.json (e.g., 'standard' or 'claude_chain').

STEP 2 - Execute the task IMMEDIATELY:
  powershell -NoProfile -ExecutionPolicy Bypass -File "$invokeFlow" -Task "Your detailed task description" -Flow "standard"

DO NOT WRITE CODE YOURSELF. WAIT FOR DISPATCHER RESULTS.
================================================================================

"@
    Write-Output $instruction
}

exit 0
