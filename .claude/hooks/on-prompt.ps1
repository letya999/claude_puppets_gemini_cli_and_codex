#Requires -Version 5.1
<#
.SYNOPSIS
    UserPromptSubmit hook — auto-classifies task and injects routing advice.
.DESCRIPTION
    Runs before Claude processes every user message.
    Reads the prompt from stdin (JSON from Claude Code), classifies it,
    and outputs routing metadata to stdout for Claude to consume.

    Exit codes:
      0 = proceed normally (with optional injected context on stdout)
      2 = block prompt (show message to user)
#>

# Read JSON input from Claude Code via stdin
$inputJson = $null
try {
    $rawInput = [Console]::In.ReadToEnd()
    if ($rawInput.Trim()) {
        $inputJson = $rawInput | ConvertFrom-Json -ErrorAction SilentlyContinue
    }
} catch { }

# Extract prompt text
$prompt = ""
if ($inputJson) {
    $prompt = $inputJson.prompt ?? $inputJson.message ?? $inputJson.content ?? ""
}
if (-not $prompt -and $env:CLAUDE_USER_PROMPT) {
    $prompt = $env:CLAUDE_USER_PROMPT
}

if (-not $prompt) { exit 0 }

$promptLower = $prompt.ToLower()

# --- Classify the task ---
$route = "claude-direct"
$reason = ""
$confidence = "low"

# Large context signals
$largeContextKeywords = @('весь проект', 'all files', 'codebase', 'логи', 'logs', 'analyze everything', 'summarize all')
$researchKeywords = @('исследуй', 'analyze', 'research', 'анализ', 'сравни', 'compare', 'объясни', 'explain', 'summarize', 'суммаризируй')
$codeKeywords = @('напиши', 'реализуй', 'implement', 'write', 'создай', 'create', 'build', 'сделай функцию', 'function', 'class', 'класс', 'скрипт', 'script')
$reviewKeywords = @('проверь', 'review', 'аудит', 'audit', 'security', 'безопасность', 'баги', 'bugs', 'рефактор', 'refactor', 'починить', 'fix')

$isLarge   = $largeContextKeywords | Where-Object { $promptLower -like "*$_*" }
$isResearch = $researchKeywords    | Where-Object { $promptLower -like "*$_*" }
$isCode    = $codeKeywords         | Where-Object { $promptLower -like "*$_*" }
$isReview  = $reviewKeywords       | Where-Object { $promptLower -like "*$_*" }

if ($isLarge -or ($isResearch -and -not $isCode)) {
    $route = "gemini"
    $reason = "Task involves research/analysis or large context"
    $confidence = "high"
} elseif ($isCode -and $isReview) {
    $route = "pipeline"
    $reason = "Task requires both implementation and review"
    $confidence = "high"
} elseif ($isCode) {
    $route = "codex"
    $reason = "Task requires code generation"
    $confidence = "medium"
} elseif ($isReview) {
    $route = "mods"
    $reason = "Task requires code review/correction"
    $confidence = "medium"
}

# Only inject advice for non-trivial routing
if ($route -ne "claude-direct" -and $confidence -ne "low") {
    $toolMap = @{
        "gemini"   = "Gemini CLI (scripts\Invoke-GeminiDelegate.ps1)"
        "codex"    = "Codex CLI (scripts\Invoke-CodexDelegate.ps1)"
        "mods"     = "Mods CLI (scripts\Invoke-ModsReview.ps1)"
        "pipeline" = "Pipeline (scripts\Invoke-Pipeline.ps1)"
    }

    # Output routing suggestion — Claude Code injects this into context
    $suggestion = @"

[DISPATCHER ROUTING SUGGESTION]
Detected task type: $route ($reason)
Recommended tool: $($toolMap[$route])
Quick command: /$(if ($route -eq 'pipeline') { 'pipeline' } elseif ($route -eq 'gemini') { 'gemini' } elseif ($route -eq 'codex') { 'codex' } else { 'review' }) <task>
Or run full pipeline: pwsh -File scripts\Invoke-Pipeline.ps1 -Task "..."
[END ROUTING SUGGESTION]
"@

    Write-Output $suggestion
}

exit 0
