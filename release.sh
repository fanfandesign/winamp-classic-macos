#!/bin/zsh
# Build a self-contained, drag-to-Applications DMG. Signing is optional for previews.
set -eu
set -o pipefail
cd "${0:A:h}"
VERSION="$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)"
SIGN_IDENTITY="${WINAMP_SIGN_IDENTITY:--}"
NOTARY_PROFILE="${WINAMP_NOTARY_PROFILE:-}"
ARCHITECTURES="${WINAMP_ARCHS:-arm64 x86_64}"
if [[ -n "$NOTARY_PROFILE" && "$SIGN_IDENTITY" == "-" ]]; then
  print -u2 "Notarization requires WINAMP_SIGN_IDENTITY (Developer ID Application)."
  exit 1
fi
mkdir -p build dist
RELEASE_ROOT="$(mktemp -d "$PWD/build/release.XXXXXX")"
WINAMP_BUILD_DIR="$RELEASE_ROOT/app" WINAMP_ARCHS="$ARCHITECTURES" WINAMP_SIGN_IDENTITY="$SIGN_IDENTITY" ./build.sh
APP="$RELEASE_ROOT/app/Winamp Classic.app"
STAGING="$RELEASE_ROOT/volume"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/Winamp Classic.app"
ln -s /Applications "$STAGING/Applications"
if [[ "$ARCHITECTURES" == *arm64* && "$ARCHITECTURES" == *x86_64* ]]; then
  SUFFIX="Universal"
else
  SUFFIX="${ARCHITECTURES// /-}"
fi
DMG="$PWD/dist/Winamp-Classic-$VERSION-$SUFFIX.dmg"
cat > "$STAGING/Install.txt" <<'TXT'
Winamp Classic for macOS

Установка / Installation:
1. Перетащите Winamp Classic.app в папку Applications (Программы).
2. Извлеките этот диск и откройте приложение из Программ.
   Drag the app to Applications, eject the disk, then open it from Applications.

Требуется macOS 13 Ventura или новее.
Requires macOS 13 Ventura or later.

Плеер работает локально. Дополнительные программы устанавливать не нужно.
The player works locally. No additional software is required.
TXT
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  cat >> "$STAGING/Install.txt" <<'TXT'

Эта предварительная сборка имеет локальную (ad-hoc) подпись и не прошла
нотарификацию Apple. После скачивания macOS может заблокировать первый запуск.
Для публичной сборки без этого предупреждения необходимы Developer ID и
нотарификация Apple. Сборка не отключает защитные механизмы macOS.

This preview is ad-hoc signed and has not been notarized by Apple. macOS may
block its first launch after download. Developer ID signing and Apple
notarization are needed for normal public distribution.
TXT
fi
hdiutil create -volname "Winamp Classic" -srcfolder "$STAGING" -format UDZO -ov "$DMG"
STATUS="Preview: ad-hoc signed, not notarized"
if [[ "$SIGN_IDENTITY" != "-" ]]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
  STATUS="Developer ID signed; not notarized"
fi
if [[ -n "$NOTARY_PROFILE" ]]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  STATUS="Developer ID signed and notarized by Apple"
fi
hdiutil verify "$DMG"
(cd dist && shasum -a 256 "${DMG:t}" > "${DMG:t}.sha256")
cat > dist/RELEASE_NOTES.md <<TXT
Winamp Classic $VERSION for macOS

- macOS 13 Ventura or later; architectures: $ARCHITECTURES.
- Download ${DMG:t}, open it, and drag the app to Applications.
- Classic Winamp appearance, compact window, HD pressed controls, audio playback,
  playlist, scrolling titles and a ten-band equalizer.
- Distribution status: $STATUS.

This is an independent project. Artwork credits are included in the app and repository.
TXT
print "DMG: $DMG"
print "Status: $STATUS"
