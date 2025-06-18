#!/bin/bash
set -e

##
# Pre-requirements:
# - env FUZZER: path to fuzzer work dir
##

if [ ! -d "$FUZZER/afl" ] || [ ! -d "$FUZZER/symsan" ]; then
    echo "fetch.sh must be executed first."
    exit 1
fi

# build AFL
(
    cd "$FUZZER/afl"
    CC=clang-12 make -j $(nproc)
    CC=clang-12 make -j $(nproc) -C llvm_mode
)

# build Z3
# (
#    cd "$FUZZER/z3"
#    mkdir -p build install cmake_conf
#    cd build
#    CXX=clang++ CC=clang cmake ../ \
#        -DCMAKE_INSTALL_PREFIX="$FUZZER/z3/install" \
#        -DCMAKE_INSTALL_Z3_CMAKE_PACKAGE_DIR="$FUZZER/z3/cmake_conf"
#    make -j $(nproc)
#    make install
#    export PATH="$FUZZER/z3/install/bin:$PATH"
# )

# build SymSan
(
    cd "$FUZZER/symsan"
    CC=clang-12 CXX=clang++-12 cmake -DCMAKE_INSTALL_PREFIX=. \
    ./ && make -j && make install
    pip install -r $FUZZER/symsan/mazerunner/requirements.txt
)

# build static analyzer
(
    cd "$FUZZER/kernel-analyzer" && make -j
)

# build symsan instrumented zlib
(
    cd "$FUZZER"
    wget https://github.com/madler/zlib/archive/refs/tags/v1.2.13.tar.gz
    tar -xzf v1.2.13.tar.gz
    cd zlib-1.2.13
    export KO_CXX=clang++-12
    export KO_CC=clang-12
    export CXX="$FUZZER/symsan/build/bin/ko-clang++"
    export CC="$FUZZER/symsan/build/bin/ko-clang"
    export KO_USE_FASTGEN=
    export KO_NO_NATIVE_ZLIB=1
    ./configure --static --prefix=$FUZZER/zlib-1.2.13/zlib-1.2.13
    make -j $(nproc) all
)

# prepare output dirs
mkdir -p "$OUT/afl" "$OUT/aflgo" "$OUT/clang_bc" "$OUT/symsan"

# compile afl_driver
"$FUZZER/afl/afl-clang-fast++" $CXXFLAGS -std=c++14 -c -fPIC \
    "$FUZZER/afl/afl_driver.cpp" -o "$OUT/afl/afl_driver.o"

export KO_CC=clang-12
export KO_CXX=clang++-12
export CC="$FUZZER/symsan/bin/ko-clang" 
export CXX="$FUZZER/symsan/bin/ko-clang++" 
unset KO_ADD_AFLGO
# $CXX $CXXFLAGS -std=c++14 -c -fPIC \
#     "$FUZZER/afl/afl_driver.cpp" -o "$OUT/symsan/afl_driver.o"

# compile libfuzzer-harness-fast
KO_DONT_OPTIMIZE=1 $CC -c $FUZZER/libfuzz-harness-proxy.c -o $OUT/symsan/libfuzzer-harness-fast.o
