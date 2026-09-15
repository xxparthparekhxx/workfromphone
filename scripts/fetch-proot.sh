#!/usr/bin/env bash
# Fetch the on-device proot runtime into android/app/src/main/jniLibs/<abi>/.
#
# Binaries must live in jniLibs so they install to nativeLibraryDir: Android
# W^X forbids executing files in app-writable directories, so a proot copied
# to filesDir would fail with EACCES on exec.
#
# Sources: Termux apt pool (patched proot for Android; oonid/pr publishes no
# binaries). Versions and SHA-256 are pinned below; the script refuses to
# install anything that does not match.
#
# Layout per ABI (all names must end in `.so` — AGP silently drops any
# jniLibs file without the `.so` suffix, e.g. versioned `libtalloc.so.2`):
#   libproot.so         Termux proot, DT_NEEDED rewritten to `libtalloc.so`
#                       (Android app processes ignore LD_LIBRARY_PATH, so a
#                       filesDir symlink to libtalloc.so.2 cannot work)
#   libtalloc.so        libtalloc runtime
#   libandroid-shmem.so proot's shmem helper (DT_NEEDED as-is)
#   libproot-loader.so  Termux proot `loader` (statically linked); the app
#                       points proot at it via PROOT_LOADER since the compiled
#                       default (/data/data/com.termux/...) is wrong here.
set -euo pipefail

PROOT_VERSION="5.1.107.92"
TALLOC_VERSION="2.4.3"
SHMEM_VERSION="0.7"
APT_BASE="https://packages.termux.dev/apt/termux-main/pool"

declare -A PROOT_SHA256=(
  [arm64-v8a]="1f1c983509701f6826f568482c70673ee453a9ba38c9f5fa445a472d6b7524e9"
  [x86_64]="70236632826c30ec0245082b633bbc7ef1e9fa5531bd51bd4f20231bfcdc999b"
)
declare -A TALLOC_SHA256=(
  [arm64-v8a]="ac81ad623d74c209718b9f3acb2dd702cc8a88c431e820d212229910b4db29da"
  [x86_64]="7ca2eaae2e53b28228a01301bc410b62845403d6317c25b8e0a7f40681de0628"
)
declare -A SHMEM_SHA256=(
  [arm64-v8a]="0da3a24d558b93c92bcf8d611e0826a99ff96e396b148e6cdf33b47c47c57ff6"
  [x86_64]="ffa9e4c87467b158b148d0ff92dda796aa038276c2075af3269cdcdb06f25797"
)
# Termux arch naming inside the pool.
declare -A TERMUX_ARCH=( [arm64-v8a]="aarch64" [x86_64]="x86_64" )

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$SCRIPT_DIR/android/app/src/main/jniLibs"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

download() { # url, sha256, out
  local url="$1" expected="$2" out="$3"
  echo "Fetching $url"
  if command -v curl >/dev/null; then
    curl -fsSL "$url" -o "$out"
  else
    wget -qO "$out" "$url"
  fi
  local actual
  actual="$(sha256sum "$out" | awk '{print $1}')"
  if [ "$actual" != "$expected" ]; then
    echo "SHA-256 mismatch for $url:" >&2
    echo "  expected $expected" >&2
    echo "  actual   $actual" >&2
    exit 1
  fi
}

extract_member() { # deb, termux-relpath (e.g. usr/bin/proot), out
  # GNU tar autodetects the data.tar compression, and the exact member path
  # avoids wildcard over-matching (which once pulled loader32/talloc symlinks
  # along as stray jniLibs files).
  local deb="$1" relpath="$2" out="$3"
  local tmp="$WORK/deb-$$"
  rm -rf "$tmp"; mkdir -p "$tmp"
  ( cd "$tmp" && ar x "$deb" )
  local data=( "$tmp"/data.tar.* )
  tar -xf "${data[0]}" -C "$tmp" -O "./data/data/com.termux/files/$relpath" > "$out"
}

PATCH="$SCRIPT_DIR/scripts/patch-proot-dtneeded.py"

for abi in arm64-v8a x86_64; do
  tarch="${TERMUX_ARCH[$abi]}"
  outdir="$DEST/$abi"
  mkdir -p "$outdir"

  proot_deb="$WORK/proot-$abi.deb"
  talloc_deb="$WORK/talloc-$abi.deb"
  shmem_deb="$WORK/shmem-$abi.deb"
  download "$APT_BASE/main/p/proot/proot_${PROOT_VERSION}_${tarch}.deb" "${PROOT_SHA256[$abi]}" "$proot_deb"
  download "$APT_BASE/main/libt/libtalloc/libtalloc_${TALLOC_VERSION}_${tarch}.deb" "${TALLOC_SHA256[$abi]}" "$talloc_deb"
  download "$APT_BASE/main/liba/libandroid-shmem/libandroid-shmem_${SHMEM_VERSION}_${tarch}.deb" "${SHMEM_SHA256[$abi]}" "$shmem_deb"

  extract_member "$proot_deb" "usr/bin/proot" "$outdir/libproot.so"
  extract_member "$proot_deb" "usr/libexec/proot/loader" "$outdir/libproot-loader.so"
  extract_member "$talloc_deb" "usr/lib/libtalloc.so.2.4.3" "$outdir/libtalloc.so"
  extract_member "$shmem_deb" "usr/lib/libandroid-shmem.so" "$outdir/libandroid-shmem.so"

  python3 "$PATCH" "$outdir/libproot.so"

  chmod 755 "$outdir"/libproot.so "$outdir"/libtalloc.so \
    "$outdir"/libandroid-shmem.so "$outdir"/libproot-loader.so
  echo "Installed $abi: $(ls "$outdir")"
done

echo "Done. Verify with: file $DEST/*/libproot.so"
if command -v readelf >/dev/null; then
  readelf -d "$DEST/arm64-v8a/libproot.so" | grep NEEDED || true
fi
