#!/bin/bash
set -e

##
# Pre-requirements:
# - env FUZZER: path to fuzzer work dir
##

git clone --no-checkout https://github.com/google/AFL.git "$FUZZER/afl"
git -C "$FUZZER/afl" checkout 61037103ae3722c8060ff7082994836a794f978e
#wget -O "$FUZZER/afl/afl_driver.cpp" \
#    "https://cs.chromium.org/codesearch/f/chromium/src/third_party/libFuzzer/src/afl/afl_driver.cpp"
cp "$FUZZER/src/afl_driver.cpp" "$FUZZER/afl/afl_driver.cpp"

git clone -b rl https://github.com/sgzeng/symsan.git "$FUZZER/symsan"

git clone -b mzt https://github.com/ChengyuSong/kernel-analyzer.git "$FUZZER/kernel-analyzer"

# git clone --no-checkout https://github.com/Z3Prover/z3.git "$FUZZER/z3"
# git -C "$FUZZER/z3" checkout z3-4.8.12