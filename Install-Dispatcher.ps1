#Requires -Version 5.1

<#
.SYNOPSIS
    Universal Installer for Claude Dispatcher v2.
.DESCRIPTION
    Supports 2 modes: Local (per-repo) and Global (user-level).
    Configures 4 formats: Directives, Hooks, Skills, Sub-agents.
    Strictly Windows 11 & PowerShell 5.1-7.x compatible.
#>

param(
    [ValidateSet("Local", "Global")]
    [string]$Mode = "Global",

    [ValidateRange(1, 4)]
    [int[]]$Formats = @(1, 2, 3, 4),

    [switch]$Force,
    [switch]$Cleanup
)

$ErrorActionPreference = "Stop"

# --- Environment Check ---
$isWin11 = (Get-ComputerInfo).OsName -match "Windows 11"
$psVersion = $PSVersionTable.PSVersion.ToString()
Write-Host "--- Environment: Windows 11 ($isWin11), PowerShell $psVersion ---" -ForegroundColor Cyan

# --- Base Paths ---
$UserClaudeDir = Join-Path $env:USERPROFILE ".claude"
$TargetDir = if ($Mode -eq "Global") { $UserClaudeDir } else { Join-Path (Get-Location) ".claude" }
$SettingsPath = Join-Path $UserClaudeDir "settings.json"

if (-not (Test-Path $TargetDir)) {
    New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
    Write-Host "Created directory: $TargetDir" -ForegroundColor Green
}

# --- Cleanup Function ---
function Reset-ClaudeSettings {
    if (Test-Path $SettingsPath) {
        Write-Host "Cleaning up old injections from settings.json..." -ForegroundColor Gray
        $Settings = Get-Content $SettingsPath | ConvertFrom-Json
        
        # Reset Hooks that point to this project or typical dispatcher paths
        if ($Settings.hooks) {
            $newHooks = @{}
            foreach ($hookType in $Settings.hooks.PSObject.Properties.Name) {
                $hooksList = $Settings.hooks.$hookType
                $cleanedHooks = @()
                foreach ($hGroup in $hooksList) {
                    $keepHooks = @()
                    foreach ($h in $hGroup.hooks) {
                        if ($h.command -notmatch "on-prompt.ps1" -and $h.command -notmatch "pre-bash.ps1") {
                            $keepHooks += $h
                        }
                    }
                    if ($keepHooks.Count -gt 0) {
                        $cleanedHooks += @{ hooks = $keepHooks; matcher = $hGroup.matcher }
                    }
                }
                if ($cleanedHooks.Count -gt 0) {
                    $newHooks[$hookType] = $cleanedHooks
                }
            }
            $Settings.hooks = $newHooks
        }

        # Reset Skills Directory if it points here
        if ($Settings.skills -and $Settings.skills.directory -match "claude_puppets") {
            $Settings.skills.directory = "" # Let it be reset or manual
        }

        $Settings | ConvertTo-Json -Depth 20 | Set-Content $SettingsPath
    }
}

if ($Force -or $Cleanup) {
    Reset-ClaudeSettings
}

# --- 1. Directives (CLAUDE.md) ---
if ($Formats -contains 1) {
    Write-Host "[Format 1] Setting up Directives..." -ForegroundColor Yellow
    
    if ($Mode -eq "Global") {
        $ClaudeMdPath = Join-Path $UserClaudeDir "CLAUDE.md"
        $ExtendedContent = Get-Content (Join-Path $PSScriptRoot "CLAUDE_EXTENDED.md") -Raw
        
        if (Test-Path $ClaudeMdPath) {
            $currentContent = Get-Content $ClaudeMdPath -Raw
            if ($currentContent -notmatch "CLAUDE ORCHESTRATOR: EXTENDED DIRECTIVES") {
                Add-Content -Path $ClaudeMdPath -Value ("`n`n" + $ExtendedContent) -Encoding UTF8
                Write-Host "Injected Extended Directives into Global CLAUDE.md" -ForegroundColor Green
            } else {
                if ($Force) {
                    # Replace existing injection
                    $CleanContent = $currentContent -replace "(?s)<!-- CLAUDE ORCHESTRATOR: EXTENDED DIRECTIVES START -->.*?<!-- CLAUDE ORCHESTRATOR: EXTENDED DIRECTIVES END -->", ""
                    Set-Content -Path $ClaudeMdPath -Value ($CleanContent.Trim() + "`n`n" + $ExtendedContent) -Encoding UTF8
                    Write-Host "Updated Extended Directives in Global CLAUDE.md" -ForegroundColor Green
                } else {
                    Write-Host "Extended Directives already present in Global CLAUDE.md" -ForegroundColor Cyan
                }
            }
        } else {
            Set-Content -Path $ClaudeMdPath -Value $ExtendedContent -Encoding UTF8
            Write-Host "Created Global CLAUDE.md with Extended Directives" -ForegroundColor Green
        }
    } else {
        Write-Host "Local Mode: Skipping CLAUDE.md creation. Refer to CLAUDE.md.template for manual setup." -ForegroundColor Gray
    }
}

