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
git reset --hard origin/cursor
if [ -n "$COMMIT" ]; then
    git checkout "$COMMIT"
fi

TARGET_NAME="$(basename "$TARGET")"
python3 "${FUZZER}/repo/launcher.py" \
    -s "${OUT}/BBtargets/${BUGID}" \
    -m "${LLM_MODEL}" \
    -c "$TARGET/repo" \
    -i "$TARGET/corpus/${PROGRAM}" \
    -o "$SHARED/findings" \
    -reached-pattern "Bug ${BUGID} reached" \
    -triggered-pattern "Bug ${BUGID} triggered" \
    -- "$OUT/clang_bc/$TARGET_NAME/$PROGRAM" $ARGS

# Start new detached tmux session running cursor-agent
# cursor cli tool does not support auto-approval of mcp servers in non-interactive mode
# This is an ugly workaround hopefully the newer cursor versions will support it
SESSION="cursor_session"
PROMPT_FILE="$SHARED/findings/prompt.txt"
AGENT_LOG_FILE="$SHARED/findings/agent.log"

SRC_DIR="$TARGET/repo/"
cd "$SRC_DIR"

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

# Load prompt.txt into buffer and paste it once, then press Enter
tmux load-buffer /dev/null
tmux load-buffer "$PROMPT_FILE"
tmux paste-buffer -t "$SESSION"
sleep 3
tmux send-keys -t "$SESSION" C-m

KEYWORDS="Generating|Reading|Running|Calling|Updating|Grepping|Summarizing|fuzz|workflow_state.md"
CRASH_DIR="$SHARED/findings/crashes"
TIMEOUT=1500
END=$(($(date +%s) + TIMEOUT))

sleep 60
while [ "$(date +%s)" -lt "$END" ]; do
    LAST9="$(tmux capture-pane -t "$SESSION" -p -S 0 | tail -n 9)"
    if ! echo "$LAST9" | grep -E -q "$KEYWORDS"; then
        sleep 5
        if percent_gt "$(extract_progress "$LAST9")" "70%"; then
            tmux send-keys -t "$SESSION" "/compress"
            tmux send-keys -t "$SESSION" C-m
            sleep 20
        fi
        LAST11="$(tmux capture-pane -t "$SESSION" -p -S 0 | tail -n 11)"
        if ! echo "$LAST11" | grep -E -q "$KEYWORDS"; then
            if [ ! -d "$CRASH_DIR" ] || [ -z "$(ls -A "$CRASH_DIR" 2>/dev/null)" ]; then
                tmux send-keys -t "$SESSION" "Do not give up. Read workflow_state.md and continue."
                tmux send-keys -t "$SESSION" C-m
            else
                echo "PoC found, stopping the agent."
                break
            fi
        fi
    fi
    sleep 10
done

tmux capture-pane -t "$SESSION" -p -S -5000 > "$AGENT_LOG_FILE"
sleep 3
cp -r "$HOME/.cursor" "$SHARED/findings" || true
cp "$TARGET/repo/.cursor/mcp.json" "$SHARED/findings/.cursor" || true
cp "$TARGET/repo/.cursor/project_config.md" "$SHARED/findings/.cursor" || true
cp "$TARGET/repo/.cursor/workflow_state.md" "$SHARED/findings/.cursor" || true

# If PoC found, make sure magma records it
if [ -d "$CRASH_DIR" ] && [ -n "$(ls -A "$CRASH_DIR" 2>/dev/null)" ]; then
    for f in "$CRASH_DIR"/*; do
        RUNARGS="${f} ${ARGS//@@/$f}"
        "$OUT/clang_bc/$TARGET_NAME/$PROGRAM" $RUNARGS
    done
    sleep 5
fi

tmux send-keys -t "$SESSION" C-c
tmux send-keys -t "$SESSION" C-d
tmux kill-session -t "$SESSION" || true