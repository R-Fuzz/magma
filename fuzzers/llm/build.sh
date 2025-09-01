#!/bin/bash
set -e

##
# Pre-requirements:
# - env FUZZER: path to fuzzer work dir
##


export CXX="clang++-${LLVM_VERSION}"
export CC="clang-${LLVM_VERSION}"
export LLVM_CONFIG="llvm-config-${LLVM_VERSION}"

# Get Python version info for dynamic path handling
PYTHON_VERSION_SHORT=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
PYTHON_VERSION_NO_DOT=$(python3 -c 'import sys; print(f"{sys.version_info.major}{sys.version_info.minor}")')

build_static_analyzer() {(
    alias clang=$CC
    alias clang++=$CXX

    cd "$FUZZER/kernel-analyzer"
    make LLVM_BUILD=/usr/lib/llvm-${LLVM_VERSION}/ -j$(nproc)

)}


build_llvm_bitcode_libs() {(
    cd "$FUZZER"
    export CC=clang-${LLVM_VERSION}
    export AR=llvm-ar-${LLVM_VERSION}
    export RANLIB=llvm-ranlib-${LLVM_VERSION}
    export CFLAGS="-O0 -g -flto"
    export LDFLAGS="-fuse-ld=lld-${LLVM_VERSION}"
    unset LIBS

    #zlib
    tar zxf v1.2.13.tar.gz
    pushd zlib-1.2.13
    ./configure --static
    make -j$(nproc) all
    popd

    #termcap
    tar zxf termcap-1.3.1.tar.gz
    pushd termcap-1.3.1
    ./configure --disable-shared
    # patch Makefile
    sed -i 's/AR = ar/AR = llvm-ar-${LLVM_VERSION}/' Makefile
    sed -i 's/CFLAGS = -g/CFLAGS = -O0 -g -flto/' Makefile
    make -j$(nproc)
    popd

    #readline
    tar zxf readline-8.1.2.tar.gz
    pushd readline-8.1.2
    ./configure --disable-shared
    make -j$(nproc)
    popd
)}

build_static_analyzer
build_llvm_bitcode_libs # For LTO mode
