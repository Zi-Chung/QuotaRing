import {
  App,
  applyDocumentTheme,
  applyHostStyleVariables,
} from '@modelcontextprotocol/ext-apps';

interface QuotaBucket {
  id: string;
  remainingFraction: number | null;
  remainingAmount: number | null;
  resetTime: string | null;
  resetInSeconds: number | null;
  disabled?: boolean;
}

interface HistorySample {
  ts: string;
  buckets: Record<string, number>;
}

interface ManualTimer {
  id: string;
  label: string;
  resetTime: string;
  remainingPercent: number | null;
  note?: string;
  resetInSeconds: number | null;
}

interface QuotaStatus {
  fetchedAt: string;
  syncState: 'live' | 'stale' | 'waiting';
  ageSeconds: number | null;
  statusLineConfigured: boolean;
  agyBinHint: string;
  snapshotPath: string;
  planTier: string | null;
  email: string | null;
  agentState: string | null;
  model: { id?: string; display_name?: string } | string | null;
  updatedAt: string | null;
  buckets: QuotaBucket[];
  history: HistorySample[];
  manualTimers: ManualTimer[];
}

const app = new App({ name: 'Quota Monitor', version: '1.0.0' }, {});

let currentStatus: QuotaStatus | null = null;
let autoRefresh = true;
let isFetching = false;
let showTimerForm = false;
let lastError = '';

const root = document.getElementById('app')!;

