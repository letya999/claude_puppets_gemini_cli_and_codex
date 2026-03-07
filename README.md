# Claude Planner/Dispatcher — PowerShell Pipeline

A native Windows PowerShell system that transforms Claude Code into a **Planner/Dispatcher** that delegates tasks to external CLI tools (Gemini CLI, Codex CLI, Mods).

No LangChain, no WSL2, no external frameworks — just PowerShell and CLI tools.

---

## Architecture

```
[You] --task--> [Claude Code: Planner]
                      |
          +-----------+-----------+
          |           |           |
    [Gemini CLI]  [Codex CLI]  [Mods CLI]
    (research)   (implement)   (review)
          |           |           |
          +-----------+-----------+
                      |
               [Claude Code: Edit tool]
                      |
               [Final file changes]
```

### Role Assignments

| Role | Tool | Use When |
|------|------|----------|
| **Planner** | Claude Code | Always — decomposes tasks, routes, applies final changes |
| **Researcher / Large Context** | Gemini CLI | >50k tokens, logs, analysis, creative ideation |
| **Code Implementer** | Codex CLI | Precise code generation, algorithms, Python |
| **Reviewer / Corrector** | Mods CLI | Code review, security audit, bug fixing |

---

## Prerequisites

### Install CLI Tools

```powershell
# Gemini CLI (Google)
npm install -g @google/generative-ai-cli
# OR via winget
winget install Google.GeminiCLI

# Codex CLI (OpenAI)
npm install -g @openai/codex

# Mods (charmbracelet)
winget install charmbracelet.mods
# OR via Go
go install github.com/charmbracelet/mods@latest
```

### Set API Keys

```powershell
# One-time setup (interactive, with optional persistence)
.\scripts\Set-DispatcherEnv.ps1 -Persist

# Or set manually for current session
$env:GEMINI_API_KEY = "AIza..."
$env:OPENAI_API_KEY = "sk-..."
```

### Verify Installation

```powershell
.\scripts\Test-Tools.ps1
```

Expected output:
```
=== Claude Dispatcher — Tool Availability Check ===

  [OK]  Gemini     -> C:\Users\user\AppData\Roaming\npm\gemini.cmd
  [OK]  Codex      -> C:\Users\user\AppData\Roaming\npm\codex.cmd
  [OK]  Mods       -> C:\Program Files\mods\mods.exe
```

---

## Quick Start — One Click Pipeline

```powershell
# Full auto pipeline (detects mode automatically)
.\scripts\Invoke-Pipeline.ps1 -Task "Create a FastAPI endpoint for user registration with JWT auth"

# Research mode: Gemini -> Codex -> Mods
.\scripts\Invoke-Pipeline.ps1 -Task "Design and implement a caching layer" -Mode research

# Code mode: Codex -> Mods review
.\scripts\Invoke-Pipeline.ps1 -Task "Write a CSV parser with validation" -Mode code -Language python

# Review mode: Mods only
.\scripts\Invoke-Pipeline.ps1 -Task "Security audit" -ContextFile ".\src\auth.py" -Mode review
```

---

## Individual Tool Scripts

### Delegate to Gemini CLI

```powershell
# Research / large context analysis
.\scripts\Invoke-GeminiDelegate.ps1 `
    -Task "Analyze this log file and identify the root cause of the crashes" `
    -ContextFile "C:\logs\application.log"

# Creative ideation
.\scripts\Invoke-GeminiDelegate.ps1 `
    -Task "Brainstorm 5 different database schema designs for a social media app" `
    -Context "Requirements: follows, posts, likes, comments, DMs"
```

### Delegate to Codex CLI

```powershell
# Code generation
.\scripts\Invoke-CodexDelegate.ps1 `
    -Task "Write a function to validate and sanitize user input for SQL queries" `
    -Language "python"

# Refactoring existing code
.\scripts\Invoke-CodexDelegate.ps1 `
    -Task "Refactor to use async/await and add proper type hints" `
    -ContextFile ".\src\database.py"
```

### Delegate to Mods for Review

```powershell
# Full review with automatic fixes
.\scripts\Invoke-ModsReview.ps1 -InputFile ".\src\auth.py" -ApplyFixes

# Security-focused review
.\scripts\Invoke-ModsReview.ps1 -InputFile ".\src\api.py" -ReviewType security

# Review Codex output before applying
$result = .\scripts\Invoke-CodexDelegate.ps1 -Task "Write auth module"
.\scripts\Invoke-ModsReview.ps1 -InputFile $result.OutputFile -ApplyFixes
```

---

## Session Management

```powershell
# Start a named session (organizes all outputs)
$session = .\scripts\New-DispatcherSession.ps1 -SessionName "feature-auth"

# View session results
.\scripts\Get-SessionResults.ps1 -ShowLatest

# View specific step output
.\scripts\Get-SessionResults.ps1 -StepName "gemini"

# Copy final output to clipboard
Get-Content "$($session.SessionDir)\codex-implementation.txt" | Set-Clipboard
```

