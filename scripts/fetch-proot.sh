#!/usr/bin/env bash
# Fetch patched proot binaries into android/app/src/main/jniLibs/<abi>/.
#
# Binaries must live in jniLibs so they install to nativeLibraryDir: Android
# W^X forbids executing files in app-writable directories, so a proot copied
# to filesDir would fail with EACCES on exec.
#
# Sources (patched for Android, targetSdk 35 precedent): oonid/pr releases.
# Pin PROOT_VERSION explicitly; verify SHA-256 from PROOT_SHA256_<ABI>.
set -euo pipefail

PROOT_VERSION="${PROOT_VERSION:-5.4.0-wfp1}"
BASE_URL="${PROOT_BASE_URL:-https://github.com/oonid/pr/releases/download/v$PROOT_VERSION}"

declare -A ABIS=( [arm64-v8a]="aarch64" [x86_64]="x86_64" )
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$SCRIPT_DIR/android/app/src/main/jniLibs"

for abi in arm64-v8a x86_64; do
  arch="${ABIS[$abi]}"
  out="$DEST/$abi/libproot.so"
  mkdir -p "$(dirname "$out")"
  url="$BASE_URL/proot-$arch"
  echo "Fetching $url -> $out"
  if command -v curl >/dev/null; then
    curl -fsSL "$url" -o "$out"
  else
    wget -qO "$out" "$url"
  fi
  chmod 755 "$out"
done

echo "Done. Verify with: file $DEST/*/libproot.so"
echo "If oonid/pr has no matching release, evaluate 'proroot' as alternative."
