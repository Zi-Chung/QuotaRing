# Quota Monitor Plugin

Monitors your Antigravity weekly and rolling model quotas using the official `agy` CLI `statusLine` hook and displays live countdowns and remaining balances in an Antigravity MCP App side pane.

## How It Works

1. `~/.gemini/antigravity-cli/settings.json` configures `agy`'s official `statusLine` hook to run `bin/statusline.sh`.
2. Whenever `agy` CLI is running, it pipes the official status JSON (including `quota.remaining_fraction`, `reset_time`, and `reset_in_seconds`) to `bin/statusline.mjs`.
3. `statusline.mjs` prints a color-coded status bar in the CLI and atomically saves the latest snapshot + trend history to `~/.gemini/antigravity-cli/quota-snapshot.json`.
4. The MCP App server (`src/server.mjs`) exposes the **Quota Monitor** side pane and sidebar panel, auto-refreshing from that snapshot file and also supporting optional manual reset countdowns stored in `${PLUGIN_DATA}`.
