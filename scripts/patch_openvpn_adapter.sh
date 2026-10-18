#!/usr/bin/env bash
# Apply SoftEther TLS fixes to OpenVPNAdapter after `pod install`.
# Patches live in patches/openvpn_adapter/ and target OpenVPNAdapter 0.7.0.
#
# Idempotent: skips a file if the patch is already applied.
# Usage:
#   scripts/patch_openvpn_adapter.sh          # ios + macos if present
#   scripts/patch_openvpn_adapter.sh ios      # ios only
#   scripts/patch_openvpn_adapter.sh macos    # macos only
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATCH_DIR="$ROOT/patches/openvpn_adapter"

if [[ ! -d "$PATCH_DIR" ]]; then
  echo "error: missing $PATCH_DIR" >&2
  exit 1
fi

platforms=()
if [[ $# -eq 0 ]]; then
  platforms=(ios macos)
else
  platforms=("$@")
fi

apply_one() {
  local pod_root="$1"
  local patch_file="$2"
  local name
  name="$(basename "$patch_file")"

  if [[ ! -d "$pod_root" ]]; then
    echo "skip: $pod_root (not installed)"
    return 0
  fi

  # Already applied?
  if patch -p1 -d "$pod_root" --dry-run --forward -i "$patch_file" >/dev/null 2>&1; then
    patch -p1 -d "$pod_root" --forward --quiet -i "$patch_file"
    echo "applied: $name → $pod_root"
    return 0
  fi

  # Reverse dry-run succeeds ⇒ already patched
  if patch -p1 -d "$pod_root" --dry-run --reverse -i "$patch_file" >/dev/null 2>&1; then
    echo "already applied: $name → $pod_root"
    return 0
  fi

  echo "error: failed to apply $name to $pod_root" >&2
  echo "       OpenVPNAdapter may have changed; refresh patches/openvpn_adapter/" >&2
  patch -p1 -d "$pod_root" --dry-run --forward -i "$patch_file" || true
  return 1
}

status=0
for platform in "${platforms[@]}"; do
  case "$platform" in
    ios|macos) ;;
    *)
      echo "error: unknown platform '$platform' (use ios or macos)" >&2
      exit 1
      ;;
  esac

  pod_root="$ROOT/$platform/Pods/OpenVPNAdapter"
  shopt -s nullglob
  patches=("$PATCH_DIR"/*.patch)
  shopt -u nullglob
  if [[ ${#patches[@]} -eq 0 ]]; then
    echo "error: no .patch files in $PATCH_DIR" >&2
    exit 1
  fi

  for patch_file in "${patches[@]}"; do
    if ! apply_one "$pod_root" "$patch_file"; then
      status=1
    fi
  done
done

exit "$status"