# --- 2. Hooks (Global Only) ---
if ($Formats -contains 2 -and $Mode -eq "Global") {
    Write-Host "[Format 2] Setting up Global Hooks..." -ForegroundColor Yellow
    
    # Ensure fresh state for our hooks
    if (-not $Force -and -not $Cleanup) { Reset-ClaudeSettings }

    $HooksConfig = @{
        UserPromptSubmit = @(
            @{
                hooks = @(
                    @{
                        type = "command"
                        command = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$($PSScriptRoot)\hooks\on-prompt.ps1`""
                    }
                )
            }
        )
        PreToolUse = @(
            @{
                matcher = "Bash"
                hooks = @(
                    @{
                        type = "command"
                        command = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$($PSScriptRoot)\hooks\pre-bash.ps1`""
                    }
                )
            }
        )
    }

    $CurrentSettings = if (Test-Path $SettingsPath) { Get-Content $SettingsPath | ConvertFrom-Json } else { @{ hooks = @{} } }
    if (-not $CurrentSettings.hooks) { $CurrentSettings | Add-Member -MemberType NoteProperty -Name "hooks" -Value @{} }

    # Set UserPromptSubmit
    $CurrentSettings.hooks.UserPromptSubmit = $HooksConfig.UserPromptSubmit
    # Set PreToolUse
    $CurrentSettings.hooks.PreToolUse = $HooksConfig.PreToolUse

    # Set Skills Directory globally if needed
    if (-not $CurrentSettings.skills) { $CurrentSettings | Add-Member -MemberType NoteProperty -Name "skills" -Value @{ directory = "" } }
    $CurrentSettings.skills.directory = (Join-Path $PSScriptRoot "skills")

    $CurrentSettings | ConvertTo-Json -Depth 20 | Set-Content $SettingsPath
    Write-Host "Global settings.json updated with Hooks and Skills path." -ForegroundColor Green
}

# --- 3. Skills ---
if ($Formats -contains 3) {
    Write-Host "[Format 3] Syncing Skills..." -ForegroundColor Yellow
    $SkillsDir = Join-Path $TargetDir "skills"
    if (-not (Test-Path $SkillsDir)) { New-Item -ItemType Directory -Path $SkillsDir -Force | Out-Null }
    # No need to copy if we point settings.json to the project folder directly in Global mode, 
    # but for local mode we might still want it.
    if ($Mode -eq "Local") {
        Copy-Item -Path (Join-Path $PSScriptRoot "skills\*") -Destination $SkillsDir -Recurse -Force
    }
}

# --- 4. Sub-agents ---
if ($Formats -contains 4) {
    Write-Host "[Format 4] Syncing Sub-agents..." -ForegroundColor Yellow
    $AgentsDir = Join-Path $TargetDir "agents"
    if (-not (Test-Path $AgentsDir)) { New-Item -ItemType Directory -Path $AgentsDir -Force | Out-Null }
    Copy-Item -Path (Join-Path $PSScriptRoot "agents\*") -Destination $AgentsDir -Recurse -Force
}

# --- Save Project State ---
$ProjectSettings = Get-Content (Join-Path $PSScriptRoot "project.settings.json") | ConvertFrom-Json
$ProjectSettings.mode = $Mode.ToLower()
$ProjectSettings | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $TargetDir "project.settings.json")

Write-Host "`nSetup Complete in $Mode mode!" -ForegroundColor Green
