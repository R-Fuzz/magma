#!/bin/bash
set -e

##
# Pre-requirements:
# - env FUZZER: path to fuzzer work dir
##

git clone --no-checkout https://github.com/klee/klee.git "$FUZZER/klee"
git -C "$FUZZER/klee" checkout 27a66461f73dcc3d43bd68d9fb3cb80ca9bfe787

git clone --no-checkout https://github.com/klee/klee-uclibc.git "$FUZZER/uclibc"
git -C "$FUZZER/uclibc" checkout 955d502cc1f0688e82348304b053ad787056c754

git clone --no-checkout https://github.com/stp/stp.git "$FUZZER/stp"
git -C "$FUZZER/stp" checkout 0510509a85b6823278211891cbb274022340fa5c
