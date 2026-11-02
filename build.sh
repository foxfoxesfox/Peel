#!/bin/bash
# Builds build.noindex/Peel.app (release, Apple silicon).
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/Peel"

# GitHub repo the app checks for updates (from this checkout's "origin" remote).
REPO=$(git remote get-url origin 2>/dev/null | sed -E 's#^(git@github\.com:|https://github\.com/)##; s#\.git$##' || true)
REPO=${REPO:-foxfoxesfox/Peel}

OUT=build.noindex/Peel.app  # .noindex keeps Spotlight from listing a second Peel
# Assembled and signed outside this folder: iCloud (Desktop sync) keeps re-tagging the bundle with Finder info,
# which codesign refuses. The signed app is copied in at the end.
APP="$(mktemp -d)/Peel.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Peel"

# App icon from Resources/icon-1024.png (regenerate with: swift scripts/icon.swift Resources/icon-1024.png)
[ -f Resources/icon-1024.png ] || swift scripts/icon.swift Resources/icon-1024.png
ICONSET="$(mktemp -d)/AppIcon.iconset"; mkdir "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) Resources/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Peel</string>
    <key>CFBundleIdentifier</key><string>com.local.peel</string>
    <key>CFBundleName</key><string>Peel</string>
    <key>CFBundleDisplayName</key><string>Peel</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>PeelUpdateFeed</key><string>https://raw.githubusercontent.com/$REPO/main/dist/latest.json</string>
    <key>PeelHomepage</key><string>https://github.com/$REPO</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.1</string>
    <key>CFBundleVersion</key><string>2</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPhotoLibraryAddUsageDescription</key><string>Peel adds the captures you save to your Photos library. It can't see or read your library.</string>
</dict>
</plist>
PLIST

# macOS ties the Screen Recording permission to the app's signature. An ad-hoc signature changes with every
# build, so each update would lose the permission; a self-signed certificate stays the same (see README).
SIGN_ID="${PEEL_SIGN_ID:-Peel App Signing}"
if security find-identity -p codesigning 2>/dev/null | grep -q "\"$SIGN_ID\""; then
  codesign --force -s "$SIGN_ID" "$APP"
  SIGNED="signed with \"$SIGN_ID\""
else
  codesign --force -s - "$APP"
  SIGNED="ad-hoc signed: Screen Recording must be allowed again after each build; see README → Signing"
fi

rm -rf "$OUT"
mkdir -p "$(dirname "$OUT")"
ditto "$APP" "$OUT"
rm -rf "$(dirname "$APP")"
echo "Built $OUT ($SIGNED)"
