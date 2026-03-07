# Skill: codex-review

## TRIGGER
Use this skill when:
- User asks to implement, write, or generate code
- A task requires precise algorithmic logic, Python scripts, or API code
- You need to review and correct AI-generated code before applying it
- User asks for a "code review" or "security check" on a file

## WHAT THIS SKILL DOES
Delegates code implementation to Codex CLI (OpenAI) and/or
delegates code review/correction to Mods CLI (charmbracelet/mods).
Claude remains Planner; Codex/Mods are Executors.

## CODEX INVOCATION (Implementation)

```powershell
# Generate new code
.\scripts\Invoke-CodexDelegate.ps1 -Task "Write a function that parses CSV files" -Language "python"

# Refactor existing code
.\scripts\Invoke-CodexDelegate.ps1 -Task "Refactor to use async/await" -ContextFile ".\src\service.py"

# With inline context
.\scripts\Invoke-CodexDelegate.ps1 `
    -Task "Add input validation" `
    -Context "This is a Flask API endpoint that accepts JSON" `
    -Language "python"
```

## MODS INVOCATION (Review & Correction)

```powershell
# Full review with auto-fixes
.\scripts\Invoke-ModsReview.ps1 -InputFile ".\generated-code.py" -ApplyFixes

# Security-focused review
.\scripts\Invoke-ModsReview.ps1 -InputFile ".\src\auth.py" -ReviewType "security"

# Review specific code string
.\scripts\Invoke-ModsReview.ps1 -Code "def login(user, pwd): return db.query(f'SELECT * FROM users WHERE pwd={pwd}')" -ReviewType "security"

# Pipe generated code directly to review
$result = .\scripts\Invoke-CodexDelegate.ps1 -Task "Write auth module"
.\scripts\Invoke-ModsReview.ps1 -InputFile $result.OutputFile -ApplyFixes
```

## CHAINED PIPELINE PATTERN

```powershell
# Step 1: Generate
$impl = .\scripts\Invoke-CodexDelegate.ps1 `
    -Task "Implement JWT authentication for FastAPI" `
    -Language "python"

# Step 2: Review & fix
$review = .\scripts\Invoke-ModsReview.ps1 `
    -InputFile $impl.OutputFile `
    -ReviewType "security" `
    -ApplyFixes

# Step 3: Claude reads and applies
# --> Claude uses Edit tool on the target file
Get-Content $review.OutputFile
```

## POWERSHELL TEMP FILE PATTERN

```powershell
# Use $env:TEMP instead of /tmp/ (Windows-native)
$tempFile = Join-Path $env:TEMP "codex-output-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
$output | Out-File -FilePath $tempFile -Encoding UTF8

# Read back
$result = Get-Content $tempFile -Raw

# Cleanup after use
Remove-Item $tempFile -ErrorAction SilentlyContinue
```

## INSTALLATION
- Codex CLI: `npm install -g @openai/codex`
- Mods CLI: `winget install charmbracelet.mods` or `go install github.com/charmbracelet/mods@latest`
- Set API key: `$env:OPENAI_API_KEY = "sk-..."`

## ERROR HANDLING
- Codex quota exceeded → fallback to Gemini: `.\scripts\Invoke-GeminiDelegate.ps1`
- Mods not available → Claude performs review inline using Read + Edit tools
- Parse errors in output → Claude manually extracts code blocks from output file
