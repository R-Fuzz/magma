#!/bin/bash
set -e

##
# Pre-requirements:
# - env FUZZER: path to fuzzer work dir
##

if [ ! -d "$FUZZER/aflpp" ] || [ ! -d "$FUZZER/symsan" ]; then
    echo "fetch.sh must be executed first."
    exit 1
fi

# build AFL++
(
    cd "$FUZZER/aflpp"
    CC=clang-14 CXX=clang++-14 make PERFORMANCE=1 LLVM_CONFIG=llvm-config-14 \
        NO_NYX=1 source-only -j$(nproc)
)

# build SymSan
(
    cd "$FUZZER/symsan"
    git pull
    mkdir build && cd build
    CC=clang-14 CXX=clang++-14 cmake -DAFLPP_PATH=$FUZZER/aflpp \
        -DCMAKE_INSTALL_PREFIX=. ../
    make -j$(nproc)
    make install
)

# build static analyzer
(
    cd "$FUZZER/kernel-analyzer"
    git pull
    make LLVM_BUILD=/usr/lib/llvm-14/ -j$(nproc)
)

# build symsan instrumented zlib
(
    cd "$FUZZER"
    wget https://github.com/madler/zlib/archive/refs/tags/v1.2.13.tar.gz
    tar -xzf v1.2.13.tar.gz
    cd zlib-1.2.13
    export KO_CXX=clang++-14
    export KO_CC=clang-14
    export CXX=$FUZZER/symsan/build/bin/ko-clang++
    export CC=$FUZZER/symsan/build/bin/ko-clang
    export KO_NO_NATIVE_ZLIB=1
    ./configure --static --prefix=$FUZZER/zlib-1.2.13/zlib-1.2.13
    make -j$(nproc) all
)

# prepare output dirs
mkdir -p "$OUT/afl" "$OUT/clang_bc" "$OUT/symsan"

export KO_CC=clang-14
export KO_CXX=clang++-14

# compile libfuzzer-harness-fast
KO_DONT_OPTIMIZE=1 $FUZZER/symsan/build/bin/ko-clang $CFLAGS -c -fPIC \
    -o $OUT/symsan/libfuzzer-harness-fast.o $FUZZER/symsan/driver/harness-proxy.c 
