#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)] [string]$Task,
    [Parameter()] [string]$Flow = "", # Leave empty to use default from config
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

# Resolve Flow: Parameter > Config Default > Hardcoded fallback
$TargetFlow = if ($Flow) { $Flow } elseif ($FlowConfig.defaultFlow) { $FlowConfig.defaultFlow } else { "standard" }

$SelectedFlow = $FlowConfig.flows.$TargetFlow
if (-not $SelectedFlow) { throw "Flow '$TargetFlow' not found in config." }

Write-Host "`n[FLOW] Starting '$TargetFlow' (Mode: $($Settings.mode))`n" -ForegroundColor Cyan

$Context = ""

# --- 2. Step Execution ---
function Sanitize-Prompt {
    param([string]$RawContent)
    if (-not $RawContent) { return "" }
    $Sanitized = $RawContent -replace '(?s)<thinking>.*?</thinking>', ''
    $Sanitized = $Sanitized -replace '(?s)<thought>.*?</thought>', ''
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

    $RoleFile = Join-Path $RolesDir "$Role.md"
    $SystemPrompt = if (Test-Path $RoleFile) { Get-Content $RoleFile -Raw } else { "" }
    $CleanContext = Sanitize-Prompt -RawContent $Context
    $FinalPrompt = "$SystemPrompt`n`nCONTEXT:`n$CleanContext`n`nTASK:`n$Task"

    $Output = ""
    $OldEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    
    try {
        switch ($Tool) {
            "gemini" {
                if (-not (Get-Command gemini -ErrorAction SilentlyContinue)) { throw "Gemini CLI not found." }
                # Use --prompt flag and ensure it's treated as a single argument
                $Args = @("--prompt", $FinalPrompt)
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
                # Fallback to gemini if codex missing
                if (-not (Get-Command codex -ErrorAction SilentlyContinue)) {
                    Write-Warning "Codex missing, falling back to Gemini..."
                    $Args = @("--prompt", $FinalPrompt)
                    if ($UseYolo) { $Args += "--yolo" }
                    $Output = & gemini @Args
                } else {
                    $Args = @("run", "--prompt", $FinalPrompt)
                    if ($Model) { $Args += "--model"; $Args += $Model }
                    if ($UseYolo) { $Args += "--yolo" }
                    $Output = & codex @Args
                }
            }
            Default { Write-Warning "Unknown tool: $Tool" }
        }
    } finally {
        $ErrorActionPreference = $OldEAP
    }

    $Context += "`n--- Output from $StepName ($Tool) ---`n$Output`n"
    Write-Host "--- DONE ---`n" -ForegroundColor Green
}

Write-Host "Flow Completed Successfully!" -ForegroundColor Green
return $Context
