#Requires -Version 5.1
<#
.SYNOPSIS
    One-click pipeline: Plan (Claude) -> Implement (Gemini/Codex) -> Review (Mods) -> Apply (Claude Edit)
.DESCRIPTION
    Orchestrates the full delegation pipeline. Takes a task description,
    routes it through the appropriate tools based on complexity and type,
    and produces a final reviewed output ready for Claude to apply.

    ROUTING LOGIC:
    - Large context / research / creative  -> Gemini CLI
    - Code implementation / algorithms     -> Codex CLI
    - Review / correction / security       -> Mods CLI
    - Final file application               -> Claude Edit tool (manual step)

.PARAMETER Task
    The task to execute through the pipeline.
.PARAMETER Mode
    Pipeline mode:
    - 'auto'    : Automatically determine routing (default)
    - 'research': Force Gemini for research phase + Codex for implementation
    - 'code'    : Skip research, go straight to Codex + Mods review
    - 'review'  : Only run Mods review on existing code file
.PARAMETER ContextFile
    Optional file to use as context/input.
.PARAMETER OutputDir
    Where to save all pipeline outputs. Defaults to $env:TEMP\pipeline-<timestamp>\
.PARAMETER SkipReview
    Skip the Mods review step.
.PARAMETER Language
    Target language for code generation. Default: 'python'
.EXAMPLE
    .\Invoke-Pipeline.ps1 -Task "Create a FastAPI endpoint that validates and stores user data"
.EXAMPLE
    .\Invoke-Pipeline.ps1 -Task "Refactor this module" -ContextFile ".\src\users.py" -Mode code
.EXAMPLE
    .\Invoke-Pipeline.ps1 -Task "Security audit" -ContextFile ".\src\auth.py" -Mode review
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Task,

    [Parameter()]
    [ValidateSet('auto', 'research', 'code', 'review')]
    [string]$Mode = 'auto',

    [Parameter()]
    [string]$ContextFile = "",

    [Parameter()]
    [string]$OutputDir = "",

    [Parameter()]
    [switch]$SkipReview,

    [Parameter()]
    [string]$Language = "python"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = $PSScriptRoot

# --- Setup session ---
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
if (-not $OutputDir) {
    $OutputDir = Join-Path $env:TEMP "pipeline-$timestamp"
}
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

$logFile = Join-Path $OutputDir "pipeline.log"
$summaryFile = Join-Path $OutputDir "pipeline-summary.md"

function Write-Log {
    param([string]$Message, [string]$Color = 'White')
    $entry = "[$(Get-Date -Format 'HH:mm:ss')] $Message"
    Write-Host $entry -ForegroundColor $Color
    $entry | Out-File -FilePath $logFile -Append -Encoding UTF8
}

function Write-Step {
    param([string]$StepNum, [string]$StepName, [string]$Tool)
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor DarkCyan
    Write-Host "  STEP $StepNum | $StepName" -ForegroundColor Cyan
    Write-Host "  Tool: $Tool" -ForegroundColor DarkCyan
    Write-Host ("=" * 60) -ForegroundColor DarkCyan
    Write-Host ""
}

# --- Header ---
Write-Host ""
Write-Host ("*" * 60) -ForegroundColor Yellow
Write-Host "  CLAUDE DISPATCHER PIPELINE" -ForegroundColor Yellow
Write-Host "  Task: $Task" -ForegroundColor White
Write-Host "  Mode: $Mode | Lang: $Language" -ForegroundColor White
Write-Host "  Output: $OutputDir" -ForegroundColor DarkGray
Write-Host ("*" * 60) -ForegroundColor Yellow
Write-Host ""

Write-Log "Pipeline started: $Task"

# --- STEP 0: Check tools ---
Write-Step "0" "Tool Availability Check" "Test-Tools.ps1"
try {
    $tools = & "$scriptDir\Test-Tools.ps1"
} catch {
    $tools = @{ Gemini = $false; Codex = $false; Mods = $false }
    Write-Log "Tool check failed: $_" 'Yellow'
}

