#!/bin/bash

##
# Pre-requirements:
# - env FUZZER: path to fuzzer work dir
# - env TARGET: path to target work dir
# - env OUT: path to directory where artifacts are stored
# - env SHARED: path to directory shared with host (to store results)
# - env PROGRAM: name of program to run (should be found in $OUT)
# - env ARGS: extra arguments to pass to the program
# - env FUZZARGS: extra arguments to pass to the fuzzer
# - env BUGID: ID of the bug under $PROGRAM
# - env COMMIT: git commit hash of mazerunner
##


pushd "$FUZZER/symsan"
if [ -n "$COMMIT" ]; then
    git fetch
    git reset --hard origin/main
    git checkout "$COMMIT"
fi
popd

mkdir -p "$SHARED/findings"

# Check if SymSan binary uses LLVMFuzzerTestOneInput or original main
if nm "$OUT/symsan/${PROGRAM}.taint" | grep -E '^[0-9a-f]+\s+[Ww]\s+main$' > /dev/null; then
    # Binary has weak main function - libFuzzer harness, use file input
    SYMSAN_ARGS="@@"
else
    # Binary has strong main function - original program, keep original ARGS
    SYMSAN_ARGS="$ARGS"
fi

# Start AFLGo fuzzer
(
    ulimit -c unlimited

    export AFL_SKIP_CPUFREQ=1
    export AFL_NO_AFFINITY=1
    export AFL_NO_UI=1
    export AFL_MAP_SIZE=256000
    export AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES=1
    export AFL_IGNORE_UNKNOWN_ENVS=1
    export AFL_FAST_CAL=1
    export AFL_NO_WARN_INSTABILITY=1
    export AFL_BENIGN_PROGRAM_ABNORMAL_EXIT=1

    nohup timeout "$TIMEOUT" \
        "$FUZZER/aflgo/afl-2.57b/afl-fuzz" \
        -S out -l /tmp/mr -m none \
        -i /magma/targets/libpng/corpus/libpng_read_fuzzer \
        -o "$SHARED/findings/aflgo" \
        $FUZZARGS -- "$OUT/aflgo/$BUGID/$PROGRAM" $ARGS \
        > "$SHARED/findings/aflgo.log" 2>&1 &
)
sleep 2s

# Start Mazerunner
(
    ulimit -c 0
    # SymSan environment variables
    export SYMSAN_TARGET="$OUT/symsan/${PROGRAM}.taint"
    export SYMSAN_SOLVE_UB=1
    export SYMSAN_USE_JIGSAW=1
    export SYMSAN_USE_NESTED=1
    export SYMSAN_DONT_EXIT_ON_MEMERROR=1

    nohup timeout "$TIMEOUT" \
        python3 -u "$FUZZER/symsan/mazerunner/mazerunner.py" \
        -monitor_resource -a hybrid -n mazerunner \
        -f "$SHARED/findings/aflgo/out" \
        -i /magma/targets/libpng/corpus/libpng_read_fuzzer \
        -m reachability \
        -o "$SHARED/findings" \
        -s "$TARGET/BBtargets" \
        $FUZZARGS -- "$OUT/symsan/${PROGRAM}.taint" $SYMSAN_ARGS \
        > "$SHARED/findings/mazerunner.log" 2>&1 &
)
