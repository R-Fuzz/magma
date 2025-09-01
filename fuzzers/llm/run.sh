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

blacklist=(
    "PNG002"                                     \
    "PHP005" "PHP008" "SQL004" "SQL005" "SQL008" \
    "SND006" "SND007" "SND024" "SSL002" "SSL004" \
    "SSL005" "SSL008" "SSL009" "SSL011" "SSL012" \
    "SSL014" "SSL015" "SSL017" "SSL018" "SSL019" \
    "SSL020" "XML004" "XML005" "XML007" "XML013" \
    "XML014" "XML015" "XML016" "PDF001" "PDF003" \
    "PDF004" "PDF006" "PDF010" "PDF013" "PDF015" \
    "PDF017" "PDF020" "TIF004" "TIF011" "TIF013"
)

export PATH=/usr/lib/llvm-20/bin:$PATH

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

    if [[ " ${blacklist[*]} " =~ " ${BUGID} " ]]; then
        echo "Skipping blacklisted BUG_ID: $BUG_ID"
        continue
    fi
    
    pushd "$TARGET/BBtargets/${BUGID}"
    cp ${PROGRAM}_policy.txt policy.txt
    cp ${PROGRAM}_distance.cfg.txt distance.cfg.txt
    cp ${PROGRAM}_bid_loc_mapping.txt bid_loc_mapping.txt
    cp ${PROGRAM}_function_info.txt function_info.txt
    popd

    PROGRAM_PATH="$OUT/clang_bc/$(basename "$TARGET")/${PROGRAM}"

# Andrew TODO: change this command. update args from env var
python launcher.py -s /magma/targets/libxml2/BBtargets/XML009 -m gemini-2.0-flash -rounds 1 -c $TARGET/repo -o output -l -reached-pattern "Bug XML009 reached" -triggered-pattern "Bug XML009 triggered" -max-fuzz-gen 30 -temperature 0.3 --- /magma_out/clang_bc/libxml2/libxml2_xml_read_memory_fuzzer @@

done