#!/bin/bash
# Builds build/DesktopPet.app from the Swift sources. Needs only the Xcode command line tools.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/DesktopPet.app"
BIN="$APP/Contents/MacOS/DesktopPet"

rm -rf "$APP" build/AppIcon.iconset
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/AppIcon.iconset

# Pin the deployment target: by default swiftc targets the SDK's version,
# which can be newer than the macOS that is actually running.
swiftc -O -target "$(uname -m)-apple-macosx13.0" -o "$BIN" Sources/*.swift

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Desktop Pet</string>
    <key>CFBundleDisplayName</key><string>Desktop Pet</string>
    <key>CFBundleIdentifier</key><string>local.desktop-pet</string>
    <key>CFBundleExecutable</key><string>DesktopPet</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

# The app draws its own icon.
"$BIN" --icon build/icon.png
for size in 16 32 128 256 512; do
    sips -z $size $size build/icon.png --out "build/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) build/icon.png --out "build/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf build/AppIcon.iconset

codesign --force --sign - "$APP" >/dev/null 2>&1

echo "Built $APP"
