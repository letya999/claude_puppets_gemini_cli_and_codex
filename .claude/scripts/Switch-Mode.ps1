#Requires -Version 5.1

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Directives", "Skills", "Agents", "Hooks", "None")]
    [string]$Mode,

    [Parameter(Mandatory=$true)]
    [ValidateSet("Local", "Global")]
    [string]$Scope
)

$ErrorActionPreference = "Continue"

# --- 1. Resolve Target Directory ---
$ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$GlobalClaudeDir = Join-Path $env:USERPROFILE ".claude"
$TargetDir = if ($Scope -eq "Global") { $GlobalClaudeDir } else { Join-Path $ProjectRoot ".claude" }

if (-not (Test-Path $TargetDir)) { New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null }

# --- 2. Identity & Paths ---
$ClaudeFile = if ($Scope -eq "Global") { Join-Path $env:USERPROFILE "CLAUDE.md" } else { Join-Path $ProjectRoot "CLAUDE.md" }
$ProjSettingsFile = Join-Path $TargetDir "project.settings.json"
$FlowFile = Join-Path $TargetDir "flow.config.json"
$GlobalClaudeSettings = Join-Path $GlobalClaudeDir "settings.json"

$SrcPaths = @{ "Skills" = Join-Path $ProjectRoot "skills"; "Agents" = Join-Path $ProjectRoot "agents"; "Hooks"  = Join-Path $ProjectRoot "hooks"; "Roles"  = Join-Path $ProjectRoot "roles"; "Scripts"= Join-Path $ProjectRoot "scripts" }
$TgtPaths = @{ "Skills" = Join-Path $TargetDir "skills"; "Agents" = Join-Path $TargetDir "agents"; "Hooks"  = Join-Path $TargetDir "hooks"; "Roles"  = Join-Path $TargetDir "roles"; "Scripts"= Join-Path $TargetDir "scripts" }

# --- 3. Helper: Surgical Toggle (Add/Remove only our files) ---
function Toggle-Feature {
    param([string]$Feature, [bool]$Enable)
    $SrcDir = $SrcPaths[$Feature]; $TgtDir = $TgtPaths[$Feature]
    if (-not (Test-Path $SrcDir)) { return }
    if (-not (Test-Path $TgtDir)) { New-Item -ItemType Directory -Path $TgtDir -Force | Out-Null }
    foreach ($Item in Get-ChildItem $SrcDir) {
        $TargetPath = Join-Path $TgtDir $Item.Name
        if ($Enable) { Copy-Item -Recurse -Force $Item.FullName $TargetPath }
        else { if (Test-Path $TargetPath) { Remove-Item -Recurse -Force $TargetPath } }
    }
}

# --- 4. Helper: Surgical Update of Global Claude settings.json ---
function Update-GlobalHooks {
    param([bool]$Enable)
    if (-not (Test-Path $GlobalClaudeSettings)) { return }
    
    # Target our specific hook script
    $HookFileName = "on-prompt.ps1"
    $HookPath = Join-Path $TgtPaths["Hooks"] $HookFileName
    
    try {
        $RawJson = Get-Content $GlobalClaudeSettings -Raw -Encoding UTF8
        $Settings = $RawJson | ConvertFrom-Json
        
        # Ensure hooks property exists as an array
        if ($null -eq $Settings.hooks) { $Settings | Add-Member -MemberType NoteProperty -Name "hooks" -Value @() }
        
        $CurrentHooks = @($Settings.hooks)
        $CleanHooks = $CurrentHooks | Where-Object { $_ -notlike "*$HookFileName" }
        
        if ($Enable) {
            $CleanHooks += $HookPath
            Write-Host "[+] Registered hook in global settings.json: $HookFileName" -ForegroundColor Green
        } else {
            Write-Host "[-] Unregistered hook from global settings.json: $HookFileName" -ForegroundColor Yellow
        }
        
        $Settings.hooks = $CleanHooks
        $Settings | ConvertTo-Json -Depth 10 | Set-Content $GlobalClaudeSettings -Encoding UTF8
    } catch {
        Write-Warning "Failed to update global settings.json: $_"
    }
}

# --- 5. Switch Logic ---
Write-Host "Surgically switching to Mode: $Mode ($Scope scope)..." -ForegroundColor Cyan

# 5.1 Directives
$DirectivesAction = if ($Mode -eq "Directives") { "On" } else { "Off" }
powershell.exe -File "$PSScriptRoot\Toggle-DispatcherMode.ps1" -Mode $DirectivesAction -TargetFile $ClaudeFile

# 5.2 Features XOR
Toggle-Feature -Feature "Skills" -Enable ($Mode -eq "Skills")
Toggle-Feature -Feature "Agents" -Enable ($Mode -eq "Agents")
Toggle-Feature -Feature "Hooks"  -Enable ($Mode -eq "Hooks")

# 5.3 Global Hook Registration (XOR)
Update-GlobalHooks -Enable ($Mode -eq "Hooks")

# 5.4 Base Infrastructure
Toggle-Feature -Feature "Roles"   -Enable $true
Toggle-Feature -Feature "Scripts" -Enable $true

# --- 6. Sync Configs ---
Copy-Item -Force (Join-Path $ProjectRoot "project.settings.json") $ProjSettingsFile
Copy-Item -Force (Join-Path $ProjectRoot "flow.config.json") $FlowFile

if (Test-Path $ProjSettingsFile) {
    $Settings = Get-Content $ProjSettingsFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $Settings.mode = $Scope.ToLower()
    $Settings.formats.directives.enabled = ($Mode -eq "Directives")
    $Settings.formats.hooks.enabled      = ($Mode -eq "Hooks")
    $Settings.formats.skills.enabled     = ($Mode -eq "Skills")
    $Settings.formats.subagents.enabled  = ($Mode -eq "Agents")
    $Settings | ConvertTo-Json -Depth 5 | Set-Content $ProjSettingsFile -Encoding UTF8
}

Write-Host "Done! Switch complete." -ForegroundColor White
