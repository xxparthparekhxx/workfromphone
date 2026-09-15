# Patched proot binaries live here after running `scripts/fetch-proot.sh`.
#
# Per ABI (arm64-v8a, x86_64):
# - `libproot.so` — Termux-patched proot (dynamic PIE). DT_NEEDED for talloc
#   is rewritten from `libtalloc.so.2` to `libtalloc.so` (Android ignores
#   LD_LIBRARY_PATH in app processes, so a versioned soname cannot resolve).
# - `libproot-loader.so` — ptrace loader (`PROOT_LOADER`).
# - `libtalloc.so` — talloc 2.x (filename must end in `.so` for AGP).
# - `libandroid-shmem.so` — SysV shm shim (DT_NEEDED as-is).
#
# Files are named `lib*.so` so the Android Gradle plugin installs them into
# `nativeLibraryDir`, the only app-associated location the kernel allows to
# `exec` (W^X forbids executing anything under app-writable dirs such as
# `filesDir`). `ProotRunner` resolves the binary via `applicationInfo
# .nativeLibraryDir + "/libproot.so"`.
#
# Binaries are intentionally NOT checked into git (size + trust: fetch pinned
# Termux .deb files and verify SHA-256). `.gitignore` covers `*.so` under
# this directory. `android/app/build.gradle.kts` runs fetch-proot.sh from
# `preBuild` when any of the files above are missing.