---

## PowerShell Here-String Patterns

### Static prompt (no variable expansion)

```powershell
$prompt = @'
Analyze the following code and identify:
1. Security vulnerabilities
2. Performance issues
3. Missing error handling

Return findings as JSON.
'@

$prompt | gemini --model gemini-2.5-pro
```

### Dynamic prompt (with variable expansion)

```powershell
$language = "python"
$task = "add input validation"
$file = Get-Content ".\src\api.py" -Raw

$prompt = @"
Task: $task
Language: $language

Code to modify:
$file

Return only the modified code, no explanations.
"@

$prompt | codex
```

### Chained pipeline (manual)

```powershell
# Step 1: Research with Gemini
$research = .\scripts\Invoke-GeminiDelegate.ps1 `
    -Task "What are the best practices for rate limiting in FastAPI?" `
    -OutputFile "$env:TEMP\research.txt"

# Step 2: Implement with Codex (using research as context)
$impl = .\scripts\Invoke-CodexDelegate.ps1 `
    -Task "Implement rate limiting middleware for FastAPI" `
    -Context (Get-Content $research.OutputFile -Raw)

# Step 3: Review with Mods
$review = .\scripts\Invoke-ModsReview.ps1 `
    -InputFile $impl.OutputFile `
    -ReviewType security `
    -ApplyFixes

# Step 4: Claude reads and applies via Edit tool
Get-Content $review.OutputFile
```

---

## Claude Code Skills

Load skills in Claude Code chat with `/skill`:

| Skill | Load Command | Use For |
|-------|-------------|---------|
| Gemini Delegation | `/gemini-delegate` | Large context, research |
| Codex Review | `/codex-review` | Code generation + review |

Skills are defined in `.claude/skills/` and loaded on-demand (token-efficient).

---

## File Structure

```
.
├── CLAUDE.md                          # Dispatcher rules for Claude Code
├── README.md                          # This file
├── .claude/
│   └── skills/
│       ├── gemini-delegate/
│       │   └── SKILL.md              # Gemini delegation skill
│       └── codex-review/
│           └── SKILL.md              # Codex + Mods review skill
└── scripts/
    ├── Test-Tools.ps1                 # Check tool availability
    ├── Set-DispatcherEnv.ps1          # Configure API keys
    ├── New-DispatcherSession.ps1      # Initialize session
    ├── Get-SessionResults.ps1         # View session outputs
    ├── Invoke-GeminiDelegate.ps1      # Delegate to Gemini CLI
    ├── Invoke-CodexDelegate.ps1       # Delegate to Codex CLI
    ├── Invoke-ModsReview.ps1          # Delegate to Mods CLI
    └── Invoke-Pipeline.ps1            # Full orchestration pipeline
```

---

## Delegation Decision Guide

```
Is the task primarily RESEARCH / ANALYSIS?
    YES -> Invoke-GeminiDelegate.ps1
    NO  -> Is it CODE GENERATION / IMPLEMENTATION?
               YES -> Invoke-CodexDelegate.ps1
               NO  -> Is it CODE REVIEW / SECURITY AUDIT?
                           YES -> Invoke-ModsReview.ps1
                           NO  -> Claude handles directly (Edit tool)

Is context > 50k tokens OR involves large log files?
    YES -> Always use Invoke-GeminiDelegate.ps1 (2M token window)

Need full pipeline automatically?
    -> Invoke-Pipeline.ps1 -Mode auto
```

---

## Error Handling

All scripts implement:
- **Retry with exponential backoff** (2s, 4s... for up to N retries)
- **Fallback routing** (Gemini fails → try Codex; Mods fails → Claude inline)
- **Session logging** to `$env:TEMP\dispatcher-<session>\session.log`
- **Error logs** per tool: `gemini-error.log`, `codex-error.log`, `mods-error.log`

Common fixes:

```powershell
# "gemini not found"
npm install -g @google/generative-ai-cli

# "API key not set"
$env:GEMINI_API_KEY = "AIza..."  # set for current session
# OR run:
.\scripts\Set-DispatcherEnv.ps1 -Persist

# "Access denied running .ps1"
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned

# View recent errors
Get-Content "$env:TEMP\dispatcher-*\*-error.log" -ErrorAction SilentlyContinue
```

---

## Design Principles

1. **Claude = Planner only** — never implements code directly when delegation is possible
2. **Token efficiency** — skills loaded on-demand, intermediate results cached to disk
3. **Windows-native** — `$env:TEMP` not `/tmp/`, Here-Strings not heredoc, no bash/WSL2
4. **Graceful degradation** — if a tool fails, pipeline continues with available tools
5. **Auditability** — every step's input/output saved to timestamped session directory
