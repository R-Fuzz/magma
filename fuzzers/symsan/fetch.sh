#!/bin/bash
set -e

##
# Pre-requirements:
# - env FUZZER: path to fuzzer work dir
##

git clone --no-checkout https://github.com/google/AFL.git "$FUZZER/afl"
git -C "$FUZZER/afl" checkout 82b5e359463238d790cadbe2dd494d6a4928bff3
cp "$FUZZER/src/afl_driver.cpp" "$FUZZER/afl/afl_driver.cpp"

git clone -b rl https://github.com/sgzeng/symsan.git "$FUZZER/symsan"

# git clone --no-checkout https://github.com/Z3Prover/z3.git "$FUZZER/z3"
# git -C "$FUZZER/z3" checkout z3-4.8.12