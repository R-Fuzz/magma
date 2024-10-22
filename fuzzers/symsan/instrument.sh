#!/bin/bash
set -e

##
# Pre-requirements:
# - env FUZZER: path to fuzzer work dir
# - env TARGET: path to target work dir
# - env MAGMA: path to Magma support files
# - env OUT: path to directory where artifacts are stored
# - env CFLAGS and CXXFLAGS must be set to link against Magma instrumentation
##

export LIBS="$LIBS -l:afl_driver.o -lstdc++"

(
    export CC="$FUZZER/afl/afl-clang-fast"
    export CXX="$FUZZER/afl/afl-clang-fast++"

    export OUT="/magma_out/afl"
    export LDFLAGS="$LDFLAGS -L$OUT -g"

    "$MAGMA/build.sh"
    "$TARGET/build.sh"
)

# build bitcode files
(
    export CXX=clang++-12
    export CC=clang-12

    export OUT="/magma_out/symsan_bc"
    export LDFLAGS="$LDFLAGS -L$OUT -g"

    "$MAGMA/build.sh"

    export CXXFLAGS="$CXXFLAGS -flto -fuse-ld=lld-12 -Wl,-plugin-opt=save-temps"
    export CFLAGS="$CFLAGS -flto -fuse-ld=lld-12 -Wl,-plugin-opt=save-temps"
    "$TARGET/build.sh"

    mv $TARGET/repo $TARGET/repo_bc
)

# static analysis
(

)

# build with SymSan
(
    export KO_CXX=clang++-12
    export KO_CC=clang-12
    export CXX="$FUZZER/symsan/bin/ko-clang++"
    export CC="$FUZZER/symsan/bin/ko-clang"
    export KO_DONT_OPTIMIZE=1
    export KO_USE_FASTGEN=1

    export KO_ADD_AFLGO=1
    export AFLGO_TARGET_DIR=$TARGET/targets
    unset AFLGO_PREPROCESSING

    export OUT="/magma_out/symsan"
    export LDFLAGS="$LDFLAGS -L$OUT -g"

    mkdir -p $AFLGO_TARGET_DIR
    "$MAGMA/build.sh"
    "$TARGET/build.sh"
)
