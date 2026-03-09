#Requires -Version 5.1

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Directives", "Skills", "Agents", "Hooks", "None")]
    [string]$Mode,

    [Parameter(Mandatory=$true)]
    [ValidateSet("Local", "Global")]
    [string]$Scope
)

$ErrorActionPreference = "Stop"

# --- 1. Identity & Paths ---
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$GlobalClaudeDir = Join-Path $env:USERPROFILE ".claude"
$TargetDir = if ($Scope -eq "Global") { $GlobalClaudeDir } else { Join-Path $ProjectRoot ".claude" }

$LocalClaudeMD = Join-Path $ProjectRoot "CLAUDE.md"
$GlobalClaudeMD = Join-Path $env:USERPROFILE "CLAUDE.md"
$GlobalSettingsJson = Join-Path $GlobalClaudeDir "settings.json"

# Footprint definitions
$OurSkills = @("codex-review", "gemini-delegate", "planner")
$OurAgents = @("coder.md", "orchestrator.md", "planner.md", "researcher.md", "reviewer.md")
$OurHooks  = @("on-prompt.ps1")
$StartMarker = "<!-- DISPATCHER_MODE_START -->"
$EndMarker = "<!-- DISPATCHER_MODE_END -->"

# --- 2. Infrastructure: Plans ---
$PlanDir = Join-Path $ProjectRoot "plans"
if (-not (Test-Path $PlanDir)) { 
    New-Item -ItemType Directory -Path $PlanDir -Force | Out-Null 
    Write-Host "[+] Created plans directory: $PlanDir" -ForegroundColor Cyan
}
$env:PLAN_DIR = $PlanDir
[Environment]::SetEnvironmentVariable("PLAN_DIR", $PlanDir, "Process")

# --- 3. Stage 0: Surgical Universal Cleanup ---
function Invoke-SurgicalCleanup {
    Write-Host "[*] Phase 0: Surgical Cleanup (Local & Global)..." -ForegroundColor Gray
    
    $Scopes = @($GlobalClaudeDir, (Join-Path $ProjectRoot ".claude"))
    $MDs = @($GlobalClaudeMD, $LocalClaudeMD)

    # 3.1 Clean CLAUDE.md
    foreach ($md in $MDs) {
        if (Test-Path $md) {
            $content = Get-Content $md -Raw -Encoding UTF8
            if ($content -match "(?s)\r?\n?$StartMarker.*$EndMarker") {
                $content = $content -replace "(?s)\r?\n?$StartMarker.*$EndMarker\r?\n?", ""
                Set-Content -Path $md -Value ($content.Trim()) -Encoding UTF8
                Write-Host "    [-] Removed directives from $(Split-Path $md -Leaf)" -ForegroundColor DarkGray
            }
        }
    }

    # 3.2 Clean Files (Skills, Agents, Hooks)
    foreach ($sDir in $Scopes) {
        if (-not (Test-Path $sDir)) { continue }
        
        # Skills
        foreach ($skill in $OurSkills) {
            $p = Join-Path $sDir "skills\$skill"
            if (Test-Path $p) { Remove-Item -Recurse -Force $p; Write-Host "    [-] Removed skill: $skill from $sDir" -ForegroundColor DarkGray }
        }
        # Agents
        foreach ($agent in $OurAgents) {
            $p = Join-Path $sDir "agents\$agent"
            if (Test-Path $p) { Remove-Item -Force $p; Write-Host "    [-] Removed agent: $agent from $sDir" -ForegroundColor DarkGray }
        }
        # Hooks
        foreach ($hook in $OurHooks) {
            $p = Join-Path $sDir "hooks\$hook"
            if (Test-Path $p) { Remove-Item -Force $p; Write-Host "    [-] Removed hook: $hook from $sDir" -ForegroundColor DarkGray }
        }
    }

    # 3.3 Clean Global Settings
    if (Test-Path $GlobalSettingsJson) {
        $json = Get-Content $GlobalSettingsJson -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -ne $json.hooks -and $null -ne $json.hooks.UserPromptSubmit) {
            $newList = New-Object System.Collections.Generic.List[PSObject]
            foreach ($entry in $json.hooks.UserPromptSubmit) {
                $isOurs = $false
                if ($null -ne $entry.hooks) {
                    foreach ($h in $entry.hooks) {
                        if ($h.command -match "on-prompt\.ps1") { $isOurs = $true; break }
                    }
                }
                if (-not $isOurs) { $newList.Add($entry) }
            }
            $json.hooks.UserPromptSubmit = $newList.ToArray()
            $json | ConvertTo-Json -Depth 10 | Set-Content $GlobalSettingsJson -Encoding UTF8
            Write-Host "    [-] Unregistered hook from global settings.json" -ForegroundColor DarkGray
        }
    }
}

# --- 4. Helpers for Stage 1 ---

