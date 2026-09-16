#!/usr/bin/env bash
# Rebuilds the bundle, replaces any running instance and launches it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$("$ROOT/Scripts/bundle.sh")"

pkill -x TapSwitch 2>/dev/null || true
open "$APP"
echo "Launched $APP"
