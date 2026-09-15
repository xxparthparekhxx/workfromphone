# On-device rootfs packaging

This directory builds the Debian userland that powers **No-PC mode**: the
FastAPI backend runs inside a `proot` Debian container on the phone itself,
and the Flutter UI talks to `http://127.0.0.1:8000`.

## Layout

- `build-debian-rootfs.sh` — builds `workfromphone-rootfs-debian-<arch>.tar.gz`
  (`aarch64` for phones, `x86_64` for the emulator) via `debootstrap`
  (Debian bookworm, `minbase` variant). Prefers embedding the prebuilt
  PyInstaller backend binary (`--backend-tar`); without it the overlay falls
  back to an apt-python venv created on first boot by `bootstrap.sh`.
- `bootstrap.sh` — first-boot script executed **inside** the proot guest:
  repairs `/etc/resolv.conf`, installs the slim toolchain
  (`git curl ca-certificates build-essential openssh-client python3`),
  creates the `coder` user, and records `.bootstrapped`.
- `launch.sh` — backend launcher executed inside the guest. Requires
  `ACCESS_TOKEN` (mandatory even on loopback), binds `127.0.0.1:$PORT`,
  exports `WORKSPACE`, and execs the prebuilt binary or the venv fallback.

## First-run download, not bundled

The rootfs (~150–300MB) downloads on first setup into app-private storage
with SHA-256 verification against the release manifest — it is **not**
bundled in the APK, keeping installs slim.

## Slim image contents

Debian minimal + backend + full dev toolchain (`git curl ca-certificates
build-essential openssh-client python3 nodejs npm vim nano tmux jq unzip
sqlite3`). No docs, man pages, or locales — see the cleanup step in
`build-debian-rootfs.sh`.

## Building locally

```bash
# Full rootfs (needs root + debootstrap; qemu-user-static for cross-arch):
sudo rootfs/build-debian-rootfs.sh arm64 \
  --backend-tar backend/workfromphone-backend-linux-aarch64.tar.gz

# Overlay only (no root needed; used by CI):
rootfs/build-debian-rootfs.sh arm64 --overlay-only \
  --backend-tar backend/workfromphone-backend-linux-aarch64.tar.gz
```

## Releases

On `backend-v*` tags, `.github/workflows/backend-release.yml` (job
`rootfs`) publishes `workfromphone-rootfs-debian-<arch>.tar.gz` +
`.sha256` alongside the backend binaries and records their URLs/hashes in
`rootfs-manifest.json` (mirroring the `backend-manifest.json` pattern).
The Flutter setup wizard fetches that manifest to resolve the download URL.

## proot binaries

Termux-patched `proot` plus its runtime (`libtalloc`, `libandroid-shmem`,
loader) are **not** checked in. They must live in
`android/app/src/main/jniLibs/<abi>/` so the loader maps them from
`nativeLibraryDir` — Android W^X forbids executing files in app-writable
directories, and AGP only packages names matching `lib*.so`. Fetch them
with:

```bash
scripts/fetch-proot.sh
```

`android/app/build.gradle.kts` runs that script from `preBuild` when the
files are missing, then rewrites proot's DT_NEEDED from `libtalloc.so.2`
to `libtalloc.so`. App processes ignore `LD_LIBRARY_PATH`, so a versioned
soname in nativeLibraryDir is the only name the linker will load — and
AGP will not package `*.so.2`.
