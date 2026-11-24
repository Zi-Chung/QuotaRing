# Contributing to QuotaRing

Thanks for your interest in contributing to **QuotaRing**!

## Core Security Principle

QuotaRing strictly adheres to a **Zero-Auth, Zero-Network, Local Read-Only** architecture:

- Pull requests that read OS Keychains / Credential Managers, decrypt browser cookies, scrape IDE auth databases (`state.vscdb`, etc.), or call undocumented cloud/internal endpoints **will not be accepted**.
- New built-in providers must read documented local files/logs or official CLI hooks (such as `statusLine` JSON snapshots).
- Any provider without a local read-only mechanism can still be integrated externally by users via the [Open Provider Slot format](./providers/README.md).

## Development

- **macOS app**: `./apps/macos/build.sh` (requires macOS 13+ & `swiftc`)
- **Windows app**: `.\apps\windows\build.ps1` (requires Windows 10/11 & .NET 8 SDK)
- **Antigravity plugin**: `cd plugin/quota-monitor && npm install && npm run build`
