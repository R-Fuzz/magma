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

# cd "$FUZZER"
# wget https://github.com/madler/zlib/archive/refs/tags/v1.2.13.tar.gz
# wget https://ftp.gnu.org/gnu/readline/readline-8.1.2.tar.gz
# wget https://ftp.gnu.org/gnu/termcap/termcap-1.3.1.tar.gz

mv "$FUZZER/src/termcap-1.3.1.tar.gz" "$FUZZER/"
mv "$FUZZER/src/readline-8.1.2.tar.gz" "$FUZZER/"
mv "$FUZZER/src/v1.2.13.tar.gz" "$FUZZER/"