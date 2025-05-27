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

export AFL_PATH="$FUZZER/repo/"
export CC="$FUZZER/repo/afl-cc"
export CXX="$FUZZER/repo/afl-cc++"
export AS="llvm-as"
export AR="llvm-ar"
export RANLIB="llvm-ranlib"

export LIBS="$LIBS $FUZZER/repo/utils/aflpp_driver/libAFLDriver.a"
export CFLAGS="$CFLAGS -fsanitize=address"
export CXXFLAGS="$CXXFLAGS -fsanitize=address -stdlib=libstdc++"
export LDFLAGS="$LDFLAGS -fsanitize=address"

# Build the AFL-only instrumented version
(
    export OUT="$OUT/afl"
    export LDFLAGS="$LDFLAGS -L$OUT"

    export AFL_LLVM_DICT2FILE="$OUT/afl++.dict"
    export AFL_LLVM_DICT2FILE_NO_MAIN="1"

    "$MAGMA/build.sh"
    "$TARGET/build.sh"
)

# Build the CmpLog instrumented version

(
    export OUT="$OUT/cmplog"
    export LDFLAGS="$LDFLAGS -L$OUT"

    export AFL_LLVM_CMPLOG=1

    "$MAGMA/build.sh"
    "$TARGET/build.sh"
)

# NOTE: We pass $OUT directly to the target build.sh script, since the artifact
#       itself is the fuzz target. In the case of Angora, we might need to
#       replace $OUT by $OUT/fast and $OUT/track, for instance.
