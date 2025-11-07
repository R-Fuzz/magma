#!/bin/bash
set -xe

##
# Pre-requirements:
# - env FUZZER: path to fuzzer work dir
# - env TARGET: path to target work dir
# - env OUT: path to directory where artifacts are stored
# - env SHARED: path to directory shared with host (to store results)
# - env PROGRAM: name of program to run (should be found in $OUT)
# - env ARGS: extra arguments to pass to the program
# - env FUZZARGS: extra arguments to pass to the fuzzer
# - env LLM_MODEL: sonnet-4.5, sonnet-4.5-thinking, gpt-5, opus-4.1, grok
##

mkdir -p "$SHARED/findings"
ARGS=${ARGS:-"@@"}

export PATH=/usr/lib/llvm-20/bin:$PATH
export PATH="$HOME/.local/bin:$PATH"

extract_progress() {                # input: block of text
    printf '%s' "$1" | grep -oE '[0-9]+(\.[0-9]+)?%' | head -n1
}

percent_gt() {                      # args: VALUE% THRESHOLD%
    local v="$1" t="$2"
    [ -n "$v" ] || return 1
    v="${v%\%}"; t="${t%\%}"
    awk -v a="$v" -v b="$t" 'BEGIN{ exit (a>b)?0:1 }'
}

if [ -d "${OUT}/BBtargets/${BUGID}" ]; then
    pushd "${OUT}/BBtargets/${BUGID}"
    cp "${PROGRAM}_policy.txt" "policy.txt" || true
    cp "${PROGRAM}_distance.cfg.txt" "distance.cfg.txt" || true
    cp "${PROGRAM}_bid_loc_mapping.txt" "bid_loc_mapping.txt" || true
    cp "${PROGRAM}_function_info.txt" "function_info.txt" || true
    cp "${PROGRAM}_caller-callee.txt" "caller-callee.txt" || true
    cp "${PROGRAM}_callee-caller.txt" "callee-caller.txt" || true
    cp "${PROGRAM}_critical_BBs.txt" "critical_BBs.txt" || true
    popd
fi

cd "${FUZZER}/repo"
git fetch --all
git reset --hard origin/baseline-w-tool
if [ -n "$COMMIT" ]; then
    git checkout "$COMMIT"
fi

TARGET_NAME="$(basename "$TARGET")"
python3 "${FUZZER}/repo/launcher.py" -baseline \
    -s "${OUT}/BBtargets/${BUGID}" \
    -m "${LLM_MODEL}" \
    -c "$TARGET/repo" \
    -o "$SHARED/findings" \
    -reached-pattern "Bug ${BUGID} reached" \
    -triggered-pattern "Bug ${BUGID} triggered" \
    -- "$OUT/clang_bc/$TARGET_NAME/$PROGRAM" $ARGS

cd "$TARGET/repo"

SESSION="cursor_session"
AGENT_LOG_FILE="$SHARED/findings/agent.log"

tmux new-session -d -s "$SESSION" "cursor-agent --force --model ${LLM_MODEL}"
sleep 3

OUTPUT="$(tmux capture-pane -t "$SESSION" -p -S -0)"
if echo "$OUTPUT" | grep -q "Workspace Trust Required"; then
    tmux send-keys -t "$SESSION" "a"
    sleep 3
fi

OUTPUT="$(tmux capture-pane -t "$SESSION" -p -S -0)"
if echo "$OUTPUT" | grep -q "MCP Server Approval Required"; then
    # Approve MCP servers
    tmux send-keys -t "$SESSION" "a"
    sleep 3
fi

OUTPUT="$(tmux capture-pane -t "$SESSION" -p -S -100)"
if ! (echo "$OUTPUT" | grep -q "Cursor Agent"); then
    exit 1
fi

tmux send-keys -t "$SESSION" C-c
tmux send-keys -t "$SESSION" C-d
tmux kill-session -t "$SESSION" || true

cursor-agent --force --model "${LLM_MODEL}" --output-format stream-json -p "$(cat $SHARED/findings/prompt.txt)" &> $SHARED/findings/agent.log