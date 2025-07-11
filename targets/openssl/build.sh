#!/bin/bash
set -e

##
# Pre-requirements:
# - env TARGET: path to target work dir
# - env OUT: path to directory where artifacts are stored
# - env CC, CXX, FLAGS, LIBS, etc...
##

if [ ! -d "$TARGET/repo" ]; then
    echo "fetch.sh must be executed first."
    exit 1
fi

cd "$TARGET/repo"

CONFIGURE_FLAGS="no-asm"

# the config script supports env var LDLIBS instead of LIBS
export LDLIBS="$LIBS"

ADDTIONAL_FLAGS=""
if [ -f "$FUZZER_LIB" ]; then
    $AR rcs "${FUZZER_LIB}.a" "$FUZZER_LIB"
    ADDTIONAL_FLAGS="--with-fuzzer-lib=$FUZZER_LIB"
fi

./config --debug enable-fuzz-libfuzzer enable-fuzz-afl disable-tests -DPEDANTIC $ADDTIONAL_FLAGS \
    -DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION no-shared no-module \
    enable-tls1_3 enable-rc5 enable-md2 enable-ec_nistp_64_gcc_128 enable-ssl3 \
    enable-ssl3-method enable-nextprotoneg enable-weak-ssl-ciphers \
    -fno-sanitize=alignment $CONFIGURE_FLAGS

make -j$(nproc) clean
make -j$(nproc) LDCMD="$CXX $CXXFLAGS"

fuzzers=$(find fuzz -executable -type f '!' -name \*.py '!' -name \*-test '!' -name \*.pl)
for f in $fuzzers; do
    fuzzer=$(basename $f)
    cp $f "$OUT/"
    if [ -f "${f}.0.0.preopt.bc" ]; then
        cp ${f}.*.bc "$OUT/"
    fi
done
