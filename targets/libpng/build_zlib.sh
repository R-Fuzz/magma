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

export LIBS="$LIBS $FUZZER/zlib-1.2.13/zlib-build/lib/libz.a"
unset $KO_NO_NATIVE_ZLIB
# build the libpng library
cd "$TARGET/repo"
autoreconf -f -i
./configure \
    --enable-hardware-optimizations=off \
    --disable-shared \
    --enable-static \
    --with-libpng-prefix=MAGMA_ \
    LDFLAGS="$LDFLAGS" CFLAGS="$CFLAGS"

export KO_NO_NATIVE_ZLIB=1
make clean
make libpng16.la

cp .libs/libpng16.a "$OUT/"

# build libpng_read_fuzzer.
$CXX $CXXFLAGS -std=c++14 -I. \
     contrib/oss-fuzz/libpng_read_fuzzer.cc \
     -o $OUT/libpng_read_fuzzer \
     $LDFLAGS .libs/libpng16.a $LIBS $FUZZER_LIB