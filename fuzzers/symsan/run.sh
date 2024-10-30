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

python3 -u "$FUZZER/symsan/mazerunner/mazerunner.py" \
    -i "$TARGET/corpus/$PROGRAM" \
    -o "$SHARED/findings" \
    -s "$TARGET/BBtargets/$BUGID" \
    -a explore -m reachability \
    $FUZZARGS -- "$OUT/$BUGID/$PROGRAM" $ARGS 2>&1
