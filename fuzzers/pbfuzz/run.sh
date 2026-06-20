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

# Derive the cursor-agent session timeout from Magma's campaign $TIMEOUT so the
# launcher self-terminates cursor-agent cleanly before Magma's outer
# `timeout $TIMEOUT` (in magma/run.sh) hard-kills this script.
to_seconds() {                      # arg: duration with optional s/m/h/d suffix
    local t="$1" n unit
    n="${t%[smhd]}"
    unit="${t#$n}"
    case "$unit" in
        s|"") echo "$n" ;;
        m)    echo "$((n * 60))" ;;
        h)    echo "$((n * 3600))" ;;
        d)    echo "$((n * 86400))" ;;
        *)    echo "$n" ;;
    esac
}

AGENT_TIMEOUT=3600
if [ -n "$TIMEOUT" ]; then
    TIMEOUT_S="$(to_seconds "$TIMEOUT")"
    if [ "$TIMEOUT_S" -gt 60 ]; then
        AGENT_TIMEOUT=$((TIMEOUT_S - 30))
    else
        AGENT_TIMEOUT="$TIMEOUT_S"
    fi
fi

TARGET_NAME="$(basename "$TARGET")"

# launcher.py generates the prompt + .cursor/mcp.json and drives cursor-agent
# non-interactively (cursor-agent --force -p). MCP/trust auto-approval is handled
# by the prebuilt ~/.cursor/cli-config.json permission allowlist. cursor auth is
# installed by launcher.py from the CURSOR_AUTH env var.
python3 "${FUZZER}/repo/launcher.py" \
    -s "${OUT}/BBtargets/${BUGID}" \
    -m "${LLM_MODEL}" \
    -c "$TARGET/repo" \
    -i "$TARGET/corpus/${PROGRAM}" \
    -o "$SHARED/findings" \
    -agent-timeout-sec "$AGENT_TIMEOUT" \
    -reached-pattern "Bug ${BUGID} reached" \
    -triggered-pattern "Bug ${BUGID} triggered" \
    -- "$OUT/clang_bc/$TARGET_NAME/$PROGRAM" $ARGS

# Persist the generated workflow/MCP artifacts for post-mortem inspection.
mkdir -p "$SHARED/findings/.cursor"
cp "$TARGET/repo/.cursor/mcp.json" "$SHARED/findings/.cursor" 2>/dev/null || true
cp "$TARGET/repo/.cursor/project_config.md" "$SHARED/findings/.cursor" 2>/dev/null || true
cp "$TARGET/repo/.cursor/workflow_state.md" "$SHARED/findings/.cursor" 2>/dev/null || true

# If a PoC was found, replay it so Magma's monitor records the triggered bug.
CRASH_DIR="$SHARED/findings/crashes"
if [ -d "$CRASH_DIR" ] && [ -n "$(ls -A "$CRASH_DIR" 2>/dev/null)" ]; then
    for f in "$CRASH_DIR"/*; do
        RUNARGS="${ARGS//@@/$f}"
        if [ "$RUNARGS" = "$ARGS" ]; then
            RUNARGS="$f"
        fi
        "$OUT/clang_bc/$TARGET_NAME/$PROGRAM" $RUNARGS || true
    done
    sleep 5
fi