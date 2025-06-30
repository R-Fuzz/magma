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
export CXX="$FUZZER/repo/afl-c++"
export CXXFLAGS="$CXXFLAGS -stdlib=libstdc++"

# Some targets cannot directly link the libfuzz driver
DYNAMIC_TARGETS=(poppler)
TARGET_NAME="$(basename $TARGET)"
if [[ ! " ${DYNAMIC_TARGETS[@]} " =~ " $TARGET_NAME " ]]; then
    export LIBS="$LIBS $FUZZER/repo/utils/aflpp_driver/libAFLDriver.a"
fi
export FUZZER_LIB="$FUZZER/repo/utils/aflpp_driver/libAFLDriver.a"

# Some targets do not support a static AFL memory region
DYNAMIC_TARGETS=(php openssl)
TARGET_NAME="$(basename $TARGET)"
if [[ " ${DYNAMIC_TARGETS[@]} " =~ " $TARGET_NAME " ]]; then
    export AFL_LLVM_MAP_DYNAMIC=1
fi

# Build the AFL-only instrumented version
(
    export OUT="$OUT/afl"
    export LDFLAGS="$LDFLAGS -L$OUT"

    export AFL_LLVM_DICT2FILE="$OUT/afl++.dict"
    export AFL_LLVM_DICT2FILE_NO_MAIN="1"

    "$MAGMA/build.sh"
    "$TARGET/build.sh"
)


# NOTE: We pass $OUT directly to the target build.sh script, since the artifact
#       itself is the fuzz target. In the case of Angora, we might need to
#       replace $OUT by $OUT/fast and $OUT/track, for instance.
