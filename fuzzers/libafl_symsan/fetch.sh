#!/bin/bash
set -e

##
# Pre-requirements:
# - env FUZZER: path to fuzzer work dir
##

# --- SymSan -----------------------------------------------------------------
#
# libafl is merged into main and main is pushed (R-Fuzz/symsan), so a plain
# clone is enough -- there is no longer an unpushed branch to work around.
#
# src/instrumentrc is the channel campaign.sh uses to reach into the image at
# build time (see instrument.sh, which sources the same file); reading it here
# too, before it is otherwise used, is what lets `--branch` override
# SYMSAN_BRANCH without a second mechanism.  The Dockerfile COPYs $FUZZER/src
# before running this script, so it is already in place.
if [ -r "$FUZZER/src/instrumentrc" ]; then
    source "$FUZZER/src/instrumentrc"
fi
SYMSAN_BRANCH="${SYMSAN_BRANCH:-main}"

echo "fetch: cloning symsan branch $SYMSAN_BRANCH"
git clone --depth 1 -b "$SYMSAN_BRANCH" \
    https://github.com/r-fuzz/symsan.git "$FUZZER/symsan"

# Fail here rather than three build steps later with a confusing error.
test -f "$FUZZER/symsan/CMakeLists.txt" || {
    echo "fetch: SymSan source is missing or truncated" >&2
    exit 1
}

# --- LibAFL -----------------------------------------------------------------
#
# The path AND the name are load-bearing: bindings/rust/Cargo.toml has a path
# dependency on ../../../libafl/crates/libafl, which from
# $FUZZER/symsan/bindings/rust/ resolves to exactly $FUZZER/libafl.
LIBAFL_COMMIT="2120857eb"
git clone https://github.com/AFLplusplus/LibAFL "$FUZZER/libafl"
git -C "$FUZZER/libafl" checkout "$LIBAFL_COMMIT"

# --- AFL++ ------------------------------------------------------------------
#
# After SymSan, because the patch that makes the coverage/concolic branch-map
# join possible lives in the SymSan tree.  It is applied unconditionally: the
# patched compiler behaves identically unless AFL_LLVM_DOCUMENT_IDS is set, so
# there is no reason to make it depend on whether we use the join today.
#
# v5.02c, not the v4.32c the aflplusplus_symsan fetch.sh pins.  The patch is
# developed against 5.02c and that is the pair the join has actually been
# measured on; it does also apply to 4.32c, but "applies" and "produces a map
# that joins" are different claims and only one of them is tested.
git clone --depth 1 -b v5.02c \
    https://github.com/AFLplusplus/AFLplusplus "$FUZZER/aflpp"
git -C "$FUZZER/aflpp" apply "$FUZZER/symsan/patches/aflpp-document-ids.patch"
