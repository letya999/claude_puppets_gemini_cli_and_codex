# Skill: codex-review

## TRIGGER
Use this skill when:
- User asks to implement, write, or generate code
- A task requires precise algorithmic logic, Python scripts, or API code
- You need to review and correct AI-generated code before applying it

## WHAT THIS SKILL DOES
Delegates code implementation to Codex CLI (OpenAI) and/or
delegates code review/correction to Gemini (research step) and Codex (implementation step).

## INVOCATION (Local Project Flow)

Run in PowerShell:

```powershell
# Full cycle: Research + Implement (uses standard flow)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "scripts\Invoke-Flow.ps1" -Task "Implement speed measurement" -Flow "standard" -Yolo

# Implementation only (via gemini-only chain for now)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "scripts\Invoke-Flow.ps1" -Task "Fix this Python function" -Yolo
```

## ERROR HANDLING
- If Codex is not available (as seen in logs): Claude falls back to Gemini via `Invoke-Flow.ps1`.
- On stderr issues: Invoke-Flow.ps1 is updated to handle them.
