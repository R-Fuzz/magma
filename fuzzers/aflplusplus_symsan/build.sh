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

export CXX="clang++-${LLVM_VERSION}"
export CC="clang-${LLVM_VERSION}"
export LLVM_CONFIG="llvm-config-${LLVM_VERSION}"

# build AFL++
(
    cd "$FUZZER/aflpp"
    export AFL_NO_X86=1
    export PYTHON_INCLUDE=/
    make NO_NYX=1 source-only -j$(nproc)
    make -C utils/aflpp_driver
)

# build SymSan
(
    cd "$FUZZER/symsan"
    git pull
    mkdir build && cd build
    cmake -DAFLPP_PATH=$FUZZER/aflpp \
        -DCMAKE_INSTALL_PREFIX=. ../
    make -j$(nproc)
    export KO_CC=clang-${LLVM_VERSION}
    export KO_CXX=clang++-${LLVM_VERSION}
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
    make LLVM_BUILD=/usr/lib/llvm-${LLVM_VERSION}/ -j$(nproc)
)

# build symsan instrumented libs
_comment() {(
    cd "$FUZZER"
    export KO_CXX=clang++-${LLVM_VERSION}
    export KO_CC=clang-${LLVM_VERSION}
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
    export CC=clang-${LLVM_VERSION}
    export AR=llvm-ar-${LLVM_VERSION}
    export RANLIB=llvm-ranlib-${LLVM_VERSION}
    export CFLAGS="-O0 -g -flto"
    export LDFLAGS="-fuse-ld=lld-${LLVM_VERSION}"
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
    sed -i 's/AR = ar/AR = llvm-ar-${LLVM_VERSION}/' Makefile
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
