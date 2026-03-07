#Requires -Version 5.1
<#
.SYNOPSIS
    Delegates code review, linting, and correction to Mods CLI.
.DESCRIPTION
    Sends code to 'mods' CLI for AI-powered review and correction.
    Best for: code review, bug detection, style fixes, refactoring suggestions,
    security review, and applying corrections to generated code.
.PARAMETER InputFile
    Path to the file containing code to review. Takes priority over -Code.
.PARAMETER Code
    Code string to review (use when file path isn't available).
.PARAMETER ReviewType
    Type of review: 'full', 'security', 'style', 'bugs', 'refactor'. Default: 'full'
.PARAMETER Language
    Programming language of the code. Default: auto-detected.
.PARAMETER OutputFile
    Optional output file for the review result.
.PARAMETER ApplyFixes
    If set, also asks mods to output a corrected version of the code.
.EXAMPLE
    .\Invoke-ModsReview.ps1 -InputFile ".\src\service.py" -ReviewType "security"
.EXAMPLE
    .\Invoke-ModsReview.ps1 -InputFile ".\codex-output.txt" -ApplyFixes
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$InputFile = "",

    [Parameter()]
    [string]$Code = "",

    [Parameter()]
    [ValidateSet('full', 'security', 'style', 'bugs', 'refactor')]
    [string]$ReviewType = "full",

    [Parameter()]
    [string]$Language = "",

    [Parameter()]
    [string]$OutputFile = "",

    [Parameter()]
    [switch]$ApplyFixes
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Session setup ---
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$sessionDir = Join-Path $env:TEMP "dispatcher-session-$timestamp"
New-Item -ItemType Directory -Path $sessionDir -Force | Out-Null

if (-not $OutputFile) {
    $OutputFile = Join-Path $sessionDir "mods-review.txt"
}
$errorLog = Join-Path $sessionDir "mods-error.log"

# --- Load code from file or parameter ---
$codeToReview = $Code
if ($InputFile -and (Test-Path $InputFile)) {
    $codeToReview = Get-Content -Path $InputFile -Raw -Encoding UTF8
    if (-not $Language) {
        $ext = [System.IO.Path]::GetExtension($InputFile).TrimStart('.')
        $Language = switch ($ext) {
            'py'   { 'python' }
            'ps1'  { 'powershell' }
            'js'   { 'javascript' }
            'ts'   { 'typescript' }
            'go'   { 'go' }
            'rs'   { 'rust' }
            'cs'   { 'csharp' }
            default { $ext }
        }
    }
}

if (-not $codeToReview) {
    throw "No code provided. Use -InputFile or -Code parameter."
}

# --- Verify mods availability ---
if (-not (Get-Command 'mods' -ErrorAction SilentlyContinue)) {
    Write-Host "[ERROR] 'mods' not found in PATH. Install: https://github.com/charmbracelet/mods" -ForegroundColor Red
    throw "Mods CLI not available"
}

# --- Build review prompt ---
$reviewInstructions = switch ($ReviewType) {
    'security' { 'Focus ONLY on security vulnerabilities: injection, auth bypass, data exposure, insecure defaults.' }
    'style'    { 'Focus ONLY on code style, naming conventions, readability, and documentation.' }
    'bugs'     { 'Focus ONLY on bugs, logic errors, off-by-ones, null dereferences, and runtime exceptions.' }
    'refactor' { 'Suggest structural refactoring: reduce complexity, improve separation of concerns, eliminate duplication.' }
    default    { 'Perform a comprehensive review covering bugs, security, style, and performance.' }
}

$fixInstruction = ""
if ($ApplyFixes) {
    $fixInstruction = @'

After the review, provide a CORRECTED VERSION of the entire code with all issues fixed.
Mark the corrected section with:
--- CORRECTED CODE START ---
[corrected code here]
--- CORRECTED CODE END ---
'@
}

$reviewPrompt = @"
You are a senior code reviewer. $reviewInstructions

Language: $Language

Code to review:
\`\`\`$Language
$codeToReview
\`\`\`

Provide your review in this format:
## ISSUES FOUND
[numbered list of issues, each with: severity (HIGH/MEDIUM/LOW), location, description, fix suggestion]

## SUMMARY
[1-3 sentence summary of overall code quality]
$fixInstruction
"@

# Save prompt
$promptFile = Join-Path $sessionDir "mods-prompt.txt"
$reviewPrompt | Out-File -FilePath $promptFile -Encoding UTF8

# --- Execute Mods ---
Write-Host ""
Write-Host ">>> Delegating to Mods CLI (review type: $ReviewType)..." -ForegroundColor Blue

try {
    # mods reads from stdin by default: echo "prompt" | mods
    $output = $reviewPrompt | & mods 2>$errorLog

    if ($LASTEXITCODE -ne 0) {
        $errContent = Get-Content $errorLog -Raw -ErrorAction SilentlyContinue
        throw "Mods exited with code $LASTEXITCODE. Error: $errContent"
    }
} catch {
    # Fallback: try with -m flag for model specification
    Write-Host "  Falling back to mods with explicit args..." -ForegroundColor Yellow
    try {
        $output = & mods $reviewPrompt 2>$errorLog
        if ($LASTEXITCODE -ne 0) { throw "Mods failed" }
    } catch {
        Write-Host "[ERROR] Mods review failed. See: $errorLog" -ForegroundColor Red
        Write-Host "        Claude will perform inline review instead." -ForegroundColor Yellow
        throw "Mods delegation failed"
    }
}

$output | Out-File -FilePath $OutputFile -Encoding UTF8

Write-Host ""
Write-Host "=== Mods Review Output ===" -ForegroundColor Blue
Write-Host $output
Write-Host "==========================" -ForegroundColor Blue
Write-Host ""
Write-Host "  Review saved to: $OutputFile" -ForegroundColor DarkGray

return @{
    Success    = $true
    Output     = $output
    OutputFile = $OutputFile
    SessionDir = $sessionDir
}
