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


SKIP_STATIC_ANALYSIS=1
# These bug IDs are verified to be statically not reachable from interprocedural whole program CFG.
blacklist=(
    "PNG002"                                     \
    "PHP005" "PHP008" "SQL004" "SQL005" "SQL008" \
    "SND006" "SND007" "SND024" "SSL002" "SSL004" \
    "SSL005" "SSL008" "SSL009" "SSL011" "SSL012" \
    "SSL014" "SSL015" "SSL017" "SSL018" "SSL019" \
    "SSL020" "XML004" "XML005" "XML007" "XML013" \
    "XML014" "XML015" "XML016" "PDF001" "PDF003" \
    "PDF004" "PDF006" "PDF010" "PDF013" "PDF015" \
    "PDF017" "PDF020" "TIF004" "TIF011" "TIF013"
)

TARGET_NAME="$(basename $TARGET)"
IR_DIR="${OUT}/clang_bc/${TARGET_NAME}"
mkdir -p "$IR_DIR"

SRC_DIR=$TARGET/repo/
cp $FUZZER/src/magma.md $SRC_DIR

# build bitcode files
build_bitcode() {(
    export CXX=clang++-${LLVM_VERSION}
    export CC=clang-${LLVM_VERSION}
    export AR=llvm-ar-${LLVM_VERSION}
    export RANLIB=llvm-ranlib-${LLVM_VERSION}
    
    # Ensure we use LLVM $LLVM_VERSION toolchain
    export PATH="/usr/lib/llvm-${LLVM_VERSION}/bin:$PATH"
    export LD_LIBRARY_PATH="/usr/lib/llvm-${LLVM_VERSION}/lib:$LD_LIBRARY_PATH"
    
    export OUT="$IR_DIR"
    export LDFLAGS="$LDFLAGS -g -L$OUT -fuse-ld=lld-${LLVM_VERSION} -Wl,-plugin-opt=save-temps"
    export FUZZER_LIB="$OUT/libfuzzer-harness-fast.a"
    $CXX $CXXFLAGS -c -fPIC -o $OUT/harness-proxy.o "$FUZZER/src/afl_driver.cpp"
    $AR rcu $FUZZER_LIB $OUT/harness-proxy.o

    export CFLAGS="$CFLAGS -O0 -g -fPIC -flto"
    export CXXFLAGS="$CXXFLAGS -O0 -g -fPIC -flto"

    if [[ "sqlite3" == "$TARGET_NAME" ]]; then
        export LDFLAGS="$LDFLAGS -stdlib=libc++ -lc++"
        export CXXFLAGS="$CXXFLAGS -stdlib=libc++"
    fi

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
static_analyze() {(
    set +e

    # Skip static analysis for php and openssl targets.
    # Some projects are large and analysis is slow.
    # Copy pre-analyzed BBtargets for faster image build.
    if [[ $SKIP_STATIC_ANALYSIS -eq 1 ]]; then
        echo "Skipping static analysis for $TARGET_NAME"
        return
    fi
    # Reuse pre-built clang bitcode files for consistent analysis results.
    if [[ $REUSE_PREBUILT_BC -eq 1 ]]; then
        echo "Reusing pre-built BBtargets for $TARGET_NAME"
        rm -rf "$OUT/clang_bc/*"
        cp -r "$FUZZER/pre-built/${TARGET_NAME}/clang_bc" "$OUT/"
    fi

    find "$TARGET/patches/bugs" -name "*.patch" | \
    while read patch; do
        echo "Preparing static analysis env for $patch"
        NAME=${patch##*/}
        BUG_ID=${NAME%.patch}

        if [[ " ${blacklist[*]} " =~ " ${BUG_ID} " ]]; then
            echo "Skipping blacklisted BUG_ID: $BUG_ID"
            continue
        fi
        
        SRC_DIR=$TARGET/repo/
        if [ "sqlite3" = $TARGET_NAME ]; then
            SRC_DIR=$TARGET/work/
        fi

        (
            OUT="${TARGET}/BBtargets/${BUG_ID}"
            rm -rf $OUT || true
            mkdir -p $OUT
            if ! grep "MAGMA_LOG(\"${BUG_ID}" "$SRC_DIR" -nR | \
                awk -F: '{print $1":"$2}' | sed 's/.*\///' \
                > $OUT/BBtargets.txt; then
                echo "Error: Failed to find MAGMA_LOG for BUG_ID: $BUG_ID" >&2
                continue
            fi

            BCS=$(find ${IR_DIR} -name "*.0.0.preopt.bc")
            for BC in $BCS; do
                PROGRAM="$(basename ${BC%%.0*})"
                # libfuzzer=$(llvm-nm-${LLVM_VERSION} $BC | grep -c -- " LLVMFuzzerTestOneInput$") || true
                # if [[ $libfuzzer -eq 0 ]]; then
                #     echo "main" > ${IR_DIR}/${PROGRAM}_BBEntry.txt
                # else
                #     echo "LLVMFuzzerTestOneInput" > ${IR_DIR}/${PROGRAM}_BBEntry.txt
                # fi
                PREFIX="${BUG_ID}_${PROGRAM}"
                rm "${BC}_${BUG_ID}.bc" || true
                if ! $FUZZER/kernel-analyzer/build/lib/KAMain \
                    --target-list=$OUT/BBtargets.txt \
                    --dump-policy=$OUT/${PROGRAM}_policy.txt \
                    --dump-distance=$OUT/${PROGRAM}_distance.cfg.txt \
                    --dump-bid-mapping=$OUT/${PROGRAM}_bid_loc_mapping.txt \
                    --dump-func-info=$OUT/${PROGRAM}_function_info.txt \
                    --dump-critical-branch=$OUT/${PROGRAM}_critical_BBs.txt \
                    --dump-caller-callee=$OUT/${PROGRAM}_caller-callee.txt \
                    --dump-callee-caller=$OUT/${PROGRAM}_callee-caller.txt \
                    --call-stack-len=20 \
                    --dump-annotated-ir="_${BUG_ID}.bc" \
                    --type-based-callgraph=1 \
                    "${BC}" 2> ${IR_DIR}/${PREFIX}.log; then
                    echo "Error: KAMain analysis failed for BUG_ID: $BUG_ID, PROGRAM: $PROGRAM" >&2
                    continue
                fi
            done
            # generate instrumentation list for afl++
            cat ${OUT}/*_distance.cfg.txt | grep '^fun:' >> ${IR_DIR}/afl_allow.txt || true
        )
    done
    if [ -s "${IR_DIR}/afl_allow.txt" ]; then
        sort -u "${IR_DIR}/afl_allow.txt" -o "${IR_DIR}/afl_allow.txt"
    else
        rm "$IR_DIR/afl_allow.txt"
    fi
)}

build_bitcode
if [[ $SKIP_STATIC_ANALYSIS -eq 0 ]]; then
    static_analyze
else
    rm -rf "${OUT}/BBtargets" || true
    mv "${FUZZER}/pre-built/BBtargets" "$OUT/"
fi
