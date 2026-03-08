# Simple shim for compatibility with old skills
param([string]$Task)
# Invoke-Flow.ps1 now handles fallback to gemini if codex is missing
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\Invoke-Flow.ps1" -Task $Task -Yolo
