#!/bin/bash
set -euo pipefail
APP="$(cd "$1" && pwd)"
TOOLS="$APP/Contents/Helpers"
# Empty PATH: binaries must not depend on a user's Python, Homebrew or shell profile.
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
"$TOOLS/yt-dlp" --version
"$TOOLS/deno" --version
"$TOOLS/ffmpeg" -version
"$TOOLS/ffprobe" -version
codesign --verify --deep --strict "$APP"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
/usr/bin/python3 - "$TEST_DIR/input.wav" <<'PYTHON'
import math, struct, sys, wave
with wave.open(sys.argv[1], "wb") as w:
    w.setparams((1, 2, 44100, 0, "NONE", "not compressed"))
    w.writeframes(b"".join(struct.pack("<h", int(12000 * math.sin(2*math.pi*440*n/44100))) for n in range(44100)))
PYTHON
"$TOOLS/ffmpeg" -v error -i "$TEST_DIR/input.wav" -c:a libmp3lame "$TEST_DIR/output.mp3"
"$TOOLS/ffmpeg" -v error -i "$TEST_DIR/input.wav" -c:a libopus "$TEST_DIR/output.opus"
"$TOOLS/ffprobe" -v error -show_entries format=duration "$TEST_DIR/output.mp3"
"$TOOLS/ffprobe" -v error -show_entries format=duration "$TEST_DIR/output.opus"
"$TOOLS/yt-dlp" --ignore-config --js-runtimes "deno:$TOOLS/deno" --ffmpeg-location "$TOOLS" --list-extractors > "$TEST_DIR/extractors"
test -s "$TEST_DIR/extractors"
# Relocation check, including spaces in the app path.
mkdir "$TEST_DIR/Folder with spaces"
cp -R "$APP" "$TEST_DIR/Folder with spaces/YT2DL.app"
"$TEST_DIR/Folder with spaces/YT2DL.app/Contents/Helpers/yt-dlp" --version
"$TEST_DIR/Folder with spaces/YT2DL.app/Contents/Helpers/ffmpeg" -version
echo "Standalone bundle verification passed"
