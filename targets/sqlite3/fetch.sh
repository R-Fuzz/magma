#!/bin/bash
set -xe
##
# Pre-requirements:
# - env TARGET: path to target work dir
##

mv $TARGET/src/sqlite.tar.gz "$OUT/sqlite.tar.gz"
mkdir -p "$TARGET/repo"
tar -C "$TARGET/repo" --strip-components=1 -xzf "$OUT/sqlite.tar.gz"