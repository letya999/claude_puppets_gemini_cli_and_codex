import { describe, it, before, after, mock } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { makeHandlers } from './lib/handlers.js';

// ── Helpers ───────────────────────────────────────────────────────────────────

function makeTmpDir() {
  return mkdtempSync(join(tmpdir(), 'mcp-test-'));
}

function makeFlowConfig(overrides = {}) {
  return {
    defaultFlow: 'standard',
    flows: {
      standard: { steps: [{ name: 'research', tool: 'gemini', role: 'researcher' }] },
      claude_chain: { steps: [{ name: 'execute', tool: 'gemini', role: 'implementer', yolo: true }] },
    },
    tools: { gemini: { executable: 'gemini' } },
    ...overrides,
  };
}

function writeConfig(dir, cfg) {
  const path = join(dir, 'flow.config.json');
  writeFileSync(path, JSON.stringify(cfg, null, 2), 'utf8');
  return path;
}

function makeRunDir(orchestrateDir, runName, files = {}) {
  const runPath = join(orchestrateDir, 'runs', 'agent-runs', runName);
  mkdirSync(runPath, { recursive: true });
  for (const [name, content] of Object.entries(files)) {
    writeFileSync(join(runPath, name), content, 'utf8');
  }
  return runPath;
}

function noopRunner() {
  return async () => 'powershell ok';
}

// ── Test suites ───────────────────────────────────────────────────────────────

