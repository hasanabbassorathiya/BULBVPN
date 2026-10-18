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

# no_screenshot declares macOS support but ships no macOS pod. A no-op
# plugin lets the desktop build link; screenshot calls already fail closed.
prepare_macos_screenshot_stub() {
  local root
  root="$(find "$HOME/.pub-cache/hosted" -type d -name 'no_screenshot-*' | head -1)"
  if [[ -z "$root" ]]; then
    return 0
  fi
  mkdir -p "$root/macos/Classes"
  cat > "$root/macos/no_screenshot.podspec" <<'EOF'
Pod::Spec.new do |s|
  s.name             = 'no_screenshot'
  s.version          = '0.3.1'
  s.summary          = 'No-op macOS screenshot plugin.'
  s.homepage         = 'https://github.com/hasanabbassorathiya/BULBVPN'
  s.license          = { :type => 'MIT' }
  s.author           = { 'BULBVPN' => 'support@bulbvpn.com' }
  s.source           = { :path => '.' }
  s.osx.deployment_target = '13.0'
  s.source_files = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.swift_version = '5.0'
end
EOF
  cat > "$root/macos/Classes/NoScreenshotPlugin.swift" <<'EOF'
import FlutterMacOS

public class NoScreenshotPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {}
}
EOF
}

build_macos() {
  echo "== macOS =="
  prepare_macos_screenshot_stub
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
  local_notes="$(cat <<EOF
BULBVPN ${VERSION}

OpenVPN-first connect for Iranian Wi-Fi and mobile data.
Android AAB/APK, iOS IPA, and desktop archives when this host can build them.
EOF
)"
  if gh release view "$TAG" >/dev/null 2>&1; then
    gh release upload "$TAG" "$OUT"/* --clobber
  else
    gh release create "$TAG" "$OUT"/* \
      --title "BULBVPN ${VERSION}" \
      --notes "$local_notes"
  fi
  gh release view "$TAG" --json url,assets --jq '{url:.url,assets:[.assets[].name]}'
fi
