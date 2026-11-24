# Open Provider Slots (`~/.config/quota-bar/providers/`)

Place any `*.json` file in `~/.config/quota-bar/providers/` (Windows: `%USERPROFILE%\.config\quota-bar\providers\`) to display custom providers such as **Cursor**, **GrokBot**, or **Claude Code** inside QuotaRing.

QuotaRing automatically reloads slot files on every refresh tick (default: 30s) without restarting.

## Minimal Example (`cursor.json`)

```json
{
  "id": "cursor",
  "name": "Cursor",
  "shortBadge": "Cu",
  "planTier": "Pro",
  "updatedAt": "2026-11-24T10:40:00Z",
  "weekly": {
    "label": "周额度",
    "remainingPercent": 80,
    "resetTime": "2026-12-01T10:40:00Z",
    "windowMinutes": 10080
  }
}
```

## Flexible Field Formats

- **Percentage**: Provide any one of `remainingPercent` (`0..100`), `usedPercent` (`0..100`), or `remainingFraction` (`0.0..1.0`).
- **Reset Time**: Provide either `resetTime` (ISO 8601 string) or `resetsAt` (Unix epoch seconds or milliseconds).
- **Atomic Writes Recommended**: External scripts should write to `<name>.json.tmp` and rename to `<name>.json` to avoid partial reads.
