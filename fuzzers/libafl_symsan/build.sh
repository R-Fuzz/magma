#!/bin/bash
set -e

##
# Pre-requirements:
# - env FUZZER: path to fuzzer work dir
# - env OUT: path to directory where artifacts are stored
##

for d in aflpp symsan libafl; do
    test -d "$FUZZER/$d" || { echo "fetch.sh must be executed first ($d missing)."; exit 1; }
done

# Unconditional, not ${LLVM_VERSION:-18}: the base image exports LLVM_VERSION=14
# for the older fuzzers, so a default-if-unset would silently give us 14 and a
# ko-clang that cannot agree with the coverage build on anything.
export LLVM_VERSION=18
export CC="clang-${LLVM_VERSION}"
export CXX="clang++-${LLVM_VERSION}"
export LLVM_CONFIG="llvm-config-${LLVM_VERSION}"

export RUSTUP_HOME=/opt/rust
# ...but not CARGO_HOME: /opt/rust is read-only to the `magma` user and cargo
# needs to write the registry cache.
export CARGO_HOME="$FUZZER/.cargo"

# --- AFL++ ------------------------------------------------------------------
(
    cd "$FUZZER/aflpp"
    export AFL_NO_X86=1
    export PYTHON_INCLUDE=/
    make NO_NYX=1 source-only -j"$(nproc)"
    make -C utils/aflpp_driver
    # The LTO pass carrying the document-ids patch.  Built whether or not
    # USE_BRANCH_MAP is on, so that turning the join on is an instrument.sh
    # decision and not a rebuild-the-fuzzer one.
    make -f GNUmakefile.llvm ./SanitizerCoverageLTO.so
)

# --- SymSan -----------------------------------------------------------------
(
    cd "$FUZZER/symsan"
    mkdir -p build && cd build
    # LLVM_DIR explicitly: apt.llvm.org installs under /usr/lib/llvm-18 rather
    # than a prefix find_package(LLVM CONFIG) searches by default.
    #
    # Release explicitly, and not because of build time: the default empty
    # build type compiles the taint runtime and the solvers unoptimized, which
    # would leave every exec/s number below a measurement of -O0.
    cmake -DAFLPP_PATH="$FUZZER/aflpp" \
          -DCMAKE_INSTALL_PREFIX=. \
          -DCMAKE_BUILD_TYPE=Release \
          -DCMAKE_C_COMPILER="$CC" \
          -DCMAKE_CXX_COMPILER="$CXX" \
          -DLLVM_DIR="/usr/lib/llvm-${LLVM_VERSION}/cmake" \
          ../
    make -j"$(nproc)"
    export KO_CC="clang-${LLVM_VERSION}"
    export KO_CXX="clang++-${LLVM_VERSION}"
    make install

    # Rebuild libc++/libc++abi/libunwind here, in the container, instead of
    # trusting the libc++.a/libc++abi.a/libunwind.a committed to the SymSan
    # repo (libcxx/build_taint/lib/).  Those are built wherever someone last
    # ran libcxx/rebuild.sh -- this dev host, currently -- and if that host's
    # glibc is newer than the image's (glibc >= 2.38 vs this image's 2.35),
    # locale.cpp.o unconditionally calls the renamed __isoc23_* symbol names,
    # which do not exist in an older glibc at all: any C++ target whose code
    # happens to reach iostream formatted extraction (e.g. libtiff's
    # std::istringstream) fails to link with "undefined reference to
    # `__isoc23_strtoull_l'". Rebuilding with *this* container's clang-18
    # against *this* glibc, using the ko-clang that was just installed above,
    # is what aflplusplus_symsan's build.sh already does for its own (LLVM 14)
    # toolchain -- same idea, same script (libcxx/rebuild.sh), just pointed at
    # this fuzzer's ko-clang instead.
    #
    # This was skipped here originally because it needs the 2.1 GB
    # llvm_project-18 checkout, which is gitignored and so isn't in the
    # fetched source -- rebuild.sh clones it itself (llvmorg-<version>,
    # matching ko-clang's own clang) when the directory isn't already there.
    # That clone, plus the ninja build, is the cost of doing this on every
    # image instead of once on a dev host -- there is no cache across targets
    # for it the way there is for docker layers, because each target's image
    # is its own `docker build` from scratch.
    (
        cd ../libcxx
        ./rebuild.sh ../build/bin/ko-clang
    )
    # Re-install: the first `make install` above copied the committed
    # (possibly glibc-mismatched) archives; this picks up what rebuild.sh just
    # produced instead.  install(FILES ...) in libcxx/CMakeLists.txt has no
    # build dependency on rebuild.sh, so nothing else re-triggers this copy.
    make install
)

# --- symsan-fuzz ------------------------------------------------------------
#
# `build` is one of the four prefixes bindings/rust/*/build.rs probes for an
# install (b4, b3, b2, build), so nothing has to be pointed at it.
(
    cd "$FUZZER/symsan/bindings/rust"
    cargo build --release
)
test -x "$FUZZER/symsan/bindings/rust/target/release/symsan-fuzz"

mkdir -p "$OUT/afl" "$OUT/symsan" "$OUT/cmplog"
