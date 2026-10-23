#!/usr/bin/env bash
# Author: lidawen
set -euo pipefail
cd "$(dirname "$0")"
if [[ -f designer.local.env ]]; then
  source designer.local.env
fi
fvm flutter pub get
exec fvm flutter run -d macos "$@"
