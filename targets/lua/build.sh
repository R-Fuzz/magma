#!/bin/bash
set -e

##
# Pre-requirements:
# - env TARGET: path to target work dir
# - env OUT: path to directory where artifacts are stored
# - env CC, CXX, FLAGS, LIBS, etc...
##

if [ ! -d "$TARGET/repo" ]; then
    echo "fetch.sh must be executed first."
    exit 1
fi

# build lua library
cd "$TARGET/repo"

# Do not hardcodes -march=native, which fails in cross-platform
# container environments (e.g. Apple Silicon running amd64 via Rosetta 2,
# or any environment where clang cannot probe the host CPU via CPUID).
# Override with a safe generic baseline that runs on any x86-64 host.
sed -i 's/-march=native/-march=x86-64/g' makefile Makefile 2>/dev/null || true

make -j$(nproc) clean
make -j$(nproc) liblua.a

cp liblua.a "$OUT/"

# build driver
make -j$(nproc) lua
cp lua "$OUT/"
if [ -f "lua.0.0.preopt.bc" ]; then
    cp lua.*.bc "$OUT/"
fi
