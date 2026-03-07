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
    # PS 5.1 compatible: no ?. operator
    if ($inputJson.command) {
        $command = $inputJson.command
    } elseif ($inputJson.input -and $inputJson.input.command) {
        $command = $inputJson.input.command
    }
}
if (-not $command -and $env:CLAUDE_TOOL_INPUT) {
    $command = $env:CLAUDE_TOOL_INPUT
}

if (-not $command) { exit 0 }

$cmdLower = $command.ToLower()

# Detect suspicious patterns: Claude writing code itself instead of delegating
$directCodePatterns = @(
    'cat.*<<.*eof',
    "python -c '",
    'echo.*>.*\.py',
    'tee.*\.py',
    'printf.*\.py'
)

$isDirect = $directCodePatterns | Where-Object { $cmdLower -match $_ }

if ($isDirect) {
    $invokeChain = Join-Path (Split-Path $PSScriptRoot -Parent) "scripts\Invoke-Chain.ps1"
    $warning = @"
[DISPATCHER WARNING] Claude is writing code directly instead of delegating.
Per CLAUDE.md rules: implementation should go through the chain.
Suggested: powershell -NoProfile -File "$invokeChain" -Task "..."
Proceeding anyway (set exit 2 in pre-bash.ps1 to enforce strict mode).
"@
    Write-Output $warning
}

exit 0
