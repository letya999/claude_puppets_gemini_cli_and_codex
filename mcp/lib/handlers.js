import { readFileSync, writeFileSync, readdirSync, statSync } from 'fs';
import { join } from 'path';

// ── Pure config helpers ───────────────────────────────────────────────────────

function readFlowConfig(flowConfigPath) {
  return JSON.parse(readFileSync(flowConfigPath, 'utf8'));
}

function writeFlowConfig(cfg, flowConfigPath) {
  writeFileSync(flowConfigPath, JSON.stringify(cfg, null, 2), 'utf8');
}

// ── Handler implementations ───────────────────────────────────────────────────

function getConfig(flowConfigPath) {
  const cfg = readFlowConfig(flowConfigPath);
  return `Default flow: ${cfg.defaultFlow}\n\n${JSON.stringify(cfg, null, 2)}`;
}

function listFlows(flowConfigPath) {
  const cfg = readFlowConfig(flowConfigPath);
  const names = Object.keys(cfg.flows);
  if (!names.length) return 'No flows defined in flow.config.json.';
  const lines = names.map(name => {
    const steps = cfg.flows[name].steps.map(s => `${s.tool}:${s.role}`).join(' → ');
    const marker = name === cfg.defaultFlow ? ' [default]' : '';
    return `  ${name}${marker}: ${steps}`;
  });
  return `Available flows (default: ${cfg.defaultFlow}):\n${lines.join('\n')}`;
}

function setDefaultFlow(args, flowConfigPath) {
  const cfg = readFlowConfig(flowConfigPath);
  const { flow } = args;
  if (!cfg.flows[flow]) {
    const available = Object.keys(cfg.flows).join(', ');
    throw new Error(`Unknown flow: "${flow}". Available: ${available}`);
  }
  cfg.defaultFlow = flow;
  writeFlowConfig(cfg, flowConfigPath);
  return `Default flow set to "${flow}"`;
}

function readReport(orchestrateDir) {
  const runsDir = join(orchestrateDir, 'runs', 'agent-runs');
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

function listRuns(args, orchestrateDir) {
  const indexPath = join(orchestrateDir, 'index', 'runs.jsonl');
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

function getRunOutput(args, orchestrateDir) {
  const runsDir = join(orchestrateDir, 'runs', 'agent-runs');
  const runId = args?.run_id;
  let dirs;
  try {
    dirs = readdirSync(runsDir);
  } catch {
    return 'No runs directory found (.orchestrate/runs/agent-runs/).';
  }
  if (!dirs.length) return 'No agent runs found.';

  let match;
  if (runId) {
    match = dirs.find(d => d === runId || d.includes(runId));
    if (!match) return `Run not found: "${runId}"`;
  } else {
    match = dirs
      .map(d => ({ name: d, mtime: statSync(join(runsDir, d)).mtime }))
      .sort((a, b) => b.mtime - a.mtime)[0]?.name;
  }

  // Try output.txt first, fall back to report.md
  for (const file of ['output.txt', 'report.md']) {
    try {
      return readFileSync(join(runsDir, match, file), 'utf8');
    } catch { /* try next */ }
  }
  return `Run found (${match}) but no output file inside.`;
}

// ── Factory — injects dependencies for testability ───────────────────────────

export function makeHandlers({ flowConfigPath, orchestrateDir, runPowershell }) {
  return {
    async flow(args) {
      const params = ['-Task', args.task];
      // use explicit flow or fall back to defaultFlow from config
      const flowName = args.flow ?? readFlowConfig(flowConfigPath).defaultFlow;
      params.push('-Flow', flowName);
      if (args.yolo) params.push('-Yolo');
      const out = await runPowershell(params);
      return out || '(flow complete — no stdout output)';
    },

    async runAgent(args) {
      const params = ['-Model', args.model, '-Role', args.role, '-Prompt', args.prompt];
      if (args.yolo)    params.push('-Yolo');
      if (args.session) params.push('-Session', args.session);
      const out = await runPowershell(params, 'Run-Agent.ps1');
      return out || '(agent complete — no stdout output)';
    },

    getConfig()            { return getConfig(flowConfigPath); },
    listFlows()            { return listFlows(flowConfigPath); },
    setDefaultFlow(args)   { return setDefaultFlow(args, flowConfigPath); },
    readReport()           { return readReport(orchestrateDir); },
    listRuns(args)         { return listRuns(args, orchestrateDir); },
    getRunOutput(args)     { return getRunOutput(args, orchestrateDir); },
  };
}
