#!/bin/bash
set -e

##
# Pre-requirements:
# - env FUZZER: path to fuzzer work dir
##

git clone --depth 1 -b v4.32c https://github.com/AFLplusplus/AFLplusplus "$FUZZER/aflpp"

git clone --depth 1 -b mzt https://github.com/ChengyuSong/kernel-analyzer.git "$FUZZER/kernel-analyzer"

git clone --depth 1 -b magma https://github.com/r-fuzz/symsan.git "$FUZZER/symsan"