function escapeHtml(text: string): string {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function formatCountdown(resetTime: string | null, fallbackSeconds: number | null): string {
  let secs: number | null = fallbackSeconds;
  if (resetTime) {
    const ms = Date.parse(resetTime);
    if (Number.isFinite(ms)) {
      secs = Math.max(0, Math.floor((ms - Date.now()) / 1000));
    }
  }
  if (secs === null || !Number.isFinite(secs)) return '--';
  if (secs <= 0) return '已到重置时间';

  const d = Math.floor(secs / 86400);
  const h = Math.floor((secs % 86400) / 3600);
  const m = Math.floor((secs % 3600) / 60);
  const s = secs % 60;
  const pad = (n: number) => String(n).padStart(2, '0');
  if (d > 0) return `${d}天 ${pad(h)}:${pad(m)}:${pad(s)}`;
  return `${pad(h)}:${pad(m)}:${pad(s)}`;
}

function formatDateTime(iso: string | null): string {
  if (!iso) return '未知';
  const dt = new Date(iso);
  if (Number.isNaN(dt.getTime())) return iso;
  const weekdays = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
  const y = dt.getFullYear();
  const mo = String(dt.getMonth() + 1).padStart(2, '0');
  const da = String(dt.getDate()).padStart(2, '0');
  const hh = String(dt.getHours()).padStart(2, '0');
  const mi = String(dt.getMinutes()).padStart(2, '0');
  return `${y}-${mo}-${da} (${weekdays[dt.getDay()]}) ${hh}:${mi}`;
}

function formatRelativeAge(iso: string | null): string {
  if (!iso) return '尚未同步';
  const ms = Date.parse(iso);
  if (!Number.isFinite(ms)) return '未知';
  const sec = Math.max(0, Math.floor((Date.now() - ms) / 1000));
  if (sec < 5) return '刚刚';
  if (sec < 60) return `${sec} 秒前`;
  if (sec < 3600) return `${Math.floor(sec / 60)} 分钟前`;
  if (sec < 86400) return `${Math.floor(sec / 3600)} 小时前`;
  return `${Math.floor(sec / 86400)} 天前`;
}

function bucketTitle(id: string): string {
  const lower = id.toLowerCase();
  if (lower === 'gemini-weekly') return 'Gemini · 周额度';
  if (lower === 'gemini-5h') return 'Gemini · 5 小时额度';
  if (lower === '3p-weekly') return '第三方模型 (3P) · 周额度';
  if (lower === '3p-5h') return '第三方模型 (3P) · 5 小时额度';
  if (/weekly/i.test(id)) return `周额度 (${id})`;
  return id;
}

function toneClass(fraction: number | null): string {
  if (fraction === null) return 'tone-info';
  if (fraction <= 0.15) return 'tone-danger';
  if (fraction <= 0.4) return 'tone-warning';
  return 'tone-success';
}

function renderSparkline(bucketId: string, history: HistorySample[]): string {
  const points = history
    .map((h) => h.buckets?.[bucketId])
    .filter((v): v is number => typeof v === 'number' && Number.isFinite(v));
  if (points.length < 2) return '';

  const w = 180;
  const h = 30;
  const coords = points.map((v, i) => {
    const x = (i / (points.length - 1)) * w;
    const y = h - Math.max(0, Math.min(1, v)) * (h - 4) - 2;
    return `${x.toFixed(1)},${y.toFixed(1)}`;
  });

  return `
    <div class="sparkline-wrap" title="近期剩余额度变化趋势 (${points.length} 个采样点)">
      <svg class="sparkline" viewBox="0 0 ${w} ${h}" preserveAspectRatio="none">
        <polyline fill="none" stroke="currentColor" stroke-width="1.75" points="${coords.join(' ')}" />
      </svg>
      <span class="sparkline-label">趋势 (${points.length})</span>
    </div>
  `;
}

function syncBadge(status: QuotaStatus): { cls: string; text: string } {
  if (status.syncState === 'live') return { cls: 'badge-live', text: 'CLI 实时同步中' };
  if (status.syncState === 'stale') return { cls: 'badge-stale', text: 'CLI 离线 (缓存快照)' };
  return { cls: 'badge-waiting', text: '等待 agy CLI 推送' };
}

function modelDisplay(model: QuotaStatus['model']): string {
  if (!model) return '';
  if (typeof model === 'string') return model;
  return model.display_name || model.id || '';
}

function defaultDatetimeLocal(): string {
  const dt = new Date(Date.now() + 7 * 24 * 3600 * 1000);
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${dt.getFullYear()}-${pad(dt.getMonth() + 1)}-${pad(dt.getDate())}T${pad(dt.getHours())}:${pad(dt.getMinutes())}`;
}

function render(): void {
  if (!currentStatus) {
    root.innerHTML = `<div class="empty-loading">正在加载配额监控数据...</div>`;
    return;
  }

  const s = currentStatus;
  const badge = syncBadge(s);
  const activeModel = modelDisplay(s.model);

  const bucketsHtml =
    s.buckets.length > 0
      ? s.buckets
          .map((b) => {
            const pctNum =
              b.remainingFraction !== null ? Math.round(b.remainingFraction * 1000) / 10 : null;
            const pctStr =
              pctNum !== null
                ? `${pctNum.toFixed(1)}%`
                : b.remainingAmount !== null
                  ? `${b.remainingAmount}`
                  : '--';
            const barWidth = pctNum !== null ? Math.max(0, Math.min(100, pctNum)) : 0;
            const tone = toneClass(b.remainingFraction);
            const countdown = formatCountdown(b.resetTime, b.resetInSeconds);
            const resetLocal = formatDateTime(b.resetTime);

            return `
              <div class="card bucket-card ${tone}">
                <div class="card-top">
                  <div class="bucket-name">${escapeHtml(bucketTitle(b.id))}</div>
                  <div class="bucket-pct">${escapeHtml(pctStr)}</div>
                </div>
                <div class="progress-track">
                  <div class="progress-fill" style="width:${barWidth}%"></div>
                </div>
                <div class="meta-grid">
                  <div class="meta-item">
                    <span class="meta-label">距离重置</span>
                    <span class="meta-value countdown" data-reset-time="${escapeHtml(b.resetTime || '')}" data-fallback-sec="${b.resetInSeconds ?? ''}">${escapeHtml(countdown)}</span>
                  </div>
                  <div class="meta-item">
                    <span class="meta-label">重置时间</span>
                    <span class="meta-value">${escapeHtml(resetLocal)}</span>
                  </div>
                </div>
                ${renderSparkline(b.id, s.history)}
              </div>
            `;
          })
          .join('')
      : `
        <div class="card hint-card">
          <div class="hint-title">尚未收到 agy CLI 的官方配额推送</div>
          <p class="hint-body">
            本插件通过 Antigravity CLI 官方 <code>statusLine</code> 钩子获取实时周额度与重置时间。
            配置状态：<strong>${s.statusLineConfigured ? '已就绪 ✓' : '未配置'}</strong>
          </p>
          <p class="hint-body">在终端中运行以下命令启动 CLI 后，本面板会自动刷新：</p>
          <pre class="code-box">${escapeHtml(s.agyBinHint)}</pre>
          <p class="hint-sub">如果暂时不用 CLI，也可以在下方添加一个手动重置倒计时。</p>
        </div>
      `;

  const manualListHtml =
    s.manualTimers.length > 0
      ? s.manualTimers
          .map((t) => {
            const pctBadge =
              typeof t.remainingPercent === 'number'
                ? `<span class="mini-pill">${t.remainingPercent}% 剩余</span>`
                : '';
            const countdown = formatCountdown(t.resetTime, t.resetInSeconds);
            return `
              <div class="card manual-card">
                <div class="card-top">
                  <div class="manual-title-row">
                    <span class="bucket-name">${escapeHtml(t.label)}</span>
                    ${pctBadge}
                  </div>
                  <button class="btn-icon" data-delete-timer="${escapeHtml(t.id)}" title="删除">✕</button>
                </div>
                <div class="meta-grid">
                  <div class="meta-item">
                    <span class="meta-label">距离重置</span>
                    <span class="meta-value countdown" data-reset-time="${escapeHtml(t.resetTime)}">${escapeHtml(countdown)}</span>
                  </div>
                  <div class="meta-item">
                    <span class="meta-label">目标时间</span>
                    <span class="meta-value">${escapeHtml(formatDateTime(t.resetTime))}</span>
                  </div>
                </div>
                ${t.note ? `<div class="manual-note">${escapeHtml(t.note)}</div>` : ''}
              </div>
            `;
          })
          .join('')
      : `<div class="muted-empty">暂无手动倒计时。可从 Settings → Models 复制重置时间到这里持续倒计时。</div>`;

  const formHtml = showTimerForm
    ? `
      <form id="timer-form" class="card form-card">
        <div class="form-row">
          <label>名称</label>
          <input name="label" type="text" required placeholder="例如：Antigravity 周额度" value="Antigravity 周额度" />
        </div>
        <div class="form-row">
          <label>重置时间（本地时间）</label>
          <input name="resetTime" type="datetime-local" required value="${escapeHtml(defaultDatetimeLocal())}" />
        </div>
        <div class="form-row">
          <label>当前剩余比例 %（可选）</label>
          <input name="remainingPercent" type="number" min="0" max="100" step="0.1" placeholder="例如：65" />
        </div>
        <div class="form-row">
          <label>备注（可选）</label>
          <input name="note" type="text" placeholder="例如：来自 Settings 页面" />
        </div>
        <div class="form-actions">
          <button type="submit" class="btn btn-primary">保存倒计时</button>
          <button type="button" id="cancel-form" class="btn">取消</button>
        </div>
      </form>
    `
    : '';

  root.innerHTML = `
    <div class="container">
      <header class="header">
        <div class="title-block">
          <h1>Quota Monitor</h1>
          <div class="sub-row">
            <span class="badge ${badge.cls}"><span class="dot"></span>${badge.text}</span>
            ${s.planTier ? `<span class="mini-pill">${escapeHtml(s.planTier)}</span>` : ''}
            ${activeModel ? `<span class="mini-pill">${escapeHtml(activeModel)}</span>` : ''}
          </div>
        </div>
        <div class="actions">
          <label class="toggle">
            <input type="checkbox" id="auto-refresh-toggle" ${autoRefresh ? 'checked' : ''} />
            <span>自动刷新</span>
          </label>
          <button id="refresh-btn" class="btn" ${isFetching ? 'disabled' : ''}>${isFetching ? '刷新中...' : '刷新'}</button>
        </div>
      </header>

      <div class="sync-strip">
        <span>上次同步：<strong id="sync-age" data-updated-at="${escapeHtml(s.updatedAt || '')}">${escapeHtml(formatRelativeAge(s.updatedAt))}</strong></span>
        ${s.updatedAt ? `<span class="sync-time">${escapeHtml(formatDateTime(s.updatedAt))}</span>` : ''}
      </div>

      ${lastError ? `<div class="error-banner">${escapeHtml(lastError)}</div>` : ''}

      <section class="section">
        <div class="section-header">
          <h2>官方 CLI 配额快照</h2>
        </div>
        <div class="cards-stack">${bucketsHtml}</div>
      </section>

      <section class="section">
        <div class="section-header">
          <h2>手动重置倒计时</h2>
          <button id="toggle-form-btn" class="btn btn-sm">${showTimerForm ? '收起' : '+ 添加'}</button>
        </div>
        ${formHtml}
        <div class="cards-stack">${manualListHtml}</div>
      </section>
    </div>
  `;

  bindEvents();
}

function bindEvents(): void {
  const refreshBtn = document.getElementById('refresh-btn');
  refreshBtn?.addEventListener('click', () => {
    void refreshFromServer();
  });

  const autoToggle = document.getElementById('auto-refresh-toggle') as HTMLInputElement | null;
  autoToggle?.addEventListener('change', () => {
    autoRefresh = autoToggle.checked;
  });

  const toggleFormBtn = document.getElementById('toggle-form-btn');
  toggleFormBtn?.addEventListener('click', () => {
    showTimerForm = !showTimerForm;
    render();
  });

  const cancelBtn = document.getElementById('cancel-form');
  cancelBtn?.addEventListener('click', () => {
    showTimerForm = false;
    render();
  });

  const form = document.getElementById('timer-form') as HTMLFormElement | null;
  form?.addEventListener('submit', async (ev) => {
    ev.preventDefault();
    const fd = new FormData(form);
    const label = String(fd.get('label') || '').trim();
    const resetTimeLocal = String(fd.get('resetTime') || '').trim();
    const pctStr = String(fd.get('remainingPercent') || '').trim();
    const note = String(fd.get('note') || '').trim();
    if (!label || !resetTimeLocal) return;

    const dt = new Date(resetTimeLocal);
    if (Number.isNaN(dt.getTime())) {
      lastError = '无效的日期时间格式';
      render();
      return;
    }

    try {
      lastError = '';
      const res = await app.callServerTool({
        name: 'save_manual_timer',
        arguments: {
          label,
          resetTime: dt.toISOString(),
          remainingPercent: pctStr === '' ? null : Number(pctStr),
          note,
        },
      });
      if (res?.structuredContent) {
        currentStatus = res.structuredContent as unknown as QuotaStatus;
      }
      showTimerForm = false;
      render();
    } catch (err) {
      lastError = err instanceof Error ? err.message : String(err);
      render();
    }
  });

  root.querySelectorAll<HTMLButtonElement>('[data-delete-timer]').forEach((btn) => {
    btn.addEventListener('click', async () => {
      const id = btn.dataset.deleteTimer;
      if (!id) return;
      try {
        lastError = '';
        const res = await app.callServerTool({
          name: 'delete_manual_timer',
          arguments: { id },
        });
        if (res?.structuredContent) {
          currentStatus = res.structuredContent as unknown as QuotaStatus;
        }
        render();
      } catch (err) {
        lastError = err instanceof Error ? err.message : String(err);
        render();
      }
    });
  });
}

async function refreshFromServer(): Promise<void> {
  if (isFetching) return;
  isFetching = true;
  render();
  try {
    lastError = '';
    const res = await app.callServerTool({
      name: 'get_quota_status',
      arguments: {},
    });
    if (res?.structuredContent) {
      currentStatus = res.structuredContent as unknown as QuotaStatus;
    }
  } catch (err) {
    lastError = err instanceof Error ? err.message : String(err);
  } finally {
    isFetching = false;
    render();
  }
}

function tickCountdowns(): void {
  root.querySelectorAll<HTMLElement>('.countdown').forEach((el) => {
    const resetTime = el.dataset.resetTime || null;
    const fallbackStr = el.dataset.fallbackSec;
    const fallbackSec = fallbackStr ? Number(fallbackStr) : null;
    if (resetTime) {
      el.textContent = formatCountdown(resetTime, fallbackSec);
    }
  });
  const syncAgeEl = document.getElementById('sync-age');
  if (syncAgeEl && syncAgeEl.dataset.updatedAt) {
    syncAgeEl.textContent = formatRelativeAge(syncAgeEl.dataset.updatedAt);
  }
}

// Register handlers BEFORE connect()
app.ontoolinput = () => {
  if (!currentStatus) render();
};

app.ontoolresult = (result) => {
  if (result?.structuredContent) {
    currentStatus = result.structuredContent as unknown as QuotaStatus;
    render();
  }
};

app.onhostcontextchanged = (ctx) => {
  if (ctx.theme) applyDocumentTheme(ctx.theme);
  if (ctx.styles?.variables) applyHostStyleVariables(ctx.styles.variables);
};

async function boot(): Promise<void> {
  render();
  await app.connect();
  const ctx = app.getHostContext();
  if (ctx?.theme) applyDocumentTheme(ctx.theme);
  if (ctx?.styles?.variables) applyHostStyleVariables(ctx.styles.variables);

  if (!currentStatus) {
    void refreshFromServer();
  }

  window.setInterval(tickCountdowns, 1000);
  window.setInterval(() => {
    if (autoRefresh && !showTimerForm) {
      void refreshFromServer();
    }
  }, 10000);
}

boot().catch((err) => {
  lastError = err instanceof Error ? err.message : String(err);
  render();
});
