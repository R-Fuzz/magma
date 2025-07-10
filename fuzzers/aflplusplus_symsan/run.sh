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
##

# AFL++ fuzz driver uses a persistent loop and reads input from stdin only
if nm "$OUT/afl/$PROGRAM" | grep -E '^[0-9a-f]+\s+[Ww]\s+main$'; then
    ARGS="-"
fi

mkdir -p "$SHARED/findings"

export AFL_SKIP_CPUFREQ=1
export AFL_NO_AFFINITY=1
export AFL_NO_UI=1
export AFL_MAP_SIZE=256000
export AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES=1
export AFL_IGNORE_UNKNOWN_ENVS=1
export AFL_FAST_CAL=1
export AFL_NO_WARN_INSTABILITY=1
export AFL_BENIGN_PROGRAM_ABNORMAL_EXIT=1

for i in $OUT/*.dict $OUT/*.dic $OUT/afl/*.dict $OUT/afl/*.dic; do
    test -f "$i" && DICT="$DICT -x $i"
done

ulimit -c unlimited

#export AFL_DISABLE_TRIM=1
export AFL_CUSTOM_MUTATOR_LIBRARY="$FUZZER/symsan/build/bin/libSymSanMutator.so"
export SYMSAN_TARGET="$OUT/symsan/${PROGRAM}.taint"
export SYMSAN_SOLVE_UB=1
export SYMSAN_USE_JIGSAW=1
export SYMSAN_USE_NESTED=1
#export SYMSAN_SAVE_SOLVED=1
#export AFL_CUSTOM_MUTATOR_ONLY=1
export SYMSAN_DONT_EXIT_ON_MEMERROR=1

"$FUZZER/aflpp/afl-fuzz" -m none \
    -i "$TARGET/corpus/$PROGRAM" -o "$SHARED/findings" \
    $DICT $FUZZARGS -- "$OUT/afl/$PROGRAM" $ARGS 2>&1
