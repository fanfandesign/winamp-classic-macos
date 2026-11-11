#!/bin/zsh
set -eu
set -o pipefail
cd "${0:A:h}"
BUILD_ROOT="${WINAMP_BUILD_DIR:-$PWD/build}"
APP="$BUILD_ROOT/Winamp Classic.app"
SIGN_IDENTITY="${WINAMP_SIGN_IDENTITY:--}"
ARCHITECTURES="${WINAMP_ARCHS:-arm64}"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$BUILD_ROOT/bin" "$PWD/build/ModuleCache"
binaries=()
for architecture in ${=ARCHITECTURES}; do
  case "$architecture" in
    arm64|x86_64) ;;
    *) print -u2 "Unsupported architecture: $architecture"; exit 1 ;;
  esac
  binary="$BUILD_ROOT/bin/WinampClassic-$architecture"
  swiftc -target "$architecture-apple-macos13.0" -module-cache-path "$PWD/build/ModuleCache" -swift-version 5 -O Sources/*.swift -o "$binary" -framework AppKit -framework AVFoundation -framework UniformTypeIdentifiers
  binaries+=("$binary")
done
if (( ${#binaries} == 1 )); then
  cp "$binaries[1]" "$APP/Contents/MacOS/WinampClassic"
else
  lipo -create "${binaries[@]}" -output "$APP/Contents/MacOS/WinampClassic"
fi
cp Resources/WinampOriginal.icns Resources/WinampIconCredits.txt "$APP/Contents/Resources/"
cp -R Resources/HD Resources/Sprites "$APP/Contents/Resources/"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --sign - --timestamp=none "$APP"
else
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
fi
codesign --verify --deep --strict "$APP"
print "Built: $APP ($ARCHITECTURES)"
