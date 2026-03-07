# Skill: gemini-delegate

## TRIGGER
Use this skill when the user asks to delegate a task to Gemini CLI, OR when:
- The task requires processing large amounts of text (>50k tokens)
- The task is research, analysis, creative brainstorming, or summarization
- The task involves reading large log files or codebases
- The task requires web knowledge or creative ideation

## WHAT THIS SKILL DOES
Delegates the current task to Google Gemini CLI (gemini) and returns its output
for Claude to review and apply. Claude remains the Planner; Gemini is the Executor.

## INVOCATION

Run in PowerShell (Windows native — NOT bash, NOT WSL):

```powershell
# Basic delegation
.\scripts\Invoke-GeminiDelegate.ps1 -Task "YOUR_TASK_HERE"

# With file context
.\scripts\Invoke-GeminiDelegate.ps1 -Task "Analyze this code" -ContextFile ".\src\main.py"

# With inline context
.\scripts\Invoke-GeminiDelegate.ps1 -Task "Explain these errors" -Context "Error: NullPointerException at line 42"

# Specifying model
.\scripts\Invoke-GeminiDelegate.ps1 -Task "Deep analysis" -Model "gemini-2.5-pro"
```

## POWERSHELL HERE-STRING PATTERN
When building complex prompts in PowerShell, use Here-Strings:

```powershell
# Single-quoted: NO variable expansion (like bash <<'EOF')
$prompt = @'
Analyze the following code and identify:
1. Performance bottlenecks
2. Security vulnerabilities
3. Code smells
'@

# Double-quoted: WITH variable expansion (like bash <<"EOF")
$task = "optimize database queries"
$prompt = @"
Your task: $task
Context: PostgreSQL, Django ORM
"@

# Pipe to gemini
$prompt | gemini --model gemini-2.5-pro
```

## OUTPUT HANDLING
- Output is saved to `$env:TEMP\dispatcher-session-<timestamp>\gemini-output.txt`
- Claude should read this file and decide what changes to apply
- Use the Edit tool to apply the actual file modifications

## ROUTING RULES
- If task needs CODE implementation after research → chain to `Invoke-CodexDelegate.ps1`
- If result needs REVIEW → chain to `Invoke-ModsReview.ps1`
- For full pipeline → use `Invoke-Pipeline.ps1 -Mode research`

## ERROR HANDLING
- If gemini not in PATH: install from https://github.com/google-gemini/gemini-cli
  ```powershell
  npm install -g @google/generative-ai-cli
  # OR
  winget install Google.GeminiCLI
  ```
- If API key missing: set `$env:GEMINI_API_KEY = "your-key"`
- On timeout: increase with `--timeout 120` flag
