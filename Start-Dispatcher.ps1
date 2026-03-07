#Requires -Version 5.1
<#
.SYNOPSIS
    Bootstrap script — запуск Claude Code с диспетчером в один клик.
.DESCRIPTION
    Настраивает окружение и запускает Claude Code CLI с загруженным диспетчером.
    Запускай этот скрипт вместо просто 'claude' при работе с проектом.
.EXAMPLE
    .\Start-Dispatcher.ps1
    .\Start-Dispatcher.ps1 -Task "Сразу дай задачу при запуске"
#>
param(
    [string]$Task = ""
)

Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   CLAUDE CODE — PLANNER/DISPATCHER MODE           ║" -ForegroundColor Cyan
Write-Host "║   Gemini CLI + Codex CLI + Mods — PowerShell      ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Check execution policy
$policy = Get-ExecutionPolicy -Scope CurrentUser
if ($policy -in @('Restricted', 'AllSigned')) {
    Write-Host "[!] Execution policy '$policy' may block scripts." -ForegroundColor Yellow
    Write-Host "    Fix: Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned" -ForegroundColor DarkGray
    Write-Host ""
}

# Quick tool check
Write-Host "Checking tools..." -ForegroundColor DarkGray
& "$PSScriptRoot\scripts\Test-Tools.ps1"

# Check API keys
$missingKeys = @()
if (-not $env:GEMINI_API_KEY)  { $missingKeys += "GEMINI_API_KEY" }
if (-not $env:OPENAI_API_KEY)  { $missingKeys += "OPENAI_API_KEY" }

if ($missingKeys) {
    Write-Host ""
    Write-Host "[!] Missing API keys: $($missingKeys -join ', ')" -ForegroundColor Yellow
    Write-Host "    Run: .\scripts\Set-DispatcherEnv.ps1 -Persist" -ForegroundColor DarkGray
    Write-Host ""
}

# Launch Claude Code
Write-Host ""
Write-Host "Launching Claude Code in dispatcher mode..." -ForegroundColor Green
Write-Host ""
Write-Host "Available commands in Claude Code interface:" -ForegroundColor Cyan
Write-Host "  /dispatch <task>   — auto-route to best tool" -ForegroundColor White
Write-Host "  /gemini <task>     — delegate to Gemini CLI" -ForegroundColor White
Write-Host "  /codex <task>      — delegate to Codex CLI" -ForegroundColor White
Write-Host "  /review <file>     — code review via Mods" -ForegroundColor White
Write-Host "  /pipeline <task>   — full pipeline" -ForegroundColor White
Write-Host "  /tools             — check tool availability" -ForegroundColor White
Write-Host ""

if ($Task) {
    # Launch with immediate task
    & claude -p $Task
} else {
    # Interactive mode
    & claude
}
