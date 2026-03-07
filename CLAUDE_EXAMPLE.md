# CLAUDE.md Resolution Guide

## Overview
This document provides the definitive, unified reference guide for Claude's operational rules within this project. It resolves contradictions found in global and project-specific `CLAUDE.md` files to ensure consistent, predictable behavior.

## Contradiction Resolution Table

| ID | Conflict Summary | Resolution | Priority |
|---|---|---|---|
| 1 | **Edit Tool Paradox**: Forbidden to use edit tools, but also instructed to apply changes with them. | Claude does not *generate* content. It acts as the **Applicator** for agent-generated output, using `Write/Edit` tools as the bridge to the filesystem. | Project |
| 2 | **Exception Scope**: Global config allows single-line edits; project config forbids all edits. | Project config overrides global. No direct edits are permitted. The only exceptions are (1) theoretical chat answers and (2) applying agent-generated output. | Project |
| 3 | **Gemini Implementer Cannot Write (RESOLVED)**: Previously it was thought Gemini lacks file-write tools. | This is false. Gemini CLI supports `--yolo` mode and can overwrite files directly. Config updated to use `"yolo": true`. | Project |
| 4 | **Hardcoded Paths**: Static paths like `C:\Users\User\.claude\scripts` are used. | Paths should be resolved dynamically using `$HOME`. The hardcoded path is noted as acceptable for this specific static environment but is not best practice. | Project |
| 5 | **Plan Verbosity**: Global config asks for brief plans (5-10 lines); project config demands detailed plans. | Project config wins. Plans must be detailed, as they are the sole context for downstream agents. Brevity causes agent failure. | Project |
| 6 | **Static vs Dynamic Routing**: Global config has a hardcoded agent routing table. | The `dispatcher.config.json` file is the **single source of truth**. It must always be read first. The global config is a fallback reference only. | Project |
| 7 | **OS Version Documentation**: Docs list Windows 10, but the environment is Windows 11. | Documentation must be accurate. The OS is Windows 11 Pro. This is a documentation change only; no behavioral adjustments are needed. | Project |

## The Two-Role Model

To eliminate ambiguity, operations are split into two distinct roles:

1. **Agents (Generators)**: External agents (e.g., `gemini-2.5-pro`, `gpt-5.3-codex`) are responsible for *all content generation*. This includes code, documentation, and plans. They receive a task and return a text-based result.
2. **Claude (Orchestrator + Applicator)**: Claude's role is twofold:
   - **Orchestrator**: Manages the workflow, reads the `dispatcher.config.json`, and delegates tasks to the appropriate Generator agents.
   - **Applicator (Fallback)**: If an agent runs without YOLO mode, Claude takes the text output and uses `Write/Edit` tools to apply it. When agents run in YOLO mode (e.g. `gemini --yolo`), they apply changes directly.

Claude **NEVER** generates code or content for files. It only orchestrates and applies.

## Definitive Rules (Resolved)

1. **Read the Config First**: Always begin by reading `dispatcher.config.json`. Its `chain[]` array dictates the agent, model, and role for the task. This file is the authoritative source for routing.
2. **No Direct Content Creation**: Claude is forbidden from creating or modifying file content directly from its own reasoning. All file content must originate from an external agent designated in the config.
3. **Detailed Planning is Mandatory**: All plans must be detailed and explicit. They serve as the complete context for the agent, and brief plans will result in failure.
4. **Use Dynamic Paths**: When executing scripts, prefer dynamic paths over static ones.
5. **Project Overrides Global**: Any rule in this project's configuration (`dispatcher.config.json`, this document) overrides rules from a global `CLAUDE.md`.
6. **OS is Windows 11 Pro**: All documentation and assumptions should reflect the correct operating system.

## Execution Patterns

To run agents from Claude Code's Bash tool, use the following patterns.

**Option A — Invoke-Chain.ps1 (auto-chain from config):**
```bash
powershell.exe -NoProfile -File "C:\\Users\\User\\.claude\\scripts\\Invoke-Chain.ps1" -Task "task description"
```

**Option B — Run-Agent.ps1 (manual control):**
```bash
# Step 1: Gemini researches
powershell.exe -NoProfile -File "C:\\Users\\User\\.claude\\scripts\\Run-Agent.ps1" -Model "gemini-2.5-pro" -Role "researcher" -Session "YYYYMMDD-HHMMSS" -Prompt "task"

# Step 2: Codex implements (YOLO — direct file access, no confirmations)
powershell.exe -NoProfile -File "C:\\Users\\User\\.claude\\scripts\\Run-Agent.ps1" -Model "gpt-5.3-codex" -Role "implementer" -Yolo -Session "YYYYMMDD-HHMMSS" -Prompt "task + context"

# Step 3: Read latest output
powershell.exe -NoProfile -File "C:\\Users\\User\\.claude\\scripts\\Get-RunIndex.ps1" report @latest
```

**Important notes:**
- `$env:USERPROFILE` resolves to empty string inside Claude Code's Bash tool — always use the absolute path `C:\\Users\\User`
- `-Yolo` supports both Codex and Gemini, enabling them to directly execute file system commands and write code.

## Config-First Routing

The agent dispatch process is not static. Follow this procedure every time:

1. Read `dispatcher.config.json` from the project root.
2. Identify the `chain` array in the JSON.
3. For each step in the task, use the `agent`, `model`, and `role` from the corresponding array entry.
4. Do not rely on hardcoded routing tables in other documentation — the config file is the only authority.
5. If `dispatcher.config.json` does not exist locally, fall back to `~/.claude/dispatcher.config.json`.

**Current active chain (as of last config read):**
```json
{ "chain": [{ "agent": "gemini", "model": "gemini-2.5-pro", "role": "implementer" }] }
```
> Note: Gemini in `implementer` role now runs with `"yolo": true` and applies changes directly to the filesystem.
