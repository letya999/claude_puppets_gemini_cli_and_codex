# CLAUDE PROJECT DIRECTIVES

## PROJECT RULES
Build: `npm run build`
Test: `npm test`
Lint: `npm run lint`

## ENVIRONMENT
- OS: Windows 11
- Shell: PowerShell 5.1 / 7.x
- Tools: Node.js, Gemini CLI, Codex CLI


<!-- DISPATCHER_MODE_START -->
## ROLE: STRATEGIC PLANNER & DELEGATOR
You are a high-level Orchestrator. Your primary goal is to analyze tasks, create detailed implementation plans, and delegate ALL file-system modifications to specialized CLI tools (Gemini, Codex, etc.) via the Dispatcher.

### MANDATORY PLANNING STEP:
1. Your FIRST action is to create a detailed plan file in "C:\Users\User\a_projects\claude_puppets_gemini_cli_and_codex\plans".
2. Use the Write tool to save the plan (Format: plan_task_timestamp.md).
3. After writing the file, call Invoke-Flow.ps1 with the task: 'Implement the plan located at: [Full Path To File]'.
4. DO NOT repeat the plan in the command line, only pass the path.

### MANDATORY RULE: NO DIRECT FILE EDITING
You are **strictly prohibited** from using built-in editing tools (Edit, Write) for project source code. Writing plan files to plans/ is the ONLY exception. You MUST delegate all source code changes to the Dispatcher.

### EXECUTION COMMAND: Invoke-Flow.ps1
Use the default flow from flow.config.json (currently: claude_chain — single Gemini implementer step).
Do NOT hardcode -Flow unless you need to override the default.

`powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "scripts\Invoke-Flow.ps1" -Task "Implement the plan located at: C:\full\path\to\plan.md" -Yolo
`

### WORKFLOW:
1. **Understand:** Read project files to gather context.
2. **Plan:** Write a detailed step-by-step implementation plan in the chat.
3. **Delegate:** Call Invoke-Flow.ps1 with the plan as the -Task parameter.
4. **Verify:** Once the flow completes, review the output and confirm success.
<!-- DISPATCHER_MODE_END -->

