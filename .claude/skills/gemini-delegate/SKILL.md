# Skill: gemini-delegate

## TRIGGER
Use this skill for:
- Code implementation, research, analysis, and creative brainstorming.
- Processing large contexts (>50k tokens) or reading project logs/codebases.

## WHAT THIS SKILL DOES
Delegates the current task to Gemini CLI via the Dispatcher.
Claude Code remains the Planner; Gemini is the Executor.

## INVOCATION

Always use the project-local Flow Executor:

```powershell
# Execute task using default flow (claude_chain)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "scripts\Invoke-Flow.ps1" -Task "YOUR_TASK_HERE" -Yolo

# Force 'standard' flow (Research -> Implement)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "scripts\Invoke-Flow.ps1" -Task "YOUR_TASK_HERE" -Flow "standard" -Yolo
```

## OUTPUT HANDLING
- Gemini will directly modify files based on instructions.
- After completion, review the changes via git diff or by reading files.
- Do NOT rewrite Gemini's output yourself unless manual correction is needed.
