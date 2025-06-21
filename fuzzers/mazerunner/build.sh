#!/bin/bash
set -e

##
# Pre-requirements:
# - env FUZZER: path to fuzzer work dir
##

if [ ! -d "$FUZZER/aflpp" ] || [ ! -d "$FUZZER/aflgo" ] || [ ! -d "$FUZZER/symsan" ]; then
    echo "fetch.sh must be executed first."
    exit 1
fi

export CXX="clang++-${LLVM_VERSION}"
export CC="clang-${LLVM_VERSION}"
export LLVM_CONFIG="llvm-config-${LLVM_VERSION}"

build_aflpp() {(
    export LLVM_VERSION=14
    export CXX="clang++-${LLVM_VERSION}"
    export CC="clang-${LLVM_VERSION}"
    export LLVM_CONFIG="llvm-config-${LLVM_VERSION}"

    cd "$FUZZER/aflpp"
    make PERFORMANCE=1 NO_NYX=1 source-only -j$(nproc)
)}

build_aflgo() {(
    cd "$FUZZER/aflgo"

    pushd afl-2.57b
    make clean all
    popd

    pushd instrument
    make clean all
    popd

    pushd distance/distance_calculator
    cmake ./
    cmake --build ./
    popd
)}

build_symsan() {(
    cd "$FUZZER/symsan"
    git pull

    git checkout main
    mkdir build_solver && cd build_solver
    cmake -DCMAKE_INSTALL_PREFIX=. ../
    make -j$(nproc) && make install
    mkdir -p /home/.local/lib/python3.10/site-packages
    cp python/symsan.cpython-310-x86_64-linux-gnu.so /home/.local/lib/python3.10/site-packages/

    cd "$FUZZER/symsan"
    git checkout -b rl origin/rl
    mkdir build && cd build
    cmake -DCMAKE_INSTALL_PREFIX=. ../
    make -j$(nproc) && make install

    # rebuild libc++
    export KO_CC=clang-${LLVM_VERSION}
    export KO_CXX=clang++-${LLVM_VERSION}
    cd "$FUZZER/symsan/libcxx"
    ./rebuild.sh ../build/bin/ko-clang
    # install new libc++
    cd "$FUZZER/symsan/build/"
    make install

    # install pip packages
    pip install -r $FUZZER/symsan/mazerunner/requirements.txt --no-cache-dir
)}

build_static_analyzer() {(
    export LLVM_VERSION=14
    export CXX="clang++-${LLVM_VERSION}"
    export CC="clang-${LLVM_VERSION}"
    export LLVM_CONFIG="llvm-config-${LLVM_VERSION}"
    alias clang=$CC
    alias clang++=$CXX

    cd "$FUZZER/kernel-analyzer"
    git pull
    make LLVM_BUILD=/usr/lib/llvm-${LLVM_VERSION}/ -j$(nproc)

)}

build_symsan_instrumented_libs() {(
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

build_llvm_bitcode_libs() {(
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
)}

# build_aflpp
build_aflgo
build_symsan
build_static_analyzer
# build_symsan_instrumented_libs
build_llvm_bitcode_libs # For LTO mode

# prepare output dirs
mkdir -p "$OUT/afl" "$OUT/aflgo" "${OUT}/clang_bc" "$OUT/symsan"

# compile fuzz driver for aflgo
cd "$FUZZER/aflgo"
$FUZZER/aflgo/instrument/aflgo-clang++ $CXXFLAGS -std=c++11 -c "afl_driver.cpp" -fPIC -o "$OUT/aflgo/afl_driver.o"

# compile fuzz driver for symsan
(
export KO_CC=clang-${LLVM_VERSION}
export KO_CXX=clang++-${LLVM_VERSION}
unset KO_ADD_AFLGO

KO_DONT_OPTIMIZE=1 $FUZZER/symsan/build/bin/ko-clang $CFLAGS -c -fPIC \
    -o $OUT/symsan/libfuzzer-harness-fast.o $FUZZER/symsan/driver/harness-proxy.c 
)
