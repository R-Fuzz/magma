#!/bin/bash -e

##
# Pre-requirements:
# - env FUZZER: fuzzer name (from fuzzers/)
# - env TARGET: target name (from targets/)
# + env MAGMA: path to magma root (default: ../../)
# + env ISAN: if set, build the benchmark with ISAN/fatal canaries (default:
#       unset)
# + env HARDEN: if set, build the benchmark with hardened canaries (default:
#       unset)
##

if [ -z $FUZZER ] || [ -z $TARGET ]; then
    echo '$FUZZER and $TARGET must be specified as environment variables.'
    exit 1
fi
IMG_NAME="magma/$FUZZER/$TARGET"
MAGMA=${MAGMA:-"$(cd "$(dirname "${BASH_SOURCE[0]}")/../../" >/dev/null 2>&1 \
    && pwd)"}
source "$MAGMA/tools/captain/common.sh"

CANARY_MODE=${CANARY_MODE:-1}

case $CANARY_MODE in
1)
    mode_flag="--build-arg canaries=1"
    ;;
2)
    mode_flag=""
    ;;
3)
    mode_flag="--build-arg fixes=1"
    ;;
esac

if [ ! -z $ISAN ]; then
    isan_flag="--build-arg isan=1"
fi
if [ ! -z $HARDEN ]; then
    harden_flag="--build-arg harden=1"
fi

GROUP_ID=$(id -g $USER)
USER_ID=$(id -u $USER)
test "$GROUP_ID" = "0" && GROUP_ID=1000
test "$USER_ID" = "0" && USER_ID=1000

if [[ -z "${DOCKERFILE_PATH:-}" ]]; then
    DOCKERFILE_PATH="$MAGMA/docker/Dockerfile"
fi

github_token_flag=""
if [[ ! -z $GITHUB_TOKEN ]]; then
    github_token_flag="--build-arg GITHUB_TOKEN=${GITHUB_TOKEN}"
fi

google_api_flag=""
if [[ ! -z $GOOGLE_API_KEY ]]; then
    google_api_flag="--build-arg GOOGLE_API_KEY=${GOOGLE_API_KEY}"
fi

openai_api_flag=""
if [[ ! -z $OPENAI_API_KEY ]]; then
    openai_api_flag="--build-arg OPENAI_API_KEY=${OPENAI_API_KEY}"
fi

anthropic_api_flag=""
if [[ ! -z $ANTHROPIC_API_KEY ]]; then
    anthropic_api_flag="--build-arg ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}"
fi

# Andrew TODOs:
# You can pass some env var to docker image from here

set -x
if [[ "$FUZZER" == *llm* || "$FUZZER" == *mazerunner ]]; then
    docker build -t "$IMG_NAME" \
        --build-arg fuzzer_name="$FUZZER" \
        --build-arg target_name="$TARGET" \
        --build-arg USER_ID=$USER_ID \
        --build-arg GROUP_ID=$GROUP_ID \
        $github_token_flag $google_api_flag $openai_api_flag $anthropic_api_flag \
        $mode_flag $isan_flag $harden_flag \
        -f "$DOCKERFILE_PATH" "$MAGMA"
else
    docker build -t "$IMG_NAME" \
        --build-arg fuzzer_name="$FUZZER" \
        --build-arg target_name="$TARGET" \
        --build-arg USER_ID=$USER_ID \
        --build-arg GROUP_ID=$GROUP_ID \
        $mode_flag $isan_flag $harden_flag \
        -f "$DOCKERFILE_PATH" "$MAGMA"
fi
set +x

echo "$IMG_NAME"
