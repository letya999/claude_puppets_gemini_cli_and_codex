#Requires -Version 5.1
<#
.SYNOPSIS
    Central auto-router — single entry point for all dispatcher tasks.
.DESCRIPTION
    Analyzes the task, detects context size, classifies intent,
    and automatically routes to the correct tool:
      - Gemini CLI  : research, large context, analysis
      - Codex CLI   : code generation, precise implementation
      - Mods CLI    : review, security, refactor
      - Pipeline    : complex multi-step tasks

    Designed to be called directly from Claude Code's Bash tool.
    Claude calls this ONE script; it does all the routing.

.PARAMETER Task
    The task description (required).
.PARAMETER ContextFile
    Optional file to include as context (auto-detects size).
.PARAMETER Force
    Force a specific tool: 'gemini', 'codex', 'mods', 'pipeline'
.PARAMETER Language
    Target language for code generation. Default: auto-detect.
.PARAMETER DryRun
    Show routing decision without executing.
.EXAMPLE
    # From Claude Code Bash tool:
    powershell -File scripts\Invoke-Router.ps1 -Task "Implement JWT auth for FastAPI"

    # Force tool:
    powershell -File scripts\Invoke-Router.ps1 -Task "Analyze logs" -Force gemini

    # With context file:
    powershell -File scripts\Invoke-Router.ps1 -Task "Refactor this" -ContextFile ".\src\auth.py"

    # Dry run (see routing without executing):
    powershell -File scripts\Invoke-Router.ps1 -Task "Write a parser" -DryRun
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Task,

    [Parameter()]
    [string]$ContextFile = "",

    [Parameter()]
    [ValidateSet('', 'gemini', 'codex', 'mods', 'pipeline')]
    [string]$Force = "",

    [Parameter()]
    [string]$Language = "",

    [Parameter()]
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot

# ============================================================
# STEP 1: Check tool availability
# ============================================================
Write-Host ""
Write-Host "╔══════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     CLAUDE DISPATCHER — AUTO ROUTER          ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Task: $Task" -ForegroundColor White

$tools = @{ Gemini = $false; Codex = $false; Mods = $false }
try {
    $tools = & "$scriptDir\Test-Tools.ps1" 2>$null
} catch { }

# ============================================================
# STEP 2: Analyze context size
# ============================================================
$contextSizeKb = 0
$contextContent = ""
if ($ContextFile -and (Test-Path $ContextFile)) {
    $fileInfo = Get-Item $ContextFile
    $contextSizeKb = [math]::Round($fileInfo.Length / 1KB, 1)
    $contextContent = Get-Content $ContextFile -Raw -Encoding UTF8
    Write-Host "  Context file: $ContextFile ($contextSizeKb KB)" -ForegroundColor DarkGray
}

# Estimate token count (rough: 1 token ≈ 4 chars)
$estimatedTokens = [math]::Round(($Task.Length + $contextContent.Length) / 4)
$isLargeContext = $contextSizeKb -gt 100 -or $estimatedTokens -gt 50000

# ============================================================
# STEP 3: Classify task intent
# ============================================================
$taskLower = $Task.ToLower()

$researchSignals = @('analyze', 'research', 'explain', 'summarize', 'compare', 'what is',
                     'анализ', 'исследуй', 'объясни', 'сравни', 'суммаризируй',
                     'log', 'лог', 'error pattern', 'architecture', 'архитектур')
$codeSignals     = @('implement', 'write', 'create', 'build', 'generate', 'make', 'add',
                     'напиши', 'реализуй', 'создай', 'сделай', 'добавь',
                     'function', 'class', 'script', 'api', 'endpoint', 'module',
                     'функцию', 'класс', 'скрипт', 'модуль')
$reviewSignals   = @('review', 'check', 'audit', 'security', 'fix', 'refactor', 'lint',
                     'проверь', 'аудит', 'безопасност', 'исправь', 'рефактор',
                     'bug', 'баг', 'vulnerability', 'уязвимост')

$researchScore = ($researchSignals | Where-Object { $taskLower -like "*$_*" }).Count
$codeScore     = ($codeSignals     | Where-Object { $taskLower -like "*$_*" }).Count
$reviewScore   = ($reviewSignals   | Where-Object { $taskLower -like "*$_*" }).Count

# ============================================================
# STEP 4: Routing decision
# ============================================================
$route = "codex"  # default

if ($Force) {
    $route = $Force
    Write-Host "  Route: $route (forced)" -ForegroundColor Yellow
} elseif ($isLargeContext -or ($researchScore -gt 0 -and $codeScore -eq 0)) {
    $route = "gemini"
} elseif ($reviewScore -gt 0 -and $codeScore -eq 0) {
    $route = "mods"
} elseif ($codeScore -gt 0 -and $reviewScore -gt 0) {
    $route = "pipeline"
} elseif ($codeScore -gt 0) {
    $route = "codex"
} elseif ($researchScore -gt 0) {
    $route = "gemini"
}

# Fallback if preferred tool unavailable
$originalRoute = $route
if ($route -eq "gemini" -and -not $tools.Gemini) {
    $route = if ($tools.Codex) { "codex" } else { "claude-direct" }
    Write-Host "  [FALLBACK] Gemini unavailable → $route" -ForegroundColor Yellow
} elseif ($route -eq "codex" -and -not $tools.Codex) {
    $route = if ($tools.Gemini) { "gemini" } else { "claude-direct" }
    Write-Host "  [FALLBACK] Codex unavailable → $route" -ForegroundColor Yellow
} elseif ($route -eq "mods" -and -not $tools.Mods) {
    Write-Host "  [FALLBACK] Mods unavailable → Claude inline review" -ForegroundColor Yellow
    $route = "claude-direct"
}

