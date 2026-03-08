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
    
    # --- Planning Detection ---
    $IsPlanFile = $Task -match "\.md$" -and (Test-Path $Task)
    if ($IsPlanFile) {
        $Task = "CRITICAL: You are in IMPLEMENTATION mode. Read and implement the plan located at: $Task`n`nINSTRUCTION: Execute the plan step-by-step. Update the plan file by marking completed tasks with [x] using `replace`. DO NOT ask questions. Just implement."
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
                $env:CI = "true" # Disable PTY / Interactive mode
                $GeminiArgs = @()
                if ($Model) { $GeminiArgs += @('--model', $Model) }
                if ($UseYolo) { $GeminiArgs += '--yolo' }
                $Output = & gemini "$FinalPrompt" @GeminiArgs
            }

            "claude" {
                $ClaudeArgs = @('-p', $FinalPrompt)
                if ($UseYolo) { $ClaudeArgs += '--dangerously-skip-permissions' }
                $Output = & claude @ClaudeArgs
            }
            "codex" {
                if (-not (Get-Command codex -ErrorAction SilentlyContinue)) {
                    Write-Warning "Codex missing, falling back to Gemini..."
                    $GeminiArgs = @()
                    if ($UseYolo) { $GeminiArgs += '--yolo' }
                    $Output = & gemini -p "$FinalPrompt" @GeminiArgs
                } else {
                    # Official Codex CLI (OpenAI) expects 'run' or direct prompt.
                    # Based on latest community gists, 'codex run' is preferred.
                    $CodexArgs = @('run')
                    
                    if ($UseYolo) { 
                        $CodexArgs += '--yolo'
                        $CodexArgs += '--non-interactive'
                    }
                    
                    if ($Model) { $CodexArgs += @('--model', $Model) }
                    
                    # Pass the prompt using the -p flag
                    $CodexArgs += @('-p', $FinalPrompt)
                    
                    Write-Host "Executing: codex $($CodexArgs -join ' ')" -ForegroundColor DarkGray
                    $Output = & codex @CodexArgs
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
