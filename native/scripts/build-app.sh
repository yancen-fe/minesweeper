#!/bin/bash
set -euo pipefail
NATIVE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_ROOT="$(dirname "$NATIVE_ROOT")"
cd "$NATIVE_ROOT"
swift build -c release
BIN_ROOT="$(swift build -c release --show-bin-path)"
mkdir -p "$PROJECT_ROOT/dist"
STAGING_ROOT="$(mktemp -d "$PROJECT_ROOT/dist/.build-XXXXXX")"
trap 'rm -rf "$STAGING_ROOT"' EXIT
APP_ROOT="$STAGING_ROOT/扫雷.app"
mkdir -p "$APP_ROOT/Contents/MacOS" "$APP_ROOT/Contents/Resources" ".build/AppIcon.iconset"
cp "$BIN_ROOT/Minesweeper" "$APP_ROOT/Contents/MacOS/Minesweeper"
ditto Assets/Fonts "$APP_ROOT/Contents/Resources/Fonts"
sips -z 1024 1024 Assets/AppIcon.png --out .build/AppIcon.png >/dev/null
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" .build/AppIcon.png --out ".build/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
    doubled=$((size * 2))
    sips -z "$doubled" "$doubled" .build/AppIcon.png --out ".build/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns .build/AppIcon.iconset -o "$APP_ROOT/Contents/Resources/AppIcon.icns"
cat > "$APP_ROOT/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Minesweeper</string>
<key>CFBundleIdentifier</key><string>com.yancen.minesweeper</string>
<key>CFBundleName</key><string>扫雷</string>
<key>CFBundleDevelopmentRegion</key><string>zh-Hans</string>
<key>CFBundleLocalizations</key><array><string>zh-Hans</string></array>
<key>CFBundleDisplayName</key><string>扫雷</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
<key>LSApplicationCategoryType</key><string>public.app-category.puzzle-games</string>
<key>NSHumanReadableCopyright</key><string>© 2026 Yancen</string>
</dict></plist>
PLIST
python3 - "$APP_ROOT/Contents/Info.plist" "$PROJECT_ROOT" <<'PYINFO'
import json, plistlib, sys
from pathlib import Path
p=Path(sys.argv[1]); root=Path(sys.argv[2]); config=json.loads((root/'release/channel.json').read_text())
with p.open('rb') as f: info=plistlib.load(f)
info.update(CFBundleShortVersionString=config['version'], CFBundleVersion=str(config['build']),
            LSMinimumSystemVersion=config['minimumSystemVersion'])
with p.open('wb') as f: plistlib.dump(info,f)
PYINFO
codesign --force --deep --sign "${APPLE_SIGNING_IDENTITY:--}" --preserve-metadata=entitlements "$APP_ROOT"
codesign --verify --deep --strict "$APP_ROOT"
FINAL_APP="$PROJECT_ROOT/dist/扫雷.app"
if [ -e "$FINAL_APP" ]; then mv "$FINAL_APP" "$STAGING_ROOT/previous.app"; fi
mv "$APP_ROOT" "$FINAL_APP"
echo "已构建 $FINAL_APP"
du -sh "$FINAL_APP"
