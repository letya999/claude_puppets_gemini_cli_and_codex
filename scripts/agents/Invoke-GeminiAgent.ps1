#Requires -Version 5.1
<#
.SYNOPSIS
    Gemini sub-agent — runs Gemini CLI for a specific role in the chain.
.DESCRIPTION
    Loads the role definition from .claude/roles/<role>.md,
    builds a role-scoped prompt, invokes Gemini CLI, and returns output.
    Supports roles: researcher, reviewer, and any custom gemini roles.
.PARAMETER Role
    Role name matching a file in .claude/roles/<role>.md
.PARAMETER Task
    Original user task.
.PARAMETER Context
    Accumulated output from previous chain steps.
.PARAMETER ContextFile
    Optional file to include verbatim as additional context.
.PARAMETER OutputFile
    Where to save this step's output.
.PARAMETER Model
    Gemini model. Default from config or 'gemini-2.5-pro'.
.PARAMETER MaxRetries
    API retry attempts. Default: 1.
.PARAMETER RolesDir
    Path to roles directory. Default: .claude\roles
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$Role,
    [Parameter(Mandatory)] [string]$Task,
    [Parameter()]          [string]$Context = "",
    [Parameter()]          [string]$ContextFile = "",
    [Parameter(Mandatory)] [string]$OutputFile,
    [Parameter()]          [string]$Model = "gemini-2.5-pro",
    [Parameter()]          [int]$MaxRetries = 1,
    [Parameter()]          [string]$RolesDir = ".claude\roles"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Verify gemini is available ─────────────────────────────────
if (-not (Get-Command 'gemini' -ErrorAction SilentlyContinue)) {
    throw "Gemini CLI not found in PATH. Install: npm install -g @google/generative-ai-cli"
}

# ── Load role definition ───────────────────────────────────────
$rolePath = Join-Path $RolesDir "$Role.md"
if (-not (Test-Path $rolePath)) {
    throw "Role definition not found: $rolePath"
}
$roleDefinition = Get-Content $rolePath -Raw -Encoding UTF8

# ── Load optional context file ─────────────────────────────────
$fileContent = ""
if ($ContextFile -and (Test-Path $ContextFile)) {
    $fileContent = Get-Content $ContextFile -Raw -Encoding UTF8
    Write-Host "  [gemini:$Role] Context file loaded: $ContextFile" -ForegroundColor DarkGray
}

# ── Build prompt ───────────────────────────────────────────────
$prompt = @"
$roleDefinition

---
## ORIGINAL USER TASK
$Task

"@

if ($Context.Trim()) {
    # Limit context to avoid token overflow — take last 80k chars
    $ctxTrimmed = if ($Context.Length -gt 80000) {
        "...[truncated]...`n" + $Context.Substring($Context.Length - 80000)
    } else { $Context }

    $prompt += @"

## CONTEXT FROM PREVIOUS STEPS
$ctxTrimmed

"@
}

if ($fileContent) {
    $prompt += @"

## FILE CONTENT
$fileContent

"@
}

$prompt += @"

---
Perform your role exactly as specified above. Output ONLY the structured format.
"@

# Save prompt
$promptFile = [System.IO.Path]::ChangeExtension($OutputFile, '.prompt.txt')
$prompt | Out-File -FilePath $promptFile -Encoding UTF8
Write-Host "  [gemini:$Role] Running (model: $Model)..." -ForegroundColor Cyan

# ── Execute with retry ─────────────────────────────────────────
$attempt = 0
$success = $false
$output  = ""

while ($attempt -le $MaxRetries -and -not $success) {
    if ($attempt -gt 0) {
        $wait = [math]::Pow(2, $attempt)
        Write-Host "  Retry $attempt (wait ${wait}s)..." -ForegroundColor Yellow
        Start-Sleep -Seconds $wait
    }

    try {
        $errorFile = [System.IO.Path]::ChangeExtension($OutputFile, '.error.txt')
        
        $geminiArgs = @("--model", $Model)
        if ($env:GEMINI_API_KEY) {
            $geminiArgs += "--api-key", "$env:GEMINI_API_KEY"
        }
        $geminiArgs += "-p", $prompt

        # Temporarily disable Stop on error so stderr doesn't throw NativeCommandError in PS 5.1
        $oldErrPref = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $output = & gemini @geminiArgs 2>$errorFile
        } finally {
            $ErrorActionPreference = $oldErrPref
        }

        if ($LASTEXITCODE -eq 0 -and $output) {
            $success = $true
        } else {
            $errContent = Get-Content $errorFile -Raw -ErrorAction SilentlyContinue
            throw "Gemini exit $LASTEXITCODE. Error: $errContent"
        }
    } catch {
        Write-Host "  [WARN] Attempt $($attempt+1): $_" -ForegroundColor Yellow
    }
    $attempt++
}

if (-not $success) {
    throw "Gemini agent failed for role '$Role' after $MaxRetries retries."
}

$output | Out-File -FilePath $OutputFile -Encoding UTF8
Write-Host "  [gemini:$Role] Done → $OutputFile" -ForegroundColor Green

return @{
    Success    = $true
    OutputFile = $OutputFile
    Agent      = 'gemini'
    Role       = $Role
    Model      = $Model
    Output     = $output
}
