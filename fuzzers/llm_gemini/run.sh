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

if nm "$OUT/aflgo/$BUGID/$PROGRAM" | grep -E '^[0-9a-f]+\s+[Ww]\s+main$'; then
    ARGS="@@"
fi

pushd "$FUZZER/symsan"
if [ -n "$COMMIT" ]; then
    git fetch --all
    git reset --hard origin/main
    git checkout "$COMMIT"
fi
popd

mkdir -p "$SHARED/findings"
cd "$SHARED/findings"

ulimit -c 0
python3 "$FUZZER/symsan/mazerunner/llm_baseline.py" \
    -s "$TARGET/BBtargets/${BUGID}" \
    -- "$OUT/symsan/$BUGID/${PROGRAM}.taint" $ARGS
sleep 5
