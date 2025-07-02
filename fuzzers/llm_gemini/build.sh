#!/bin/bash
set -e

##
# Pre-requirements:
# - env FUZZER: path to fuzzer work dir
##

cd "$FUZZER/symsan"

git fetch && git reset --hard origin/main
