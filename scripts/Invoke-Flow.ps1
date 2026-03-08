#Requires -Version 5.1

<#
.SYNOPSIS
    Universal Flow Executor (v2.1).
.DESCRIPTION
    Executes toolchains from flow.config.json.
    - Resolves Roles from .claude/roles/ or global path.
    - Executes gemini, claude, or codex cli.
    - Supports MCP-like task delegation.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)] [string]$Task,
    [Parameter()] [string]$Flow = "standard",
    [Parameter()] [switch]$Yolo
)

$ErrorActionPreference = "Stop"

# --- 1. Path Resolution ---
$CurrentDir = Get-Location
$GlobalBase = Join-Path $env:USERPROFILE ".claude"
$LocalBase  = $CurrentDir

# Prioritize local config, fallback to global
$SettingsFile = if (Test-Path "$LocalBase\project.settings.json") { "$LocalBase\project.settings.json" } else { "$GlobalBase\project.settings.json" }
if (-not (Test-Path $SettingsFile)) { throw "Dispatcher not installed. Run Install-Dispatcher.ps1 first." }
$Settings = Get-Content $SettingsFile | ConvertFrom-Json

$FlowConfigFile = if ($Settings.mode -eq "local") { Join-Path $CurrentDir "flow.config.json" } else { Join-Path $GlobalBase "flow.config.json" }
$FlowConfig = Get-Content $FlowConfigFile | ConvertFrom-Json

$RolesDir = if ($Settings.mode -eq "local") { "$LocalBase\roles" } else { "$GlobalBase\roles" }

$SelectedFlow = $FlowConfig.flows.$Flow
if (-not $SelectedFlow) { throw "Flow '$Flow' not found in config." }

Write-Host "`n[FLOW] Starting '$Flow' (Mode: $($Settings.mode))`n" -ForegroundColor Cyan

$Context = ""

# --- 2. Step Execution ---
function Sanitize-Prompt {
    param([string]$RawContent)
    if (-not $RawContent) { return "" }

    # Remove <thinking> and <thought> blocks (multi-line supported)
    $Sanitized = $RawContent -replace '(?s)<thinking>.*?</thinking>', ''
    $Sanitized = $Sanitized -replace '(?s)<thought>.*?</thought>', ''
    
    # Remove excessive blank lines
    $Sanitized = $Sanitized -replace '(\r?\n){3,}', "`n`n"
    
    return $Sanitized.Trim()
}

foreach ($Step in $SelectedFlow.steps) {
    $StepName = $Step.name
    $Tool = $Step.tool
    $Role = $Step.role
    $Model = $Step.model
    $UseYolo = if ($Yolo -or $Step.yolo) { $true } else { $false }

    Write-Host ">>> Step: $StepName | Tool: $Tool | Role: $Role" -ForegroundColor Yellow

    # Resolve Role (System Prompt)
    $RoleFile = Join-Path $RolesDir "$Role.md"
    $SystemPrompt = if (Test-Path $RoleFile) { Get-Content $RoleFile -Raw } else { "" }

    # Sanitize accumulated context before passing to the next model
    $CleanContext = Sanitize-Prompt -RawContent $Context

    # Build Final Prompt: System Prompt + Context + Task
    $FinalPrompt = "$SystemPrompt`n`nCONTEXT:`n$CleanContext`n`nTASK:`n$Task"

    $Output = ""
    
    switch ($Tool) {
        "gemini" {
            # Recommended: use -p/--prompt for non-interactive (headless) mode to avoid AttachConsole issues in Windows
            $Args = @("-p", $FinalPrompt)
            if ($Model) { $Args += "--model"; $Args += $Model }
            if ($UseYolo) { $Args += "--yolo" }
            $Output = & gemini @Args
        }
        "claude" {
            $Args = @("-p", $FinalPrompt)
            if ($UseYolo) { $Args += "--dangerously-skip-permissions" }
            $Output = & claude @Args
        }
        "codex" {
            $Args = @("run", "--prompt", $FinalPrompt)
            if ($Model) { $Args += "--model"; $Args += $Model }
            if ($UseYolo) { $Args += "--dangerously-bypass-approvals-and-sandbox" }
            $Output = & codex @Args
        }
        "mcp" {
            # Placeholder for MCP bridge
            $Output = "[MCP Output Placeholder]"
        }
        Default {
            Write-Warning "Unknown tool: $Tool"
            $Output = "[Unknown Tool Output]"
        }
    }

    $Context += "`n--- Output from $StepName ($Tool) ---`n$Output`n"
    Write-Host "--- DONE ---`n" -ForegroundColor Green
}

Write-Host "Flow Completed Successfully!" -ForegroundColor Green
return $Context
