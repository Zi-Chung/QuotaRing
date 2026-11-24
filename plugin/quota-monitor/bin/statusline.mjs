#!/usr/bin/env node
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const SNAPSHOT_PATH =
  process.env.AGY_QUOTA_SNAPSHOT ||
  path.join(os.homedir(), '.gemini', 'antigravity-cli', 'quota-snapshot.json');

const MAX_HISTORY = 120;
const MIN_HISTORY_INTERVAL_MS = 60_000;

function readStdin() {
  return new Promise((resolve) => {
    let data = '';
    const timer = setTimeout(() => resolve(data), 1500);
    process.stdin.setEncoding('utf8');
    process.stdin.on('data', (chunk) => {
      data += chunk;
    });
    process.stdin.on('end', () => {
      clearTimeout(timer);
      resolve(data);
    });
    process.stdin.on('error', () => {
      clearTimeout(timer);
      resolve(data);
    });
  });
}

function normalizeBuckets(quotaObj) {
  if (!quotaObj || typeof quotaObj !== 'object') return [];
  const entries = Object.entries(quotaObj).filter(
    ([, val]) => val && typeof val === 'object',
  );

  return entries
    .map(([id, raw]) => {
      const remainingFraction =
        typeof raw.remaining_fraction === 'number'
          ? Math.max(0, Math.min(1, raw.remaining_fraction))
          : typeof raw.remainingFraction === 'number'
            ? Math.max(0, Math.min(1, raw.remainingFraction))
            : null;
      const remainingAmount =
        typeof raw.remaining_amount === 'number'
          ? raw.remaining_amount
          : typeof raw.remainingAmount === 'number'
            ? raw.remainingAmount
            : null;
      const resetTime =
        typeof raw.reset_time === 'string'
          ? raw.reset_time
          : typeof raw.resetTime === 'string'
            ? raw.resetTime
            : null;
      const resetInSeconds =
        typeof raw.reset_in_seconds === 'number'
          ? raw.reset_in_seconds
          : typeof raw.resetInSeconds === 'number'
            ? raw.resetInSeconds
            : resetTime
              ? Math.max(0, Math.round((Date.parse(resetTime) - Date.now()) / 1000))
              : null;
      const disabled = Boolean(raw.disabled);

      return {
        id,
        remainingFraction,
        remainingAmount,
        resetTime,
        resetInSeconds,
        disabled,
      };
    })
    .sort((a, b) => {
      const aWeekly = /weekly/i.test(a.id) ? 0 : 1;
      const bWeekly = /weekly/i.test(b.id) ? 0 : 1;
      if (aWeekly !== bWeekly) return aWeekly - bWeekly;
      return a.id.localeCompare(b.id);
    });
}

function loadExistingSnapshot(filePath) {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch {
    return null;
  }
}

function atomicWriteJson(filePath, data) {
  const dir = path.dirname(filePath);
  fs.mkdirSync(dir, { recursive: true });
  const tmpPath = `${filePath}.${process.pid}.tmp`;
  fs.writeFileSync(tmpPath, JSON.stringify(data, null, 2) + '\n', 'utf8');
  fs.renameSync(tmpPath, filePath);
}

function formatDuration(seconds) {
  if (typeof seconds !== 'number' || !Number.isFinite(seconds)) return '--';
  const s = Math.max(0, Math.floor(seconds));
  const d = Math.floor(s / 86400);
  const h = Math.floor((s % 86400) / 3600);
  const m = Math.floor((s % 3600) / 60);
  if (d > 0) return `${d}d${h}h`;
  if (h > 0) return `${h}h${m}m`;
  return `${m}m`;
}

function formatLocalReset(iso) {
  if (!iso) return '';
  const dt = new Date(iso);
  if (Number.isNaN(dt.getTime())) return '';
  const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  const mm = String(dt.getMonth() + 1).padStart(2, '0');
  const dd = String(dt.getDate()).padStart(2, '0');
  const hh = String(dt.getHours()).padStart(2, '0');
  const mi = String(dt.getMinutes()).padStart(2, '0');
  return `${mm}-${dd} ${days[dt.getDay()]} ${hh}:${mi}`;
}

