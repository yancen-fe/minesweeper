#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
bash native/scripts/build-app.sh
mkdir -p release/artifacts/macos
VERSION="$(python3 -c 'import json; print(json.load(open("release/channel.json"))["version"])')"
ARCH="$(uname -m)"
DMG_ROOT="$(mktemp -d "$ROOT/native/.build/dmg-XXXXXX")"
trap 'rm -rf "$DMG_ROOT"' EXIT
ditto 'dist/扫雷.app' "$DMG_ROOT/扫雷.app"
ln -s /Applications "$DMG_ROOT/Applications"
hdiutil create -volname '扫雷' -srcfolder "$DMG_ROOT" -ov -format UDZO "release/artifacts/macos/minesweeper-$VERSION-macos-$ARCH.dmg" >/dev/null
