#!/bin/bash
set -e

##
# Pre-requirements:
# - env FUZZER: path to fuzzer work dir
##

git clone \
  --depth 1 \
  --branch v4.32c \
  https://github.com/AFLplusplus/AFLplusplus \
  "$FUZZER/repo"
