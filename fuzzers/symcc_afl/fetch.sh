#!/bin/bash
set -e

##
# Pre-requirements:
# - env FUZZER: path to fuzzer work dir
##

git clone --no-checkout https://github.com/google/AFL.git "$FUZZER/afl"
git -C "$FUZZER/afl" checkout 61037103ae3722c8060ff7082994836a794f978e
cp "$FUZZER/src/afl_driver.cpp" "$FUZZER/afl/afl_driver.cpp"

git clone --no-checkout https://github.com/eurecom-s3/symcc.git "$FUZZER/symcc"
git -C "$FUZZER/symcc" checkout 3f98002a66f18a5c09856c5e66a6c1e48b0ee1a9

git -C "$FUZZER/symcc" submodule init
git -C "$FUZZER/symcc" submodule update

git clone --depth 1 -b release/17.x \
    https://github.com/llvm/llvm-project.git "$FUZZER/llvm"
