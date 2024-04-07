#!/bin/bash
set -e

##
# Pre-requirements:
# - env FUZZER: path to fuzzer work dir
##

git clone --no-checkout https://github.com/elManto/DDFuzz "$FUZZER/repo"
git -C "$FUZZER/repo" checkout 319f702e9a2317970d829e458ec6d035f0aeb134
