import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import esbuild from 'esbuild';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const ROOT = path.resolve(__dirname, '..');

const CSS = `
*, *::before, *::after { box-sizing: border-box; }
html, body {
  margin: 0;
  padding: 0;
  background: var(--color-background-primary, #111318);
  color: var(--color-text-primary, #f3f4f6);
  font-family: var(--font-sans, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif);
  font-size: 13px;
  line-height: 1.45;
}
.container {
  padding: 14px 16px 20px;
  max-width: 720px;
  margin: 0 auto;
}
.header {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  gap: 10px;
  flex-wrap: wrap;
  margin-bottom: 10px;
}
.title-block h1 {
  margin: 0 0 6px;
  font-size: 16px;
  font-weight: 600;
}
.sub-row {
  display: flex;
  align-items: center;
  gap: 6px;
  flex-wrap: wrap;
}
.actions {
  display: flex;
  align-items: center;
  gap: 8px;
}
.toggle {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  font-size: 12px;
  color: var(--color-text-secondary, #9ca3af);
  cursor: pointer;
}
.btn {
  appearance: none;
  border: 1px solid var(--color-border-primary, #2e333d);
  background: var(--color-background-secondary, #1a1d24);
  color: var(--color-text-primary, #f3f4f6);
  border-radius: 6px;
  padding: 5px 10px;
  font-size: 12px;
  cursor: pointer;
}
.btn:hover { filter: brightness(1.08); }
.btn:disabled { opacity: 0.6; cursor: default; }
.btn-sm { padding: 3px 8px; font-size: 11px; }
.btn-primary {
  background: var(--color-background-info, #2563eb);
  border-color: var(--color-border-info, #3b82f6);
  color: var(--color-text-inverse, #ffffff);
}
.btn-icon {
  appearance: none;
  border: none;
  background: transparent;
  color: var(--color-text-secondary, #9ca3af);
  cursor: pointer;
  padding: 2px 6px;
  border-radius: 4px;
}
.btn-icon:hover {
  color: var(--color-text-danger, #ef4444);
  background: var(--color-background-tertiary, #232730);
}
.badge {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 2px 8px;
  border-radius: 999px;
  font-size: 11px;
  font-weight: 500;
  border: 1px solid var(--color-border-primary, #2e333d);
}
.dot {
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: currentColor;
}
.badge-live {
  color: var(--color-text-success, #22c55e);
  background: var(--color-background-success, rgba(34, 197, 94, 0.12));
  border-color: var(--color-border-success, rgba(34, 197, 94, 0.35));
}
.badge-stale {
  color: var(--color-text-warning, #f59e0b);
  background: var(--color-background-warning, rgba(245, 158, 11, 0.12));
  border-color: var(--color-border-warning, rgba(245, 158, 11, 0.35));
}
.badge-waiting {
  color: var(--color-text-secondary, #9ca3af);
  background: var(--color-background-secondary, #1a1d24);
}
.mini-pill {
  font-size: 11px;
  padding: 2px 7px;
  border-radius: 999px;
  background: var(--color-background-tertiary, #232730);
  color: var(--color-text-secondary, #cbd5e1);
}
.sync-strip {
  display: flex;
  justify-content: space-between;
  align-items: center;
  font-size: 11px;
  color: var(--color-text-secondary, #9ca3af);
  padding: 6px 10px;
  border-radius: 6px;
  background: var(--color-background-secondary, #1a1d24);
  border: 1px solid var(--color-border-secondary, #262a33);
  margin-bottom: 14px;
}
.error-banner {
  padding: 8px 10px;
  border-radius: 6px;
  margin-bottom: 12px;
  font-size: 12px;
  color: var(--color-text-danger, #f87171);
  background: var(--color-background-danger, rgba(239, 68, 68, 0.12));
  border: 1px solid var(--color-border-danger, rgba(239, 68, 68, 0.35));
}
.section { margin-bottom: 16px; }
.section-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 8px;
}
.section-header h2 {
  margin: 0;
  font-size: 12px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  color: var(--color-text-secondary, #9ca3af);
}
.cards-stack {
  display: flex;
  flex-direction: column;
  gap: 10px;
}
.card {
  background: var(--color-background-secondary, #1a1d24);
  border: 1px solid var(--color-border-primary, #2e333d);
  border-radius: 10px;
  padding: 12px 14px;
}
.card-top {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 8px;
  margin-bottom: 8px;
}
.bucket-name { font-weight: 600; font-size: 13px; }
.bucket-pct { font-weight: 700; font-size: 15px; font-variant-numeric: tabular-nums; }
.tone-success .bucket-pct, .tone-success .progress-fill, .tone-success .sparkline { color: var(--color-text-success, #22c55e); }
.tone-warning .bucket-pct, .tone-warning .progress-fill, .tone-warning .sparkline { color: var(--color-text-warning, #f59e0b); }
.tone-danger .bucket-pct, .tone-danger .progress-fill, .tone-danger .sparkline { color: var(--color-text-danger, #ef4444); }
.tone-info .bucket-pct, .tone-info .progress-fill, .tone-info .sparkline { color: var(--color-text-info, #38bdf8); }
.progress-track {
  width: 100%;
  height: 7px;
  border-radius: 999px;
  background: var(--color-background-tertiary, #272c36);
  overflow: hidden;
  margin-bottom: 10px;
}
.progress-fill {
  height: 100%;
  border-radius: 999px;
  background: currentColor;
  transition: width 0.25s ease;
}
.meta-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 8px;
}
.meta-item {
  display: flex;
  flex-direction: column;
  gap: 2px;
}
.meta-label {
  font-size: 11px;
  color: var(--color-text-tertiary, #9ca3af);
}
.meta-value {
  font-size: 12px;
  font-weight: 500;
  font-variant-numeric: tabular-nums;
}
.sparkline-wrap {
  margin-top: 10px;
  padding-top: 8px;
  border-top: 1px solid var(--color-border-secondary, #262a33);
  display: flex;
  align-items: center;
  gap: 10px;
}
.sparkline {
  flex: 1;
  height: 28px;
  display: block;
}
.sparkline-label {
  font-size: 11px;
  color: var(--color-text-tertiary, #9ca3af);
}
.hint-title {
  font-weight: 600;
  margin-bottom: 6px;
}
.hint-body, .hint-sub {
  margin: 0 0 8px;
  color: var(--color-text-secondary, #cbd5e1);
  font-size: 12px;
}
.hint-sub { margin-bottom: 0; color: var(--color-text-tertiary, #9ca3af); }
.code-box {
  margin: 0 0 8px;
  padding: 8px 10px;
  border-radius: 6px;
  background: var(--color-background-tertiary, #111318);
  border: 1px solid var(--color-border-secondary, #262a33);
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
  font-size: 12px;
  overflow-x: auto;
}
.manual-title-row {
  display: flex;
  align-items: center;
  gap: 6px;
}
.manual-note {
  margin-top: 8px;
  font-size: 11px;
  color: var(--color-text-secondary, #9ca3af);
}
.muted-empty, .empty-loading {
  font-size: 12px;
  color: var(--color-text-tertiary, #9ca3af);
  padding: 12px;
  text-align: center;
  border: 1px dashed var(--color-border-secondary, #2e333d);
  border-radius: 8px;
}
.form-card { margin-bottom: 10px; }
.form-row {
  display: flex;
  flex-direction: column;
  gap: 4px;
  margin-bottom: 8px;
}
.form-row label {
  font-size: 11px;
  color: var(--color-text-secondary, #9ca3af);
}
.form-row input {
  width: 100%;
  padding: 6px 8px;
  border-radius: 6px;
  border: 1px solid var(--color-border-primary, #2e333d);
  background: var(--color-background-primary, #111318);
  color: var(--color-text-primary, #f3f4f6);
  font-size: 12px;
}
.form-actions {
  display: flex;
  gap: 8px;
  margin-top: 10px;
}
`;

async function build() {
  const result = await esbuild.build({
    entryPoints: [path.join(ROOT, 'src', 'app.ts')],
    bundle: true,
    format: 'esm',
    target: 'es2022',
    minify: true,
    write: false,
  });

  const jsCode = result.outputFiles[0].text.replace(/<\/script>/gi, '<\\/script>');
  const html = `<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Quota Monitor</title>
  <style>${CSS}</style>
</head>
<body>
  <div id="app"></div>
  <script type="module">${jsCode}</script>
</body>
</html>
`;

  const distDir = path.join(ROOT, 'dist');
  fs.mkdirSync(distDir, { recursive: true });
  fs.writeFileSync(path.join(distDir, 'app.html'), html, 'utf8');
  console.log(`Built dist/app.html (${Buffer.byteLength(html, 'utf8')} bytes)`);
}

build().catch((err) => {
  console.error(err);
  process.exit(1);
});
