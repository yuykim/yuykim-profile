#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v node >/dev/null 2>&1; then
  echo "node is required for macOS/Linux collection." >&2
  echo "Install Node.js, then run: ./scripts/collect-all.sh" >&2
  exit 1
fi

node "$SCRIPT_DIR/collect-all.mjs"
