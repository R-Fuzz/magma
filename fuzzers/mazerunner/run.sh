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
##

mkdir -p "$SHARED/findings"
ulimit -c 0

(
    export AFL_HANG_TMOUT=100
    export AFL_SKIP_CPUFREQ=1
    export AFL_NO_AFFINITY=1
    export AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES=1
    export ASAN_OPTIONS="abort_on_error=1:symbolize=0"
    export AFL_NO_UI=1

    nohup timeout "$TIMEOUT" \
        "$FUZZER/aflgo/afl-2.57b/afl-fuzz" \
        -S out -l /tmp/mr -m none \
        -i /magma/targets/libpng/corpus/libpng_read_fuzzer \
        -o "$SHARED/findings/aflgo" \
        $FUZZARGS -- "$OUT/$BUGID/$PROGRAM" $ARGS \
        > "$SHARED/findings/aflgo.log" 2>&1 &
)
sleep 2s
(
    nohup timeout "$TIMEOUT" \
        python3 -u "$FUZZER/symsan/mazerunner/mazerunner.py" \
        -monitor_resource -a hybrid -n mazerunner \
        -f "$SHARED/findings/aflgo/out" \
        -i /magma/targets/libpng/corpus/libpng_read_fuzzer \
        -m reachability \
        -o "$SHARED/findings" \
        -s "$TARGET/BBtargets" \
        $FUZZARGS -- "$OUT/$BUGID/$PROGRAM" $ARGS \
        > "$SHARED/findings/mazerunner.log" 2>&1 &
)
