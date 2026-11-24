import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import {
  CallToolRequestSchema,
  ListResourcesRequestSchema,
  ListToolsRequestSchema,
  ReadResourceRequestSchema,
} from '@modelcontextprotocol/sdk/types.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const PLUGIN_ROOT = path.resolve(__dirname, '..');

function parseDataDirArg() {
  for (const arg of process.argv.slice(2)) {
    if (arg.startsWith('--data_dir=')) {
      return arg.slice('--data_dir='.length);
    }
  }
  return path.join(os.homedir(), '.gemini', 'antigravity-cli', 'quota-monitor-data');
}

const DATA_DIR = parseDataDirArg();
const SNAPSHOT_PATH =
  process.env.AGY_QUOTA_SNAPSHOT ||
  path.join(os.homedir(), '.gemini', 'antigravity-cli', 'quota-snapshot.json');
const CLI_SETTINGS_PATH = path.join(
  os.homedir(),
  '.gemini',
  'antigravity-cli',
  'settings.json',
);
const MANUAL_TIMERS_PATH = path.join(DATA_DIR, 'manual-timers.json');
const APP_HTML_PATH =
  process.env.QUOTA_MONITOR_APP_HTML || path.join(PLUGIN_ROOT, 'dist', 'app.html');
const APP_URI = 'ui://quota-monitor/app.html';

function readJsonSafe(filePath, fallback = null) {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch {
    return fallback;
  }
}

function atomicWriteJson(filePath, data) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  const tmpPath = `${filePath}.${process.pid}.tmp`;
  fs.writeFileSync(tmpPath, JSON.stringify(data, null, 2) + '\n', 'utf8');
  fs.renameSync(tmpPath, filePath);
}

function loadManualTimers() {
  const data = readJsonSafe(MANUAL_TIMERS_PATH, { timers: [] });
  return Array.isArray(data?.timers) ? data.timers : [];
}

function saveManualTimers(timers) {
  atomicWriteJson(MANUAL_TIMERS_PATH, { version: 1, timers });
}

function computeLiveBucket(bucket, snapshotUpdatedMs, nowMs) {
  let resetInSeconds = bucket.resetInSeconds ?? null;
  if (bucket.resetTime) {
    const targetMs = Date.parse(bucket.resetTime);
    if (Number.isFinite(targetMs)) {
      resetInSeconds = Math.max(0, Math.round((targetMs - nowMs) / 1000));
    }
  } else if (typeof resetInSeconds === 'number' && Number.isFinite(snapshotUpdatedMs)) {
    const elapsedSec = Math.max(0, Math.round((nowMs - snapshotUpdatedMs) / 1000));
    resetInSeconds = Math.max(0, resetInSeconds - elapsedSec);
  }
  return {
    ...bucket,
    resetInSeconds,
  };
}

function buildStatusPayload() {
  const nowMs = Date.now();
  const nowIso = new Date(nowMs).toISOString();
  const snapshot = readJsonSafe(SNAPSHOT_PATH, null);
  const cliSettings = readJsonSafe(CLI_SETTINGS_PATH, null);
  const statusLineConfigured = Boolean(
    cliSettings?.statusLine?.enabled &&
      typeof cliSettings?.statusLine?.command === 'string' &&
      cliSettings.statusLine.command.includes('statusline'),
  );

  let syncState = 'waiting';
  let ageSeconds = null;
  let buckets = [];
  let history = [];

  if (snapshot && snapshot.updatedAt) {
    const updatedMs = Date.parse(snapshot.updatedAt);
    if (Number.isFinite(updatedMs)) {
      ageSeconds = Math.max(0, Math.round((nowMs - updatedMs) / 1000));
      syncState = ageSeconds <= 180 ? 'live' : 'stale';
    }
    buckets = Array.isArray(snapshot.buckets)
      ? snapshot.buckets.map((b) => computeLiveBucket(b, updatedMs, nowMs))
      : [];
    history = Array.isArray(snapshot.history) ? snapshot.history.slice(-60) : [];
  }

  const manualTimers = loadManualTimers().map((t) => {
    const targetMs = Date.parse(t.resetTime);
    const resetInSeconds = Number.isFinite(targetMs)
      ? Math.max(0, Math.round((targetMs - nowMs) / 1000))
      : null;
    return {
      ...t,
      resetInSeconds,
    };
  });

  return {
    fetchedAt: nowIso,
    syncState,
    ageSeconds,
    statusLineConfigured,
    agyBinHint: path.join(os.homedir(), '.gemini', 'bin', 'agy'),
    snapshotPath: SNAPSHOT_PATH,
    planTier: snapshot?.planTier ?? null,
    email: snapshot?.email ?? null,
    agentState: snapshot?.agentState ?? null,
    model: snapshot?.model ?? null,
    updatedAt: snapshot?.updatedAt ?? null,
    buckets,
    history,
    manualTimers,
  };
}

