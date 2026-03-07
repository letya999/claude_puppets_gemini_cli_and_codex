#Requires -Version 5.1
<#
.SYNOPSIS
    Verifies availability of all required CLI tools in PATH.
.DESCRIPTION
    Checks for gemini, codex, and mods executables.
    Sets $env:AVAILABLE_TOOLS and prints a status table.
    Returns a hashtable of tool availability for use by other scripts.
.OUTPUTS
    [hashtable] with keys: Gemini, Codex, Mods
.EXAMPLE
    $tools = .\Test-Tools.ps1
    if ($tools.Gemini) { Write-Host "Gemini ready" }
#>
[CmdletBinding()]
param()

$tools = @{
    Gemini = $false
    Codex  = $false
    Mods   = $false
}

$checks = @(
    @{ Name = 'Gemini'; Commands = @('gemini') },
    @{ Name = 'Codex';  Commands = @('codex') },
    @{ Name = 'Mods';   Commands = @('mods') }
)

Write-Host ""
Write-Host "=== Claude Dispatcher — Tool Availability Check ===" -ForegroundColor Cyan
Write-Host ""

foreach ($check in $checks) {
    $found = $false
    $foundCmd = $null

    foreach ($cmd in $check.Commands) {
        $resolved = Get-Command $cmd -ErrorAction SilentlyContinue
        if ($resolved) {
            $found = $true
            $foundCmd = $resolved.Source
            break
        }
    }

    $tools[$check.Name] = $found

    if ($found) {
        Write-Host ("  [OK]  {0,-10} -> {1}" -f $check.Name, $foundCmd) -ForegroundColor Green
    } else {
        Write-Host ("  [--]  {0,-10} -> NOT FOUND in PATH" -f $check.Name) -ForegroundColor Yellow
    }
}

Write-Host ""

# Set environment variable as CSV for sub-scripts to read
$availableList = ($tools.GetEnumerator() | Where-Object { $_.Value } | Select-Object -ExpandProperty Key) -join ','
$env:AVAILABLE_TOOLS = $availableList

if (-not $availableList) {
    Write-Host "WARNING: No delegation tools found. Claude will handle all tasks directly." -ForegroundColor Red
} else {
    Write-Host "Available tools: $availableList" -ForegroundColor Cyan
}

Write-Host ""
return $tools
