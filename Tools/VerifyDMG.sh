#!/bin/zsh
set -eu
set -o pipefail
cd "${0:A:h}/.."
DMG="${1:-$PWD/dist/Winamp-Classic-1.1-Universal.dmg}"
MOUNT_DIR="$(mktemp -d /private/tmp/winamp-dmg.XXXXXX)"
mounted=0
cleanup() {
  if (( mounted )); then hdiutil detach "$MOUNT_DIR" -quiet; fi
  rmdir "$MOUNT_DIR"
}
trap cleanup EXIT
hdiutil attach "$DMG" -readonly -nobrowse -mountpoint "$MOUNT_DIR" -quiet
mounted=1
APP="$MOUNT_DIR/Winamp Classic.app"
[[ "$(readlink "$MOUNT_DIR/Applications")" == "/Applications" ]]
codesign --verify --all-architectures --deep --strict "$APP"
lipo "$APP/Contents/MacOS/WinampClassic" -verify_arch arm64 x86_64
file "$APP/Contents/MacOS/WinampClassic"
vtool -show-build "$APP/Contents/MacOS/WinampClassic"
otool -L "$APP/Contents/MacOS/WinampClassic"
"$APP/Contents/MacOS/WinampClassic" --smoke-test
print "DMG PASS: read-only mount, Applications shortcut, both architectures, signatures, bundled app smoke test"
