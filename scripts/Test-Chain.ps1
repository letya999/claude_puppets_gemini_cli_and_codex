#Requires -Version 5.1
<#
.SYNOPSIS
    Validates the chain configuration and tests workability without API calls.
.DESCRIPTION
    Performs a comprehensive check of the dispatcher system:
    1. Config JSON validity
    2. All chain steps reference existing role files
    3. All chain steps reference existing agent scripts
    4. All CLI tools are in PATH
    5. API keys are set (warns but doesn't fail)
    6. DryRun execution of the full chain
    7. Script syntax validation for all .ps1 files

    Exit codes: 0=all pass, 1=errors found
.PARAMETER ConfigPath
    Path to dispatcher config. Default: .claude\dispatcher.config.json
.PARAMETER SkipDryRun
    Skip the full dry-run execution test.
.PARAMETER Fix
    Attempt to auto-fix common issues (create missing role stubs).
.EXAMPLE
    pwsh -File scripts\Test-Chain.ps1
    pwsh -File scripts\Test-Chain.ps1 -Fix
#>
[CmdletBinding()]
param(
    [string] $ConfigPath  = ".claude\dispatcher.config.json",
    [switch] $SkipDryRun,
    [switch] $Fix
)

$scriptDir  = $PSScriptRoot
$projectDir = Split-Path $scriptDir -Parent
$rolesDir   = Join-Path $projectDir ".claude\roles"
$agentsDir  = Join-Path $scriptDir "agents"

$pass = 0
$warn = 0
$fail = 0

function OK   ([string]$msg) { Write-Host "  [PASS] $msg" -ForegroundColor Green;  $script:pass++ }
function WARN ([string]$msg) { Write-Host "  [WARN] $msg" -ForegroundColor Yellow; $script:warn++ }
function FAIL ([string]$msg) { Write-Host "  [FAIL] $msg" -ForegroundColor Red;    $script:fail++ }
function HEAD ([string]$msg) {
    Write-Host ""
    Write-Host "  ── $msg ──────────────────────────────────────────" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║   CHAIN WORKABILITY TEST                             ║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# ════════════════════════════════════════════════════════════════
# TEST 1: Config file exists and is valid JSON
# ════════════════════════════════════════════════════════════════
HEAD "1. Config validation"

if (-not (Test-Path $ConfigPath)) {
    FAIL "Config not found: $ConfigPath"
    exit 1
}
OK "Config file exists: $ConfigPath"

$config = $null
try {
    $raw    = Get-Content $ConfigPath -Raw -Encoding UTF8
    $config = $raw | ConvertFrom-Json
    OK "Config is valid JSON"
} catch {
    FAIL "Config JSON parse error: $_"
    exit 1
}

if (-not $config.chain -or $config.chain.Count -eq 0) {
    FAIL "Config has no chain steps"
    exit 1
}
OK "Chain has $($config.chain.Count) step(s)"

# ════════════════════════════════════════════════════════════════
# TEST 2: Each chain step has agent + role
# ════════════════════════════════════════════════════════════════
HEAD "2. Chain step structure"

$stepNum = 0
foreach ($step in $config.chain) {
    $stepNum++
    if (-not $step.agent) { FAIL "Step $stepNum missing 'agent' field" } else { OK "Step $stepNum: agent='$($step.agent)'" }
    if (-not $step.role)  { FAIL "Step $stepNum missing 'role' field"  } else { OK "Step $stepNum: role='$($step.role)'" }
}

# ════════════════════════════════════════════════════════════════
# TEST 3: Role files exist in .claude/roles/
# ════════════════════════════════════════════════════════════════
HEAD "3. Role definitions"

$usedRoles = $config.chain | Select-Object -ExpandProperty role -Unique
foreach ($role in $usedRoles) {
    $rolePath = Join-Path $rolesDir "$role.md"
    if (Test-Path $rolePath) {
        # Check it has content
        $content = Get-Content $rolePath -Raw
        if ($content.Length -gt 50) {
            OK "Role '$role' → $rolePath"
        } else {
            WARN "Role '$role' exists but seems empty"
        }
    } else {
        FAIL "Role '$role' not found: $rolePath"
        if ($Fix) {
            # Create stub
            "# Role: $role`n`nTODO: Define this role." | Out-File $rolePath -Encoding UTF8
            WARN "  Created stub: $rolePath"
        }
    }
}

# Check fallback roles too
foreach ($step in $config.chain) {
    if ($step.fallback -and $step.fallback.role) {
        $fbRole = $step.fallback.role
        $fbPath = Join-Path $rolesDir "$fbRole.md"
        if (Test-Path $fbPath) {
            OK "Fallback role '$fbRole' → exists"
        } else {
            WARN "Fallback role '$fbRole' not found (non-critical)"
        }
    }
}

# ════════════════════════════════════════════════════════════════
# TEST 4: Agent scripts exist in scripts/agents/
# ════════════════════════════════════════════════════════════════
HEAD "4. Agent scripts"

$usedAgents = $config.chain | Select-Object -ExpandProperty agent -Unique
foreach ($agent in $usedAgents) {
    $pascal      = (Get-Culture).TextInfo.ToTitleCase($agent.ToLower())
    $agentScript = Join-Path $agentsDir "Invoke-${pascal}Agent.ps1"
    if (Test-Path $agentScript) {
        OK "Agent '$agent' → $agentScript"
    } else {
        FAIL "Agent script not found: $agentScript"
        WARN "  To add: create scripts\agents\Invoke-${pascal}Agent.ps1"
    }
}

# ════════════════════════════════════════════════════════════════
# TEST 5: CLI tools in PATH
# ════════════════════════════════════════════════════════════════
HEAD "5. CLI tool availability"

$toolMap = @{
    gemini = 'gemini'
    codex  = 'codex'
    mods   = 'mods'
    claude = 'claude'
}

$agentsNeedingTools = $usedAgents | Where-Object { $_ -ne 'claude' }
foreach ($agent in $agentsNeedingTools) {
    $cmd = $toolMap[$agent]
    if ($cmd) {
        $found = Get-Command $cmd -ErrorAction SilentlyContinue
        if ($found) {
            OK "Tool '$cmd' found: $($found.Source)"
        } else {
            FAIL "Tool '$cmd' not in PATH (needed by agent '$agent')"
        }
    }
}

# Claude CLI check
$claudeInChain = $usedAgents -contains 'claude'
if ($claudeInChain) {
    $claudeFound = Get-Command 'claude' -ErrorAction SilentlyContinue
    if ($claudeFound) {
        OK "claude CLI found: $($claudeFound.Source)"
    } else {
        WARN "claude CLI not in PATH — sub-agent steps will use fallback"
    }
}

# ════════════════════════════════════════════════════════════════
# TEST 6: API keys
# ════════════════════════════════════════════════════════════════
HEAD "6. API keys"

$keyChecks = @(
    @{ Agent='gemini'; Key='GEMINI_API_KEY' },
    @{ Agent='codex';  Key='OPENAI_API_KEY' },
    @{ Agent='claude'; Key='ANTHROPIC_API_KEY' }
)

foreach ($kc in $keyChecks) {
    if ($usedAgents -contains $kc.Agent) {
        $val = [System.Environment]::GetEnvironmentVariable($kc.Key)
        if ($val -and $val.Length -gt 8) {
            $masked = $val.Substring(0,4) + "****" + $val.Substring($val.Length-4)
            OK "$($kc.Key) = $masked"
        } else {
            WARN "$($kc.Key) not set (agent '$($kc.Agent)' will fail at runtime)"
        }
    }
}

# ════════════════════════════════════════════════════════════════
# TEST 7: PowerShell syntax check on all .ps1 files
# ════════════════════════════════════════════════════════════════
HEAD "7. Script syntax validation"

$ps1Files = Get-ChildItem -Path $scriptDir -Filter "*.ps1" -Recurse
$ps1Files += Get-ChildItem -Path (Join-Path $projectDir ".claude\hooks") -Filter "*.ps1" -ErrorAction SilentlyContinue

foreach ($f in $ps1Files) {
    $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile(
        $f.FullName, [ref]$null, [ref]$errors)
    if ($errors.Count -eq 0) {
        OK "Syntax OK: $($f.Name)"
    } else {
        FAIL "Syntax error in $($f.Name):"
        $errors | ForEach-Object { Write-Host "       Line $($_.Extent.StartLineNumber): $($_.Message)" -ForegroundColor Red }
    }
}

# ════════════════════════════════════════════════════════════════
# TEST 8: Dry-run execution
# ════════════════════════════════════════════════════════════════
if (-not $SkipDryRun) {
    HEAD "8. Dry-run chain execution"

    try {
        $dryResult = & "$scriptDir\Invoke-Chain.ps1" `
            -Task "TEST: write a hello world function" `
            -ConfigPath $ConfigPath `
            -DryRun

        if ($dryResult.Success) {
            OK "Dry-run completed successfully"
            OK "Session created: $($dryResult.SessionDir)"
        } else {
            FAIL "Dry-run reported failures"
        }
    } catch {
        FAIL "Dry-run threw exception: $_"
    }
}

# ════════════════════════════════════════════════════════════════
# SUMMARY
# ════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "  ════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  RESULTS:  PASS=$pass  WARN=$warn  FAIL=$fail" -ForegroundColor $(if ($fail -gt 0) { 'Red' } elseif ($warn -gt 0) { 'Yellow' } else { 'Green' })
Write-Host "  ════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

if ($fail -eq 0 -and $warn -eq 0) {
    Write-Host "  Chain is ready to use." -ForegroundColor Green
} elseif ($fail -eq 0) {
    Write-Host "  Chain is functional. Resolve warnings before production use." -ForegroundColor Yellow
} else {
    Write-Host "  Fix the FAIL items before running the chain." -ForegroundColor Red
    Write-Host "  Quick fixes:" -ForegroundColor Yellow
    Write-Host "    API keys:   pwsh -File scripts\Set-DispatcherEnv.ps1 -Persist" -ForegroundColor DarkGray
    Write-Host "    Gemini CLI: npm install -g @google/generative-ai-cli" -ForegroundColor DarkGray
    Write-Host "    Codex CLI:  npm install -g @openai/codex" -ForegroundColor DarkGray
    Write-Host "    Mods CLI:   winget install charmbracelet.mods" -ForegroundColor DarkGray
}

Write-Host ""
exit $(if ($fail -gt 0) { 1 } else { 0 })
