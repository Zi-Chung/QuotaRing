---
name: quota-monitor
description: Open the Quota Monitor panel and check the latest Antigravity weekly/rolling quota snapshot synced from the agy CLI statusLine, plus any manual reset timers. Use when the user asks about their remaining quota, weekly reset time, or quota monitoring panel.
---

# Quota Monitor

When the user asks about their current Antigravity quota, weekly reset countdown, or wants to view the Quota Monitor dashboard:

1. Call the `open_quota_monitor` tool from the `quota-monitor_monitor` MCP server (with `{}`).
2. Summarize the synced quota buckets (remaining percentage, exact local reset time, and countdown) and note how fresh the last `agy` CLI sync is.
3. If no CLI snapshot has been recorded yet (or it is stale), remind the user to start `agy` in their terminal so the official `statusLine` hook pushes fresh quota updates automatically, or mention they can add a manual reset countdown right inside the Quota Monitor panel.
