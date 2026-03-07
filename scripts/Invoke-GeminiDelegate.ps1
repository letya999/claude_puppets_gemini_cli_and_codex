#Requires -Version 5.1
<#
.SYNOPSIS
    Delegates a task to Gemini CLI and captures the output.
.DESCRIPTION
    Constructs a structured prompt using PowerShell Here-Strings,
    invokes Gemini CLI, saves output to $env:TEMP, and returns the result.
    Designed for: large context analysis, creative tasks, web research,
    log analysis, and tasks requiring >200k token context windows.
.PARAMETER Task
    The task description to send to Gemini.
.PARAMETER Context
    Additional context or file contents to include in the prompt.
.PARAMETER ContextFile
    Path to a file whose contents will be included as context.
.PARAMETER OutputFile
    Optional: custom path for the output file. Defaults to $env:TEMP\gemini-out-<timestamp>.txt
.PARAMETER Model
    Gemini model to use. Defaults to 'gemini-2.5-pro'.
.PARAMETER MaxRetries
    Number of retry attempts on failure. Default: 1.
.EXAMPLE
    .\Invoke-GeminiDelegate.ps1 -Task "Analyze this log file for errors" -ContextFile "C:\logs\app.log"
.EXAMPLE
    .\Invoke-GeminiDelegate.ps1 -Task "Brainstorm API design approaches" -Context "We use FastAPI with PostgreSQL"
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
    [string]$OutputFile = "",

    [Parameter()]
    [string]$Model = "gemini-2.5-pro",

    [Parameter()]
    [int]$MaxRetries = 1
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Resolve output path ---
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$sessionDir = Join-Path $env:TEMP "dispatcher-session-$timestamp"
New-Item -ItemType Directory -Path $sessionDir -Force | Out-Null

if (-not $OutputFile) {
    $OutputFile = Join-Path $sessionDir "gemini-output.txt"
}
$errorLog = Join-Path $sessionDir "gemini-error.log"

# --- Load context from file if provided ---
$fileContext = ""
if ($ContextFile -and (Test-Path $ContextFile)) {
    Write-Host "  Loading context from: $ContextFile" -ForegroundColor DarkGray
    $fileContext = Get-Content -Path $ContextFile -Raw -Encoding UTF8
}

# --- Verify gemini is available ---
$geminiCmd = Get-Command 'gemini' -ErrorAction SilentlyContinue
if (-not $geminiCmd) {
    Write-Host "[ERROR] 'gemini' not found in PATH. Install from: https://github.com/google-gemini/gemini-cli" -ForegroundColor Red
    throw "Gemini CLI not available"
}

# --- Build structured prompt using PowerShell Here-String ---
# Note: @' ... '@ prevents variable expansion (equivalent to bash <<'EOF')
# Use @" ... "@ if you need variable interpolation inside the prompt

$promptHeader = @'
You are a senior software engineer assistant. Respond with actionable, precise output.
Format your response as structured text with clear sections.
Do NOT include preamble or unnecessary explanation — output only what was requested.

'@

$taskSection = @"
## TASK
$Task

"@

$contextSection = ""
if ($Context) {
    $contextSection = @"
## PROVIDED CONTEXT
$Context

"@
}

$fileContextSection = ""
if ($fileContext) {
    $fileContextSection = @"
## FILE CONTENT
$fileContext

"@
}

$promptFooter = @'
## INSTRUCTIONS
- Be specific and actionable
- Use code blocks for any code
- Separate concerns clearly
- End with a "## NEXT STEPS" section listing concrete actions
'@

$fullPrompt = $promptHeader + $taskSection + $contextSection + $fileContextSection + $promptFooter

# Save prompt for debugging
$promptFile = Join-Path $sessionDir "gemini-prompt.txt"
$fullPrompt | Out-File -FilePath $promptFile -Encoding UTF8
Write-Host "  Prompt saved to: $promptFile" -ForegroundColor DarkGray

# --- Execute Gemini CLI with retry logic ---
Write-Host ""
Write-Host ">>> Delegating to Gemini CLI ($Model)..." -ForegroundColor Cyan

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
        # Pipe the prompt into gemini via stdin
        # gemini CLI accepts: gemini -m <model> -p <prompt>  OR  echo "prompt" | gemini
        $output = $fullPrompt | & gemini --model $Model 2>$errorLog

        if ($LASTEXITCODE -ne 0) {
            $errContent = Get-Content $errorLog -Raw -ErrorAction SilentlyContinue
            throw "Gemini exited with code $LASTEXITCODE. Error: $errContent"
        }

        $success = $true
    } catch {
        Write-Host "  [WARN] Attempt $($attempt + 1) failed: $_" -ForegroundColor Yellow
        $_ | Out-File -FilePath $errorLog -Append -Encoding UTF8

        # Fallback: try passing prompt as argument instead of stdin
        if ($attempt -eq 0) {
            try {
                Write-Host "  Trying argument-based invocation..." -ForegroundColor DarkGray
                $output = & gemini --model $Model -p $fullPrompt 2>$errorLog
                if ($LASTEXITCODE -eq 0) {
                    $success = $true
                }
            } catch {
                # Will retry in next loop iteration
            }
        }
    }

    $attempt++
}

if (-not $success) {
    Write-Host "[ERROR] Gemini delegation failed after $MaxRetries retries. See: $errorLog" -ForegroundColor Red
    Write-Host "        Falling back: consider using Invoke-CodexDelegate.ps1" -ForegroundColor Yellow
    throw "Gemini delegation failed"
}

# --- Save and display output ---
$output | Out-File -FilePath $OutputFile -Encoding UTF8

Write-Host ""
Write-Host "=== Gemini Output ===" -ForegroundColor Green
Write-Host $output
Write-Host "=====================" -ForegroundColor Green
Write-Host ""
Write-Host "  Output saved to: $OutputFile" -ForegroundColor DarkGray
Write-Host "  Session dir:     $sessionDir" -ForegroundColor DarkGray

return @{
    Success    = $true
    Output     = $output
    OutputFile = $OutputFile
    SessionDir = $sessionDir
    Model      = $Model
}
