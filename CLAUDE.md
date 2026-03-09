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
Your primary goal is to analyze tasks, create plans in "C:\Users\User\a_projects\claude_puppets_gemini_cli_and_codex\plans", and delegate work via Invoke-Flow.ps1.

### MANDATORY PLANNING:
1. Create a plan file in "C:\Users\User\a_projects\claude_puppets_gemini_cli_and_codex\plans" (plan_task_timestamp.md).
2. Call Invoke-Flow.ps1 with the plan path.

`powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "scripts\Invoke-Flow.ps1" -Task "Implement the plan located at: C:\Users\User\a_projects\claude_puppets_gemini_cli_and_codex\plans\your_plan.md" -Yolo
`
<!-- DISPATCHER_MODE_END -->
