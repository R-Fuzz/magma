#!/bin/bash
set -e

##
# Pre-requirements:
# - runs as root, before the `magma` user does anything
##

apt-get update
apt-get install -y \
    make build-essential cmake ninja-build \
    python3-minimal python-is-python3 python3-dev \
    zlib1g-dev libprotobuf-dev libboost-container-dev \
    libgoogle-perftools-dev \
    git wget curl unzip lsb-release software-properties-common gnupg2

# Z3, from upstream rather than apt.  jammy ships 4.8.12 and SymSan's
# CMakeLists requires 4.8.15 or later for the string-theory APIs, so
# `apt-get install libz3-dev` -- which is what aflplusplus_symsan does -- stops
# the build at the configure step.
#
# 4.14.1 rather than the 4.15.4 on the host: upstream's Linux binaries moved to
# a glibc 2.39 baseline at 4.15, and this image is 22.04 (glibc 2.35).  4.14.1
# is the newest release still built against 2.35.  Building 4.15.4 from source
# instead would cost ten minutes a layer to close a gap that only matters if a
# solver-version difference ever shows up in the results -- if one does, that
# is the change to make.
Z3_VERSION=4.14.1
Z3_DIST="z3-${Z3_VERSION}-x64-glibc-2.35"
curl -fsSL -o /tmp/z3.zip \
    "https://github.com/Z3Prover/z3/releases/download/z3-${Z3_VERSION}/${Z3_DIST}.zip"
unzip -q /tmp/z3.zip -d /tmp
cp -a "/tmp/${Z3_DIST}/bin/z3" /usr/local/bin/
cp -a "/tmp/${Z3_DIST}/bin/libz3.so" /usr/local/lib/
cp -a "/tmp/${Z3_DIST}/include/"*.h /usr/local/include/
ldconfig
rm -rf /tmp/z3.zip "/tmp/${Z3_DIST}"
z3 --version

# LLVM 18, not the 14 the base image's LLVM_VERSION names.  `all` is what pulls
# in the two pieces that are easy to forget: libclang-18-dev, which bindgen
# needs to read include/symsan_c.h, and lld-18, which afl-clang-lto needs.
curl -O https://apt.llvm.org/llvm.sh \
    && chmod +x llvm.sh \
    && ./llvm.sh 18 all
rm -f llvm.sh

# Rust, for the LibAFL front-end.  This script is the only one that runs as
# root -- fetch.sh, build.sh and instrument.sh are all the `magma` user -- so
# the toolchain has to land somewhere world-readable rather than in root's
# home.  CARGO_HOME here is only the install location; build.sh points it at a
# writable directory for the registry.
export RUSTUP_HOME=/opt/rust
export CARGO_HOME=/opt/rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --no-modify-path --profile minimal
chmod -R a+rX /opt/rust
ln -sf /opt/rust/bin/cargo /usr/local/bin/cargo
ln -sf /opt/rust/bin/rustc /usr/local/bin/rustc
ln -sf /opt/rust/bin/rustup /usr/local/bin/rustup
