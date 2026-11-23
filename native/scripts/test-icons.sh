#!/bin/bash
set -euo pipefail
NATIVE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$NATIVE_ROOT/.build/checks"
xcrun swiftc -O -parse-as-library "$NATIVE_ROOT/Sources/CustomIcons.swift" "$NATIVE_ROOT/Tests/IconChecks.swift" -o "$NATIVE_ROOT/.build/checks/IconChecks"
"$NATIVE_ROOT/.build/checks/IconChecks"
