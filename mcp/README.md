# Claude Puppets MCP Server

This server provides a [Model Context Protocol (MCP)](https://github.com/model-context-protocol/specification) interface for the Claude Puppets agent framework. It allows MCP-compatible clients like Claude Desktop, VS Code, and Cursor to interact with the agent chain and supporting tools.

## Features

- **Run Agent Chains**: Trigger the full `Invoke-Chain.ps1` script for a given task.
- **Run Single Agents**: Execute a single agent with a specific model, role, and prompt.
- **Configuration Management**: View and switch between different agent chain presets defined in `dispatcher.config.json`.
- **Reporting**: Read the latest run report or list recent run history.

## Installation

The server is a simple Node.js application.

1.  Navigate to the MCP directory:
    ```sh
    cd mcp
    ```
2.  Install dependencies:
    ```sh
    npm install
    ```
3.  (No build step is required)

## Configuration

To use the server, you need to configure your MCP client to launch it. The client will communicate with the server via standard input/output.

### Claude Desktop

File: `%APPDATA%\Claude\claude_desktop_config.json`

```json
{
  "mcpServers": {
    "orchestrator": {
      "command": "node",
      "args": ["C:/Users/User/a_projects/claude_puppets_gemini_cli_and_codex/mcp/server.js"]
    }
  }
}
```

### VS Code (GitHub Copilot / MCP extension)

File: `.vscode/mcp.json` in your workspace, or in user `settings.json`:

```json
{
  "mcp": {
    "servers": {
      "orchestrator": {
        "type": "stdio",
        "command": "node",
        "args": ["C:/Users/User/a_projects/claude_puppets_gemini_cli_and_codex/mcp/server.js"]
      }
    }
  }
}
```

### Cursor

File: `%USERPROFILE%\.cursor\mcp.json` (global) or `.cursor/mcp.json` (project):

```json
{
  "mcpServers": {
    "orchestrator": {
      "command": "node",
      "args": ["C:/Users/User/a_projects/claude_puppets_gemini_cli_and_codex/mcp/server.js"]
    }
  }
}
```

*Adjust paths if the project is in a different location.*

## Tools

The server exposes the following tools to the MCP client:

### 1. `dispatch`
Run the full agent chain for a task.

- **Input**:
  - `task` (string, required): The task description.
  - `dry_run` (boolean, optional): If `true`, runs the chain in dry-run mode.
- **Example**: `@Claude Puppets dispatch task="Refactor the authentication module to use JWT"`

### 2. `run_agent`
Run a single agent step.

- **Input**:
  - `model` (string, required): e.g., 'gemini-2.5-pro', 'claude-sonnet-4-6'.
  - `role` (string, required): The agent's role.
  - `prompt` (string, required): The input prompt.
  - `yolo` (boolean, optional): If `true`, runs in 'YOLO' mode.
  - `session` (string, optional): A session ID to continue.
- **Example**: `@Claude Puppets run_agent model="gemini-2.5-pro" role="coder" prompt="Write a function that sorts an array."`

### 3. `get_config`
Read the current `dispatcher.config.json`.

- **Input**: None
- **Example**: `@Claude Puppets get_config`

### 4. `switch_preset`
Switch the active agent chain to a pre-defined preset from `_presets` in the config.

- **Input**:
  - `preset` (string, required): Must be one of `research_then_implement`, `full_with_validation`, `gemini_only`, `codex_plus_review`, `research_only`, `claude_plan_gemini_execute`.
- **Example**: `@Claude Puppets switch_preset preset="gemini_only"`

### 5. `read_report`
Read the `report.md` from the most recent agent run.

- **Input**: None
- **Example**: `@Claude Puppets read_report`

### 6. `list_runs`
List recent entries from the run index (`.orchestrate/index/runs.jsonl`).

- **Input**:
  - `limit` (number, optional): Number of runs to list (default: 10).
- **Example**: `@Claude Puppets list_runs limit=5`

## Usage

1.  Start your MCP-compatible client (Claude Desktop, VS Code with the MCP extension, etc.).
2.  Ensure the "Claude Puppets" server is connected.
3.  Use the `@Claude Puppets` handle in the chat to invoke any of the available tools.