function formatDurationText(seconds) {
  if (typeof seconds !== 'number' || !Number.isFinite(seconds)) return 'unknown';
  const s = Math.max(0, Math.floor(seconds));
  const d = Math.floor(s / 86400);
  const h = Math.floor((s % 86400) / 3600);
  const m = Math.floor((s % 3600) / 60);
  if (d > 0) return `${d}d ${h}h ${m}m`;
  if (h > 0) return `${h}h ${m}m`;
  return `${m}m`;
}

function buildTextSummary(status) {
  const lines = [];
  lines.push(`# Quota Monitor (${status.syncState.toUpperCase()})`);
  if (status.planTier) lines.push(`- Plan: ${status.planTier}`);
  if (status.updatedAt) {
    lines.push(
      `- Last CLI sync: ${status.updatedAt} (${formatDurationText(status.ageSeconds)} ago)`,
    );
  } else {
    lines.push(
      `- Last CLI sync: none yet. Run \`${status.agyBinHint}\` to stream live official quota updates.`,
    );
  }

  if (status.buckets.length > 0) {
    lines.push('\n## CLI Synced Quotas');
    for (const b of status.buckets) {
      const pct =
        b.remainingFraction !== null
          ? `${(b.remainingFraction * 100).toFixed(1)}%`
          : b.remainingAmount !== null
            ? `${b.remainingAmount}`
            : 'N/A';
      lines.push(
        `- **${b.id}**: ${pct} remaining | resets in ${formatDurationText(b.resetInSeconds)}${b.resetTime ? ` (${b.resetTime})` : ''}`,
      );
    }
  }

  if (status.manualTimers.length > 0) {
    lines.push('\n## Manual Reset Timers');
    for (const t of status.manualTimers) {
      const pct =
        typeof t.remainingPercent === 'number' ? ` (${t.remainingPercent}% left)` : '';
      lines.push(
        `- **${t.label}**${pct}: resets in ${formatDurationText(t.resetInSeconds)} (${t.resetTime})`,
      );
    }
  }

  return lines.join('\n');
}

const server = new Server(
  {
    name: 'quota-monitor',
    version: '1.0.0',
  },
  {
    capabilities: {
      tools: {},
      resources: {},
    },
  },
);

server.setRequestHandler(ListResourcesRequestSchema, async () => ({
  resources: [
    {
      uri: APP_URI,
      name: 'Quota Monitor App',
      description: 'Interactive Antigravity quota and reset countdown dashboard',
      mimeType: 'text/html;profile=mcp-app',
      _meta: {
        ui: {
          prefersBorder: false,
        },
      },
    },
  ],
}));

