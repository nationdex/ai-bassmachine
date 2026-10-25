#!/usr/bin/env bash
# Rebuild the native Windows console/process helper DLLs from source (needs mingw-w64).
#   Debian/Ubuntu: sudo apt install gcc-mingw-w64
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
SRC=src/utils/windows/bass_wincon.c
OUT=bin/windows
CFLAGS=(-shared -O2 -s -Wall)
x86_64-w64-mingw32-gcc "${CFLAGS[@]}" -o "$OUT/bass_wincon64.dll" "$SRC"
i686-w64-mingw32-gcc "${CFLAGS[@]}" -o "$OUT/bass_wincon32.dll" "$SRC"
sha256sum "$OUT"/bass_wincon*.dll
