# Simple shim for compatibility with old skills
param([string]$Task)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\Invoke-Flow.ps1" -Task $Task -Yolo