server.setRequestHandler(ReadResourceRequestSchema, async (request) => {
  if (request.params.uri !== APP_URI) {
    throw new Error(`Unknown resource URI: ${request.params.uri}`);
  }
  const html = fs.readFileSync(APP_HTML_PATH, 'utf8');
  return {
    contents: [
      {
        uri: APP_URI,
        mimeType: 'text/html;profile=mcp-app',
        text: html,
        _meta: {
          ui: {
            prefersBorder: false,
          },
        },
      },
    ],
  };
});

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: 'open_quota_monitor',
      title: 'Quota Monitor',
      description:
        'Open the interactive Quota Monitor panel showing live Antigravity weekly/rolling quotas synced from the official agy CLI statusLine plus manual reset countdowns.',
      inputSchema: {
        type: 'object',
        properties: {},
        additionalProperties: false,
      },
      _meta: {
        ui: {
          resourceUri: APP_URI,
        },
        'com.google.antigravity/ui': {
          entrypoints: [
            { type: 'aux_pane', title: 'Quota Monitor' },
            { type: 'global', title: 'Quota Monitor' },
          ],
        },
      },
    },
    {
      name: 'get_quota_status',
      title: 'Get Quota Status',
      description: 'Fetch the latest quota snapshot and manual timers for the UI.',
      inputSchema: {
        type: 'object',
        properties: {},
        additionalProperties: false,
      },
      _meta: {
        ui: {
          visibility: ['app'],
        },
      },
    },
    {
      name: 'save_manual_timer',
      title: 'Save Manual Reset Timer',
      description: 'Create or update a manual quota reset countdown timer.',
      inputSchema: {
        type: 'object',
        properties: {
          id: { type: 'string' },
          label: { type: 'string' },
          resetTime: { type: 'string' },
          remainingPercent: { type: ['number', 'null'] },
          note: { type: 'string' },
        },
        required: ['label', 'resetTime'],
        additionalProperties: false,
      },
      _meta: {
        ui: {
          visibility: ['app'],
        },
      },
    },
    {
      name: 'delete_manual_timer',
      title: 'Delete Manual Reset Timer',
      description: 'Remove a manual quota reset countdown timer by id.',
      inputSchema: {
        type: 'object',
        properties: {
          id: { type: 'string' },
        },
        required: ['id'],
        additionalProperties: false,
      },
      _meta: {
        ui: {
          visibility: ['app'],
        },
      },
    },
  ],
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args = {} } = request.params;

  if (name === 'open_quota_monitor' || name === 'get_quota_status') {
    const status = buildStatusPayload();
    return {
      content: [{ type: 'text', text: buildTextSummary(status) }],
      structuredContent: status,
    };
  }

  if (name === 'save_manual_timer') {
    const label = String(args.label || '').trim();
    const resetTimeRaw = String(args.resetTime || '').trim();
    const parsedMs = Date.parse(resetTimeRaw);
    if (!label || !Number.isFinite(parsedMs)) {
      return {
        isError: true,
        content: [{ type: 'text', text: 'Invalid label or resetTime.' }],
      };
    }
    const timers = loadManualTimers();
    const id =
      typeof args.id === 'string' && args.id.trim()
        ? args.id.trim()
        : `timer-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;
    const remainingPercent =
      typeof args.remainingPercent === 'number' && Number.isFinite(args.remainingPercent)
        ? Math.max(0, Math.min(100, args.remainingPercent))
        : null;
    const entry = {
      id,
      label,
      resetTime: new Date(parsedMs).toISOString(),
      remainingPercent,
      note: typeof args.note === 'string' ? args.note.trim() : '',
      updatedAt: new Date().toISOString(),
    };
    const idx = timers.findIndex((t) => t.id === id);
    if (idx >= 0) timers[idx] = entry;
    else timers.push(entry);
    saveManualTimers(timers);

    const status = buildStatusPayload();
    return {
      content: [{ type: 'text', text: `Saved manual timer "${label}".` }],
      structuredContent: status,
    };
  }

  if (name === 'delete_manual_timer') {
    const id = String(args.id || '').trim();
    const timers = loadManualTimers().filter((t) => t.id !== id);
    saveManualTimers(timers);

    const status = buildStatusPayload();
    return {
      content: [{ type: 'text', text: `Deleted manual timer "${id}".` }],
      structuredContent: status,
    };
  }

  return {
    isError: true,
    content: [{ type: 'text', text: `Unknown tool: ${name}` }],
  };
});

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch((err) => {
  console.error('quota-monitor MCP server failed:', err);
  process.exit(1);
});
