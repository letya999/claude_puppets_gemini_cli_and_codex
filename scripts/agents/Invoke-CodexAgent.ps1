#Requires -Version 5.1
<#
.SYNOPSIS
    Codex sub-agent — runs Codex CLI for a specific role in the chain.
.DESCRIPTION
    Loads role definition, builds a role-scoped prompt for Codex,
    invokes Codex CLI, and returns the generated code output.
    Primary role: implementer. Also supports: security-implementer.
.PARAMETER Role
    Role name matching .claude/roles/<role>.md
.PARAMETER Task
    Original user task.
.PARAMETER Context
    Accumulated output from previous steps (research, plans, etc.)
.PARAMETER ContextFile
    Optional source file to modify/extend.
.PARAMETER OutputFile
    Where to save this step's output.
.PARAMETER Language
    Programming language hint. Default: auto-detect from context.
.PARAMETER MaxRetries
    Retry attempts. Default: 1.
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
    [Parameter()]          [string]$Language = "",
    [Parameter()]          [int]$MaxRetries = 1,
    [Parameter()]          [string]$RolesDir = ".claude\roles"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Verify codex ───────────────────────────────────────────────
if (-not (Get-Command 'codex' -ErrorAction SilentlyContinue)) {
    throw "Codex CLI not found in PATH. Install: npm install -g @openai/codex"
}

# ── Load role definition ───────────────────────────────────────
$rolePath = Join-Path $RolesDir "$Role.md"
if (-not (Test-Path $rolePath)) {
    throw "Role definition not found: $rolePath"
}
$roleDefinition = Get-Content $rolePath -Raw -Encoding UTF8

# ── Auto-detect language from context ─────────────────────────
if (-not $Language) {
    $ctxLower = ($Task + $Context).ToLower()
    $Language = switch -Regex ($ctxLower) {
        'python|fastapi|django|flask|pandas|pydantic' { 'python'; break }
        'typescript|react|nextjs|angular|nest'        { 'typescript'; break }
        'javascript|nodejs|express|vue'               { 'javascript'; break }
        'powershell|ps1|pwsh'                         { 'powershell'; break }
        'go |golang'                                  { 'go'; break }
        'rust|cargo'                                  { 'rust'; break }
        'csharp|dotnet|asp\.net'                      { 'csharp'; break }
        default                                       { 'python' }
    }
}

# ── Load context file ──────────────────────────────────────────
$fileContent = ""
if ($ContextFile -and (Test-Path $ContextFile)) {
    $fileContent = Get-Content $ContextFile -Raw -Encoding UTF8
}

# ── Build prompt ───────────────────────────────────────────────
$prompt = @"
$roleDefinition

---
## ORIGINAL TASK
$Task

## LANGUAGE
$Language

"@

if ($Context.Trim()) {
    $ctxTrimmed = if ($Context.Length -gt 60000) {
        "...[truncated]...`n" + $Context.Substring($Context.Length - 60000)
    } else { $Context }

    $prompt += @"

## IMPLEMENTATION PLAN AND RESEARCH (from previous steps)
$ctxTrimmed

"@
}

if ($fileContent) {
    $prompt += @"

## EXISTING CODE TO MODIFY
\`\`\`$Language
$fileContent
\`\`\`

"@
}

$prompt += @"

---
Implement now. Follow the role instructions exactly. Output complete runnable code.
"@

# Save prompt
$promptFile = [System.IO.Path]::ChangeExtension($OutputFile, '.prompt.txt')
$prompt | Out-File -FilePath $promptFile -Encoding UTF8
Write-Host "  [codex:$Role] Running (lang: $Language)..." -ForegroundColor Magenta

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

        # YOLO mode: --dangerously-bypass-approvals-and-sandbox
        # This skips ALL sandboxing — unrestricted filesystem + network access.
        # Safe alternative: --sandbox workspace-write (writes to workspace only)
        # Read-only alternative: --sandbox read-only
        $output = $prompt | & codex exec `
            -m ($MaxRetries -gt 0 ? "gpt-5.3-codex" : "gpt-4o") `
            --dangerously-bypass-approvals-and-sandbox `
            --json - 2>$errorFile

        if ($LASTEXITCODE -eq 0 -and $output) {
            $success = $true
        } else {
            # Fallback: legacy codex CLI syntax
            $output = & codex -q $prompt 2>$errorFile
            if ($output) { $success = $true }
        }
    } catch {
        Write-Host "  [WARN] Attempt $($attempt+1): $_" -ForegroundColor Yellow
    }
    $attempt++
}

if (-not $success) {
    throw "Codex agent failed for role '$Role' after $MaxRetries retries."
}

$output | Out-File -FilePath $OutputFile -Encoding UTF8
Write-Host "  [codex:$Role] Done → $OutputFile" -ForegroundColor Green

return @{
    Success    = $true
    OutputFile = $OutputFile
    Agent      = 'codex'
    Role       = $Role
    Language   = $Language
    Output     = $output
}
