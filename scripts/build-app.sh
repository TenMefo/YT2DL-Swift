#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -n "${RUNTIME_ARCHIVE_URL:-}" ]; then
    RUNTIME_ZIP="$(mktemp -t yt2dl-runtime).zip"
    trap 'rm -f "$RUNTIME_ZIP"' EXIT
    curl --fail --location --retry 3 "$RUNTIME_ARCHIVE_URL" --output "$RUNTIME_ZIP"
    echo "$RUNTIME_ARCHIVE_SHA256  $RUNTIME_ZIP" | shasum -a 256 -c -
    mkdir -p dist
    ditto -x -k "$RUNTIME_ZIP" dist
fi
mkdir -p dist/YT2DL.app/Contents/MacOS
swift build -c release "$@"
BIN="$(swift build -c release "$@" --show-bin-path)"
cp "$BIN/YT2DL" dist/YT2DL.app/Contents/MacOS/YT2DL
cat > dist/YT2DL.app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>YT2DL</string>
<key>CFBundleIdentifier</key><string>pl.mefosoft.yt2dl</string>
<key>CFBundleName</key><string>YT2DL</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.2.0</string>
<key>CFBundleVersion</key><string>3</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict></plist>
PLIST
if [ -z "${RUNTIME_ARCHIVE_URL:-}" ]; then
    python3 scripts/prepare-tools.py
fi
codesign --force --sign - dist/YT2DL.app
bash scripts/verify-bundle.sh dist/YT2DL.app
ditto -c -k --sequesterRsrc --keepParent dist/YT2DL.app dist/YT2DL-All-in-One-macOS.zip
echo "Gotowe: dist/YT2DL.app i dist/YT2DL-All-in-One-macOS.zip"
