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

# --- 3. Helper: Toggle Markdown Instructions (Consolidated from Toggle-DispatcherMode.ps1) ---
function Set-MarkdownBlock {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("On", "Off")]
        [string]$Action,

        [Parameter(Mandatory = $true)]
        [string]$TargetFile
    )

    if (-not (Test-Path $TargetFile)) {
        if ($Action -eq "Off") { return }
        New-Item -ItemType File -Path $TargetFile -Force | Out-Null
        "# BASE CLAUDE DIRECTIVES`n" | Set-Content $TargetFile -Encoding UTF8
    }

    $StartMarker = "<!-- DISPATCHER_MODE_START -->"
    $EndMarker = "<!-- DISPATCHER_MODE_END -->"

    $DispatcherInstructions = @"

$StartMarker
## ROLE: STRATEGIC PLANNER & DELEGATOR
You are a high-level Orchestrator. Your primary goal is to analyze tasks, create detailed implementation plans, and delegate ALL file-system modifications to specialized CLI tools (Gemini, Codex, etc.) via the Dispatcher.

### MANDATORY RULE: NO DIRECT FILE EDITING
You are **strictly prohibited** from using built-in editing tools (like `edit_file` or `write_file`) for project source code. You MUST delegate all implementation tasks to the Dispatcher.

### EXECUTION COMMAND: Invoke-Flow.ps1
To execute a task or a chain of tools, use the following PowerShell command.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "scripts\Invoke-Flow.ps1" -Task "Your detailed task description" -Flow "standard" -Yolo
```

### WORKFLOW:
1. **Understand:** Read project files to gather context.
2. **Plan:** Write a detailed step-by-step implementation plan in the chat.
3. **Delegate:** Call `Invoke-Flow.ps1` with the plan as the `-Task` parameter.
4. **Verify:** Once the flow completes, review the output and confirm success.
$EndMarker
"@

    $Content = Get-Content $TargetFile -Raw -Encoding UTF8
    $HasBlock = $Content.Contains($StartMarker)

    if ($Action -eq "Off" -and $HasBlock) {
        Write-Host "[-] Removing Dispatcher directives from $(Split-Path $TargetFile -Leaf)..." -ForegroundColor Yellow
        $NewContent = $Content -replace "(?s)\r?\n?$StartMarker.*$EndMarker\r?\n?", ""
        $NewContent = $NewContent.Trim()
        Set-Content -Path $TargetFile -Value $NewContent -Encoding UTF8
    }
    elseif ($Action -eq "On" -and -not $HasBlock) {
        Write-Host "[+] Adding Dispatcher directives to $(Split-Path $TargetFile -Leaf)..." -ForegroundColor Green
        $NewContent = $Content.Trim() + "`n`n" + $DispatcherInstructions
        Set-Content -Path $TargetFile -Value $NewContent -Encoding UTF8
    }
}

# --- 4. Helper: Surgical Toggle (Add/Remove only our files) ---
function Toggle-Feature {
    param([string]$Feature, [bool]$Enable)
    $SrcDir = $SrcPaths[$Feature]; $TgtDir = $TgtPaths[$Feature]
    if (-not (Test-Path $SrcDir)) { return }
    if (-not (Test-Path $TgtDir)) { New-Item -ItemType Directory -Path $TgtDir -Force | Out-Null }

    $SrcItems = Get-ChildItem $SrcDir
    if ($Enable) {
        Write-Host "[+] Enabling $Feature ($Scope scope)..." -ForegroundColor Green
        foreach ($Item in $SrcItems) {
            $TargetPath = Join-Path $TgtDir $Item.Name
            Copy-Item -Recurse -Force $Item.FullName $TargetPath
        }

        if ($Scope -eq "Local") {
            foreach ($TgtItem in Get-ChildItem $TgtDir) {
                if (-not (Test-Path (Join-Path $SrcDir $TgtItem.Name))) {
                    Remove-Item -Recurse -Force $TgtItem.FullName
                    Write-Host "    [-] Removed stale $Feature item: $($TgtItem.Name)" -ForegroundColor Yellow
                }
            }
        }
    } else {
        Write-Host "[-] Disabling $Feature ($Scope scope)..." -ForegroundColor Yellow
        foreach ($Item in $SrcItems) {
            $TargetPath = Join-Path $TgtDir $Item.Name
            if (Test-Path $TargetPath) {
                Remove-Item -Recurse -Force $TargetPath
                Write-Host "    [-] Removed $Feature item: $($Item.Name)" -ForegroundColor DarkGray
            }
        }
    }
}

# --- 5. Helper: Surgical Update of Global Claude settings.json ---
function Update-GlobalHooks {
    param([bool]$Enable)
    if (-not (Test-Path $GlobalClaudeSettings)) { return }

    $HookFileName = "on-prompt.ps1"
    $HookPath = Join-Path $TgtPaths["Hooks"] $HookFileName

    try {
        $RawJson = Get-Content $GlobalClaudeSettings -Raw -Encoding UTF8
        $Settings = $RawJson | ConvertFrom-Json

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

# --- 6. Switch Logic ---
Write-Host "Surgically switching to Mode: $Mode ($Scope scope)..." -ForegroundColor Cyan

# 6.1 Markdown Directives
$DirectivesAction = if ($Mode -eq "Directives") { "On" } else { "Off" }
Set-MarkdownBlock -Action $DirectivesAction -TargetFile $ClaudeFile

# 6.2 Features XOR
Toggle-Feature -Feature "Skills" -Enable ($Mode -eq "Skills")
Toggle-Feature -Feature "Agents" -Enable ($Mode -eq "Agents")
Toggle-Feature -Feature "Hooks"  -Enable ($Mode -eq "Hooks")

# 6.3 Global Hook Registration (XOR)
Update-GlobalHooks -Enable ($Mode -eq "Hooks")

# 6.4 Base Infrastructure
Toggle-Feature -Feature "Roles"   -Enable $true
Toggle-Feature -Feature "Scripts" -Enable $true

# --- 7. Sync Configs ---
Copy-Item -Force (Join-Path $ProjectRoot "project.settings.json") $ProjSettingsFile
Copy-Item -Force (Join-Path $ProjectRoot "flow.config.json") $FlowFile

if (Test-Path $ProjSettingsFile) {
    $Settings = Get-Content $ProjSettingsFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $Settings.mode = $Scope.ToLower()
    $Settings.formats.directives.enabled = ($Mode -eq "Directives")
    $Settings.formats.hooks.enabled      = ($Mode -eq "Hooks")
    $Settings.formats.skills.enabled     = ($Mode -eq $null) # Skills are always implicitly available if enabled? Actually, XOR logic.
    # Manual XOR adjustment
    $Settings.formats.skills.enabled     = ($Mode -eq "Skills")
    $Settings.formats.subagents.enabled  = ($Mode -eq "Agents")
    $Settings | ConvertTo-Json -Depth 5 | Set-Content $ProjSettingsFile -Encoding UTF8
}

Write-Host "Done! Switch complete." -ForegroundColor White
