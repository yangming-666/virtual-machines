#!/usr/bin/env sh
set -eu

manifest="${1:-$(dirname "$0")/host-hardware.json}"

if [ ! -f "$manifest" ]; then
  echo "Host hardware manifest not found: $manifest" >&2
  exit 1
fi

if command -v jq >/dev/null 2>&1; then
  jq '.computerSystem, .bios, .baseBoard, .processor, .videoControllers, .networkAdapters, .disks' "$manifest"
else
  cat "$manifest"
fi
