#!/bin/bash
# Builds ATKBar.app into .build/ATKBar.app. `--install` also copies it to /Applications and opens it.
# Signs ad hoc, which needs no keychain, but macOS ties Input Monitoring to an ad hoc build's exact
# code: after a rebuild ATKBar is refused the mouse until the permission is granted again. Set
# SIGN_IDENTITY (and SIGN_KEYCHAIN if the identity lives in another keychain) to a certificate to
# keep the permission across builds.
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
keychain=()
[[ -n "${SIGN_KEYCHAIN:-}" ]] && keychain=(--keychain "$SIGN_KEYCHAIN")
codesign --force --options runtime --timestamp=none ${keychain[@]+"${keychain[@]}"} --sign "${identity:--}" "$app"
echo "built $app (signed: ${identity:-ad hoc})"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x ATKBar 2>/dev/null || true
    rm -rf /Applications/ATKBar.app
    cp -R "$app" /Applications/
    open /Applications/ATKBar.app
    echo "installed /Applications/ATKBar.app"
fi
