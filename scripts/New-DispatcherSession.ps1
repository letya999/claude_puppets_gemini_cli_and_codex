#Requires -Version 5.1
<#
.SYNOPSIS
    Initializes a new dispatcher session and sets up environment.
.DESCRIPTION
    Creates a timestamped session directory in $env:TEMP,
    sets environment variables for all dispatcher scripts,
    checks tool availability, and optionally opens a session log.
    Run this ONCE before starting a multi-step pipeline.
.PARAMETER SessionName
    Optional human-readable name for this session (e.g., "auth-refactor")
.PARAMETER Force
    Overwrite an existing session with the same name.
.OUTPUTS
    [hashtable] Session info: SessionId, SessionDir, LogFile, Tools
.EXAMPLE
    $session = .\New-DispatcherSession.ps1 -SessionName "api-redesign"
    .\Invoke-GeminiDelegate.ps1 -Task "..." -OutputFile "$($session.SessionDir)\step1.txt"
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$SessionName = "",

    [Parameter()]
    [switch]$Force
)

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$sessionId = if ($SessionName) { "$SessionName-$timestamp" } else { "session-$timestamp" }
$sessionDir = Join-Path $env:TEMP "dispatcher-$sessionId"

if ((Test-Path $sessionDir) -and -not $Force) {
    Write-Host "[WARN] Session dir exists: $sessionDir" -ForegroundColor Yellow
    Write-Host "       Use -Force to overwrite." -ForegroundColor Yellow
}

New-Item -ItemType Directory -Path $sessionDir -Force | Out-Null

$logFile = Join-Path $sessionDir "session.log"

# Set environment variables for child scripts
$env:DISPATCHER_SESSION_ID  = $sessionId
$env:DISPATCHER_SESSION_DIR = $sessionDir
$env:DISPATCHER_LOG_FILE    = $logFile

function Write-SessionLog {
    param([string]$Message)
    $entry = "[$(Get-Date -Format 'HH:mm:ss')] $Message"
    $entry | Out-File -FilePath $logFile -Append -Encoding UTF8
}

Write-Host ""
Write-Host "============================" -ForegroundColor Cyan
Write-Host "  DISPATCHER SESSION INIT" -ForegroundColor Cyan
Write-Host "============================" -ForegroundColor Cyan
Write-Host "  Session ID : $sessionId"
Write-Host "  Session Dir: $sessionDir"
Write-Host "  Log File   : $logFile"
Write-Host ""

Write-SessionLog "Session initialized: $sessionId"

# Check API keys
$apiStatus = @{}
$apiChecks = @(
    @{ Name = 'GEMINI_API_KEY';  Tool = 'Gemini' },
    @{ Name = 'OPENAI_API_KEY';  Tool = 'Codex' }
)

Write-Host "  API Keys:" -ForegroundColor DarkCyan
foreach ($check in $apiChecks) {
    $val = [System.Environment]::GetEnvironmentVariable($check.Name)
    if ($val -and $val.Length -gt 8) {
        $masked = $val.Substring(0, 4) + ("*" * ($val.Length - 8)) + $val.Substring($val.Length - 4)
        Write-Host ("    {0,-20} = {1}" -f $check.Name, $masked) -ForegroundColor Green
        $apiStatus[$check.Tool] = $true
    } else {
        Write-Host ("    {0,-20} = NOT SET" -f $check.Name) -ForegroundColor Yellow
        $apiStatus[$check.Tool] = $false
    }
}

Write-Host ""

# Run tool check
$scriptDir = $PSScriptRoot
$tools = @{ Gemini = $false; Codex = $false; Mods = $false }
try {
    $tools = & "$scriptDir\Test-Tools.ps1"
} catch {
    Write-Host "  [WARN] Tool check script failed: $_" -ForegroundColor Yellow
}

# Warn about missing API keys for available tools
if ($tools.Gemini -and -not $apiStatus.Gemini) {
    Write-Host "  [WARN] gemini found but GEMINI_API_KEY not set!" -ForegroundColor Yellow
    Write-Host "         Set it: `$env:GEMINI_API_KEY = 'your-api-key'" -ForegroundColor DarkGray
}
if ($tools.Codex -and -not $apiStatus.Codex) {
    Write-Host "  [WARN] codex found but OPENAI_API_KEY not set!" -ForegroundColor Yellow
    Write-Host "         Set it: `$env:OPENAI_API_KEY = 'sk-...'" -ForegroundColor DarkGray
}

Write-SessionLog "Tools: $(($tools.GetEnumerator() | Where-Object { $_.Value } | Select-Object -ExpandProperty Key) -join ', ')"

# Save session manifest
$manifest = @{
    SessionId  = $sessionId
    SessionDir = $sessionDir
    LogFile    = $logFile
    StartedAt  = (Get-Date -Format 'o')
    Tools      = $tools
    ApiKeys    = $apiStatus
} | ConvertTo-Json -Depth 3

$manifest | Out-File -FilePath (Join-Path $sessionDir "session-manifest.json") -Encoding UTF8

Write-Host ""
Write-Host "  Session ready. Use these paths in subsequent calls:" -ForegroundColor Green
Write-Host "  `$env:DISPATCHER_SESSION_DIR = '$sessionDir'" -ForegroundColor White
Write-Host ""

return @{
    SessionId  = $sessionId
    SessionDir = $sessionDir
    LogFile    = $logFile
    Tools      = $tools
}
