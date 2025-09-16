#!/bin/bash
set -e

##
# Pre-requirements:
# - env FUZZER: path to fuzzer work dir
##

if [ ! -d "$FUZZER/repo" ] || [ ! -d "$FUZZER/kernel-analyzer" ]; then
    echo "fetch.sh must be executed first."
    exit 1
fi

export CXX="clang++-${LLVM_VERSION}"
export CC="clang-${LLVM_VERSION}"
export LLVM_CONFIG="llvm-config-${LLVM_VERSION}"

build_static_analyzer() {(
    alias clang=$CC
    alias clang++=$CXX

    cd "$FUZZER/kernel-analyzer"
    make LLVM_BUILD=/usr/lib/llvm-${LLVM_VERSION}/ -j$(nproc)

)}

build_static_analyzer

$FUZZER/cursor_install.sh
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
echo 'export PATH=/usr/lib/llvm-20/bin:$PATH' >> ~/.bashrc