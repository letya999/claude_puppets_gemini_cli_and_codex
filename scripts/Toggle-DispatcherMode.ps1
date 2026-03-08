#Requires -Version 5.1

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("On", "Off")]
    [string]$Mode,

    [Parameter(Mandatory = $true)]
    [string]$TargetFile
)

if (-not (Test-Path $TargetFile)) {
    # If file doesn't exist, create a base one
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

### ZERO TOLERANCE FOR DIRECT EDITS
This rule applies to ALL changes, regardless of size or complexity. Even a 1-line script, a single comment, or a trivial print statement MUST be delegated via Invoke-Flow.ps1. Do NOT use built-in tools for ANY project file modification. NO EXCEPTIONS for simplicity, speed, or triviality.

### EXECUTION COMMAND: Invoke-Flow.ps1
To execute a task or a chain of tools, use the following PowerShell command. Check `flow.config.json` for available flows (e.g., "standard" or use the default by omitting the `-Flow` parameter).

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

if ($Mode -eq "Off" -and $HasBlock) {
    # Disable: Remove the block
    $NewContent = $Content -replace "(?s)\r?\n?$StartMarker.*$EndMarker\r?\n?", ""
    $NewContent = $NewContent.Trim()
    Set-Content -Path $TargetFile -Value $NewContent -Encoding UTF8
}
elseif ($Mode -eq "On" -and -not $HasBlock) {
    # Enable: Append the block
    $NewContent = $Content.Trim() + "`n`n" + $DispatcherInstructions
    Set-Content -Path $TargetFile -Value $NewContent -Encoding UTF8
}
