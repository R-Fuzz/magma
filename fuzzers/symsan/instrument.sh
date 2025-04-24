#!/bin/bash
set -xe

##
# Pre-requirements:
# - env FUZZER: path to fuzzer work dir
# - env TARGET: path to target work dir
# - env MAGMA: path to Magma support files
# - env OUT: path to directory where artifacts are stored
# - env CFLAGS and CXXFLAGS must be set to link against Magma instrumentation
##

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

    export CXXFLAGS="$CXXFLAGS -O0 -g -flto -fuse-ld=lld-12 -Wl,-plugin-opt=save-temps"
    export CFLAGS="$CFLAGS -O0 -g -flto -fuse-ld=lld-12 -Wl,-plugin-opt=save-temps"

    "$TARGET/build_bc.sh"
)

blacklist=("XML005" "XML007" "XML013" "XML014" "XML015")
find "$TARGET/patches/bugs" -name "*.patch" | \
while read patch; do
    echo "Preparing env for $patch"
    NAME=${patch##*/}
    BUG_ID=${NAME%.patch}

    if [[ " ${blacklist[@]} " =~ " ${BUG_ID} " ]]; then
        echo "Skipping blacklisted BUG_ID: $BUG_ID"
        continue
    fi

    # static analysis
    (
        $FUZZER/kernel-analyzer/build/lib/KAMain \
        --entry-list=${TARGET}/BBEntry.txt \
        --target-list=${TARGET}/BBtargets/${BUG_ID}/BBtargets.txt \
        --dump-policy=${TARGET}/BBtargets/${BUG_ID}/policy_reach.txt \
        --dump-distance=${TARGET}/BBtargets/${BUG_ID}/distance_reach.cfg.txt \
        --dump-bid-mapping=${TARGET}/BBtargets/${BUG_ID}/bid_loc_mapping.txt \
        --dump-func-info=${TARGET}/BBtargets/${BUG_ID}/function_info.txt \
        @${TARGET}/bcfiles.txt

        #$FUZZER/kernel-analyzer/build/lib/KAMain \
        #--entry-list=${MAGMA}/BBEntry.txt \
        #--target-list=${MAGMA}/BBtargets.txt \
        #--dump-policy=${TARGET}/BBtargets/${BUG_ID}/policy_trigger.txt \
        #--dump-distance=${TARGET}/BBtargets/${BUG_ID}/distance_trigger.cfg.txt \
        #"$OUT/clang_bc/canary.o"

        #python3 $FUZZER/merge_distance_policy.py ${TARGET}/BBtargets/${BUG_ID}
        mv ${TARGET}/BBtargets/${BUG_ID}/distance_reach.cfg.txt ${TARGET}/BBtargets/${BUG_ID}/distance.cfg.txt
        mv ${TARGET}/BBtargets/${BUG_ID}/policy_reach.txt ${TARGET}/BBtargets/${BUG_ID}/policy.txt
    )

    # build with AFLGo instrumented version
    (
        export CC="$FUZZER/aflgo/instrument/afl-clang-fast"
        export CXX="$FUZZER/aflgo/instrument/afl-clang-fast++"
        # Set aflgo-instrumentation flags
        export CFLAGS="$CFLAGS -O0 -g -distance=${TARGET}/BBtargets/${BUG_ID}/distance.cfg.txt"
        export CXXFLAGS="$CXXFLAGS -O0 -g -distance=${TARGET}/BBtargets/${BUG_ID}/distance.cfg.txt"

        export BUG_DIR="$OUT/aflgo/${BUG_ID}"
        export FUZZER_LIB="-l:afl_driver.o -lstdc++"
        export LDFLAGS="$LDFLAGS -L${OUT}/aflgo -L${BUG_DIR} -g"
        export OUT=$BUG_DIR

        mkdir -p $OUT
        "$MAGMA/build.sh"
        "$TARGET/build.sh"
    )

    # build with SymSan instrumented version
    (
        export KO_CXX=clang++-12
        export KO_CC=clang-12
        export CXX="$FUZZER/symsan/build/bin/ko-clang++"
        export CC="$FUZZER/symsan/build/bin/ko-clang"
        export KO_DONT_OPTIMIZE=1
        export KO_USE_FASTGEN=1

        export KO_ADD_AFLGO=1
        export AFLGO_TARGET_DIR="${TARGET}/BBtargets/${BUG_ID}"
        unset AFLGO_PREPROCESSING

        export LDFLAGS="$LDFLAGS -L$OUT/symsan"
        export FUZZER_LIB="-l:libfuzzer-harness-fast.o -lstdc++"
        export OUT="$OUT/symsan/${BUG_ID}"
        export LDFLAGS="$LDFLAGS -L$OUT"

        mkdir -p $OUT
        "$MAGMA/build.sh"
        "$TARGET/build.sh"
    )
done