#!/bin/bash
# Builds ATKBar.app into .build/ATKBar.app. `--install` also copies it to /Applications and opens it.
# Signs ad hoc, which needs no keychain. macOS then asks for Input Monitoring again after a rebuild;
# set SIGN_IDENTITY to a signing identity to keep the permission across builds.
set -euo pipefail
cd "$(dirname "$0")/.."

version=$(sed -n 's/^let version = "\(.*\)"/\1/p' Sources/atkctl/main.swift)
swift build -c release --product ATKBar

app=.build/ATKBar.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/ATKBar "$app/Contents/MacOS/ATKBar"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>ATKBar</string>
    <key>CFBundleIdentifier</key><string>dev.cobanov.atkbar</string>
    <key>CFBundleName</key><string>ATKBar</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$version</string>
    <key>CFBundleVersion</key><string>$version</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict>
</plist>
PLIST

identity=${SIGN_IDENTITY:-}
codesign --force --options runtime --sign "${identity:--}" "$app"
echo "built $app (signed: ${identity:-ad hoc})"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x ATKBar 2>/dev/null || true
    rm -rf /Applications/ATKBar.app
    cp -R "$app" /Applications/
    open /Applications/ATKBar.app
    echo "installed /Applications/ATKBar.app"
fi
