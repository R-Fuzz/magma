#!/bin/bash -e

##
# Pre-requirements:
# - $1: path to test case
# - env FUZZER: path to fuzzer work dir
# - env TARGET: path to target work dir
# - env OUT: path to directory where artifacts are stored
# - env PROGRAM: name of program to run (should be found in $OUT)
# - env ARGS: extra arguments to pass to the program
# - env BUGID: ID of the bug under $PROGRAM
##

export TIMELIMIT=0.1s
export MEMLIMIT_MB=100

run_limited()
{
    ulimit -Sv $[MEMLIMIT_MB << 10];
    ${@:1}
    test $? -lt 128
}
export -f run_limited

args="${ARGS/@@/"'$1'"}"
if [ -z "$args" ]; then
    args="'$1'"
fi

TARGET_NAME="$(basename "$TARGET")"
timeout -s KILL --preserve-status $TIMELIMIT bash -c \
    "run_limited '$OUT/clang_bc/$TARGET_NAME/$PROGRAM' $args"
