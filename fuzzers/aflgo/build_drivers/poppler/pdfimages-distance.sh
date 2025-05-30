#!/bin/bash
set -e

##
# Pre-requirements:
# - env TARGET: path to target work dir
# - env OUT: path to directory where artifacts are stored
# - env CC, CXX, FLAGS, LIBS, etc...
##


export TMP_DIR=$OUT/tmp-$1
cp $OUT/tmp-pdf_fuzzer/distance.cfg.txt $TMP_DIR