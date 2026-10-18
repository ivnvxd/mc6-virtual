#!/bin/sh
# Renders the panel of a backup to a PNG, with no window and no MIDI ports.
# Usage: scripts/snapshot.sh <backup.json> <out.png> [state], for example state "bank=2,pos2=0,exp=64".
set -eu
absolute() { (cd "$(dirname "$1")" && printf '%s/%s\n' "$(pwd)" "$(basename "$1")"); }
backup="$(absolute "$1")"
out="$(absolute "$2")"
cd "$(dirname "$0")/.."

swift build --product MC6App 2>&1 | grep -E "error" && exit 1
bin="$(swift build --show-bin-path)/MC6App"
MC6_BACKUP="$backup" MC6_SNAPSHOT="$out" MC6_SNAPSHOT_STATE="${3:-}" "$bin"
echo "Wrote $out"
