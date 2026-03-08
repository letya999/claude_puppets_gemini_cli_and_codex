# Skill: codex-review

## TRIGGER
Use this skill when:
- User asks to implement, write, or generate code
- A task requires precise algorithmic logic, Python scripts, or API code
- You need to review and correct AI-generated code before applying it

## WHAT THIS SKILL DOES
Delegates code implementation to Codex CLI (OpenAI) and/or
delegates code review/correction to Gemini (research step) and Codex (implementation step).

## CLAUDE BEHAVIOR (Framing)
- **Complex Features:** Use a flow with a research step (e.g., `-Flow "standard"`) to analyze requirements and existing code before implementation.
- **Quick Fixes:** Use the default flow (omit `-Flow`) for simple bug fixes or localized changes.
- **Autonomous Implementation:** Always use the `-Yolo` flag to allow the Dispatcher to execute the implementation without redundant confirmation prompts.

## INVOCATION (Local Project Flow)

Check `flow.config.json` for available flows. Use the one that includes a research step (usually `standard`) for complex tasks, or the default flow for simple implementations.

```powershell
# Full cycle: Research + Implement (check flow.config.json for flow name, e.g. "standard")
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "scripts\Invoke-Flow.ps1" -Task "Implement speed measurement" -Flow "standard" -Yolo

# Simple implementation (omitting -Flow uses "defaultFlow" from config)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "scripts\Invoke-Flow.ps1" -Task "Fix this Python function" -Yolo
```

## ERROR HANDLING
- If Codex is not available (as seen in logs): Claude falls back to Gemini via `Invoke-Flow.ps1`.
- On stderr issues: Invoke-Flow.ps1 is updated to handle them.