# Detect language
if (-not $Language) {
    $Language = switch -Regex ($taskLower) {
        'python|fastapi|django|flask|pandas'      { 'python'; break }
        'typescript|react|next\.?js|angular'      { 'typescript'; break }
        'javascript|node|express|vue'             { 'javascript'; break }
        'powershell|ps1|powershell'                     { 'powershell'; break }
        'go|golang'                               { 'go'; break }
        'rust|cargo'                              { 'rust'; break }
        'c#|csharp|dotnet|\.net|asp\.net'        { 'csharp'; break }
        default                                   { 'python' }
    }
}

# ============================================================
# DISPLAY PLAN
# ============================================================
$routeDisplay = @{
    "gemini"       = "Gemini CLI  (large context, research)"
    "codex"        = "Codex CLI   (code generation)"
    "mods"         = "Mods CLI    (review & correction)"
    "pipeline"     = "Pipeline    (full: Codex + Mods)"
    "claude-direct"= "Claude      (direct, no delegation)"
}

Write-Host ""
Write-Host "  ┌─ ROUTING DECISION ──────────────────────────" -ForegroundColor Cyan
Write-Host ("  │  Route:    {0}" -f $routeDisplay[$route]) -ForegroundColor Green
Write-Host ("  │  Language: {0}" -f $Language) -ForegroundColor DarkGray
Write-Host ("  │  Signals:  research={0} code={1} review={2}" -f $researchScore, $codeScore, $reviewScore) -ForegroundColor DarkGray
Write-Host ("  │  Context:  {0} KB / ~{1:N0} tokens" -f $contextSizeKb, $estimatedTokens) -ForegroundColor DarkGray
Write-Host "  └─────────────────────────────────────────────" -ForegroundColor Cyan
Write-Host ""

if ($DryRun) {
    Write-Host "  [DRY RUN] Would execute: $route" -ForegroundColor Yellow
    Write-Host "  To run: Remove -DryRun flag" -ForegroundColor DarkGray
    exit 0
}

# ============================================================
# STEP 5: EXECUTE
# ============================================================
$result = $null

switch ($route) {

    "gemini" {
        Write-Host "  Executing: Gemini CLI delegation..." -ForegroundColor Cyan
        $result = & "$scriptDir\Invoke-GeminiDelegate.ps1" `
            -Task $Task `
            -ContextFile $ContextFile `
            -MaxRetries 1
    }

    "codex" {
        Write-Host "  Executing: Codex CLI delegation..." -ForegroundColor Magenta
        $result = & "$scriptDir\Invoke-CodexDelegate.ps1" `
            -Task $Task `
            -ContextFile $ContextFile `
            -Language $Language `
            -MaxRetries 1
    }

    "mods" {
        Write-Host "  Executing: Mods CLI review..." -ForegroundColor Blue
        $reviewTarget = if ($ContextFile) { $ContextFile } else { "" }
        if (-not $reviewTarget) {
            Write-Host "  [ERROR] Mods review requires -ContextFile. Specify the file to review." -ForegroundColor Red
            Write-Host "  Falling back to Claude direct..." -ForegroundColor Yellow
        } else {
            $result = & "$scriptDir\Invoke-ModsReview.ps1" `
                -InputFile $reviewTarget `
                -ReviewType "full" `
                -Language $Language `
                -ApplyFixes
        }
    }

    "pipeline" {
        Write-Host "  Executing: Full pipeline (Codex + Mods)..." -ForegroundColor Yellow
        $result = & "$scriptDir\Invoke-Pipeline.ps1" `
            -Task $Task `
            -Mode "code" `
            -ContextFile $ContextFile `
            -Language $Language
    }

    "claude-direct" {
        Write-Host "  No delegation tools available." -ForegroundColor Yellow
        Write-Host "  Claude should handle this task directly using the Edit tool." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Install tools:" -ForegroundColor DarkGray
        Write-Host "    npm install -g @google/generative-ai-cli @openai/codex" -ForegroundColor DarkGray
        Write-Host "    winget install charmbracelet.mods" -ForegroundColor DarkGray
        exit 0
    }
}

# ============================================================
# STEP 6: REPORT — tell Claude what to do next
# ============================================================
Write-Host ""
Write-Host "╔══════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║     ROUTER COMPLETE — ACTION REQUIRED        ║" -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""

if ($result -and $result.OutputFile -and (Test-Path $result.OutputFile)) {
    Write-Host "  Output file: $($result.OutputFile)" -ForegroundColor White
    Write-Host ""
    Write-Host "  CLAUDE: Read this file and apply changes via Edit tool:" -ForegroundColor Yellow
    Write-Host "  > Get-Content '$($result.OutputFile)' | Set-Clipboard" -ForegroundColor White
    Write-Host ""

    # Print the output summary for Claude to consume immediately
    Write-Host "--- GENERATED OUTPUT (for Claude to apply) ---" -ForegroundColor DarkCyan
    Get-Content $result.OutputFile -Encoding UTF8 | Select-Object -First 100
    if ((Get-Content $result.OutputFile).Count -gt 100) {
        Write-Host "  ... [truncated, full output in: $($result.OutputFile)]" -ForegroundColor DarkGray
    }
    Write-Host "--- END OUTPUT ---" -ForegroundColor DarkCyan
}

return $result
