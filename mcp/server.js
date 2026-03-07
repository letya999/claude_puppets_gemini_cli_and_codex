import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { CallToolRequestSchema, ListToolsRequestSchema } from '@modelcontextprotocol/sdk/types.js';
import { spawn } from 'child_process';
import { readFileSync, writeFileSync, readdirSync, statSync } from 'fs';
import { readFile } from 'fs/promises';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const PROJECT_ROOT = join(__dirname, '..');
const SCRIPTS_DIR  = join(PROJECT_ROOT, 'scripts');
const CONFIG_PATH  = join(PROJECT_ROOT, 'dispatcher.config.json');
const ORCHESTRATE  = join(PROJECT_ROOT, '.orchestrate');

// ── PowerShell runner ────────────────────────────────────────────────────────
function runPowershell(scriptPath, args = []) {
  return new Promise((resolve, reject) => {
    const ps = spawn('powershell.exe', ['-NoProfile', '-File', scriptPath, ...args], {
      cwd: PROJECT_ROOT,
    });
    let stdout = '';
    let stderr = '';
    ps.stdout.on('data', d => { stdout += d; });
    ps.stderr.on('data', d => { stderr += d; });
    ps.on('close', code => {
      // Accept exit 0 OR non-empty stdout (some tools write to stderr but succeed)
      if (code === 0 || stdout.trim()) resolve(stdout.trim());
      else reject(new Error(`Exit ${code}:\n${stderr.slice(0, 1000)}`));
    });
    ps.on('error', reject);
  });
}

// ── Tool definitions ─────────────────────────────────────────────────────────
const TOOLS = [
  {
    name: 'dispatch',
    description: 'Run the full agent chain from dispatcher.config.json on a task. Equivalent to Invoke-Chain.ps1 -Task "..."',
    inputSchema: {
      type: 'object',
      properties: {
        task:    { type: 'string',  description: 'The task description to run through the agent chain.' },
        dry_run: { type: 'boolean', description: 'If true, prints what would run without making API calls.', default: false },
      },
      required: ['task'],
    },
  },
  {
    name: 'run_agent',
    description: 'Run a single agent step. Equivalent to Run-Agent.ps1 -Model X -Role Y -Prompt Z',
    inputSchema: {
      type: 'object',
      properties: {
        model:   { type: 'string',  description: 'Model ID: gemini-2.5-pro | claude-sonnet-4-6 | gpt-5.3-codex' },
        role:    { type: 'string',  description: 'Role name (must exist in .claude/roles/<role>.md)' },
        prompt:  { type: 'string',  description: 'The prompt / task for the agent.' },
        yolo:    { type: 'boolean', description: 'UNSAFE: bypass all confirmations/sandbox.', default: false },
        session: { type: 'string',  description: 'Session ID to group related runs.' },
      },
      required: ['model', 'role', 'prompt'],
    },
  },
  {
    name: 'get_config',
    description: 'Return the current dispatcher.config.json (active chain + all presets).',
    inputSchema: { type: 'object', properties: {} },
  },
  {
    name: 'switch_preset',
    description: 'Switch the active chain to one of the named presets in dispatcher.config.json.',
    inputSchema: {
      type: 'object',
      properties: {
        preset: {
          type: 'string',
          description: 'Preset name to activate.',
          enum: [
            'research_then_implement',
            'full_with_validation',
            'gemini_only',
            'codex_plus_review',
            'research_only',
            'claude_plan_gemini_execute',
          ],
        },
      },
      required: ['preset'],
    },
  },
  {
    name: 'read_report',
    description: 'Read report.md from the most recent agent run in .orchestrate/runs/agent-runs/.',
    inputSchema: { type: 'object', properties: {} },
  },
  {
    name: 'list_runs',
    description: 'Show recent entries from .orchestrate/index/runs.jsonl.',
    inputSchema: {
      type: 'object',
      properties: {
        limit: { type: 'number', description: 'Number of recent runs to return (default 10).', default: 10 },
      },
    },
  },
];

