#!/usr/bin/env node
/**
 * Cross-platform installer (macOS / Windows / Linux) for the QuotaRing Antigravity plugin:
 * 1. Copies the built plugin bundle to ~/.gemini/config/plugins/quota-monitor/
 * 2. Safely configures ~/.gemini/antigravity-cli/settings.json statusLine hook
 * 3. Initializes ~/.config/quota-bar/providers/ with example open-slot files
 */
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const PLUGIN_SRC = path.resolve(__dirname, '..');
const REPO_ROOT = path.resolve(PLUGIN_SRC, '..', '..');
const HOME = os.homedir();

const PLUGIN_DEST = path.join(HOME, '.gemini', 'config', 'plugins', 'quota-monitor');
const CLI_SETTINGS_PATH = path.join(HOME, '.gemini', 'antigravity-cli', 'settings.json');
const PROVIDERS_DEST = path.join(HOME, '.config', 'quota-bar', 'providers');

function copyDir(src, dst, skipNames = new Set()) {
  fs.mkdirSync(dst, { recursive: true });
  for (const entry of fs.readdirSync(src, { withFileTypes: true })) {
    if (skipNames.has(entry.name)) continue;
    const s = path.join(src, entry.name);
    const d = path.join(dst, entry.name);
    if (entry.isDirectory()) {
      copyDir(s, d, skipNames);
    } else {
      fs.copyFileSync(s, d);
    }
  }
}

function main() {
  const distHtml = path.join(PLUGIN_SRC, 'dist', 'app.html');
  if (!fs.existsSync(distHtml)) {
    console.error('Error: dist/app.html not found. Run `npm install && npm run build` first.');
    process.exit(1);
  }

  console.log(`==> Installing plugin to ${PLUGIN_DEST}`);
  copyDir(PLUGIN_SRC, PLUGIN_DEST, new Set(['.git', '.DS_Store']));

  const statusLineScript = path.join(PLUGIN_DEST, 'bin', 'statusline.mjs');
  const nodeBin = process.execPath;
  const statusCommand = `"${nodeBin}" "${statusLineScript}"`;

  let settings = {};
  if (fs.existsSync(CLI_SETTINGS_PATH)) {
    try {
      settings = JSON.parse(fs.readFileSync(CLI_SETTINGS_PATH, 'utf8'));
    } catch {
      console.warn(`Warning: existing ${CLI_SETTINGS_PATH} could not be parsed; backing up.`);
      fs.copyFileSync(CLI_SETTINGS_PATH, `${CLI_SETTINGS_PATH}.bak`);
    }
  }

  settings.statusLine = {
    type: 'command',
    command: statusCommand,
    enabled: true,
    padding: 0,
    stack_with_default: true,
  };

  fs.mkdirSync(path.dirname(CLI_SETTINGS_PATH), { recursive: true });
  fs.writeFileSync(CLI_SETTINGS_PATH, JSON.stringify(settings, null, 2) + '\n', 'utf8');
  console.log(`==> Updated ${CLI_SETTINGS_PATH}`);

  const providersSrc = path.join(REPO_ROOT, 'providers');
  if (fs.existsSync(providersSrc)) {
    fs.mkdirSync(PROVIDERS_DEST, { recursive: true });
    for (const file of ['README.md', 'cursor.json.example', 'grokbot.json.example']) {
      const s = path.join(providersSrc, file);
      const d = path.join(PROVIDERS_DEST, file);
      if (fs.existsSync(s) && !fs.existsSync(d)) {
        fs.copyFileSync(s, d);
      }
    }
    console.log(`==> Initialized open slots directory: ${PROVIDERS_DEST}`);
  }

  console.log('\nDone! Launch `agy` in your terminal to push live official quota snapshots.');
}

main();
