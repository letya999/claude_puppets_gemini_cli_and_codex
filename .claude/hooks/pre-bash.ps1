#Requires -Version 5.1
<#
.SYNOPSIS
    PreToolUse hook for Bash — warns when Claude tries to implement code directly.
.DESCRIPTION
    Intercepts Bash tool calls. If Claude is attempting to write implementation
    code directly (cat heredoc, python -c, etc.) instead of delegating,
    outputs a warning to redirect to the dispatcher pipeline.

    Exit codes:
      0 = allow the tool call
      2 = block the tool call (show message)
#>

# Read tool input from stdin
$inputJson = $null
try {
    $rawInput = [Console]::In.ReadToEnd()
    if ($rawInput.Trim()) {
        $inputJson = $rawInput | ConvertFrom-Json -ErrorAction SilentlyContinue
    }
} catch { }

$command = ""
if ($inputJson) {
    $command = $inputJson.command ?? $inputJson.input?.command ?? ""
}
if (-not $command -and $env:CLAUDE_TOOL_INPUT) {
    $command = $env:CLAUDE_TOOL_INPUT
}

if (-not $command) { exit 0 }

$cmdLower = $command.ToLower()

# Detect suspicious patterns: Claude writing code itself instead of delegating
$directCodePatterns = @(
    'cat.*<<.*eof',          # bash heredoc writing files
    "python -c '",           # inline python execution
    'echo.*>.*\.py',         # echo writing .py files
    'tee.*\.py',             # tee writing .py files
    'printf.*\.py'           # printf writing .py files
)

$isDirect = $directCodePatterns | Where-Object { $cmdLower -match $_ }

if ($isDirect) {
    # Warn but don't block (exit 0 still allows it)
    # Change to exit 2 if you want to enforce strict delegation
    $warning = @"
[DISPATCHER WARNING] Claude is writing code directly instead of delegating.
Per CLAUDE.md rules: implementation should go through Codex CLI.
Suggested: pwsh -File scripts\Invoke-CodexDelegate.ps1 -Task "..."
Proceeding anyway (change exit code to 2 in pre-bash.ps1 to enforce).
"@
    Write-Output $warning
}

# Always allow dispatcher scripts through without warning
$isDispatcherCall = $cmdLower -match 'invoke-(gemini|codex|mods|pipeline|router)|test-tools|dispatcher'
if ($isDispatcherCall) {
    exit 0
}

exit 0
