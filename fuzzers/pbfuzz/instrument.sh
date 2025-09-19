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
TARGET_NAME="$(basename "$TARGET")"
if [ "sqlite3" = "$TARGET_NAME" ]; then
    SRC_DIR=$TARGET/work/
fi
cp $FUZZER/src/magma.md $SRC_DIR

# build bitcode files
build_bitcode() {(
    export PATH=/usr/lib/llvm-${LLVM_VERSION}/bin:$PATH
    export LLVM_COMPILER=clang
    export CC="wllvm"
    export CXX="wllvm++"
    export AR=llvm-ar-${LLVM_VERSION}
    export RANLIB=llvm-ranlib-${LLVM_VERSION}
    
    export OUT="$IR_DIR"
    export LDFLAGS="$LDFLAGS -L$OUT -g"
    export FUZZER_LIB="$OUT/libafl_driver.a"
    
    # Build AFL driver and create static library
    $CXX -std=c++11 -c "$FUZZER/src/afl_driver.cpp" -fPIC -o "$OUT/afl_driver.o"
    $AR rcs $FUZZER_LIB "$OUT/afl_driver.o"

    DYNAMIC_TARGETS=(poppler)
    if [[ ! " ${DYNAMIC_TARGETS[@]} " =~ " $TARGET_NAME " ]]; then
        export LIBS="$LIBS $FUZZER_LIB"
    fi

    "$MAGMA/build.sh"
    "$TARGET/build.sh"
)}

static_analyze() (
    cd "$OUT"
    source "$TARGET/configrc"

    for PROGRAM in "${PROGRAMS[@]}"; do
        extract-bc "$PROGRAM"
    done

    find "$TARGET/patches/bugs" -name "*.patch" | \
        while read -r patch; do
        echo "Preparing static analysis env for $patch"  
        NAME=${patch##*/}
        BUG_ID=${NAME%.patch}

        if [[ " ${blacklist[*]} " =~ " ${BUG_ID} " ]]; then
            echo "Skipping blacklisted BUG_ID: $BUG_ID"
            continue
        fi

        for PROGRAM in "${PROGRAMS[@]}"; do
            BUG_PATH="${OUT}/BBtargets/${PROGRAM}/${BUG_ID}"
            rm -rf "$BUG_PATH" || true
            mkdir -p "$BUG_PATH"

            if ! grep "MAGMA_LOG(\"${BUG_ID}" "$SRC_DIR" -nR | \
            awk -F: '{print $1":"$2}' | sed 's/.*\///' \
            > "$BUG_PATH/BBtargets.txt"; then
            echo "Error: Failed to find MAGMA_LOG for BUG_ID: $BUG_ID" >&2
            continue
            fi

            BC=$(find "$OUT" -name "$PROGRAM.bc")
            if ! "$FUZZER/kernel-analyzer/build/lib/KAMain" \
                --target-list="$BUG_PATH/BBtargets.txt" \
                --dump-distance="$BUG_PATH/${PROGRAM}_distance.cfg.txt" \
                --dump-bid-mapping="$BUG_PATH/${PROGRAM}_bid_loc_mapping.txt" \
                --dump-func-info="$BUG_PATH/${PROGRAM}_function_info.txt" \
                --dump-critical-branch="$BUG_PATH/${PROGRAM}_critical_BBs.txt" \
                --dump-caller-callee="$BUG_PATH/${PROGRAM}_caller-callee.txt" \
                --dump-callee-caller="$BUG_PATH/${PROGRAM}_callee-caller.txt" \
                --call-stack-len=20 \
                --type-based-callgraph=1 \
                "$BC"; then
            echo "Error: KAMain analysis failed for BUG_ID: $BUG_ID, PROGRAM: $PROGRAM" >&2
            continue
            fi
        done
    done
)

build_bitcode
if [[ $SKIP_STATIC_ANALYSIS -eq 0 ]]; then
    static_analyze
else
    rm -rf "${OUT}/BBtargets" || true
    rm -rf "${OUT}/clang_bc" || true
    mv "${FUZZER}/pre-built/BBtargets" "$OUT/"
    mv "${FUZZER}/pre-built/clang_bc" "$OUT/"
fi
