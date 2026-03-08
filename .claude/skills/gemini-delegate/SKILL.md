# Skill: gemini-delegate

## TRIGGER
Use this skill for:
- Code implementation, research, analysis, and creative brainstorming.
- Processing large contexts (>50k tokens) or reading project logs/codebases.

## WHAT THIS SKILL DOES
Delegates the current task to Gemini CLI via the Dispatcher.
Claude Code remains the Planner; Gemini is the Executor.

## CLAUDE BEHAVIOR (Framing)
- **Multi-step Research:** Use a flow that starts with research if the task requires deep codebase analysis.
- **Large Changes:** Delegate large-scale implementation tasks to Gemini via the default flow.
- **Self-Correction:** If the flow output contains errors, analyze them and run the flow again with a more detailed task description.

## INVOCATION

Always use the project-local Flow Executor. Check `flow.config.json` for available flows.

```powershell
# Execute task using "defaultFlow" from config (e.g. "claude_chain")
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "scripts\Invoke-Flow.ps1" -Task "YOUR_TASK_HERE" -Yolo

# Force a specific flow from config (e.g. "standard" for Research -> Implement)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "scripts\Invoke-Flow.ps1" -Task "YOUR_TASK_HERE" -Flow "standard" -Yolo
```

## OUTPUT HANDLING
- Gemini will directly modify files based on instructions.
- After completion, review the changes via git diff or by reading files.
- Do NOT rewrite Gemini's output yourself unless manual correction is needed.
