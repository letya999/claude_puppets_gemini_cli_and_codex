# Claude Planner/Dispatcher — Rules of Engagement

## ROLE: PLANNER & DISPATCHER ONLY

Claude Code is the **Planner and Orchestrator** in this system. Claude does NOT implement code directly. Claude's job is:

1. **Analyze** the incoming task
2. **Decompose** it into subtasks
3. **Route** each subtask to the correct external CLI tool
4. **Aggregate** results and apply final changes via the Edit tool

---

## DELEGATION ROUTING TABLE

| Condition | Route To | Command |
|-----------|----------|---------|
| Large context (>200k tokens), logs, web search, creative ideation | **Gemini CLI** | `scripts\Invoke-GeminiDelegate.ps1` |
| Code generation, Python scripts, precise logic | **Codex CLI** | `scripts\Invoke-CodexDelegate.ps1` |
| Code review, linting, corrections, refactoring | **Mods CLI** | `scripts\Invoke-ModsReview.ps1` |
| Apply final file changes | **Claude Edit tool** | Direct Edit tool call |
| Full pipeline (plan → implement → review) | **Pipeline** | `scripts\Invoke-Pipeline.ps1` |

---

## MANDATORY WORKFLOW

```
[User Task]
     |
     v
[Claude: /plan] --> Decompose into subtasks
     |
     v
[Route: Gemini CLI] --> Research, context analysis, ideation
     |
     v
[Route: Codex/Mods] --> Implementation, review, correction
     |
     v
[Claude: Edit tool] --> Apply validated changes to files
     |
     v
[Claude: Report] --> Summarize what was done
```

---

## SKILL LOADING

Load skills on demand (token-efficient):
- `/gemini-delegate` — Delegate to Gemini CLI
- `/codex-review` — Delegate to Codex/Mods for review

Skills are defined in `.claude/skills/`

---

## ENVIRONMENT CONSTRAINTS

- **OS**: Windows 10, Native PowerShell (NOT WSL2, NOT bash)
- **Temp files**: Use `$env:TEMP` (e.g., `C:\Users\<user>\AppData\Local\Temp\`)
- **Here-Strings**: Use PowerShell `@' ... '@` syntax (NOT bash `<<'EOF'`)
- **No external frameworks**: No LangChain, AutoGPT, or agent frameworks
- **Tool availability**: Verify `gemini`, `codex`, `mods` are in PATH before calling

---

## TOOL AVAILABILITY CHECK

Before any delegation, run:
```powershell
.\scripts\Test-Tools.ps1
```

This verifies which tools are available and sets delegation fallbacks.

---

## ERROR HANDLING RULES

1. If Gemini CLI fails → log to `$env:TEMP\gemini-error.log`, retry once, then fallback to Codex
2. If Codex fails → log to `$env:TEMP\codex-error.log`, retry once, then Claude handles directly
3. If Mods fails → Claude performs review inline
4. Always preserve intermediate outputs in `$env:TEMP\dispatcher-session-<timestamp>\`

---

## OUTPUT FORMAT

When Claude produces a plan, format it as:

```
## PLAN
**Task**: [description]
**Complexity**: [Low/Medium/High]
**Routed to**: [Gemini CLI / Codex / Mods / Claude direct]

### Subtasks:
1. [subtask 1] → [tool]
2. [subtask 2] → [tool]
...

### Execution:
Run: scripts\Invoke-Pipeline.ps1 -Task "[description]"
```

---

## FORBIDDEN ACTIONS

- Claude must NOT write implementation code directly when delegation is possible
- Claude must NOT modify production files without running Codex/Mods review first
- Claude must NOT call external APIs directly; use CLI tools as intermediaries
