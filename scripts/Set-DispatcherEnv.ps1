#Requires -Version 5.1
<#
.SYNOPSIS
    Sets up all required environment variables for the dispatcher system.
.DESCRIPTION
    Run this script once per PowerShell session (or add to your $PROFILE).
    Sets API keys, tool paths, and dispatcher configuration.
    Use -Persist to save to user environment (survives shell restarts).
.PARAMETER GeminiApiKey
    Google Gemini API key (get from https://aistudio.google.com/apikey)
.PARAMETER OpenAiApiKey
    OpenAI API key for Codex (get from https://platform.openai.com/api-keys)
.PARAMETER Persist
    Save variables to user-level environment (permanent, no admin required)
.PARAMETER ShowCurrent
    Display current environment configuration without modifying anything.
.EXAMPLE
    # Interactive setup
    .\Set-DispatcherEnv.ps1

    # Set keys directly (be careful with shell history)
    .\Set-DispatcherEnv.ps1 -GeminiApiKey "AIza..." -OpenAiApiKey "sk-..."

    # Persist to user environment
    .\Set-DispatcherEnv.ps1 -Persist

    # Show current config
    .\Set-DispatcherEnv.ps1 -ShowCurrent
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$GeminiApiKey = "",

    [Parameter()]
    [string]$OpenAiApiKey = "",

    [Parameter()]
    [switch]$Persist,

    [Parameter()]
    [switch]$ShowCurrent
)

function Mask-Key ([string]$key) {
    if (-not $key -or $key.Length -lt 8) { return "NOT SET" }
    return $key.Substring(0, 4) + ("*" * [Math]::Min(12, $key.Length - 8)) + $key.Substring($key.Length - 4)
}

if ($ShowCurrent) {
    Write-Host ""
    Write-Host "=== Current Dispatcher Environment ===" -ForegroundColor Cyan
    Write-Host ""
    $vars = @('GEMINI_API_KEY', 'OPENAI_API_KEY', 'DISPATCHER_SESSION_DIR',
              'DISPATCHER_SESSION_ID', 'AVAILABLE_TOOLS')
    foreach ($v in $vars) {
        $val = [System.Environment]::GetEnvironmentVariable($v)
        if ($v -match 'KEY' -and $val) { $val = Mask-Key $val }
        Write-Host ("  {0,-30} = {1}" -f $v, ($val ?? 'NOT SET')) -ForegroundColor $(if ($val) { 'Green' } else { 'Yellow' })
    }
    Write-Host ""
    return
}

Write-Host ""
Write-Host "=== Dispatcher Environment Setup ===" -ForegroundColor Cyan
Write-Host ""

# --- Gemini API Key ---
if (-not $GeminiApiKey) {
    $existing = $env:GEMINI_API_KEY
    if ($existing) {
        Write-Host "  GEMINI_API_KEY already set: $(Mask-Key $existing)" -ForegroundColor Green
        $GeminiApiKey = $existing
    } else {
        Write-Host "  Enter your Gemini API Key (get from https://aistudio.google.com/apikey):" -ForegroundColor Yellow
        Write-Host "  Press ENTER to skip." -ForegroundColor DarkGray
        $secureKey = Read-Host "  GEMINI_API_KEY" -AsSecureString
        $GeminiApiKey = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey))
    }
}

# --- OpenAI API Key ---
if (-not $OpenAiApiKey) {
    $existing = $env:OPENAI_API_KEY
    if ($existing) {
        Write-Host "  OPENAI_API_KEY already set: $(Mask-Key $existing)" -ForegroundColor Green
        $OpenAiApiKey = $existing
    } else {
        Write-Host "  Enter your OpenAI API Key (get from https://platform.openai.com/api-keys):" -ForegroundColor Yellow
        Write-Host "  Press ENTER to skip." -ForegroundColor DarkGray
        $secureKey = Read-Host "  OPENAI_API_KEY" -AsSecureString
        $OpenAiApiKey = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey))
    }
}

# --- Set session environment ---
if ($GeminiApiKey) {
    $env:GEMINI_API_KEY = $GeminiApiKey
    Write-Host "  [SET] GEMINI_API_KEY = $(Mask-Key $GeminiApiKey)" -ForegroundColor Green
}

if ($OpenAiApiKey) {
    $env:OPENAI_API_KEY = $OpenAiApiKey
    Write-Host "  [SET] OPENAI_API_KEY = $(Mask-Key $OpenAiApiKey)" -ForegroundColor Green
}

# --- Persist to user environment ---
if ($Persist) {
    Write-Host ""
    Write-Host "  Persisting to user environment..." -ForegroundColor Cyan
    if ($GeminiApiKey) {
        [System.Environment]::SetEnvironmentVariable('GEMINI_API_KEY', $GeminiApiKey, 'User')
        Write-Host "  [SAVED] GEMINI_API_KEY" -ForegroundColor Green
    }
    if ($OpenAiApiKey) {
        [System.Environment]::SetEnvironmentVariable('OPENAI_API_KEY', $OpenAiApiKey, 'User')
        Write-Host "  [SAVED] OPENAI_API_KEY" -ForegroundColor Green
    }
    Write-Host "  Keys saved. Restart PowerShell or open new session to load permanently." -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "  Environment ready. Run .\scripts\Test-Tools.ps1 to verify tool availability." -ForegroundColor Green
Write-Host ""

# --- Add to PROFILE tip ---
Write-Host "  TIP: To auto-load on shell start, add this to your `$PROFILE:" -ForegroundColor Yellow
Write-Host "  `$env:GEMINI_API_KEY = (Get-Content '~\.gemini-key' -ErrorAction SilentlyContinue)" -ForegroundColor DarkGray
Write-Host "  `$env:OPENAI_API_KEY  = (Get-Content '~\.openai-key'  -ErrorAction SilentlyContinue)" -ForegroundColor DarkGray
Write-Host ""
