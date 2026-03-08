# SKILL: STRATEGIC PLANNING
This skill enables Claude to manage the lifecycle of an implementation plan.

## CAPABILITIES:
- **Analyze and Plan**: Claude can research the codebase and write a detailed plan to a file.
- **Plan File Management**: The plan is always saved in the `$env:PLAN_DIR` directory.
- **Delegation Protocol**: After creating the plan, Claude must call `Invoke-Flow.ps1` with the absolute path of the plan file.

## MANDATORY WORKFLOW:
1. **Analyze**: Use `grep_search` and `read_file` to understand the request.
2. **Write Plan**: Generate a structured plan and save it using `write_file`.
   - Path format: `$env:PLAN_DIR\plan_<task_slug>_<timestamp>.md`.
   - Content: Objective, Tasks (File|Action|Description), Verification commands.
3. **Delegate**: Execute `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "scripts\Invoke-Flow.ps1" -Task "<Full-Path-To-Plan>"`.

## RULES:
- Never perform implementation directly when planning is required.
- The plan file is the "Single Source of Truth" for the sub-agent.
