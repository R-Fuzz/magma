#!/bin/bash
set -e

##
# Pre-requirements:
# - env FUZZER: path to fuzzer work dir
##

# We need the version of LLVM which has the LLVMFuzzerRunDriver exposed
cd "$FUZZER/repo/compiler-rt/lib/fuzzer"
./build.sh
mv libFuzzer.a "$OUT/libFuzzer.a"

clang++ $CXXFLAGS -std=c++11 -c "$FUZZER/src/driver.cpp" -fPIC -o "$OUT/driver.o"
