#!/bin/bash
set -x

##
# Pre-requirements:
# - env FUZZER: path to fuzzer work dir
# - env TARGET: path to target work dir
# - env OUT: path to directory where artifacts are stored
# - env SHARED: path to directory shared with host (to store results)
# - env PROGRAM: name of program to run (should be found in $OUT)
# - env ARGS: extra arguments to pass to the program
# - env FUZZARGS: extra arguments to pass to the fuzzer
# - env LLM_MODEL: sonnet-4, gpt-5, opus-4.1, grok
##

mkdir -p "$SHARED/findings"
ARGS=${ARGS:-"@@"}

export PATH=/usr/lib/llvm-20/bin:$PATH
export PATH="$HOME/.local/bin:$PATH"

pushd "${OUT}/BBtargets/${PROGRAM}/${BUGID}"
cp ${PROGRAM}_policy.txt policy.txt
cp ${PROGRAM}_distance.cfg.txt distance.cfg.txt
cp ${PROGRAM}_bid_loc_mapping.txt bid_loc_mapping.txt
cp ${PROGRAM}_function_info.txt function_info.txt
cp ${PROGRAM}_caller-callee.txt caller-callee.txt
cp ${PROGRAM}_callee-caller.txt callee-caller.txt
cp ${PROGRAM}_critical_BBs.txt critical_BBs.txt
popd

cd python3 ${FUZZER}/repo
git fetch --all
git reset --hard origin/cursor
if [ -n "$COMMIT" ]; then
    git checkout "$COMMIT"
fi

python3 ${FUZZER}/repo/launcher.py \
    -s ${OUT}/BBtargets/${PROGRAM}/${BUGID} \
    -m ${LLM_MODEL} \
    -c $TARGET/repo \
    -i $TARGET/corpus/${PROGRAM} \
    -o "$SHARED/findings" \
    -reached-pattern "Bug ${BUGID} reached" \
    -triggered-pattern "Bug ${BUGID} triggered" \
    -- "$OUT/clang_bc/$PROGRAM" $ARGS

# Start new detached tmux session running cursor-agent
# cursor cli tool does not support auto-approval of mcp servers in non-interactive mode
# This is an ugly workaround hopefully the newer cursor versions will support it
SESSION="cursor_session"
PROMPT_FILE="$SHARED/findings/prompt.txt"
AGENT_LOG_FILE="$SHARED/findings/agent.log"
tmux new-session -d -s "$SESSION" "cursor-agent --force --model ${LLM_MODEL}"
sleep 3

OUTPUT=$(tmux capture-pane -t "$SESSION" -p -S -100)
if echo "$OUTPUT" | grep -q "Workspace Trust Required"; then
    # Trust workspace
    tmux send-keys -t "$SESSION" "a"
    sleep 3
fi

OUTPUT=$(tmux capture-pane -t "$SESSION" -p -S -100)
if echo "$OUTPUT" | grep -q "MCP Server Approval Required"; then
    # Approve MCP servers
    tmux send-keys -t "$SESSION" "a"
    sleep 3
fi

OUTPUT=$(tmux capture-pane -t "$SESSION" -p -S -100)
if echo "$OUTPUT" | grep -q "Welcome to Cursor Agent"; then
    # Load prompt.txt into buffer and paste it once, then press Enter
    tmux load-buffer "$PROMPT_FILE"
    tmux paste-buffer -t "$SESSION"
    tmux send-keys -t "$SESSION" C-m
fi

sleep $TIMEOUT
tmux send-keys -t "$SESSION" C-c
tmux send-keys -t "$SESSION" C-c
tmux capture-pane -t "$SESSION" -p -S -1000 > $AGENT_LOG_FILE
sleep 1
tmux send-keys -t "$SESSION" C-d
cp -r /root/.cursor $SHARED/findings