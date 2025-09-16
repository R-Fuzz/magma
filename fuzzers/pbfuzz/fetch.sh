#!/bin/bash
set -e

##
# Pre-requirements:
# - env FUZZER: path to fuzzer work dir
##

git clone -b mzt https://github.com/sgzeng/kernel-analyzer.git "$FUZZER/kernel-analyzer"

# generate a GitHub token @https://github.com/settings/personal-access-tokens and set env var GITHUB_TOKEN
git clone -b cursor https://${GITHUB_TOKEN}@github.com/sgzeng/directed_property_based_fuzzer.git "$FUZZER/repo"

curl -fsS https://cursor.com/install -o "$FUZZER/cursor_install.sh" && \
chmod +x "$FUZZER/cursor_install.sh"