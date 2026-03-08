import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { CallToolRequestSchema, ListToolsRequestSchema } from '@modelcontextprotocol/sdk/types.js';
import { spawn } from 'child_process';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { makeHandlers } from './lib/handlers.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const PROJECT_ROOT    = join(__dirname, '..');
const SCRIPTS_DIR     = join(PROJECT_ROOT, 'scripts');
const FLOW_CONFIG     = join(PROJECT_ROOT, 'flow.config.json');
const ORCHESTRATE_DIR = join(PROJECT_ROOT, '.orchestrate');

// ── PowerShell runner ─────────────────────────────────────────────────────────
function makePowershellRunner(script) {
  return (args = []) => new Promise((resolve, reject) => {
    const ps = spawn('powershell.exe', ['-NoProfile', '-File', script, ...args], {
      cwd: PROJECT_ROOT,
    });
    let stdout = '';
    let stderr = '';
    ps.stdout.on('data', d => { stdout += d; });
    ps.stderr.on('data', d => { stderr += d; });
    ps.on('close', code => {
      if (code === 0 || stdout.trim()) resolve(stdout.trim());
      else reject(new Error(`Exit ${code}:\n${stderr.slice(0, 1000)}`));
    });
    ps.on('error', reject);
  });
}

function runPowershell(params, script = 'Invoke-Flow.ps1') {
  return makePowershellRunner(join(SCRIPTS_DIR, script))(params);
}

// ── Handler registry ──────────────────────────────────────────────────────────
const h = makeHandlers({
  flowConfigPath: FLOW_CONFIG,
  orchestrateDir: ORCHESTRATE_DIR,
  runPowershell,
});

// ── Tool definitions ──────────────────────────────────────────────────────────
const TOOLS = [
  {
    name: 'flow',
    description: 'Execute a toolchain flow defined in flow.config.json.',
    inputSchema: {
      type: 'object',
      properties: {
        task: { type: 'string', description: 'Task for the flow to execute.' },
        flow: { type: 'string', description: 'Flow name (defaults to defaultFlow from config).' },
        yolo: { type: 'boolean', description: 'Enable YOLO mode for the entire flow.', default: false },
      },
      required: ['task'],
    },
  },
  {
    name: 'run_agent',
    description: 'Run a single agent step via Run-Agent.ps1.',
    inputSchema: {
      type: 'object',
      properties: {
        model:   { type: 'string',  description: 'Model ID: gemini-2.5-pro | claude-sonnet-4-6 | gpt-4-codex' },
        role:    { type: 'string',  description: 'Role name (must exist in roles/<role>.md)' },
        prompt:  { type: 'string',  description: 'Prompt / task for the agent.' },
        yolo:    { type: 'boolean', description: 'Bypass all confirmations/sandbox.', default: false },
        session: { type: 'string',  description: 'Session ID to group related runs.' },
      },
      required: ['model', 'role', 'prompt'],
    },
  },
  {
    name: 'get_config',
    description: 'Return the current flow.config.json content.',
    inputSchema: { type: 'object', properties: {} },
  },
  {
    name: 'list_flows',
    description: 'List all available flows from flow.config.json with their steps.',
    inputSchema: { type: 'object', properties: {} },
  },
  {
    name: 'set_default_flow',
    description: 'Set the defaultFlow in flow.config.json.',
    inputSchema: {
      type: 'object',
      properties: {
        flow: { type: 'string', description: 'Flow name to set as default.' },
      },
      required: ['flow'],
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
  {
    name: 'get_run_output',
    description: 'Read output from a specific agent run. Omit run_id to get the latest.',
    inputSchema: {
      type: 'object',
      properties: {
        run_id: { type: 'string', description: 'Run ID or partial name. Omit for latest.' },
      },
    },
  },
];

// ── MCP Server ────────────────────────────────────────────────────────────────
const server = new Server(
  { name: 'orchestrator-mcp', version: '2.0.0' },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({ tools: TOOLS }));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;
  try {
    let result;
    switch (name) {
      case 'flow':             result = await h.flow(args);          break;
      case 'run_agent':        result = await h.runAgent(args);      break;
      case 'get_config':       result =       h.getConfig();         break;
      case 'list_flows':       result =       h.listFlows();         break;
      case 'set_default_flow': result =       h.setDefaultFlow(args); break;
      case 'read_report':      result =       h.readReport();        break;
      case 'list_runs':        result =       h.listRuns(args);      break;
      case 'get_run_output':   result =       h.getRunOutput(args);  break;
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