function colorForFraction(frac) {
  if (frac === null) return '\x1b[36m'; // cyan
  if (frac <= 0.15) return '\x1b[31m'; // red
  if (frac <= 0.4) return '\x1b[33m'; // yellow
  return '\x1b[32m'; // green
}

function makeBar(frac, width = 8) {
  if (frac === null) return '--------';
  const filled = Math.round(frac * width);
  return '█'.repeat(filled) + '░'.repeat(Math.max(0, width - filled));
}

function shortBucketLabel(id) {
  if (/weekly/i.test(id)) return 'Weekly';
  return id.replace(/^gemini-?/i, '').slice(0, 14) || id;
}

async function main() {
  const rawInput = (await readStdin()).trim();
  if (!rawInput) {
    process.stdout.write('\x1b[90mQuota: waiting for CLI payload...\x1b[0m');
    return;
  }

  let payload;
  try {
    payload = JSON.parse(rawInput);
  } catch {
    process.stdout.write('\x1b[90mQuota: invalid statusLine payload\x1b[0m');
    return;
  }

  const nowIso = new Date().toISOString();
  const nowMs = Date.now();
  const buckets = normalizeBuckets(payload.quota);

  const prev = loadExistingSnapshot(SNAPSHOT_PATH);
  let history = Array.isArray(prev?.history) ? prev.history : [];

  if (buckets.length > 0) {
    const sampleBuckets = {};
    for (const b of buckets) {
      if (b.remainingFraction !== null) {
        sampleBuckets[b.id] = Number(b.remainingFraction.toFixed(4));
      }
    }
    const last = history[history.length - 1];
    const lastMs = last ? Date.parse(last.ts) : 0;
    const changed =
      !last || JSON.stringify(last.buckets) !== JSON.stringify(sampleBuckets);
    if (changed || nowMs - lastMs >= MIN_HISTORY_INTERVAL_MS) {
      history = [...history.slice(-(MAX_HISTORY - 1)), { ts: nowIso, buckets: sampleBuckets }];
    }
  }

  const snapshot = {
    version: 1,
    source: 'agy-statusline',
    updatedAt: nowIso,
    planTier: payload.plan_tier ?? payload.planTier ?? null,
    email: payload.email ?? null,
    agentState: payload.agent_state ?? payload.agentState ?? null,
    model: payload.model ?? null,
    buckets,
    history,
  };

  try {
    atomicWriteJson(SNAPSHOT_PATH, snapshot);
  } catch {
    // Do not fail the statusLine if filesystem write fails
  }

  const resetAnsi = '\x1b[0m';
  const dimAnsi = '\x1b[90m';

  if (buckets.length === 0) {
    const tier = snapshot.planTier ? ` [${snapshot.planTier}]` : '';
    process.stdout.write(`${dimAnsi}Quota${tier}: no quota buckets in payload${resetAnsi}`);
    return;
  }

  const parts = buckets.slice(0, 3).map((b) => {
    const label = shortBucketLabel(b.id);
    const pct =
      b.remainingFraction !== null
        ? `${(b.remainingFraction * 100).toFixed(1)}%`
        : b.remainingAmount !== null
          ? `${b.remainingAmount}`
          : '--';
    const color = colorForFraction(b.remainingFraction);
    const bar = makeBar(b.remainingFraction, 8);
    const dur = formatDuration(b.resetInSeconds);
    const localAt = formatLocalReset(b.resetTime);
    const resetInfo = localAt ? `reset ${dur} (${localAt})` : `reset ${dur}`;
    return `${color}${label} [${bar}] ${pct}${resetAnsi} ${dimAnsi}${resetInfo}${resetAnsi}`;
  });

  const tierTag = snapshot.planTier ? `${dimAnsi}[${snapshot.planTier}]${resetAnsi} ` : '';
  process.stdout.write(`${tierTag}${parts.join(` ${dimAnsi}|${resetAnsi} `)}`);
}

main().catch(() => {
  process.stdout.write('\x1b[90mQuota: statusLine error\x1b[0m');
});
