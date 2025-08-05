#!/bin/bash

##
# Pre-requirements:
# - env FUZZER: path to fuzzer work dir
# - env TARGET: path to target work dir
# - env OUT: path to directory where artifacts are stored
# - env SHARED: path to directory shared with host (to store results)
# - env PROGRAM: name of program to run (should be found in $OUT)
# - env ARGS: extra arguments to pass to the program
# - env COMMIT: git commit hash of mazerunner
# - env LLM_MODEL: name of the LLM model to use
# - env ROUND: experiment round number
# - env BUGID: ID of the bug under $PROGRAM
##

ARGS=${ARGS:-"@@"}

cd "$FUZZER/symsan"
git fetch --all
git reset --hard origin/main
if [ -n "$COMMIT" ]; then
    git checkout "$COMMIT"
fi

mkdir -p "$SHARED/findings"
cd "$SHARED/findings"

ulimit -c 0
find "$TARGET/patches/bugs" -name "*.patch" | \
while read patch; do
    echo "Preparing env for $patch"
    NAME=${patch##*/}
    BUGID=${NAME%.patch}

    GEN_CODE_FILE=$(find "$FUZZER/llm_response/$PROGRAM" -maxdepth 1 -type f -name "${BUGID}_${LLM_MODEL}*${ROUND}.txt" 2>/dev/null | head -n 1)
    if [ -n "$GEN_CODE_FILE" ]; then
        echo "Found LLM produced generator $GEN_CODE_FILE"
        PRE_BUILT_FLAG="-code ${GEN_CODE_FILE}"
    else
        echo "No pre-produced GEN_CODE_FILE for $PROGRAM,$BUGID,$LLM_MODEL,$ROUND"
        PRE_BUILT_FLAG=""
        # continue
    fi
    
    pushd "$TARGET/BBtargets/${BUGID}"
    cp ${PROGRAM}_policy.txt policy.txt
    cp ${PROGRAM}_distance.cfg.txt distance.cfg.txt
    cp ${PROGRAM}_bid_loc_mapping.txt bid_loc_mapping.txt
    cp ${PROGRAM}_function_info.txt function_info.txt
    popd

    PROGRAM_PATH="$OUT/clang_bc/$(basename "$TARGET")/${PROGRAM}"

    if [ ! -f "$PROGRAM_PATH" ]; then
        echo "ERROR: Executable File $PROGRAM_PATH not found" >&2
        continue
    fi
    
    cd "$SHARED/findings"
    python3 "$FUZZER/symsan/mazerunner/llm_baseline.py" \
        -s "$TARGET/BBtargets/${BUGID}" \
        -m "$LLM_MODEL" \
        -l prompt_${BUGID}.log \
        -info ${BUGID} \
        $PRE_BUILT_FLAG \
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