# --- Auto-detect mode based on task keywords ---
if ($Mode -eq 'auto') {
    $taskLower = $Task.ToLower()
    $researchKeywords = @('analyze', 'research', 'explain', 'summarize', 'compare', 'log', 'audit', 'review architecture')
    $codeKeywords = @('implement', 'write', 'create', 'build', 'fix', 'refactor', 'script', 'function', 'class', 'api')
    $reviewKeywords = @('review', 'check', 'security', 'lint', 'validate', 'test')

    $isResearch = $researchKeywords | Where-Object { $taskLower -like "*$_*" }
    $isCode = $codeKeywords | Where-Object { $taskLower -like "*$_*" }
    $isReview = $reviewKeywords | Where-Object { $taskLower -like "*$_*" }

    if ($isReview -and $ContextFile) {
        $Mode = 'review'
    } elseif ($isResearch -and -not $isCode) {
        $Mode = 'research'
    } else {
        $Mode = 'code'
    }

    Write-Log "Auto-detected mode: $Mode" 'Cyan'
}

$results = @{}

# ============================================================
# MODE: research
# Phase 1: Gemini -> Phase 2: Codex -> Phase 3: Mods review
# ============================================================
if ($Mode -eq 'research') {

    # STEP 1: Gemini research
    Write-Step "1" "Research & Analysis" "Gemini CLI"
    if ($tools.Gemini) {
        try {
            $geminiOut = Join-Path $OutputDir "gemini-research.txt"
            $geminiResult = & "$scriptDir\Invoke-GeminiDelegate.ps1" `
                -Task $Task `
                -ContextFile $ContextFile `
                -OutputFile $geminiOut
            $results.GeminiOutput = $geminiResult.OutputFile
            Write-Log "Gemini research complete: $geminiOut" 'Green'
        } catch {
            Write-Log "Gemini failed: $_" 'Yellow'
            Write-Log "Skipping to Codex..." 'Yellow'
        }
    } else {
        Write-Log "Gemini not available — skipping research phase" 'Yellow'
    }

    # STEP 2: Codex implementation based on research
    Write-Step "2" "Code Implementation" "Codex CLI"
    if ($tools.Codex) {
        $codexContext = ""
        if ($results.GeminiOutput -and (Test-Path $results.GeminiOutput)) {
            $codexContext = "Research findings from previous phase:`n" + (Get-Content $results.GeminiOutput -Raw)
        }

        try {
            $codexOut = Join-Path $OutputDir "codex-implementation.txt"
            $codexResult = & "$scriptDir\Invoke-CodexDelegate.ps1" `
                -Task "Based on the research, implement: $Task" `
                -Context $codexContext `
                -Language $Language `
                -OutputFile $codexOut
            $results.CodexOutput = $codexResult.OutputFile
            Write-Log "Codex implementation complete: $codexOut" 'Green'
        } catch {
            Write-Log "Codex failed: $_" 'Yellow'
        }
    } else {
        Write-Log "Codex not available" 'Yellow'
    }
}

