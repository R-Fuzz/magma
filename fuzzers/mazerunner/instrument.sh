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


blacklist=("PNG002" "XML005" "XML007" "XML013" "XML014" "XML015")

TARGET_NAME="$(basename $TARGET)"
IR_DIR="${OUT}/clang_bc/${TARGET_NAME}"
mkdir -p "$IR_DIR"

# build bitcode files
build_bitcode() {(
    export CXX=clang++-${LLVM_VERSION}
    export CC=clang-${LLVM_VERSION}
    export AR=llvm-ar-${LLVM_VERSION}
    export RANLIB=llvm-ranlib-${LLVM_VERSION}

    export OUT="$IR_DIR"
    export LDFLAGS="$LDFLAGS -g -L$OUT -stdlib=libc++ -fuse-ld=lld-${LLVM_VERSION} -Wl,-plugin-opt=save-temps"
    export FUZZER_LIB="$OUT/libfuzzer-harness-fast.a"
    $CC $CFLAGS -c -fPIC -o $OUT/harness-proxy.o $FUZZER/symsan/driver/harness-proxy.c
    $AR rcu $FUZZER_LIB $OUT/harness-proxy.o

    export CFLAGS="$CFLAGS -O0 -g -fPIC -flto"
    export CXXFLAGS="$CXXFLAGS -O0 -g -fPIC -flto -stdlib=libc++"

    DYNAMIC_TARGETS=(poppler)
    if [[ ! " ${DYNAMIC_TARGETS[@]} " =~ " $TARGET_NAME " ]]; then
        export LIBS="$LIBS $FUZZER_LIB"
    fi

    ZLIB_TARGETS=(libpng libtiff)
    if [[ " ${ZLIB_TARGETS[@]} " =~ " $TARGET_NAME " ]]; then
        cp $FUZZER/zlib-1.2.13/libz.a $OUT
        export LIBS="$LIBS $OUT/libz.a"
    fi

    if [ "lua" = ${TARGET_NAME} ]; then
        #readline
        cp $FUZZER/readline-8.1.2/libreadline.a $OUT
        cp $FUZZER/termcap-1.3.1/libtermcap.a $OUT
        export LIBS="$LIBS $OUT/libtermcap.a $OUT/libreadline.a"
    fi

    "$MAGMA/build.sh"
    "$TARGET/build.sh"
)}

