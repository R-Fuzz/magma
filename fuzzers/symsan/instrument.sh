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

export FUZZER_LIB="-l:libfuzzer-harness-fast.o -lstdc++"

# build bitcode files
(
    export CXX=clang++-12
    export CC=clang-12

    export OUT="$OUT/clang_bc"
    export LDFLAGS="$LDFLAGS -L$OUT -g"

    "$MAGMA/build.sh"

    cp -r $TARGET/repo $TARGET/repo_bc

    $CC $CFLAGS -DMAGMA_FATAL_CANARIES -emit-llvm -c -D"MAGMA_STORAGE=\"$MAGMA_STORAGE\"" -c "$MAGMA/src/canary.c" \
    -fPIC -I "$MAGMA/src/" -o "$OUT/canary.o" $LDFLAGS

    export CXXFLAGS="$CXXFLAGS -flto -fuse-ld=lld-12 -Wl,-plugin-opt=save-temps"
    export CFLAGS="$CFLAGS -flto -fuse-ld=lld-12 -Wl,-plugin-opt=save-temps"
    "$TARGET/build_bc.sh"
)

# build AFL instrumented version
(
    export CC="$FUZZER/afl/afl-clang-fast"
    export CXX="$FUZZER/afl/afl-clang-fast++"

    export OUT="$OUT/afl"
    export FUZZER_LIB="-l:afl_driver.o -lstdc++"
    export LDFLAGS="$LDFLAGS -L$OUT -g"

    "$MAGMA/build.sh"
    "$TARGET/build.sh"
)

find "$TARGET/patches/bugs" -name "*.patch" | \
while read patch; do
    echo "Preparing env for $patch"
    NAME=${patch##*/}
    BUG_ID=${NAME%.patch}
    # static analysis
    (
        $FUZZER/kernel-analyzer/build/lib/KAMain \
        --entry-list=${TARGET}/BBEntry.txt \
        --target-list=${TARGET}/BBtargets/${BUG_ID}/BBtargets.txt \
        --dump-policy=${TARGET}/BBtargets/${BUG_ID}/policy.txt \
        --dump-distance=${TARGET}/BBtargets/${BUG_ID}/distance.cfg.txt \
        @${TARGET}/bcfiles.txt

        $FUZZER/kernel-analyzer/build/lib/KAMain \
        --entry-list=${MAGMA}/BBEntry.txt \
        --target-list=${MAGMA}/BBtargets.txt \
        --dump-policy=${TARGET}/BBtargets/${BUG_ID}/policy.txt \
        --dump-distance=${TARGET}/BBtargets/${BUG_ID}/distance.cfg.txt \
        "$OUT/clang_bc/canary.o"
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
        export AFLGO_TARGET_DIR="${TARGET}/BBtargets/${BUG_ID}"
        unset AFLGO_PREPROCESSING

        export LDFLAGS="$LDFLAGS -L$OUT/symsan"
        export OUT="$OUT/${BUG_ID}"

        mkdir -p $OUT
        "$MAGMA/build.sh"
        export LDFLAGS="$LDFLAGS -L$OUT"
        "$TARGET/build.sh"
    )
done
