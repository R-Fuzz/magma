#!/bin/bash
set -e
set -x

##
# Pre-requirements:
# - env TARGET: path to target work dir
##

# Stop immediately on any patch failure
find "$TARGET/patches/setup" "$TARGET/patches/bugs" -name "*.patch" | while read patch; do
    echo "Applying $patch"
    name=${patch##*/}
    name=${name%.patch}
    sed "s/%MAGMA_BUG%/$name/g" "$patch" | patch -p1 -d "$TARGET/repo" || {
        echo "❌ Failed to apply patch: $patch"
        exit 1
    }
done
