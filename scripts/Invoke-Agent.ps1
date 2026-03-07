#Requires -Version 5.1
<#
.SYNOPSIS
    Universal agent dispatcher — routes a step to the correct agent script.
.DESCRIPTION
    Given an agent name and role, loads the appropriate agent script
    from scripts/agents/ and executes it with the provided parameters.
    This is the extensibility point: add new agents by dropping a new
    Invoke-<Name>Agent.ps1 into scripts/agents/.

    Supported agents (auto-discovered from scripts/agents/):
      claude  → Invoke-ClaudeAgent.ps1
      gemini  → Invoke-GeminiAgent.ps1
      codex   → Invoke-CodexAgent.ps1
      mods    → Invoke-ModsAgent.ps1
      <any>   → Invoke-<Any>Agent.ps1 (auto-discovered)

.PARAMETER Agent
    Agent identifier: claude | gemini | codex | mods | <custom>
.PARAMETER Role
    Role name matching a file in RolesDir.
.PARAMETER Task
    Original user task.
.PARAMETER Context
    Accumulated context from previous steps.
.PARAMETER ContextFile
    Optional file to pass as additional context.
.PARAMETER OutputFile
    Where to save this step's output.
.PARAMETER StepConfig
    Hashtable of step-specific config from dispatcher.config.json.
.PARAMETER RolesDir
    Path to roles directory.
.PARAMETER AgentsDir
    Path to agents directory.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$Agent,
    [Parameter(Mandatory)] [string]$Role,
    [Parameter(Mandatory)] [string]$Task,
    [Parameter()]          [string]$Context = "",
    [Parameter()]          [string]$ContextFile = "",
    [Parameter(Mandatory)] [string]$OutputFile,
    [Parameter()]          [hashtable]$StepConfig = @{},
    [Parameter()]          [string]$RolesDir = ".claude\roles",
    [Parameter()]          [string]$AgentsDir = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = $PSScriptRoot
if (-not $AgentsDir) {
    $AgentsDir = Join-Path $scriptDir "agents"
}

# ── Discover agent script ──────────────────────────────────────
# Naming convention: Invoke-<PascalCase(agent)>Agent.ps1
$agentPascal = (Get-Culture).TextInfo.ToTitleCase($Agent.ToLower())
$agentScript = Join-Path $AgentsDir "Invoke-${agentPascal}Agent.ps1"

if (-not (Test-Path $agentScript)) {
    throw "Agent script not found: $agentScript`nAdd 'Invoke-${agentPascal}Agent.ps1' to $AgentsDir to register this agent."
}

Write-Host "  [Invoke-Agent] $Agent → $Role" -ForegroundColor DarkCyan

# ── Build common parameters ────────────────────────────────────
$agentParams = @{
    Role       = $Role
    Task       = $Task
    Context    = $Context
    OutputFile = $OutputFile
    RolesDir   = $RolesDir
}

# ── Merge step-specific config into params ─────────────────────
# Config keys map to agent parameters:
#   model    → -Model    (gemini)
#   language → -Language (codex)
#   retries  → -MaxRetries (gemini, codex)
$paramMap = @{
    model    = 'Model'
    language = 'Language'
    retries  = 'MaxRetries'
    timeout  = 'TimeoutSec'
}

foreach ($key in $StepConfig.Keys) {
    $mappedParam = $paramMap[$key]
    if ($mappedParam) {
        $agentParams[$mappedParam] = $StepConfig[$key]
    }
}

# Add ContextFile only for agents that accept it
if ($ContextFile -and $Agent -in @('gemini', 'codex', 'mods')) {
    $agentParams['ContextFile'] = $ContextFile
}
if ($ContextFile -and $Agent -eq 'mods') {
    $agentParams['InputFile'] = $ContextFile
    $agentParams.Remove('ContextFile') | Out-Null
}

# ── Execute agent ──────────────────────────────────────────────
try {
    $result = & $agentScript @agentParams
    return $result
} catch {
    Write-Host "  [ERROR] Agent '$Agent' role '$Role' failed: $_" -ForegroundColor Red
    throw
}
