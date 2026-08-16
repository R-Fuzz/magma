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
# + env AFL_MAP_SIZE: coverage map size (default: whatever instrument.sh
#       recorded in $OUT/afl/map_size when it built the target, else 65536)
# + env EXEC_TIMEOUT: per-execution timeout in ms (default: 5000)
##

ARGS=${ARGS:-"@@"}

# The map size belongs to the build, not to the run, so instrument.sh writes
# down the number it used and this only overrides it when told to.  Reading it
# from a file rather than the environment is not a stylistic choice: captain
# passes only PROGRAM, ARGS, FUZZARGS, POLL, TIMEOUT and BUGID through to the
# container, so an AFL_MAP_SIZE set on the host would be lost in between.
if [ -z "$AFL_MAP_SIZE" ] && [ -r "$OUT/afl/map_size" ]; then
    AFL_MAP_SIZE="$(cat "$OUT/afl/map_size")"
fi
export AFL_MAP_SIZE=${AFL_MAP_SIZE:-65536}

mkdir -p "$SHARED/findings"

# Not `ulimit -c unlimited`, which is what the AFL++ fuzzers here use.  The
# container shares the host's /proc/sys/kernel/core_pattern, so on a host
# running apport every crash pays roughly a second of handler time -- enough to
# dominate a campaign on a target that crashes often, and to make the exec rate
# a measure of the crash handler rather than the fuzzer.
#
# 1, not 0, for the reason spelled out at symsan driver/launcher/launch.c:705:
# the kernel only compares RLIMIT_CORE against the dump size when core_pattern
# names a file.  When it starts with '|' -- Ubuntu's apport -- that check is
# skipped and a limit of 0 dumps anyway; 1 is the value do_coredump treats as
# "abort the core" for pipes.  launch.c already sets 1 on the children it
# spawns, but the concolic target is not the only process here that can crash,
# and a SymSan-linked one that does drags its ~114 TB of shadow VMAs through
# do_coredump at 100% system time, unkillable while PF_DUMPCORE is set.
ulimit -c 1

# Both extra stages are selected by what instrument.sh actually built, so the
# four measurement arms (havoc / cmplog / symsan / both) need no second script:
# drop a build, drop an arm.  symsan-fuzz takes both --symsan and --cmplog as
# options and builds each stage only when given one, so all four fall out of
# this without a flag to say which arm is running.
#
# Dropping the concolic build has to be *deliberate*, though, which is why this
# is not simply the same `if -x` as cmplog below.  A missing concolic binary is
# almost always a build that failed, and quietly measuring the havoc floor
# instead -- for 24 hours, under the name of the symsan arm -- is the most
# expensive mistake this directory can make.  So instrument.sh leaves
# $OUT/no_symsan behind when it was told USE_SYMSAN=0, and only that marker
# turns the absence into an arm.
EXTRA=()
SYMSAN_BIN="$OUT/symsan/$PROGRAM"
if [ -x "$SYMSAN_BIN" ]; then
    EXTRA+=(--symsan "$SYMSAN_BIN")
elif [ -f "$OUT/no_symsan" ]; then
    echo "run.sh: concolic stage off (built with USE_SYMSAN=0)"
else
    echo "run.sh: no SymSan build at $SYMSAN_BIN" >&2
    exit 1
fi

if [ -x "$OUT/cmplog/$PROGRAM" ]; then
    EXTRA+=(--cmplog "$OUT/cmplog/$PROGRAM")
fi
# The map TaintPass wrote beside the SymSan binary, not the AFL++ id listing
# next to the coverage binary -- $OUT/afl/$PROGRAM.docids is ground truth for
# covcheck and is not a format this reads.  It exists iff instrument.sh ran the
# two-stage build, which is also exactly when the SymSan binary's cids are edge
# ids worth looking up; a per-TU build has neither and correctly gets neither.
if [ -f "$OUT/symsan/$PROGRAM.bmap" ]; then
    EXTRA+=(--branch-map "$OUT/symsan/$PROGRAM.bmap")
fi

exec "$FUZZER/symsan/bindings/rust/target/release/symsan-fuzz" \
    -i "$TARGET/corpus/$PROGRAM" -o "$SHARED/findings" \
    "${EXTRA[@]}" \
    -t "${EXEC_TIMEOUT:-5000}" \
    $FUZZARGS -- "$OUT/afl/$PROGRAM" $ARGS 2>&1
