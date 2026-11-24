#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bash "${SCRIPT_DIR}/build.sh" "$@"

killall QuotaRing 2>/dev/null || true
rm -rf /Applications/QuotaRing.app
cp -R "${SCRIPT_DIR}/build/QuotaRing.app" /Applications/QuotaRing.app
open /Applications/QuotaRing.app

echo "==> Installed and launched /Applications/QuotaRing.app"
