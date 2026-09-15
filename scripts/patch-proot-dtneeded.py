#!/usr/bin/env python3
"""Rewrite proot's DT_NEEDED so Android's linker can find talloc.

Termux proot NEEDs `libtalloc.so.2`. AGP only packages names ending in `.so`,
and the installer will not extract a versioned soname into nativeLibraryDir.
App processes also ignore LD_LIBRARY_PATH, so a filesDir symlink cannot
satisfy the linker.

This rewrites the dynamic string in-place (NUL-padded, same byte length) to
`libtalloc.so`, which is already shipped beside libproot.so. Offsets, hashes,
and 16 KB page alignment are unchanged — no patchelf.
"""

from __future__ import annotations

import sys
from pathlib import Path

OLD = b"libtalloc.so.2\x00"
# Also rewrite a previous experimental alias some local APKs used.
OLD_ALIASES = (
    OLD,
    b"libtalloc2.so\x00",
)
NEW = b"libtalloc.so\x00"


def patch(path: Path) -> str:
    data = bytearray(path.read_bytes())
    if NEW in data and not any(alias in data for alias in OLD_ALIASES):
        return f"{path}: already NEEDs libtalloc.so"

    replaced = 0
    for alias in OLD_ALIASES:
        if alias not in data:
            continue
        if len(NEW) > len(alias):
            raise SystemExit(f"cannot expand {alias!r} -> {NEW!r}")
        padded = NEW.ljust(len(alias), b"\x00")
        data = bytearray(bytes(data).replace(alias, padded))
        replaced += 1
    if replaced == 0:
        raise SystemExit(
            f"{path}: neither libtalloc.so.2 nor libtalloc2.so found in DT_NEEDED",
        )
    path.write_bytes(data)
    return f"{path}: rewrote DT_NEEDED -> libtalloc.so"


def main() -> int:
    paths = [Path(a) for a in sys.argv[1:]]
    if not paths:
        print("usage: patch-proot-dtneeded.py <libproot.so>...", file=sys.stderr)
        return 2
    for path in paths:
        if not path.is_file():
            raise SystemExit(f"missing {path}")
        print(patch(path))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
