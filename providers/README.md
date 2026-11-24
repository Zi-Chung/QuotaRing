# Open Provider Slots (`~/.config/quota-bar/providers/`)

Place any `*.json` file in `~/.config/quota-bar/providers/` (Windows: `%USERPROFILE%\.config\quota-bar\providers\`) to display custom providers such as **Cursor**, **GrokBot**, or **Claude Code** inside QuotaRing.

QuotaRing automatically reloads slot files on every refresh tick (default: 30s) without restarting.

## Minimal Example (`cursor.json` — Monthly Quota `M`)

```json
{
  "id": "cursor",
  "name": "Cursor",
  "shortBadge": "Cu",
  "planTier": "Pro",
  "updatedAt": "2026-11-24T10:40:00Z",
  "monthly": {
    "label": "月额度",
    "remainingPercent": 80,
    "resetTime": "2026-12-24T10:40:00Z",
    "windowMinutes": 43200
  }
}
```

## Flexible Field Formats

- **Windows (`fiveHour` / `weekly` / `monthly`)**: Include whichever billing cycles the service uses (`5` = 300m, `W` = 10080m, `M` = 43200m by default). You can override `windowMinutes` (e.g., `44640` for a 31-day month or `1440` for daily) and `shortTag` (e.g., `"D"`).
- **Percentage**: Provide any one of `remainingPercent` (`0..100`), `usedPercent` (`0..100`), or `remainingFraction` (`0.0..1.0`).
- **Reset Time**: Provide either `resetTime` (ISO 8601 string) or `resetsAt` (Unix epoch seconds or milliseconds).
- **Atomic Writes Recommended**: External scripts should write to `<name>.json.tmp` and rename to `<name>.json` to avoid partial reads.