function Set-Directives {
    param([string]$FilePath)
    $Instructions = @"

$StartMarker
## ROLE: STRATEGIC PLANNER & DELEGATOR
Your primary goal is to analyze tasks, create plans in "$PlanDir", and delegate work via Invoke-Flow.ps1.

### MANDATORY PLANNING:
1. Create a plan file in "$PlanDir" (plan_task_timestamp.md).
2. Call Invoke-Flow.ps1 with the plan path.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "scripts\Invoke-Flow.ps1" -Task "Implement the plan located at: $PlanDir\your_plan.md" -Yolo
```
$EndMarker
"@
    $content = if (Test-Path $FilePath) { Get-Content $FilePath -Raw -Encoding UTF8 } else { "# CLAUDE DIRECTIVES`n" }
    $newContent = $content.Trim() + "`n`n" + $Instructions
    Set-Content -Path $FilePath -Value $newContent -Encoding UTF8
    Write-Host "[+] Applied Directives to $FilePath" -ForegroundColor Green
}

function Copy-OurFeature {
    param([string]$Feature, [string]$TargetBase)
    $Src = Join-Path $ProjectRoot $Feature
    $Tgt = Join-Path $TargetBase $Feature
    if (-not (Test-Path $Tgt)) { New-Item -ItemType Directory -Path $Tgt -Force | Out-Null }
    
    $Items = if ($Feature -eq "skills") { $OurSkills } elseif ($Feature -eq "agents") { $OurAgents } else { $OurHooks }
    foreach ($name in $Items) {
        $s = Join-Path $Src $name
        if (Test-Path $s) {
            Copy-Item -Recurse -Force $s (Join-Path $Tgt $name)
            Write-Host "    [+] Deployed $name to $Tgt" -ForegroundColor Cyan
        }
    }
}

# --- 5. Main Execution ---

Invoke-SurgicalCleanup

if ($Mode -eq "None") { 
    Write-Host "Cleanup complete. No new mode applied." -ForegroundColor Yellow
    exit 
}

Write-Host "[*] Phase 1: Applying Mode: $Mode ($Scope scope)..." -ForegroundColor Cyan

# Ensure target structure exists
if (-not (Test-Path $TargetDir)) { New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null }
# Always sync roles and scripts as base infra
Copy-Item -Recurse -Force (Join-Path $ProjectRoot "roles") $TargetDir
Copy-Item -Recurse -Force (Join-Path $ProjectRoot "scripts") $TargetDir

switch ($Mode) {
    "Directives" {
        $targetMD = if ($Scope -eq "Global") { $GlobalClaudeMD } else { $LocalClaudeMD }
        Set-Directives -FilePath $targetMD
    }
    "Skills" {
        Copy-OurFeature -Feature "skills" -TargetBase $TargetDir
        $plannerMD = Join-Path $TargetDir "skills\planner\SKILL.md"
        if (Test-Path $plannerMD) {
            $c = Get-Content $plannerMD -Raw
            $escPath = $PlanDir -replace "\\", "\\"
            $c = $c -replace '\$env:PLAN_DIR', $escPath
            Set-Content $plannerMD $c -Encoding UTF8
        }
    }
    "Agents" {
        Copy-OurFeature -Feature "agents" -TargetBase $TargetDir
        $orchMD = Join-Path $TargetDir "agents\orchestrator.md"
        if (Test-Path $orchMD) {
            $c = Get-Content $orchMD -Raw
            $c = $c -replace "plans/", ($PlanDir.Replace("\","/") + "/")
            Set-Content $orchMD $c -Encoding UTF8
        }
    }
    "Hooks" {
        Copy-OurFeature -Feature "hooks" -TargetBase $TargetDir
        $hookPath = if ($Scope -eq "Global") { Join-Path $GlobalClaudeDir "hooks\on-prompt.ps1" } else { Join-Path $ProjectRoot ".claude\hooks\on-prompt.ps1" }
        
        $json = Get-Content $GlobalSettingsJson -Raw -Encoding UTF8 | ConvertFrom-Json
        $newHook = @{
            matcher = "*"
            hooks = @(@{ type = "command"; command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$hookPath`"" })
        }
        $list = if ($null -eq $json.hooks.UserPromptSubmit) { @() } else { [System.Collections.Generic.List[PSObject]]($json.hooks.UserPromptSubmit) }
        $list.Add($newHook)
        $json.hooks.UserPromptSubmit = $list
        $json | ConvertTo-Json -Depth 10 | Set-Content $GlobalSettingsJson -Encoding UTF8
        Write-Host "[+] Registered hook in global settings.json -> $hookPath" -ForegroundColor Green
    }
}

# --- 6. Sync Configs ---
$LocalSettings = Join-Path $ProjectRoot "project.settings.json"
$TargetSettings = Join-Path $TargetDir "project.settings.json"

$Settings = Get-Content $LocalSettings -Raw | ConvertFrom-Json
$Settings.mode = $Scope.ToLower()
$Settings.formats.directives.enabled = ($Mode -eq "Directives")
$Settings.formats.skills.enabled     = ($Mode -eq "Skills")
$Settings.formats.subagents.enabled  = ($Mode -eq "Agents")
$Settings.formats.hooks.enabled      = ($Mode -eq "Hooks")

$Settings | ConvertTo-Json -Depth 5 | Set-Content $LocalSettings -Encoding UTF8
Copy-Item -Force $LocalSettings $TargetSettings
Copy-Item -Force (Join-Path $ProjectRoot "flow.config.json") (Join-Path $TargetDir "flow.config.json")

Write-Host "Done! Surgical switch to $Mode ($Scope) complete." -ForegroundColor White
