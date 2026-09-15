# Patched proot binaries live here after running `scripts/fetch-proot.sh`.
#
# - `arm64-v8a/libproot.so` — patched proot for physical phones (aarch64).
# - `x86_64/libproot.so` — patched proot for the Android emulator.
#
# Files are named `lib*.so` so the Android Gradle plugin installs them into
# `nativeLibraryDir`, the only app-associated location the kernel allows to
# `exec` (W^X forbids executing anything under app-writable dirs such as
# `filesDir`). `ProotRunner` resolves the binary via `applicationInfo
# .nativeLibraryDir + "/libproot.so"`.
#
# Binaries are intentionally NOT checked into git (size + trust: fetch pinned
# versions from oonid/pr and verify SHA-256). `.gitignore` covers `*.so`
# under this directory; the `.gitkeep` files preserve the layout.