# static analysis
static_analyze() {
    echo "LLVMFuzzerTestOneInput" > ${IR_DIR}/BBEntry.txt

    find "$TARGET/patches/bugs" -name "*.patch" | \
    while read patch; do
        echo "Preparing env for $patch"
        NAME=${patch##*/}
        BUG_ID=${NAME%.patch}

        if [[ " ${blacklist[@]} " =~ " ${BUG_ID} " ]]; then
            echo "Skipping blacklisted BUG_ID: $BUG_ID"
            continue
        fi

        SRC_DIR=$TARGET/repo/
        if [ "sqlite3" = $TARGET_NAME ]; then
            SRC_DIR=$TARGET/work/
        fi

        (
            OUT="${TARGET}/BBtargets/${BUG_ID}"
            mkdir -p $OUT
            grep "MAGMA_LOG(\"${BUG_ID}" "$SRC_DIR" -nR | \
                awk -F: '{print $1":"$2}' | sed 's/.*\///' \
                > $OUT/BBtargets.txt

            BCS=$(find ${IR_DIR} -name "*.0.0.preopt.bc")
            for BC in $BCS; do
                PROGRAM="$(basename ${BC%%.0*})"
                PREFIX="${BUG_ID}_${PROGRAM}"
                $FUZZER/kernel-analyzer/build/lib/KAMain \
                    --entry-list=${IR_DIR}/BBEntry.txt \
                    --target-list=$OUT/BBtargets.txt \
                    --dump-policy=$OUT/policy_reach.txt \
                    --dump-distance=$OUT/distance_reach.cfg.txt \
                    --dump-bid-mapping=$OUT/bid_loc_mapping.txt \
                    --dump-func-info=$OUT/function_info.txt \
                    --type-based-callgraph=1 \
                    --verbose=2 \
                    "${BC}" 2> ${IR_DIR}/${PREFIX}.log

            mv $OUT/distance_reach.cfg.txt $OUT/distance.cfg.txt
            mv $OUT/policy_reach.txt $OUT/policy.txt
            done
        )
    done
}

# Build AFL++ instrumented version
build_afl() {(
    export AFL_PATH="$FUZZER/aflpp"
    export CC="$FUZZER/aflpp/afl-clang-fast"
    export CXX="$FUZZER/aflpp/afl-clang-fast++"

    # Some targets cannot directly link the libfuzz driver
    DYNAMIC_TARGETS=(poppler)
    if [[ ! " ${DYNAMIC_TARGETS[@]} " =~ " $TARGET_NAME " ]]; then
        export LIBS="$LIBS $FUZZER/aflpp/utils/aflpp_driver/libAFLDriver.a"
    fi
    export FUZZER_LIB="$FUZZER/aflpp/utils/aflpp_driver/libAFLDriver.a"

    # Some targets do not support a static AFL memory region
    DYNAMIC_TARGETS=(php openssl)
    if [[ " ${DYNAMIC_TARGETS[@]} " =~ " $TARGET_NAME " ]]; then
        export AFL_LLVM_MAP_DYNAMIC=1
    fi

    export OUT="$OUT/afl"
    export LDFLAGS="$LDFLAGS -L$OUT"

    export AFL_LLVM_DICT2FILE="$OUT/afl++.dict"
    export AFL_LLVM_DICT2FILE_NO_MAIN="1"

    "$MAGMA/build.sh"
    "$TARGET/build.sh"
)}

# build with AFLGo instrumented version
build_aflgo() {
    find "$TARGET/patches/bugs" -name "*.patch" | while read -r patch; do
        echo "Preparing env for $patch"
        NAME=$(basename "$patch")
        BUG_ID="${NAME%.patch}"

        if [[ " ${blacklist[*]} " =~ " ${BUG_ID} " ]]; then
            echo "Skipping blacklisted BUG_ID: $BUG_ID"
            continue
        fi

        (
            export CC="$FUZZER/aflgo/instrument/afl-clang-fast"
            export CXX="$FUZZER/aflgo/instrument/afl-clang-fast++"

            DISTANCE_FILE="${TARGET}/BBtargets/${BUG_ID}/distance.cfg.txt"
            if [[ ! -f "$DISTANCE_FILE" ]]; then
                echo "Warning: distance file not found for $BUG_ID"
                exit 1
            fi

            export CFLAGS="-O0 -g -distance=$DISTANCE_FILE"
            export CXXFLAGS="-O0 -g -distance=$DISTANCE_FILE"

            export BUG_DIR="$OUT/aflgo/${BUG_ID}"
            export LIBS="$LIBS -l:afl_driver.o -lstdc++"
            export LDFLAGS="-L${OUT}/aflgo -L${BUG_DIR} -g"
            export OUT="$BUG_DIR"

            mkdir -p "$OUT"

            echo "Building MAGMA for $BUG_ID..."
            if ! "$MAGMA/build.sh"; then
                echo "MAGMA build failed for $BUG_ID"
                exit 1
            fi

            echo "Building TARGET for $BUG_ID..."
            if ! "$TARGET/build.sh"; then
                echo "TARGET build failed for $BUG_ID"
                exit 1
            fi
        )
    done
}

# build with MazeRunner instrumented version
build_mr() {
    find "$TARGET/patches/bugs" -name "*.patch" | \
    while read patch; do
        echo "Preparing env for $patch"
        NAME=${patch##*/}
        BUG_ID=${NAME%.patch}

        if [[ " ${blacklist[@]} " =~ " ${BUG_ID} " ]]; then
            echo "Skipping blacklisted BUG_ID: $BUG_ID"
            continue
        fi
        (
        export KO_CXX=clang++-${LLVM_VERSION}
        export KO_CC=clang-${LLVM_VERSION}
        export CXX="$FUZZER/symsan/build/bin/ko-clang++"
        export CC="$FUZZER/symsan/build/bin/ko-clang"
        export KO_DONT_OPTIMIZE=1
        export KO_USE_FASTGEN=1

        export KO_ADD_AFLGO=1
        export AFLGO_TARGET_DIR="${TARGET}/BBtargets/${BUG_ID}"
        unset AFLGO_PREPROCESSING

        export LDFLAGS="$LDFLAGS -L$OUT/symsan"
        export FUZZER_LIB="$OUT/libfuzzer-harness-fast.o"
        export OUT="$OUT/symsan/${BUG_ID}"
        export LDFLAGS="$LDFLAGS -L$OUT"
        
        $CC $CFLAGS -c -fPIC -o $FUZZER_LIB $FUZZER/symsan/driver/harness-proxy.c

        ZLIB_TARGETS=(libpng libtiff)
        if [[ " ${ZLIB_TARGETS[@]} " =~ " $TARGET_NAME " ]]; then
            export KO_NO_NATIVE_ZLIB=1
        else
            unset KO_NO_NATIVE_ZLIB
        fi

        mkdir -p $OUT
        "$MAGMA/build.sh"

        OBJ_PATH="$FUZZER/symsan/build/lib/symsan"
        OPTFLAGS="-taint-abilist=${OBJ_PATH}/dfsan_abilist.txt"
        if [[ -z "$KO_NO_NATIVE_ZLIB" ]]; then
            OPTFLAGS="$OPTFLAGS -taint-abilist=${OBJ_PATH}/zlib_abilist.txt"
        fi
        if [[ "$KO_SOLVE_UB" = 1 ]]; then
            OPTFLAGS="$OPTFLAGS -taint-solve-ub=true"
        fi

        if [ "php" = $TARGET_NAME ]; then
            OPTFLAGS="$OPTFLAGS -taint-abilist=${FUZZER}/src/icu.txt"
            OPTFLAGS="$OPTFLAGS -taint-abilist=${FUZZER}/src/php.txt"
            LIBS="$LIBS $TARGET/repo/Zend/asm/make_x86_64_sysv_elf_gas.o"
            LIBS="$LIBS $TARGET/repo/Zend/asm/jump_x86_64_sysv_elf_gas.o"
            LIBS="$LIBS -licuio -licui18n -licuuc -licudata"
        elif [ "poppler" = $TARGET_NAME ]; then
            OPTFLAGS="$OPTFLAGS -taint-abilist=${FUZZER}/src/poppler.txt"
            CXXFLAGS="$CXXFLAGS -fuse-ld=lld-${LLVM_VERSION}"
            LIBS="$LIBS -lbrotlidec -ljpeg -lz -lopenjp2 -lpng -ltiff -llcms2 -lm -lpthread -pthread"
        fi

        pushd $OUT
        ORIG_LIBS="$LIBS" # make a backup
        BCS=$(find ${IR_DIR} -name "*.0.0.preopt.bc")
        for BC in $BCS; do
            PROGRAM="$(basename ${BC%%.0*})"
            IBC="${PROGRAM}.taint.bc"
            IOBJ="${PROGRAM}.taint.o"

            if [[ -f ${BC}_distance.bc ]]; then
                BC=${BC}_distance.bc
            fi

            # instrument symsan taint pass and distance pass
            opt-${LLVM_VERSION} \
            -load="${OBJ_PATH}/libTaintPass.so" \
            -load="${OBJ_PATH}/libAFLGOPass.so" \
            -enable-new-pm=0 \
            -distance=${AFLGO_TARGET_DIR}/distance.cfg.txt \
            -outdir=${AFLGO_TARGET_DIR} \
            $OPTFLAGS -o $IBC $BC

            # compile to object file
            llc-${LLVM_VERSION} -filetype=obj --relocation-model=pic -o $IOBJ $IBC

            # link with fuzzer harness and produce final binary
            with_main=$(llvm-nm-${LLVM_VERSION} $BC | grep -c -- " main$") || true
            if [[ $with_main -eq 0 ]]; then
                LIBS="$ORIG_LIBS $FUZZER_LIB"
            else
                LIBS="$ORIG_LIBS"
            fi
            $CXX $CXXFLAGS $IOBJ $LDFLAGS $LIBS -o ${PROGRAM}.taint
        done
        popd
    )
    done
}

build_bitcode
static_analyze
# build_afl
build_aflgo
build_mr
