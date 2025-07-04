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

ARGS=${ARGS:-"@@"}

pushd "$FUZZER/symsan"
git fetch --all
git reset --hard origin/main
if [ -n "$COMMIT" ]; then
    git checkout "$COMMIT"
fi
popd

mkdir -p "$SHARED/findings"
cd "$SHARED/findings"

ulimit -c 0
find "$TARGET/patches/bugs" -name "*.patch" | \
while read patch; do
    echo "Preparing env for $patch"
    NAME=${patch##*/}
    BUGID=${NAME%.patch}

    python3 "$FUZZER/symsan/mazerunner/llm_baseline.py" \
        -s "$TARGET/BBtargets/${BUGID}" \
        -l prompt_${BUGID}.log -info ${BUGID} \
        -- "$OUT/symsan/$BUGID/${PROGRAM}.taint" $ARGS

    # fill up cannary buffer to let monitor read it
    i=0
    while [ $i -lt 20 ]; do
        "$OUT/symsan/$BUGID/${PROGRAM}.taint" llm_${BUGID}
        sleep 1
        i=$((i + 1))
    done
done