describe('getConfig', () => {
  it('returns defaultFlow and full JSON', () => {
    const dir = makeTmpDir();
    try {
      const cfgPath = writeConfig(dir, makeFlowConfig());
      const h = makeHandlers({ flowConfigPath: cfgPath, orchestrateDir: dir, runPowershell: noopRunner() });
      const result = h.getConfig();
      assert.match(result, /Default flow: standard/);
      assert.match(result, /"defaultFlow"/);
      assert.match(result, /"flows"/);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it('throws when flow.config.json is missing', () => {
    const h = makeHandlers({ flowConfigPath: '/nonexistent/flow.config.json', orchestrateDir: '/tmp', runPowershell: noopRunner() });
    assert.throws(() => h.getConfig(), /ENOENT/);
  });
});

describe('listFlows', () => {
  it('lists all flows, marks default', () => {
    const dir = makeTmpDir();
    try {
      const cfgPath = writeConfig(dir, makeFlowConfig());
      const h = makeHandlers({ flowConfigPath: cfgPath, orchestrateDir: dir, runPowershell: noopRunner() });
      const result = h.listFlows();
      assert.match(result, /standard \[default\]/);
      assert.match(result, /claude_chain/);
      assert.match(result, /gemini:researcher/);
      assert.match(result, /gemini:implementer/);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it('returns message when no flows defined', () => {
    const dir = makeTmpDir();
    try {
      const cfgPath = writeConfig(dir, { defaultFlow: '', flows: {}, tools: {} });
      const h = makeHandlers({ flowConfigPath: cfgPath, orchestrateDir: dir, runPowershell: noopRunner() });
      const result = h.listFlows();
      assert.match(result, /No flows defined/);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
});

describe('setDefaultFlow', () => {
  it('updates defaultFlow and persists to disk', () => {
    const dir = makeTmpDir();
    try {
      const cfgPath = writeConfig(dir, makeFlowConfig());
      const h = makeHandlers({ flowConfigPath: cfgPath, orchestrateDir: dir, runPowershell: noopRunner() });

      const result = h.setDefaultFlow({ flow: 'claude_chain' });
      assert.match(result, /claude_chain/);

      // verify persisted
      const written = JSON.parse(readFileSync(cfgPath, 'utf8'));
      assert.equal(written.defaultFlow, 'claude_chain');
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it('throws for unknown flow name', () => {
    const dir = makeTmpDir();
    try {
      const cfgPath = writeConfig(dir, makeFlowConfig());
      const h = makeHandlers({ flowConfigPath: cfgPath, orchestrateDir: dir, runPowershell: noopRunner() });
      assert.throws(
        () => h.setDefaultFlow({ flow: 'no_such_flow' }),
        /Unknown flow.*no_such_flow/
      );
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
});

describe('readReport', () => {
  it('returns message when runs dir is missing', () => {
    const dir = makeTmpDir();
    try {
      const cfgPath = writeConfig(dir, makeFlowConfig());
      const h = makeHandlers({ flowConfigPath: cfgPath, orchestrateDir: dir, runPowershell: noopRunner() });
      assert.match(h.readReport(), /No runs directory found/);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it('returns message when runs dir is empty', () => {
    const dir = makeTmpDir();
    try {
      mkdirSync(join(dir, 'runs', 'agent-runs'), { recursive: true });
      const cfgPath = writeConfig(dir, makeFlowConfig());
      const h = makeHandlers({ flowConfigPath: cfgPath, orchestrateDir: dir, runPowershell: noopRunner() });
      assert.match(h.readReport(), /No agent runs found/);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it('returns message when report.md is missing from run', () => {
    const dir = makeTmpDir();
    try {
      makeRunDir(dir, 'run-001');
      const cfgPath = writeConfig(dir, makeFlowConfig());
      const h = makeHandlers({ flowConfigPath: cfgPath, orchestrateDir: dir, runPowershell: noopRunner() });
      assert.match(h.readReport(), /no report\.md inside/);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it('returns report.md content from latest run', () => {
    const dir = makeTmpDir();
    try {
      makeRunDir(dir, 'run-001', { 'report.md': '# Report\nAll good.' });
      const cfgPath = writeConfig(dir, makeFlowConfig());
      const h = makeHandlers({ flowConfigPath: cfgPath, orchestrateDir: dir, runPowershell: noopRunner() });
      assert.match(h.readReport(), /All good/);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
});

describe('listRuns', () => {
  it('returns message when index is missing', () => {
    const dir = makeTmpDir();
    try {
      const cfgPath = writeConfig(dir, makeFlowConfig());
      const h = makeHandlers({ flowConfigPath: cfgPath, orchestrateDir: dir, runPowershell: noopRunner() });
      assert.match(h.listRuns({}), /Run index not found/);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it('returns recent runs as JSON array', () => {
    const dir = makeTmpDir();
    try {
      const indexDir = join(dir, 'index');
      mkdirSync(indexDir, { recursive: true });
      const entries = [
        { id: 'run-001', status: 'ok' },
        { id: 'run-002', status: 'ok' },
        { id: 'run-003', status: 'fail' },
      ];
      writeFileSync(join(indexDir, 'runs.jsonl'), entries.map(e => JSON.stringify(e)).join('\n'), 'utf8');

      const cfgPath = writeConfig(dir, makeFlowConfig());
      const h = makeHandlers({ flowConfigPath: cfgPath, orchestrateDir: dir, runPowershell: noopRunner() });

      const result = JSON.parse(h.listRuns({}));
      assert.equal(result.length, 3);
      assert.equal(result[0].id, 'run-001');
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it('respects limit parameter', () => {
    const dir = makeTmpDir();
    try {
      const indexDir = join(dir, 'index');
      mkdirSync(indexDir, { recursive: true });
      const entries = Array.from({ length: 15 }, (_, i) => ({ id: `run-${i + 1}` }));
      writeFileSync(join(indexDir, 'runs.jsonl'), entries.map(e => JSON.stringify(e)).join('\n'), 'utf8');

      const cfgPath = writeConfig(dir, makeFlowConfig());
      const h = makeHandlers({ flowConfigPath: cfgPath, orchestrateDir: dir, runPowershell: noopRunner() });

      const result = JSON.parse(h.listRuns({ limit: 5 }));
      assert.equal(result.length, 5);
      assert.equal(result[0].id, 'run-11');
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it('defaults limit to 10', () => {
    const dir = makeTmpDir();
    try {
      const indexDir = join(dir, 'index');
      mkdirSync(indexDir, { recursive: true });
      const entries = Array.from({ length: 20 }, (_, i) => ({ id: `run-${i + 1}` }));
      writeFileSync(join(indexDir, 'runs.jsonl'), entries.map(e => JSON.stringify(e)).join('\n'), 'utf8');

      const cfgPath = writeConfig(dir, makeFlowConfig());
      const h = makeHandlers({ flowConfigPath: cfgPath, orchestrateDir: dir, runPowershell: noopRunner() });

      const result = JSON.parse(h.listRuns({}));
      assert.equal(result.length, 10);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
});

describe('getRunOutput', () => {
  it('returns message when runs dir is missing', () => {
    const dir = makeTmpDir();
    try {
      const cfgPath = writeConfig(dir, makeFlowConfig());
      const h = makeHandlers({ flowConfigPath: cfgPath, orchestrateDir: dir, runPowershell: noopRunner() });
      assert.match(h.getRunOutput({}), /No runs directory found/);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it('returns output.txt content for latest run when no run_id given', () => {
    const dir = makeTmpDir();
    try {
      makeRunDir(dir, 'run-alpha', { 'output.txt': 'hello from alpha' });
      const cfgPath = writeConfig(dir, makeFlowConfig());
      const h = makeHandlers({ flowConfigPath: cfgPath, orchestrateDir: dir, runPowershell: noopRunner() });
      assert.match(h.getRunOutput({}), /hello from alpha/);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it('falls back to report.md when output.txt is missing', () => {
    const dir = makeTmpDir();
    try {
      makeRunDir(dir, 'run-beta', { 'report.md': '# Fallback report' });
      const cfgPath = writeConfig(dir, makeFlowConfig());
      const h = makeHandlers({ flowConfigPath: cfgPath, orchestrateDir: dir, runPowershell: noopRunner() });
      assert.match(h.getRunOutput({}), /Fallback report/);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it('finds run by partial ID', () => {
    const dir = makeTmpDir();
    try {
      makeRunDir(dir, 'run-2024-abc123', { 'output.txt': 'specific run output' });
      const cfgPath = writeConfig(dir, makeFlowConfig());
      const h = makeHandlers({ flowConfigPath: cfgPath, orchestrateDir: dir, runPowershell: noopRunner() });
      assert.match(h.getRunOutput({ run_id: 'abc123' }), /specific run output/);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it('returns not-found message for unknown run_id', () => {
    const dir = makeTmpDir();
    try {
      makeRunDir(dir, 'run-001', { 'output.txt': 'data' });
      const cfgPath = writeConfig(dir, makeFlowConfig());
      const h = makeHandlers({ flowConfigPath: cfgPath, orchestrateDir: dir, runPowershell: noopRunner() });
      assert.match(h.getRunOutput({ run_id: 'nonexistent' }), /Run not found/);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
});

describe('flow', () => {
  it('calls runPowershell with -Task and default flow from config', async () => {
    const dir = makeTmpDir();
    try {
      const cfgPath = writeConfig(dir, makeFlowConfig());
      const calls = [];
      const mockRunner = async (params) => { calls.push(params); return 'flow result'; };
      const h = makeHandlers({ flowConfigPath: cfgPath, orchestrateDir: dir, runPowershell: mockRunner });

      const result = await h.flow({ task: 'do something' });
      assert.equal(result, 'flow result');
      assert.ok(calls[0].includes('-Task'));
      assert.ok(calls[0].includes('do something'));
      assert.ok(calls[0].includes('-Flow'));
      assert.ok(calls[0].includes('standard'));
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it('passes explicit flow name when provided', async () => {
    const dir = makeTmpDir();
    try {
      const cfgPath = writeConfig(dir, makeFlowConfig());
      const calls = [];
      const mockRunner = async (params) => { calls.push(params); return 'ok'; };
      const h = makeHandlers({ flowConfigPath: cfgPath, orchestrateDir: dir, runPowershell: mockRunner });

      await h.flow({ task: 'task', flow: 'claude_chain' });
      assert.ok(calls[0].includes('claude_chain'));
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it('appends -Yolo when yolo is true', async () => {
    const dir = makeTmpDir();
    try {
      const cfgPath = writeConfig(dir, makeFlowConfig());
      const calls = [];
      const mockRunner = async (params) => { calls.push(params); return 'ok'; };
      const h = makeHandlers({ flowConfigPath: cfgPath, orchestrateDir: dir, runPowershell: mockRunner });

      await h.flow({ task: 'task', yolo: true });
      assert.ok(calls[0].includes('-Yolo'));
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it('returns placeholder when powershell produces no output', async () => {
    const dir = makeTmpDir();
    try {
      const cfgPath = writeConfig(dir, makeFlowConfig());
      const h = makeHandlers({ flowConfigPath: cfgPath, orchestrateDir: dir, runPowershell: async () => '' });
      const result = await h.flow({ task: 'task' });
      assert.match(result, /no stdout output/);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
});

describe('runAgent', () => {
  it('passes -Model, -Role, -Prompt to powershell', async () => {
    const dir = makeTmpDir();
    try {
      const cfgPath = writeConfig(dir, makeFlowConfig());
      const calls = [];
      const mockRunner = async (params, script) => { calls.push({ params, script }); return 'agent done'; };
      const h = makeHandlers({ flowConfigPath: cfgPath, orchestrateDir: dir, runPowershell: mockRunner });

      const result = await h.runAgent({ model: 'gemini-2.5-pro', role: 'researcher', prompt: 'analyze this' });
      assert.equal(result, 'agent done');
      assert.ok(calls[0].params.includes('-Model'));
      assert.ok(calls[0].params.includes('gemini-2.5-pro'));
      assert.ok(calls[0].params.includes('-Role'));
      assert.ok(calls[0].params.includes('researcher'));
      assert.ok(calls[0].params.includes('-Prompt'));
      assert.ok(calls[0].params.includes('analyze this'));
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it('appends -Yolo and -Session when provided', async () => {
    const dir = makeTmpDir();
    try {
      const cfgPath = writeConfig(dir, makeFlowConfig());
      const calls = [];
      const mockRunner = async (params, script) => { calls.push(params); return 'ok'; };
      const h = makeHandlers({ flowConfigPath: cfgPath, orchestrateDir: dir, runPowershell: mockRunner });

      await h.runAgent({ model: 'gpt-4', role: 'coder', prompt: 'task', yolo: true, session: 'ses-42' });
      assert.ok(calls[0].includes('-Yolo'));
      assert.ok(calls[0].includes('-Session'));
      assert.ok(calls[0].includes('ses-42'));
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it('uses Run-Agent.ps1 script name', async () => {
    const dir = makeTmpDir();
    try {
      const cfgPath = writeConfig(dir, makeFlowConfig());
      const calls = [];
      const mockRunner = async (params, script) => { calls.push({ params, script }); return 'ok'; };
      const h = makeHandlers({ flowConfigPath: cfgPath, orchestrateDir: dir, runPowershell: mockRunner });

      await h.runAgent({ model: 'm', role: 'r', prompt: 'p' });
      assert.equal(calls[0].script, 'Run-Agent.ps1');
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
});