// ── Tool handlers ─────────────────────────────────────────────────────────────
async function handleDispatch(args) {
  const ps1 = join(SCRIPTS_DIR, 'Invoke-Chain.ps1');
  const params = ['-Task', args.task];
  if (args.dry_run) params.push('-DryRun');
  const out = await runPowershell(ps1, params);
  return out || '(chain complete — no stdout output)';
}

async function handleRunAgent(args) {
  const ps1 = join(SCRIPTS_DIR, 'Run-Agent.ps1');
  const params = ['-Model', args.model, '-Role', args.role, '-Prompt', args.prompt];
  if (args.yolo)    params.push('-Yolo');
  if (args.session) params.push('-Session', args.session);
  const out = await runPowershell(ps1, params);
  return out || '(agent complete — no stdout output)';
}

function handleGetConfig() {
  const cfg = JSON.parse(readFileSync(CONFIG_PATH, 'utf8'));
  const chain = cfg.chain.map(s => `${s.agent}:${s.role}${s.yolo ? ' (yolo)' : ''}`).join(' → ');
  return `Active chain: ${chain}\n\n${JSON.stringify(cfg, null, 2)}`;
}

function handleSwitchPreset(args) {
  const cfg = JSON.parse(readFileSync(CONFIG_PATH, 'utf8'));
  const preset = cfg._presets?.[args.preset];
  if (!preset) {
    throw new Error(`Unknown preset: "${args.preset}". Available: ${Object.keys(cfg._presets || {}).join(', ')}`);
  }
  cfg.chain = preset;
  writeFileSync(CONFIG_PATH, JSON.stringify(cfg, null, 2), 'utf8');
  const summary = preset.map(s => `${s.agent}:${s.role}`).join(' → ');
  return `Switched to preset "${args.preset}"\nNew chain: ${summary}`;
}

function handleReadReport() {
  const runsDir = join(ORCHESTRATE, 'runs', 'agent-runs');
  let dirs;
  try {
    dirs = readdirSync(runsDir);
  } catch {
    return 'No runs directory found (.orchestrate/runs/agent-runs/).';
  }
  if (!dirs.length) return 'No agent runs found.';

  const sorted = dirs
    .map(d => ({ name: d, mtime: statSync(join(runsDir, d)).mtime }))
    .sort((a, b) => b.mtime - a.mtime);

  const reportPath = join(runsDir, sorted[0].name, 'report.md');
  try {
    return readFileSync(reportPath, 'utf8');
  } catch {
    return `Run found (${sorted[0].name}) but no report.md inside.`;
  }
}

function handleListRuns(args) {
  const indexPath = join(ORCHESTRATE, 'index', 'runs.jsonl');
  let content;
  try {
    content = readFileSync(indexPath, 'utf8');
  } catch {
    return 'Run index not found. No runs recorded yet.';
  }
  const limit = args?.limit ?? 10;
  const lines = content.trim().split('\n').filter(Boolean);
  const recent = lines.slice(-limit);
  const parsed = recent.map(l => { try { return JSON.parse(l); } catch { return l; } });
  return JSON.stringify(parsed, null, 2);
}

// ── MCP Server ────────────────────────────────────────────────────────────────
const server = new Server(
  { name: 'orchestrator-mcp', version: '1.0.0' },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({ tools: TOOLS }));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;
  try {
    let result;
    switch (name) {
      case 'dispatch':      result = await handleDispatch(args);    break;
      case 'run_agent':     result = await handleRunAgent(args);    break;
      case 'get_config':    result =       handleGetConfig();       break;
      case 'switch_preset': result =       handleSwitchPreset(args); break;
      case 'read_report':   result =       handleReadReport();       break;
      case 'list_runs':     result =       handleListRuns(args);     break;
      default:
        return { content: [{ type: 'text', text: `Unknown tool: ${name}` }], isError: true };
    }
    return { content: [{ type: 'text', text: String(result) }] };
  } catch (e) {
    return { content: [{ type: 'text', text: `Error: ${e.message}` }], isError: true };
  }
});

const transport = new StdioServerTransport();
await server.connect(transport);
process.stderr.write('orchestrator-mcp ready\n');
