#!/bin/bash
set -e

##
# Pre-requirements:
# - env FUZZER: path to fuzzer work dir
##

git clone --branch main --depth 1 https://${GITHUB_TOKEN}@github.com/sgzeng/MazeRunner.git "$FUZZER/symsan"
pushd "$FUZZER/symsan"
git fetch --depth 1 origin rl:refs/remotes/origin/rl --depth 1
popd

git clone --depth 1 -b v4.32c https://github.com/AFLplusplus/AFLplusplus "$FUZZER/aflpp"

git clone --depth 1 -b mzt https://github.com/ChengyuSong/kernel-analyzer.git "$FUZZER/kernel-analyzer"

git clone --no-checkout https://github.com/sgzeng/aflgo.git "$FUZZER/aflgo"
git -C "$FUZZER/aflgo" checkout magma 
cp "$FUZZER/src/afl_driver.cpp" "$FUZZER/aflgo/afl_driver.cpp"