# ============================================================
# MODE: code
# Phase 1: Codex implementation -> Phase 2: Mods review
# ============================================================
if ($Mode -eq 'code') {

    Write-Step "1" "Code Implementation" "Codex CLI"
    if ($tools.Codex) {
        try {
            $codexOut = Join-Path $OutputDir "codex-implementation.txt"
            $codexResult = & "$scriptDir\Invoke-CodexDelegate.ps1" `
                -Task $Task `
                -ContextFile $ContextFile `
                -Language $Language `
                -OutputFile $codexOut
            $results.CodexOutput = $codexResult.OutputFile
            Write-Log "Codex implementation complete" 'Green'
        } catch {
            Write-Log "Codex failed: $_. Falling back to Gemini..." 'Yellow'
            if ($tools.Gemini) {
                $geminiOut = Join-Path $OutputDir "gemini-fallback.txt"
                $geminiResult = & "$scriptDir\Invoke-GeminiDelegate.ps1" `
                    -Task $Task -ContextFile $ContextFile -OutputFile $geminiOut
                $results.CodexOutput = $geminiResult.OutputFile
                Write-Log "Gemini fallback complete" 'Green'
            }
        }
    } elseif ($tools.Gemini) {
        Write-Log "Codex unavailable, using Gemini for implementation" 'Yellow'
        $geminiOut = Join-Path $OutputDir "gemini-implementation.txt"
        $geminiResult = & "$scriptDir\Invoke-GeminiDelegate.ps1" `
            -Task $Task -ContextFile $ContextFile -OutputFile $geminiOut
        $results.CodexOutput = $geminiResult.OutputFile
    } else {
        Write-Log "No implementation tools available" 'Red'
    }
}

# ============================================================
# MODE: review
# Only Mods review on existing file
# ============================================================
if ($Mode -eq 'review') {

    Write-Step "1" "Code Review" "Mods CLI"
    $reviewTarget = if ($ContextFile) { $ContextFile } elseif ($results.CodexOutput) { $results.CodexOutput } else { "" }

    if ($reviewTarget -and $tools.Mods) {
        try {
            $modsOut = Join-Path $OutputDir "mods-review.txt"
            $modsResult = & "$scriptDir\Invoke-ModsReview.ps1" `
                -InputFile $reviewTarget `
                -ReviewType 'full' `
                -OutputFile $modsOut `
                -ApplyFixes
            $results.ModsOutput = $modsResult.OutputFile
            Write-Log "Mods review complete" 'Green'
        } catch {
            Write-Log "Mods failed: $_" 'Yellow'
        }
    }
}

# ============================================================
# STEP N-1: Mods review (applies to research + code modes)
# ============================================================
if ($Mode -in @('research', 'code') -and -not $SkipReview) {

    $reviewTarget = $results.CodexOutput

    if ($reviewTarget -and (Test-Path $reviewTarget) -and $tools.Mods) {
        Write-Step "3" "Code Review & Correction" "Mods CLI"
        try {
            $modsOut = Join-Path $OutputDir "mods-review.txt"
            $modsResult = & "$scriptDir\Invoke-ModsReview.ps1" `
                -InputFile $reviewTarget `
                -ReviewType 'full' `
                -Language $Language `
                -OutputFile $modsOut `
                -ApplyFixes
            $results.ModsOutput = $modsResult.OutputFile
            Write-Log "Mods review complete" 'Green'
        } catch {
            Write-Log "Mods review failed: $_" 'Yellow'
        }
    } elseif (-not $tools.Mods) {
        Write-Log "Mods not available — skipping review" 'Yellow'
    }
}

# ============================================================
# FINAL: Generate summary for Claude
# ============================================================
Write-Step "FINAL" "Pipeline Summary" "Claude (manual apply)"

$summaryContent = @"
# Pipeline Execution Summary
**Date**: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
**Task**: $Task
**Mode**: $Mode
**Language**: $Language
**Session**: $OutputDir

## Outputs Generated
"@

foreach ($key in $results.Keys) {
    if ($results[$key] -and (Test-Path $results[$key])) {
        $summaryContent += "`n- **$key**: ``$($results[$key])``"
    }
}

$summaryContent += @"

## Next Step for Claude
Apply the final output to your codebase using the Edit tool.
The reviewed implementation is in: ``$($results.ModsOutput ?? $results.CodexOutput ?? $results.GeminiOutput ?? 'No output')``

## Pipeline Log
See full log at: ``$logFile``
"@

$summaryContent | Out-File -FilePath $summaryFile -Encoding UTF8

Write-Host ""
Write-Host ("=" * 60) -ForegroundColor Yellow
Write-Host "  PIPELINE COMPLETE" -ForegroundColor Green
Write-Host ("=" * 60) -ForegroundColor Yellow
Write-Host ""
Write-Host "  Summary: $summaryFile" -ForegroundColor Cyan
Write-Host "  Log:     $logFile" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  NEXT: Claude should read the output and apply changes:" -ForegroundColor Yellow

$finalOutput = $results.ModsOutput ?? $results.CodexOutput ?? $results.GeminiOutput
if ($finalOutput) {
    Write-Host "  > Get-Content '$finalOutput' | clip" -ForegroundColor White
}

Write-Host ""

return @{
    Success     = $true
    OutputDir   = $OutputDir
    SummaryFile = $summaryFile
    LogFile     = $logFile
    Results     = $results
    FinalOutput = $finalOutput
}
