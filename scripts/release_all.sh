#!/usr/bin/env bash
# Build every platform this machine can sign, then optionally publish a
# GitHub release. Android, iOS, and macOS are built on macOS. Windows is
# built when this script runs on Windows.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PUBLISH=0
if [[ "${1:-}" == "--github" ]]; then
  PUBLISH=1
fi

if [[ -x "$HOME/development/flutter/bin/flutter" ]]; then
  export PATH="$HOME/development/flutter/bin:$PATH"
fi
export PATH="$HOME/.blitz/bin:$PATH"

VERSION="$(awk '/^version:/{print $2; exit}' pubspec.yaml)"
NAME="$(awk '/^name:/{print $2; exit}' pubspec.yaml)"
TAG="v${VERSION//+/-}"
OUT="$ROOT/dist/$TAG"
mkdir -p "$OUT"

echo "BULBVPN ${VERSION} → ${OUT}"
flutter pub get

copy_first() {
  local dest="$1"
  shift
  local path
  for path in "$@"; do
    if [[ -f "$path" ]]; then
      cp "$path" "$dest"
      echo "saved $(basename "$dest")"
      return 0
    fi
  done
  echo "missing artifact for ${dest}" >&2
  return 1
}

build_android() {
  echo "== Android =="
  (cd android && ./gradlew :app:bundleRelease :app:assembleRelease)
  copy_first "$OUT/${NAME}-android.aab" \
    android/app/build/outputs/bundle/release/app-release.aab
  copy_first "$OUT/${NAME}-android.apk" \
    android/app/build/outputs/flutter-apk/app-release.apk \
    android/app/build/outputs/apk/release/app-release.apk
}

build_ios() {
  echo "== iOS =="
  flutter build ipa --release --export-method app-store
  local ipa
  ipa="$(find build/ios/ipa -name '*.ipa' -print -quit)"
  copy_first "$OUT/${NAME}-ios.ipa" "$ipa"
}

build_macos() {
  echo "== macOS =="
  flutter build macos --release
  local app="build/macos/Build/Products/Release/${NAME}.app"
  if [[ ! -d "$app" ]]; then
    app="$(find build/macos/Build/Products/Release -name '*.app' -print -quit)"
  fi
  ditto -c -k --keepParent "$app" "$OUT/${NAME}-macos.zip"
  echo "saved ${NAME}-macos.zip"
}

build_windows() {
  echo "== Windows =="
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) ;;
    *)
      echo "Windows build runs on Windows. Skipped on $(uname -s)."
      return 0
      ;;
  esac
  flutter build windows --release
  local dir="build/windows/x64/runner/Release"
  (cd "$dir" && zip -r "$OUT/${NAME}-windows.zip" .)
  echo "saved ${NAME}-windows.zip"
}

build_android
build_ios
build_macos
build_windows

echo "Artifacts:"
ls -lh "$OUT"

if [[ "$PUBLISH" -eq 1 ]]; then
  echo "== GitHub release ${TAG} =="
  gh release create "$TAG" "$OUT"/* \
    --title "BULBVPN ${VERSION}" \
    --notes "OpenVPN-first connect for Iranian Wi-Fi and mobile data on Android, iOS, and macOS. Windows archive is included when this script is run on Windows."
fi
