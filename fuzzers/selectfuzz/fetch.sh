#!/bin/bash
set -e

##
# Pre-requirements:
# - env FUZZER: path to fuzzer work dir
##

git clone --no-checkout https://github.com/sgzeng/SelectFuzz.git "$FUZZER/repo"
git -C "$FUZZER/repo" checkout aa5311039cff17595ad92cb1110eb409e4963c5a

cp "$FUZZER/src/afl_driver.cpp" "$FUZZER/repo/afl_driver.cpp"
