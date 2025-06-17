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
    export KO_CC=clang-14
    export KO_CXX=clang++-14
    make install
    # rebuild libc++
    cd ../libcxx
    ./rebuild.sh ../build/bin/ko-clang
    # install new libc++
    cd ../build/
    make install
)

# build static analyzer
(
    cd "$FUZZER/kernel-analyzer"
    git pull
    make LLVM_BUILD=/usr/lib/llvm-14/ -j$(nproc)
)

# build symsan instrumented libs
_comment() {(
    cd "$FUZZER"
    export KO_CXX=clang++-14
    export KO_CC=clang-14
    export CXX=$FUZZER/symsan/build/bin/ko-clang++
    export CC=$FUZZER/symsan/build/bin/ko-clang
    export KO_NO_NATIVE_ZLIB=1

    #zlib
    wget https://github.com/madler/zlib/archive/refs/tags/v1.2.13.tar.gz
    tar zxf v1.2.13.tar.gz
    pushd zlib-1.2.13
    ./configure --static --prefix=$FUZZER/zlib-1.2.13/zlib-1.2.13
    make -j$(nproc) all
    popd

    #readline
    wget https://ftp.gnu.org/gnu/readline/readline-8.1.2.tar.gz
    tar zxf readline-8.1.2.tar.gz
    pushd readline-8.1.2
    ./configure --disable-shared
    make -j$(nproc)
    popd

    #termcap
    wget https://ftp.gnu.org/gnu/termcap/termcap-1.3.1.tar.gz
    tar zxf termcap-1.3.1.tar.gz
    pushd termcap-1.3.1
    ./configure --disable-shared
    make -j$(nproc)
    popd
)}

# build libs in llvm bitcode for lto
(
    cd "$FUZZER"
    export CC=clang-14
    export AR=llvm-ar-14
    export RANLIB=llvm-ranlib-14
    export CFLAGS="-O0 -g -flto"
    export LDFLAGS="-fuse-ld=lld-14"
    unset LIBS

    #zlib
    wget https://github.com/madler/zlib/archive/refs/tags/v1.2.13.tar.gz
    tar zxf v1.2.13.tar.gz
    pushd zlib-1.2.13
    ./configure --static
    make -j$(nproc) all
    popd

    #termcap
    wget https://ftp.gnu.org/gnu/termcap/termcap-1.3.1.tar.gz
    tar zxf termcap-1.3.1.tar.gz
    pushd termcap-1.3.1
    ./configure --disable-shared
    # patch Makefile
    sed -i 's/AR = ar/AR = llvm-ar-14/' Makefile
    sed -i 's/CFLAGS = -g/CFLAGS = -O0 -g -flto/' Makefile
    make -j$(nproc)
    popd

    #readline
    wget https://ftp.gnu.org/gnu/readline/readline-8.1.2.tar.gz
    tar zxf readline-8.1.2.tar.gz
    pushd readline-8.1.2
    ./configure --disable-shared
    make -j$(nproc)
    popd
)

# prepare output dirs
mkdir -p "$OUT/afl" "$OUT/clang_bc" "$OUT/symsan"

export KO_CC=clang-14
export KO_CXX=clang++-14

# compile libfuzzer-harness-fast
KO_DONT_OPTIMIZE=1 $FUZZER/symsan/build/bin/ko-clang $CFLAGS -c -fPIC \
    -o $OUT/symsan/libfuzzer-harness-fast.o $FUZZER/symsan/driver/harness-proxy.c 
