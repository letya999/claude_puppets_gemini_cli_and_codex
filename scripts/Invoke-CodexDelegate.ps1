#Requires -Version 5.1
<#
.SYNOPSIS
    Delegates a code implementation task to Codex CLI.
.DESCRIPTION
    Sends a precise implementation task to Codex CLI.
    Optimized for: code generation, Python scripts, algorithms,
    precise logic implementation, and structured code output.
    Saves output to session temp directory and returns result.
.PARAMETER Task
    The implementation task to send to Codex.
.PARAMETER Context
    Additional context (existing code, requirements, etc.)
.PARAMETER ContextFile
    Path to a file to include as context (e.g., existing source file).
.PARAMETER Language
    Target programming language hint. Default: "python"
.PARAMETER OutputFile
    Optional: custom output file path.
.PARAMETER MaxRetries
    Retry attempts on failure. Default: 1.
.EXAMPLE
    .\Invoke-CodexDelegate.ps1 -Task "Write a function to parse CSV and return a list of dicts" -Language "python"
.EXAMPLE
    .\Invoke-CodexDelegate.ps1 -Task "Refactor this function to use async/await" -ContextFile ".\src\service.py"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Task,

    [Parameter()]
    [string]$Context = "",

    [Parameter()]
    [string]$ContextFile = "",

    [Parameter()]
    [string]$Language = "python",

    [Parameter()]
    [string]$OutputFile = "",

    [Parameter()]
    [int]$MaxRetries = 1
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Resolve session directory ---
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$sessionDir = Join-Path $env:TEMP "dispatcher-session-$timestamp"
New-Item -ItemType Directory -Path $sessionDir -Force | Out-Null

if (-not $OutputFile) {
    $OutputFile = Join-Path $sessionDir "codex-output.txt"
}
$errorLog = Join-Path $sessionDir "codex-error.log"

# --- Load context file ---
$fileContext = ""
if ($ContextFile -and (Test-Path $ContextFile)) {
    Write-Host "  Loading context from: $ContextFile" -ForegroundColor DarkGray
    $fileContext = Get-Content -Path $ContextFile -Raw -Encoding UTF8
}

# --- Verify codex availability ---
$codexCmd = Get-Command 'codex' -ErrorAction SilentlyContinue
if (-not $codexCmd) {
    Write-Host "[ERROR] 'codex' not found in PATH. Install: npm install -g @openai/codex" -ForegroundColor Red
    throw "Codex CLI not available"
}

# --- Build prompt Here-String (no variable expansion in single-quoted) ---
$systemContext = @'
You are an expert software engineer. Produce clean, production-ready code.
Output ONLY the requested code/implementation. No explanations unless asked.
Use proper error handling, type hints (for Python), and follow best practices.

'@

$taskBlock = @"
## IMPLEMENTATION TASK
Language: $Language
Task: $Task

"@

$contextBlock = ""
if ($Context) {
    $contextBlock = @"
## CONTEXT / REQUIREMENTS
$Context

"@
}

$fileBlock = ""
if ($fileContext) {
    $fileBlock = @"
## EXISTING CODE (to modify or extend)
\`\`\`$Language
$fileContext
\`\`\`

"@
}

$outputSpec = @'
## OUTPUT FORMAT
- Provide complete, runnable code
- Include all necessary imports
- Add inline comments for non-obvious logic
- End with usage example in a comment block
'@

$fullPrompt = $systemContext + $taskBlock + $contextBlock + $fileBlock + $outputSpec

# Save prompt
$promptFile = Join-Path $sessionDir "codex-prompt.txt"
$fullPrompt | Out-File -FilePath $promptFile -Encoding UTF8
Write-Host "  Prompt saved to: $promptFile" -ForegroundColor DarkGray

# --- Execute Codex CLI ---
Write-Host ""
Write-Host ">>> Delegating to Codex CLI..." -ForegroundColor Magenta

$attempt = 0
$success = $false
$output = ""

while ($attempt -le $MaxRetries -and -not $success) {
    if ($attempt -gt 0) {
        $waitSec = [math]::Pow(2, $attempt)
        Write-Host "  Retry $attempt/$MaxRetries (waiting ${waitSec}s)..." -ForegroundColor Yellow
        Start-Sleep -Seconds $waitSec
    }

    try {
        # Codex CLI: codex -q "prompt"  (quiet mode, no interactive)
        $output = & codex -q $fullPrompt 2>$errorLog

        if ($LASTEXITCODE -ne 0) {
            $errContent = Get-Content $errorLog -Raw -ErrorAction SilentlyContinue
            throw "Codex exited with code $LASTEXITCODE. Error: $errContent"
        }

        $success = $true
    } catch {
        Write-Host "  [WARN] Attempt $($attempt + 1) failed: $_" -ForegroundColor Yellow
        $_ | Out-File -FilePath $errorLog -Append -Encoding UTF8

        # Fallback: try stdin pipe
        if ($attempt -eq 0) {
            try {
                Write-Host "  Trying stdin invocation..." -ForegroundColor DarkGray
                $output = $fullPrompt | & codex 2>$errorLog
                if ($LASTEXITCODE -eq 0) { $success = $true }
            } catch { }
        }
    }

    $attempt++
}

if (-not $success) {
    Write-Host "[ERROR] Codex delegation failed. See: $errorLog" -ForegroundColor Red
    throw "Codex delegation failed"
}

# --- Save and return ---
$output | Out-File -FilePath $OutputFile -Encoding UTF8

Write-Host ""
Write-Host "=== Codex Output ===" -ForegroundColor Magenta
Write-Host $output
Write-Host "====================" -ForegroundColor Magenta
Write-Host ""
Write-Host "  Output saved to: $OutputFile" -ForegroundColor DarkGray

return @{
    Success    = $true
    Output     = $output
    OutputFile = $OutputFile
    SessionDir = $sessionDir
}
