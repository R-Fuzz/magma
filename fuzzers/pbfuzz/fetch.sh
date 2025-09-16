#!/bin/bash
set -e

##
# Pre-requirements:
# - env FUZZER: path to fuzzer work dir
##

git clone -b mzt https://github.com/sgzeng/kernel-analyzer.git "$FUZZER/kernel-analyzer"

git clone https://${GITHUB_TOKEN}@github.com/sgzeng/directed_property_based_fuzzer.git "$FUZZER/repo"

curl https://cursor.com/install -fsS | bash