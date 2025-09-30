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

WORK="$TARGET/work"
rm -rf "$WORK"
mkdir -p "$WORK"
mkdir -p "$WORK/lib" "$WORK/include"

cd "$TARGET/repo"
(set +e ; ./autogen.sh) || \
echo "autogen.sh failed to grab config.guess and config.sub from upstream master, continuing anyway"
./configure --disable-shared --prefix="$WORK" \
    --disable-lzma --disable-jpeg --disable-zstd
make -j$(nproc) clean
make -j$(nproc)
make install

cp "$WORK/bin/tiffcp" "$OUT/"
if [ -f "$TARGET/repo/tools/tiffcp.0.0.preopt.bc" ]; then
    cp $TARGET/repo/tools/tiffcp.*.bc "$OUT/"
fi

$CXX $CXXFLAGS -std=c++11 -I$WORK/include \
    contrib/oss-fuzz/tiff_read_rgba_fuzzer.cc \
    -c -o $OUT/tiff_read_rgba_fuzzer.o

$CXX $CXXFLAGS -std=c++11 -I$WORK/include \
    $OUT/tiff_read_rgba_fuzzer.o -o $OUT/tiff_read_rgba_fuzzer \
    $WORK/lib/libtiffxx.a $WORK/lib/libtiff.a \
    -lz -Wl,-Bstatic -Wl,-Bdynamic \
    $LDFLAGS $LIBS
