#!/bin/bash
set -e

##
# Pre-requirements:
# - env FUZZER: path to fuzzer work dir
##


git clone --depth 1 -b v4.32c https://github.com/AFLplusplus/AFLplusplus "$FUZZER/aflpp"

git clone --depth 1 -b mzt https://github.com/ChengyuSong/kernel-analyzer.git "$FUZZER/kernel-analyzer"

git clone --depth 1 -b rl https://github.com/sgzeng/MazeRunner.git "$FUZZER/symsan"

git clone --no-checkout https://github.com/sgzeng/aflgo.git "$FUZZER/aflgo"
git -C "$FUZZER/aflgo" checkout magma 
cp "$FUZZER/src/afl_driver.cpp" "$FUZZER/aflgo/afl_driver.cpp"