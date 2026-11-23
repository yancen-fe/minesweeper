#!/bin/bash
set -euo pipefail
NATIVE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$NATIVE_ROOT/.build/checks"
xcrun swiftc -O -parse-as-library "$NATIVE_ROOT/Sources/Game.swift" "$NATIVE_ROOT/Sources/GameLibrary.swift" "$NATIVE_ROOT/Sources/Sharing.swift" "$NATIVE_ROOT/Sources/History.swift" "$NATIVE_ROOT/Sources/Presentation.swift" "$NATIVE_ROOT/Sources/Logic.swift" "$NATIVE_ROOT/Sources/Layout.swift" "$NATIVE_ROOT/Sources/ReleaseTag.swift" "$NATIVE_ROOT/Tests/EngineChecks.swift" -o "$NATIVE_ROOT/.build/checks/EngineChecks"
"$NATIVE_ROOT/.build/checks/EngineChecks"

bash "$NATIVE_ROOT/scripts/test-sharing.sh"

bash "$NATIVE_ROOT/scripts/test-multiwindow.sh"
