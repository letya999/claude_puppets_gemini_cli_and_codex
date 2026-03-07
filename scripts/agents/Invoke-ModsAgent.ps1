#Requires -Version 5.1
<#
.SYNOPSIS
    Mods sub-agent — runs Mods CLI for review/validation roles.
.DESCRIPTION
    Loads role definition, builds review prompt, pipes previous step's
    output through Mods CLI for AI-powered code review and correction.
    Primary roles: reviewer, validator.
.PARAMETER Role
    Role name matching .claude/roles/<role>.md
.PARAMETER Task
    Original user task.
.PARAMETER Context
    Accumulated output from previous steps (the code to review).
.PARAMETER InputFile
    File containing code to review (preferred over Context for large inputs).
.PARAMETER OutputFile
    Where to save review output.
.PARAMETER RolesDir
    Path to roles directory. Default: .claude\roles
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$Role,
    [Parameter(Mandatory)] [string]$Task,
    [Parameter()]          [string]$Context = "",
    [Parameter()]          [string]$InputFile = "",
    [Parameter(Mandatory)] [string]$OutputFile,
    [Parameter()]          [string]$RolesDir = ".claude\roles"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Verify mods ────────────────────────────────────────────────
if (-not (Get-Command 'mods' -ErrorAction SilentlyContinue)) {
    throw "Mods CLI not found in PATH. Install: winget install charmbracelet.mods"
}

# ── Load role definition ───────────────────────────────────────
$rolePath = Join-Path $RolesDir "$Role.md"
if (-not (Test-Path $rolePath)) {
    throw "Role definition not found: $rolePath"
}
$roleDefinition = Get-Content $rolePath -Raw -Encoding UTF8

# ── Resolve code to review ────────────────────────────────────
$codeToReview = $Context
if ($InputFile -and (Test-Path $InputFile)) {
    $codeToReview = Get-Content $InputFile -Raw -Encoding UTF8
    Write-Host "  [mods:$Role] Reading from file: $InputFile" -ForegroundColor DarkGray
}

if (-not $codeToReview.Trim()) {
    throw "No code to review. Provide -Context or -InputFile."
}

# ── Build prompt ───────────────────────────────────────────────
$prompt = @"
$roleDefinition

---
## ORIGINAL TASK
$Task

## CODE TO REVIEW
$codeToReview

---
Perform your review role exactly as specified. Output the structured format.
"@

$promptFile = [System.IO.Path]::ChangeExtension($OutputFile, '.prompt.txt')
$prompt | Out-File -FilePath $promptFile -Encoding UTF8
Write-Host "  [mods:$Role] Running review..." -ForegroundColor Blue

# ── Execute mods ───────────────────────────────────────────────
$output = ""
$success = $false

try {
    $errorFile = [System.IO.Path]::ChangeExtension($OutputFile, '.error.txt')
    $output = $prompt | & mods 2>$errorFile

    if ($LASTEXITCODE -eq 0 -and $output) {
        $success = $true
    } else {
        # Fallback: pass as argument
        $output = & mods $prompt 2>$errorFile
        if ($output) { $success = $true }
    }
} catch {
    Write-Host "  [WARN] mods execution: $_" -ForegroundColor Yellow
}

if (-not $success) {
    throw "Mods agent failed for role '$Role'."
}

$output | Out-File -FilePath $OutputFile -Encoding UTF8
Write-Host "  [mods:$Role] Done → $OutputFile" -ForegroundColor Green

return @{
    Success    = $true
    OutputFile = $OutputFile
    Agent      = 'mods'
    Role       = $Role
    Output     = $output
}
