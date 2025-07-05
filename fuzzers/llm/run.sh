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
# - env LLM_MODEL: name of the LLM model to use
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

    PROGRAM_PATH="$OUT/clang_bc/$(basename "$TARGET")/${PROGRAM}"
    DISTANCE_FILE="$TARGET/BBtargets/${BUGID}/distance.cfg.txt"
    POLICY_FILE="$TARGET/BBtargets/${BUGID}/policy.txt"
    if [ ! -f "$DISTANCE_FILE" ] || [ ! -s "$DISTANCE_FILE" ]; then
        echo "ERROR: $DISTANCE_FILE for $BUGID is missing or empty" >&2
        continue
    fi
    if [ ! -f "$POLICY_FILE" ] || [ ! -s "$POLICY_FILE" ]; then
        echo "ERROR: $POLICY_FILE for $BUGID is missing or empty" >&2
        continue
    fi
    if [ ! -f "$PROGRAM_PATH" ]; then
        echo "ERROR: Executable File $PROGRAM_PATH not found" >&2
        continue
    fi
    
    python3 "$FUZZER/symsan/mazerunner/llm_baseline.py" \
        -s "$TARGET/BBtargets/${BUGID}" \
        -m "$LLM_MODEL" \
        -l prompt_${BUGID}.log -info ${BUGID} \
        -- "$PROGRAM_PATH" $ARGS

    LLM_FILE="$SHARED/findings/llm_${BUGID}"
    if [ ! -f "$LLM_FILE" ]; then
        echo "ERROR: $LLM_FILE not found" >&2
        continue
    fi
    "$PROGRAM_PATH" "$LLM_FILE"
    # fill up canary buffer to let monitor read it
    i=0
    while [ $i -lt 60 ]; do
        sleep 1
        "$PROGRAM_PATH" "$LLM_FILE" &> /dev/null
        i=$((i + 1))
    done
done