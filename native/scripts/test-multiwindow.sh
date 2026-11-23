#!/bin/bash
set -euo pipefail
NATIVE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$NATIVE_ROOT/.build/checks"
xcrun swiftc -O -parse-as-library "$NATIVE_ROOT/Sources/Game.swift" "$NATIVE_ROOT/Sources/GameLibrary.swift" "$NATIVE_ROOT/Sources/Sharing.swift" "$NATIVE_ROOT/Sources/History.swift" "$NATIVE_ROOT/Sources/Logic.swift" "$NATIVE_ROOT/Sources/Presentation.swift" "$NATIVE_ROOT/Tests/MultiwindowChecks.swift" -o "$NATIVE_ROOT/.build/checks/MultiwindowChecks"
"$NATIVE_ROOT/.build/checks/MultiwindowChecks" "$NATIVE_ROOT/../tests/fixtures/share-v1.json"
