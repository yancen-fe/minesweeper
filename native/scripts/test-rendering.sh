#!/bin/bash
set -euo pipefail
NATIVE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$NATIVE_ROOT/.build/checks"
xcrun swiftc -O -parse-as-library "$NATIVE_ROOT/Sources/Game.swift" "$NATIVE_ROOT/Sources/GameLibrary.swift" "$NATIVE_ROOT/Sources/Sharing.swift" "$NATIVE_ROOT/Sources/History.swift" "$NATIVE_ROOT/Sources/Logic.swift" "$NATIVE_ROOT/Sources/Layout.swift" "$NATIVE_ROOT/Sources/BoardTypography.swift" "$NATIVE_ROOT/Sources/Tile.swift" "$NATIVE_ROOT/Sources/Counter.swift" "$NATIVE_ROOT/Sources/WindowSizing.swift" "$NATIVE_ROOT/Tests/RenderingChecks.swift" -o "$NATIVE_ROOT/.build/checks/RenderingChecks"
"$NATIVE_ROOT/.build/checks/RenderingChecks"
