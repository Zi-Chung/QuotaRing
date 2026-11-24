# QuotaRing

> Minimalist concentric dual-ring AI quota monitor for **macOS** & **Windows** — **zero credentials, zero network requests, 100% local read-only**.

[简体中文](./README.zh-CN.md) | English

---

## Why QuotaRing?

Most AI quota monitors extract OAuth tokens, decrypt browser cookies via OS Keychain, or poll undocumented internal APIs — creating security risks and potential Terms-of-Service issues.

**QuotaRing takes a strictly local-first, zero-auth approach:**

- **Zero Auth & Zero Network**: Never reads Keychain, never scrapes browser cookies, never proxies or calls cloud APIs.
- **Concentric Dual-Ring Design**:
  - **Outer Ring** — Remaining quota (`0%–100%`)
  - **Inner Ring** — Time remaining until quota reset
  - **`5` / `W` / `M` Rings** — Ultra-compact `5 [◎]  W [◎]` or `M [◎]` (5-hour, weekly, monthly, or custom cycles) in the macOS menu bar, or crisp high-DPI dual-ring in the Windows system tray.
- **Multi-Provider Support**:
  - **Antigravity**: Synced via the official `agy` CLI `statusLine` hook (bundled cross-platform MCP App plugin included).
  - **OpenAI Codex**: Automatically reads local session logs under `~/.codex/sessions/**/*.jsonl` (`rate_limits`).
  - **Open Provider Slots**: Drop any `*.json` file into `~/.config/quota-bar/providers/` (e.g., `cursor.json`, `grokbot.json`, `claude.json`) to visualize any brand with the same dual-ring UI.
- **2-Key Global Summon (`⌥Q` / `Alt+Q`)**: Even if the macOS notch or Windows tray overflow hides the icon, press **`⌥Q`** (macOS) or **`Alt+Q`** (Windows) anytime to pop up the quota card immediately — no macOS Accessibility permission required.
- **Native & Ultra-Lightweight**:
  - **macOS**: Pure Swift + AppKit (`~1 MB`, zero Electron bloat, automatic Dark/Light template icon).
  - **Windows**: Native .NET 8 WinForms single-file tray app (zero third-party NuGet dependencies, automatic Dark/Light taskbar adaptation).

---

## Project Structure

```text
QuotaRing/
├── apps/
│   ├── macos/                  # Native Swift / AppKit macOS menu bar app
│   └── windows/                # Native .NET 8 WinForms Windows system tray app
├── plugin/
│   └── quota-monitor/          # Cross-platform Antigravity MCP App plugin + agy statusLine hook
├── providers/                  # Open Provider Slot JSON schema & templates (Cursor, GrokBot, ...)
└── .github/workflows/          # Automated macOS + Windows CI & Release builds
```

---

## Quick Start

### 1. macOS (Menu Bar App)

Requirements: macOS 13.0+ and Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/Zi-Chung/QuotaRing.git
cd QuotaRing
./apps/macos/install.sh
```

Or download the prebuilt Universal `QuotaRing-macOS.zip` from **GitHub Releases**, unzip, and move `QuotaRing.app` to `/Applications`.

### 2. Windows (System Tray App)

Requirements for building from source: Windows 10/11 and [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0).

```powershell
git clone https://github.com/Zi-Chung/QuotaRing.git
cd QuotaRing
.\apps\windows\build.ps1
.\apps\windows\publish\QuotaRing.exe
```

Or download the single-file `QuotaRing-win-x64.exe` directly from **GitHub Releases**.

### 3. Antigravity Official `statusLine` + Side-Pane Plugin (macOS & Windows)

To feed live official Antigravity quotas into QuotaRing (and add a side-pane Quota Monitor dashboard inside Antigravity):

```bash
cd plugin/quota-monitor
npm install
npm run build
node scripts/install-plugin.mjs
```

Then start `agy` in your terminal whenever you want to push a fresh official quota snapshot to `~/.gemini/antigravity-cli/quota-snapshot.json`.

---

## Open Provider Slots (Cursor, GrokBot, Claude, ...)

QuotaRing watches `~/.config/quota-bar/providers/*.json` (Windows: `%USERPROFILE%\.config\quota-bar\providers\*.json`).

Any external script, enterprise Admin API integration, or manual tracker can write a simple JSON file:

```json
{
  "id": "cursor",
  "name": "Cursor",
  "shortBadge": "Cu",
  "planTier": "Pro",
  "updatedAt": "2026-11-24T10:40:00Z",
  "monthly": {
    "label": "Monthly",
    "remainingPercent": 80,
    "resetTime": "2026-12-24T10:40:00Z",
    "windowMinutes": 43200
  }
}
```

See [providers/README.md](./providers/README.md) and [providers/schema.json](./providers/schema.json) for full field details.

---

## Security & Privacy Guarantee

- **No network code**: Neither the macOS nor the Windows app contains any HTTP client or telemetry.
- **No credential access**: Never reads Keychain, Windows Credential Manager, browser cookies, or IDE auth databases.
- **Local-only read**: Strictly reads documented local snapshots (`quota-snapshot.json`, `~/.codex/sessions/*.jsonl`, `~/.config/quota-bar/providers/*.json`).

---

## License

[MIT](./LICENSE)
