#!/bin/bash
set -e

##
# Pre-requirements:
# - env FUZZER: path to fuzzer work dir
##

git clone https://${GITHUB_TOKEN}@github.com/sgzeng/MazeRunner.git "$FUZZER/symsan"

git clone --depth 1 -b v4.32c https://github.com/AFLplusplus/AFLplusplus "$FUZZER/aflpp"

git clone --depth 1 -b mzt https://github.com/sgzeng/kernel-analyzer.git "$FUZZER/kernel-analyzer"

git clone --depth 1 -b magma https://github.com/sgzeng/aflgo.git "$FUZZER/aflgo"
cp "$FUZZER/src/afl_driver.cpp" "$FUZZER/aflgo/afl_driver.cpp"

cd "$FUZZER"
wget https://github.com/madler/zlib/archive/refs/tags/v1.2.13.tar.gz
wget https://ftp.gnu.org/gnu/readline/readline-8.1.2.tar.gz
wget https://ftp.gnu.org/gnu/termcap/termcap-1.3.1.tar.gz