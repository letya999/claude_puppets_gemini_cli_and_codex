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
$LocalClaudeDir = Join-Path $CurrentDir ".claude"

# Prioritize local config (prefer .claude subdir if it exists, fallback to root)
$SettingsFile = if (Test-Path "$LocalClaudeDir\project.settings.json") { "$LocalClaudeDir\project.settings.json" } 
                elseif (Test-Path "$CurrentDir\project.settings.json") { "$CurrentDir\project.settings.json" }
                else { "$GlobalBase\project.settings.json" }

if (-not (Test-Path $SettingsFile)) { throw "Dispatcher settings not found. Run Install-Dispatcher.ps1 or Switch-Mode.ps1." }
$Settings = Get-Content $SettingsFile -Raw | ConvertFrom-Json

$FlowConfigFile = if ($Settings.mode -eq "local") { 
    if (Test-Path "$LocalClaudeDir\flow.config.json") { "$LocalClaudeDir\flow.config.json" } else { "$CurrentDir\flow.config.json" }
} else { 
    Join-Path $GlobalBase "flow.config.json" 
}

if (-not (Test-Path $FlowConfigFile)) { throw "Flow config not found at $FlowConfigFile." }
$FlowConfig = Get-Content $FlowConfigFile -Raw | ConvertFrom-Json

$RolesDir = if ($Settings.mode -eq "local") { 
    if (Test-Path "$LocalClaudeDir\roles") { "$LocalClaudeDir\roles" } else { "$CurrentDir\roles" }
} else { 
    Join-Path $GlobalBase "roles" 
}

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
    $SystemPrompt = if (Test-Path $RoleFile) { Get-Content $RoleFile -Raw } else { 
        Write-Warning "Role file not found: $RoleFile. Using empty system prompt."
        "" 
    }
    
    $CleanContext = Sanitize-Prompt -RawContent $Context
    $FinalPrompt = "$SystemPrompt`n`nCONTEXT:`n$CleanContext`n`nTASK:`n$Task"

    $Output = ""
    $OldEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    
    try {
        switch ($Tool) {
            "gemini" {
                if (-not (Get-Command gemini -ErrorAction SilentlyContinue)) { throw "Gemini CLI not found." }
                # Using explicit string construction for the command to avoid argument splatting issues on Windows
                $GeminiCmd = "gemini -p `"$($FinalPrompt -replace '"', '\"')`""
                if ($Model) { $GeminiCmd += " --model $Model" }
                if ($UseYolo) { $GeminiCmd += " --yolo" }
                
                # Use Invoke-Expression or direct call with string to ensure -p is respected
                $Output = iex $GeminiCmd
            }
            "claude" {
                $ClaudeCmd = "claude -p `"$($FinalPrompt -replace '"', '\"')`""
                if ($UseYolo) { $ClaudeCmd += " --dangerously-skip-permissions" }
                $Output = iex $ClaudeCmd
            }
            "codex" {
                if (-not (Get-Command codex -ErrorAction SilentlyContinue)) {
                    Write-Warning "Codex missing, falling back to Gemini..."
                    $GeminiCmd = "gemini -p `"$($FinalPrompt -replace '"', '\"')`""
                    if ($UseYolo) { $GeminiCmd += " --yolo" }
                    $Output = iex $GeminiCmd
                } else {
                    $CodexCmd = "codex run -p `"$($FinalPrompt -replace '"', '\"')`""
                    if ($Model) { $CodexCmd += " --model $Model" }
                    if ($UseYolo) { $CodexCmd += " --yolo" }
                    $Output = iex $CodexCmd
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
