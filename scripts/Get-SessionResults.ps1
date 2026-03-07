#Requires -Version 5.1
<#
.SYNOPSIS
    Lists and displays results from a dispatcher session.
.DESCRIPTION
    Finds session directories in $env:TEMP and displays their outputs.
    Useful for reviewing what each pipeline step produced.
.PARAMETER SessionDir
    Explicit session directory path. If omitted, uses $env:DISPATCHER_SESSION_DIR
    or lists recent sessions for selection.
.PARAMETER ShowLatest
    Show output from the most recent session automatically.
.PARAMETER StepName
    Filter output files by step name (e.g., 'gemini', 'codex', 'mods').
.EXAMPLE
    # Show latest session outputs
    .\Get-SessionResults.ps1 -ShowLatest

    # Show specific session
    .\Get-SessionResults.ps1 -SessionDir "C:\Users\user\AppData\Local\Temp\dispatcher-session-20240101-120000"

    # Show only codex outputs from current session
    .\Get-SessionResults.ps1 -StepName "codex"
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$SessionDir = "",

    [Parameter()]
    [switch]$ShowLatest,

    [Parameter()]
    [string]$StepName = ""
)

# Resolve session dir
if (-not $SessionDir) {
    if ($env:DISPATCHER_SESSION_DIR -and (Test-Path $env:DISPATCHER_SESSION_DIR)) {
        $SessionDir = $env:DISPATCHER_SESSION_DIR
    } else {
        # Find recent sessions
        $sessions = Get-ChildItem -Path $env:TEMP -Directory -Filter "dispatcher-*" |
                    Sort-Object LastWriteTime -Descending

        if (-not $sessions) {
            Write-Host "No dispatcher sessions found in $env:TEMP" -ForegroundColor Yellow
            return
        }

        if ($ShowLatest) {
            $SessionDir = $sessions[0].FullName
        } else {
            Write-Host ""
            Write-Host "Recent Dispatcher Sessions:" -ForegroundColor Cyan
            $i = 0
            foreach ($s in $sessions | Select-Object -First 10) {
                Write-Host "  [$i] $($s.Name)  ($(($s.LastWriteTime).ToString('MM/dd HH:mm')))" -ForegroundColor White
                $i++
            }
            Write-Host ""
            $choice = Read-Host "Select session [0-$($i-1)]"
            $SessionDir = $sessions[[int]$choice].FullName
        }
    }
}

if (-not (Test-Path $SessionDir)) {
    Write-Host "Session directory not found: $SessionDir" -ForegroundColor Red
    return
}

Write-Host ""
Write-Host "=== Session Results ===" -ForegroundColor Cyan
Write-Host "Directory: $SessionDir" -ForegroundColor DarkGray
Write-Host ""

# List all output files
$filter = if ($StepName) { "*$StepName*" } else { "*.txt" }
$files = Get-ChildItem -Path $SessionDir -File -Filter $filter | Sort-Object LastWriteTime

if (-not $files) {
    Write-Host "No output files found (filter: $filter)" -ForegroundColor Yellow
    return
}

foreach ($file in $files) {
    $size = "{0:N1} KB" -f ($file.Length / 1KB)
    Write-Host "  $($file.Name)  [$size]  $($file.LastWriteTime.ToString('HH:mm:ss'))" -ForegroundColor White

    # Show preview of output files (not prompts or logs)
    if ($file.Name -match '-(output|review|implementation|research)\.txt$') {
        $preview = Get-Content $file.FullName -TotalCount 5 -Encoding UTF8 -ErrorAction SilentlyContinue
        foreach ($line in $preview) {
            Write-Host "    | $line" -ForegroundColor DarkGray
        }
        Write-Host "    | ... ($(((Get-Content $file.FullName).Count)) lines total)" -ForegroundColor DarkGray
        Write-Host ""
    }
}

# Show manifest if present
$manifest = Join-Path $SessionDir "session-manifest.json"
if (Test-Path $manifest) {
    Write-Host ""
    Write-Host "Session Manifest:" -ForegroundColor Cyan
    Get-Content $manifest -Raw | ConvertFrom-Json | Format-List
}

Write-Host ""
Write-Host "To copy final output to clipboard:" -ForegroundColor Yellow
$lastOutput = $files | Where-Object { $_.Name -match '-(output|review|implementation)\.txt$' } | Select-Object -Last 1
if ($lastOutput) {
    Write-Host "  Get-Content '$($lastOutput.FullName)' | Set-Clipboard" -ForegroundColor White
}
