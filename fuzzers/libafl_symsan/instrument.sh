#!/bin/bash
set -xe

##
# Pre-requirements:
# - env FUZZER: path to fuzzer work dir
# - env TARGET: path to target work dir
# - env MAGMA: path to Magma support files
# - env OUT: path to directory where artifacts are stored
# - env CFLAGS and CXXFLAGS must be set to link against Magma instrumentation
# + env USE_BRANCH_MAP: build for the coverage/concolic branch-map join
#       (default: unset -- see the note on build_afl below)
# + env USE_CMPLOG: also build the cmplog target (default: 1)
# + env USE_SYMSAN: also build the concolic target (default: 1); 0 gives the
#       havoc floor -- see the dispatch at the bottom
##

export LLVM_VERSION=18
TARGET_NAME="$(basename "$TARGET")"
OUT_ROOT="$OUT"

# Build-time options, for which captain has no channel.  tools/captain/build.sh
# passes a fixed list of --build-args and the Dockerfile turns those into ENV;
# adding one more would mean editing docker/Dockerfile, which every fuzzer here
# shares.  src/ is already this fuzzer's own way into the image -- the
# Dockerfile COPYs it before fetch.sh runs -- so a sourced rc file does the same
# job without touching anything shared.  See src/instrumentrc.example.
if [ -r "$FUZZER/src/instrumentrc" ]; then
    source "$FUZZER/src/instrumentrc"
fi

USE_CMPLOG=${USE_CMPLOG:-1}
USE_SYMSAN=${USE_SYMSAN:-1}

# PROGRAMS, for the branch map below.
source "$TARGET/configrc"

# The branch map exists only to tell the concolic stage which branches the
# fuzzer has already covered, and under USE_BRANCH_MAP the concolic build *is*
# the second half of the two-stage pipeline.  Asking for both is therefore a
# contradiction rather than a combination, and one that would otherwise produce
# a perfectly good .bmap that nothing ever reads.
if [ -n "$USE_BRANCH_MAP" ] && [ "$USE_SYMSAN" = "0" ]; then
    echo "USE_SYMSAN=0 with USE_BRANCH_MAP: the branch map is consumed by the" \
         "concolic stage, which this build does not produce." >&2
    exit 1
fi

# How many edge ids AFL++ is told to leave free at the bottom of the map.  Must
# equal symsan::AFL_ID_BASE (symsan/include/branch_id.h): the SymSan runtime
# emits its undefined_check_ids as bare cids in that range, and the whole point
# of the reservation is that "cid < base" is then a complete test for "not an
# edge".  If the two ever disagree a UB check and a real edge share a number and
# nothing downstream can tell them apart.
AFL_ID_BASE=4096

# Multi-program targets are fine, because the join is per link and so is
# everything the join is made of.  lld's --save-temps=precodegen writes one
# merged module per link output, TaintPass turns each into its own .bmap and
# its own SymSan binary, and each of those pairs with the coverage binary that
# came out of the very same link.  The edge ids therefore agree within a
# program by construction; that two programs both number from
# AFL_LLVM_LTO_STARTID and so reuse each other's ids never matters, because no
# consumer ever holds ids from two programs at once.  build_symsan_lto loops.
#
# What genuinely cannot be attributed is AFL_LLVM_DOCUMENT_IDS: it is one file
# for the whole build and AFL++ appends to it per link, so on a multi-program
# target it is the union of several id spaces.  That file is *only* covcheck's
# ground truth -- the join itself is structural and reads the .bmap -- so the
# restriction now lands exactly where the ambiguity is, instead of on the
# build.  See the naming in build_afl.
if [ -n "$USE_BRANCH_MAP" ] && [ ${#PROGRAMS[@]} -ne 1 ]; then
    echo "USE_BRANCH_MAP: $TARGET_NAME builds ${#PROGRAMS[@]} programs" \
         "(${PROGRAMS[*]}); each gets its own .bmap, but the document-ids" \
         "file will be their union and covcheck cannot use it." >&2
fi

# The coverage map size is a property of the build, so it is decided here and
# recorded in $OUT/afl/map_size for run.sh to read.  It cannot simply be an
# environment variable the way it is for the AFL++ fuzzers: tools/captain
# forwards only PROGRAM, ARGS, FUZZARGS, POLL, TIMEOUT and BUGID into the
# container, so an AFL_MAP_SIZE exported on the host never arrives.
#
# 64K is right for most targets and cheaper than the reference's blanket
# 256000, which every execution must clear and scan.  A too-small map is a loud
# failure rather than a silent one for the fixed-map builds -- afl-cc's runtime
# reports its size in the forkserver handshake and LibAFL refuses to start --
# so the targets that need the wide map are exactly the AFL_LLVM_MAP_DYNAMIC
# ones below, where the coverage would instead fold in on itself unremarked.
# To check a target: AFL_DEBUG=1 afl-showmap -o /dev/null -- $OUT/afl/$PROGRAM.
#
# Under USE_BRANCH_MAP this is only a floor: build_symsan reads the real edge
# count out of the .bmap header afterwards and raises it if need be.  It has to,
# because AFL_ID_BASE shifts every id up by 4096 and a target that used to just
# fit no longer would.
case "$TARGET_NAME" in
    php|openssl|poppler) MAP_SIZE=256000 ;;
    *)                   MAP_SIZE=65536 ;;
esac

# Dependencies this pipeline never compiles.  A library that $TARGET/build.sh
# builds from source goes through the instrumented compiler with everything
# else and needs nothing here; a system -l one does not.  It arrives as a
# native object, so the module holds only its declarations -- and TaintPass
# renames a declaration exactly like a definition, because DFSan's rule is that
# anything not on an ABI list is instrumented.  Every call to it then asks the
# linker for <fn>.taint, which no native library has: the build dies at the
# link with a page of "undefined reference to `jpeg_read_scanlines.taint'".
#
# The ABI list is DFSan's answer, and it is per target rather than per fuzzer
# because the set of uninstrumented libraries is a property of how the target
# was configured.  "uninstrumented" keeps the call at its real name;
# "discard" says the return value carries no label, which is the honest
# summary of a call whose body this build cannot see.  The taint therefore
# stops at the library boundary -- a decoded JPEG scanline is concrete -- which
# is the same trade aflplusplus_symsan makes, and $TARGET_NAME.txt here is a
# copy of its src/poppler.txt so the two fuzzers see the same target.
#
# TARGET_NATIVE_LIBS is the other half, and only build_symsan_lto needs it:
# there the SymSan binary is linked from the merged module by this script,
# not by $TARGET/build.sh, so the -l flags that build.sh puts on its own link
# line have to be repeated.  The per-TU build_symsan links through build.sh
# and already has them.  It also carries plain object files: php's fiber
# switching is hand-written assembly, which never becomes bitcode either, so
# the merged module refers to make_fcontext/jump_fcontext and the .o that
# defines them has to be named the same way a library would be.
TARGET_ABILISTS=()
[ -r "$FUZZER/src/$TARGET_NAME.txt" ] && TARGET_ABILISTS+=("$FUZZER/src/$TARGET_NAME.txt")
case "$TARGET_NAME" in
    poppler) TARGET_NATIVE_LIBS="-lbrotlidec -ljpeg -lz -lopenjp2 -lpng -ltiff
                                 -llcms2 -lm -lpthread -pthread" ;;
    lua)     TARGET_NATIVE_LIBS="-lreadline -ldl -lm" ;;
    php)     TARGET_ABILISTS+=("$FUZZER/src/icu.txt")
             TARGET_NATIVE_LIBS="$TARGET/repo/Zend/asm/make_x86_64_sysv_elf_gas.o
                                 $TARGET/repo/Zend/asm/jump_x86_64_sysv_elf_gas.o
                                 -licuio -licui18n -licuuc -licudata" ;;
    *)       TARGET_NATIVE_LIBS="" ;;
esac
if [ -n "$TARGET_NATIVE_LIBS" ] && [ "${#TARGET_ABILISTS[@]}" -eq 0 ]; then
    echo "$TARGET_NAME links native libraries ($TARGET_NATIVE_LIBS) but has no" \
         "$FUZZER/src/$TARGET_NAME.txt; every call into them will be renamed" \
         ".taint and the concolic link will fail." >&2
    exit 1
fi

# Three builds of the same program, into three subdirectories of $OUT, because
# the LibAFL front-end runs all three as separate processes:
#
#   $OUT/afl/$PROGRAM      coverage feedback, run by the forkserver executor
#   $OUT/symsan/$PROGRAM   concolic tracing, run once per corpus entry
#   $OUT/cmplog/$PROGRAM   the cmplog baseline, run by the tracing stage
#
# Unlike aflplusplus_symsan there is no bitcode stage: that pipeline exists so
# kernel-analyzer's distance annotations can be spliced between clang and the
# taint pass, and nothing here is directed.  ko-clang does the whole job.
#
# ...except under USE_BRANCH_MAP, where there is exactly one compile of the
# program and the two binaries are both derived from it.  See build_symsan_lto.

# Build the AFL++ coverage target.
build_afl() {(
    export AFL_PATH="$FUZZER/aflpp"

    if [ -n "$USE_BRANCH_MAP" ]; then
        # This link does double duty: it produces the coverage binary *and*, via
        # --save-temps=precodegen, the merged AFL++-instrumented module that
        # build_symsan_lto turns into the concolic binary.  Both arms therefore
        # come out of one compile and one merge, so their edge ids agree by
        # construction rather than because two separate compiles happened to
        # produce identical IR.
        #
        # precodegen is the stage after the LTO optimisation pipeline, hence
        # after AFL++'s registerFullLinkTimeOptimizationLastEPCallback -- the
        # counters are in.  Naming the stage matters: a bare --save-temps writes
        # six large bitcode files per link, and every configure probe is a link.
        #
        # -flto and the LLVM binutils are what get the TUs there as bitcode.
        # Plain ar leaves a bitcode archive without an index that lld cannot
        # search, which surfaces much later as undefined symbols at the final
        # link.
        #
        # -u __clang_call_terminate: LTO internalises it when nothing in the
        # merged module refers to it, and the separately-compiled instrumented
        # libc++ then has nothing to bind to.  That is the whole of the 133->129
        # solved-branch delta the post-LTO experiment measured.
        #
        # -stdlib=libc++ because one module cannot have two C++ standard
        # libraries and the SymSan arm's is not negotiable: ko-clang++ links
        # SymSan's taint-instrumented libc++.a, which is where the .taint
        # clones of the STL out-of-line symbols live.  Left at the default,
        # this compile emits libstdc++ references, TaintPass rewrites them to
        # .taint anyway, and the final link fails on the first one the headers
        # did not inline (std::__throw_length_error, out of std::vector).  The
        # AFL++ arm links the system libc++ for the same symbols, which
        # llvm.sh installs -- see preinstall.sh.  ko-clang++ strips any
        # -stdlib= from its own command line and re-adds this one
        # (ko_clang.c:389, :500), so the two arms cannot drift apart.
        export CC="$FUZZER/aflpp/afl-clang-lto"
        export CXX="$FUZZER/aflpp/afl-clang-lto++"
        export AR="llvm-ar-${LLVM_VERSION}"
        export RANLIB="llvm-ranlib-${LLVM_VERSION}"
        export NM="llvm-nm-${LLVM_VERSION}"
        export CFLAGS="$CFLAGS -g -flto"
        export CXXFLAGS="$CXXFLAGS -g -flto -stdlib=libc++"
        export LDFLAGS="$LDFLAGS -fuse-ld=lld -Wl,--save-temps=precodegen"
        export LDFLAGS="$LDFLAGS -Wl,-u,__clang_call_terminate"

        # The C++ standard library is added by the *driver*, and only when the
        # driver is clang++.  php's link lines are $(CC) -- sapi/cli/php is
        # built by the C driver even though --enable-intl compiles ext/intl as
        # C++ -- so configure's own -lstdc++ is all that lands there, and the
        # -stdlib=libc++ above leaves the module referring to libc++ symbols
        # nothing defines (std::__throw_bad_array_new_length, out of new:174,
        # is the first).  Name libc++ on the link line ourselves.  --as-needed
        # is not in play here, but say --no-as-needed anyway: these appear
        # before the objects that need them.
        case "$TARGET_NAME" in
            php) export LDFLAGS="$LDFLAGS -Wl,--push-state,--no-as-needed -lc++ -lc++abi -Wl,--pop-state"
                 export LIBS="$LIBS -lc++ -lc++abi" ;;
        esac

        # Number edges from the reserved base so the runtime's own cids stay
        # below every real edge id.
        export AFL_LLVM_LTO_STARTID="$AFL_ID_BASE"

        # Ground truth for covcheck, not an input to the join any more -- the
        # join is now structural, and TaintPass writes the .bmap the backend
        # actually reads.  Deliberately *not* named <executable>.map: run.sh
        # auto-detects that name and would feed a source-hash map to a binary
        # whose cids are edge ids, which resolves to nothing and looks like a
        # target with no mappable branches.  AFL++ appends, so a stale file
        # would claim ids this binary never assigned -- hence the rm.
        rm -f "$OUT/afl/"*.map "$OUT/afl/"*.docids "$OUT/afl/"*.precodegen.bc
        # One file for the whole build, because the variable is read at link
        # time and $TARGET/build.sh links every program in one invocation.  On
        # a single-program target that is the program's own listing and
        # covcheck can use it; on a multi-program one it is a union of id
        # spaces that describes none of them, so it is named after the target
        # rather than after a program.  Naming it <program>.docids there would
        # be the silent version of the same ambiguity -- covcheck would read it
        # as ground truth for one binary and report on another's ids.
        if [ ${#PROGRAMS[@]} -eq 1 ]; then
            export AFL_LLVM_DOCUMENT_IDS="$OUT/afl/${PROGRAMS[0]}.docids"
        else
            export AFL_LLVM_DOCUMENT_IDS="$OUT/afl/$TARGET_NAME.all.docids"
        fi
    else
        export CC="$FUZZER/aflpp/afl-clang-fast"
        export CXX="$FUZZER/aflpp/afl-clang-fast++"
    fi

    # Some targets cannot directly link the libFuzzer driver.
    DYNAMIC_TARGETS=(poppler)
    if [[ ! " ${DYNAMIC_TARGETS[*]} " =~ " $TARGET_NAME " ]]; then
        export LIBS="$LIBS $FUZZER/aflpp/utils/aflpp_driver/libAFLDriver.a"
    fi
    export FUZZER_LIB="$FUZZER/aflpp/utils/aflpp_driver/libAFLDriver.a"

    # Some targets do not support a static AFL memory region.
    DYNAMIC_TARGETS=(php openssl)
    if [[ " ${DYNAMIC_TARGETS[*]} " =~ " $TARGET_NAME " ]]; then
        export AFL_LLVM_MAP_DYNAMIC=1
    fi

    export OUT="$OUT/afl"
    export LDFLAGS="$LDFLAGS -L$OUT"

    export AFL_LLVM_DICT2FILE="$OUT/afl++.dict"
    export AFL_LLVM_DICT2FILE_NO_MAIN=1

    "$MAGMA/build.sh"
    "$TARGET/build.sh"

    # lld writes the save-temps bitcode next to the *link output*, which is
    # $OUT only for the targets whose build.sh links straight into it (libpng
    # does; libsndfile links in its own tree and copies the binary afterwards).
    # So go and find it rather than requiring every targets/*/build.sh to know
    # about this pipeline.  Searched by the program's exact name because every
    # autoconf link probe leaves a conftest.0.5.precodegen.bc of its own.
    #
    # The link output is not always named after the program, though: php links
    # sapi/fuzzer/php-fuzz-json and $TARGET/build.sh copies it out as `json`,
    # so the bitcode lld left behind is php-fuzz-json.0.5.precodegen.bc.  Hence
    # the suffix retry -- still anchored at the end, so conftest is still out,
    # and still only reached when the exact name found nothing.
    if [ -n "$USE_BRANCH_MAP" ]; then
        local prog bc found
        for prog in "${PROGRAMS[@]}"; do
            bc="$prog.0.5.precodegen.bc"
            if [ ! -r "$OUT/$bc" ]; then
                found="$(find "$TARGET" -name "$bc" -print -quit 2>/dev/null)"
                [ -n "$found" ] ||
                    found="$(find "$TARGET" -name "*-$bc" -print -quit 2>/dev/null)"
                if [ -n "$found" ]; then
                    cp -v "$found" "$OUT/$bc"
                else
                    echo "USE_BRANCH_MAP: no $bc anywhere under $TARGET after" \
                         "the build; the link that produced $prog did not go" \
                         "through lld with --save-temps=precodegen." >&2
                    # What *did* it write?  Without this the next thing anyone
                    # sees is build_symsan_lto exiting on the same missing
                    # file, which cannot tell "linked some other way" from
                    # "linked under some other name".
                    find "$TARGET" -name "*.precodegen.bc" \
                         ! -name "conftest.*" -printf "  %p\n" 2>/dev/null |
                        head -20 >&2
                fi
            fi
        done
    fi

    echo "$MAP_SIZE" > "$OUT/map_size"
)}

# Build the SymSan concolic target, per translation unit.
build_symsan() {(
    export KO_CC="clang-${LLVM_VERSION}"
    export KO_CXX="clang++-${LLVM_VERSION}"
    export CC="$FUZZER/symsan/build/bin/ko-clang"
    export CXX="$FUZZER/symsan/build/bin/ko-clang++"
    export KO_DONT_OPTIMIZE=1
    export KO_USE_FASTGEN=1

    # KO_NO_NATIVE_ZLIB is deliberately NOT set: ko-clang defaults to modelling
    # zlib through zlib_abilist.txt against the system -lz, which is what lets
    # us skip the reference's whole instrumented-zlib apparatus.  Set it, and
    # every zlib-using target needs a ko-clang-built libz.a linked in.
    unset KO_NO_NATIVE_ZLIB

    # The target's own ABI list, if it has one.  ko-clang has no environment
    # variable for an extra abilist -- add_taint_pass() picks the list from
    # KO_ flags and hardcodes the rest -- but it forwards -mllvm through to
    # clang untouched, and -taint-abilist is a cl::list, so one passed here
    # simply appends to the ones add_taint_pass() already supplied.  Compare
    # build_symsan_lto, which calls opt itself and can just add the flag.
    #
    # No $TARGET_NATIVE_LIBS: this path links through $TARGET/build.sh, whose
    # own link lines already name the libraries.
    local abilist
    for abilist in "${TARGET_ABILISTS[@]}"; do
        export CFLAGS="$CFLAGS -mllvm -taint-abilist=$abilist"
        export CXXFLAGS="$CXXFLAGS -mllvm -taint-abilist=$abilist"
    done

    export OUT="$OUT/symsan"
    mkdir -p "$OUT"
    export LDFLAGS="$LDFLAGS -L$OUT"

    # The targets are libFuzzer harnesses; harness-proxy supplies the main()
    # that reads argv[1] and calls LLVMFuzzerTestOneInput.  Putting it in LIBS
    # is what keeps every targets/*/build.sh unmodified.
    #
    # An archive, not the bare object.  Every autoconf target links a conftest.c
    # with its own main() before it builds anything, and a bare .o in LIBS joins
    # that link unconditionally -- "multiple definition of `main'", which
    # configure reports as "C compiler cannot create executables".  An archive
    # member is pulled in only to resolve an undefined symbol, so it stays out
    # of the probes and lands in exactly the links that need a main.
    export FUZZER_LIB="$OUT/harness-proxy.a"
    $CC $CFLAGS -c -fPIC -o "$OUT/harness-proxy.o" \
        "$FUZZER/symsan/driver/harness-proxy.c"
    rm -f "$FUZZER_LIB"
    "${AR:-ar}" rcs "$FUZZER_LIB" "$OUT/harness-proxy.o"

    # glibc-isoc23-compat.o (src/glibc-isoc23-compat.c): a bare object, not an
    # archive member.  ko-clang++ appends its own -lc++ after everything on
    # this command line, and it is libc++.a's locale.cpp.o -- pulled in by
    # whatever in the target references iostream -- that needs these symbols.
    # An archive member is only extracted to satisfy an undefined reference
    # that already exists *when the linker reaches that archive*; this link
    # uses BFD ld (not lld), which never revisits an archive once it has moved
    # past it, so bundling this with harness-proxy.a resolved nothing -- by
    # the time libc++.a shows up later on the command line asking for
    # __isoc23_strtoull_l, ld is not looking at harness-proxy.a any more.  A
    # plain object's symbols go into the link unconditionally regardless of
    # position, which sidesteps the ordering problem instead of fighting it.
    $CC $CFLAGS -c -fPIC -o "$OUT/glibc-isoc23-compat.o" \
        "$FUZZER/src/glibc-isoc23-compat.c"

    DYNAMIC_TARGETS=(poppler)
    if [[ ! " ${DYNAMIC_TARGETS[*]} " =~ " $TARGET_NAME " ]]; then
        export LIBS="$LIBS $FUZZER_LIB"
    fi
    export LIBS="$LIBS $OUT/glibc-isoc23-compat.o"

    "$MAGMA/build.sh"
    "$TARGET/build.sh"
)}

# Build the SymSan concolic target from the module build_afl already merged.
#
# The target is not built again here.  build_afl's link left the merged,
# AFL++-instrumented module next to its output, and the three commands below
# turn that one module into the concolic binary: taint-instrument it, lower it,
# link it.  That is the entire reason the edge id can serve as SymSan's branch
# id -- the ids are not matched afterwards, they are the same ids.
#
# The flags spelled out here duplicate ko_clang.c's add_taint_pass(), which is
# what a per-TU ko-clang would have passed.  There are now two lists; whoever
# writes the bin/ko-lto driver that collapses them should start here.
build_symsan_lto() {(
    local L="$FUZZER/symsan/build/lib/symsan"
    local out="$OUT_ROOT/symsan"
    local prog bc

    for prog in "${PROGRAMS[@]}"; do
        bc="$OUT_ROOT/afl/$prog.0.5.precodegen.bc"
        if [ ! -r "$bc" ]; then
            echo "USE_BRANCH_MAP: $bc not found.  build_afl's link should have" \
                 "written it via -Wl,--save-temps=precodegen; if the target" \
                 "links its programs some other way, this pipeline cannot see" \
                 "the merged module." >&2
            exit 1
        fi
    done

    mkdir -p "$out"

    export KO_CC="clang-${LLVM_VERSION}"
    export KO_CXX="clang++-${LLVM_VERSION}"
    export KO_USE_FASTGEN=1
    unset KO_NO_NATIVE_ZLIB

    # Instrument.  -taint-with-afl=1 rather than letting it auto-detect: if the
    # module ever arrives without AFL++'s counters -- a changed link line, a
    # different lld -- auto-detection would quietly fall back to source hashes
    # and ship a binary whose cids cannot be looked up in any coverage map.
    # Failing the build is the only version of that anyone notices.
    #
    # The abilists are the ones add_taint_pass() selects under this
    # environment: dfsan always, zlib because KO_NO_NATIVE_ZLIB is unset.  Not
    # libc++_abilist.txt, which is conditioned on KO_USE_NATIVE_LIBCXX.  Plus
    # the target's own, when it has one -- see TARGET_ABILISTS above.
    #
    # -taint-solve-ub emits the __taint_solve_bounds / __taint_solve_size calls
    # that symsan-fuzz's --symsan-solve-ub then switches on.  Without it that
    # flag would half work on this pipeline: the arithmetic checks -- divide by
    # zero, shift past the width, signed overflow -- are raised inside
    # __taint_union and need no instrumentation, but the out-of-bounds index and
    # libc size ones need these calls to exist.  Emitting them unconditionally
    # costs a call that returns on its first predicate when the runtime flag is
    # off, and only at a GEP whose index shadow is not statically zero, right
    # next to the trace call already emitted there.  That is cheaper than a
    # build-time switch nobody remembers to set.
    #
    # The opt invocation these flags belong to is in the per-program loop
    # below, after harness-proxy.

    # harness-proxy is the same object for every program, so it is compiled
    # once here and each program's link pulls the same archive.
    #
    # It still has to be compiled by ko-clang, not by plain clang: it is the
    # code that read()s the input, and the taint source is the compile-time
    # rewrite of that read() into __dfsw_read.  Uninstrumented, it would read
    # the file and taint nothing.  Its own branches therefore get source-hash
    # cids in a binary where everything else has edge ids -- an instance of the
    # id-space overlap noted on Taint::getBranchId(), harmless here only
    # because nothing in it is worth solving.
    local FUZZER_LIB="$out/harness-proxy.a"
    "$FUZZER/symsan/build/bin/ko-clang" $CFLAGS -c -fPIC \
        -o "$out/harness-proxy.o" "$FUZZER/symsan/driver/harness-proxy.c"
    rm -f "$FUZZER_LIB"
    "llvm-ar-${LLVM_VERSION}" rcs "$FUZZER_LIB" "$out/harness-proxy.o"

    # glibc-isoc23-compat.o (src/glibc-isoc23-compat.c): compiled once like
    # harness-proxy, but added to each program's link as a bare object rather
    # than into the same archive -- see the matching comment in build_symsan
    # for why an archive member here resolves nothing (BFD ld, not lld, never
    # revisits an archive it has already scanned past, and ko-clang++ appends
    # -lc++ after everything passed to it below).
    "$FUZZER/symsan/build/bin/ko-clang" $CFLAGS -c -fPIC \
        -o "$out/glibc-isoc23-compat.o" "$FUZZER/src/glibc-isoc23-compat.c"

    # Once per program.  lld writes one merged module per link, so each program
    # has its own precodegen .bc, its own edge id space and its own .bmap, and
    # nothing ever joins two of them: run.sh hands the backend the .bmap next
    # to the binary it is about to run.
    local abilists=(-taint-abilist="$L/dfsan_abilist.txt"
                    -taint-abilist="$L/zlib_abilist.txt")
    local abilist
    for abilist in "${TARGET_ABILISTS[@]}"; do
        abilists+=(-taint-abilist="$abilist")
    done

    local edges
    for prog in "${PROGRAMS[@]}"; do
        bc="$OUT_ROOT/afl/$prog.0.5.precodegen.bc"

        "opt-${LLVM_VERSION}" \
            -load-pass-plugin="$L/TaintPass.so" -passes=taint \
            "${abilists[@]}" \
            -taint-with-afl=1 \
            -taint-solve-ub=true \
            -taint-branch-map="$out/$prog.bmap" \
            "$bc" -o "$out/$prog.taint.bc"

        # Lower.  PIC because the runtime and the instrumented libc++ are.
        "llc-${LLVM_VERSION}" -relocation-model=pic -filetype=obj \
            "$out/$prog.taint.bc" -o "$out/$prog.taint.o"

        # Link with the real driver, so add_runtime()'s archive selection,
        # --dynamic-list and taint.ld handling are reused rather than
        # reproduced.  ko-clang skips instrumentation when there is nothing to
        # compile, so handing it a finished object needs no extra flag.
        #
        # Plain BFD ld, not -fuse-ld=lld: tried lld here to chase a "DWARF
        # error: invalid or unhandled FORM value: 0x23" warning that BFD emits
        # right before misreporting libc++.a's own .taint-cloned throw-helper
        # symbols as undefined.  lld resolves them, but places them ~112 TB
        # from the caller and fails with "relocation R_X86_64_PLT32 out of
        # range" instead -- taint.ld links this binary non-PIE at a fixed
        # 0x700000200000 for DFSan's shadow scheme (see launch.c's
        # child_disable_aslr, the runtime-side half of that same fixed-address
        # design), and lld does not place archive-extracted sections the same
        # way BFD does under this script. Two different failures from two
        # linkers on the same root cause -- an open problem, not something
        # -fuse-ld= papers over.
        #
        # $TARGET_NATIVE_LIBS last, after the object that references them:
        # BFD resolves an archive or shared library against the undefined
        # symbols it has accumulated so far and does not go back.
        "$FUZZER/symsan/build/bin/ko-clang++" \
            "$out/$prog.taint.o" "$out/glibc-isoc23-compat.o" "$FUZZER_LIB" \
            $TARGET_NATIVE_LIBS \
            -o "$out/$prog"

        # The map has to hold every id this build assigned, and only the build
        # knows how many that is.  TaintPass copies AFL++'s __afl_final_loc
        # into the .bmap header for exactly this.  Raising the floor rather
        # than replacing it keeps the AFL_LLVM_MAP_DYNAMIC targets' wider map.
        # There is one $OUT/afl/map_size for the target, so on a multi-program
        # one the widest program sets it: oversizing a narrower program's map
        # costs a clear and a scan, undersizing it would silently fold that
        # program's coverage in on itself.
        edges="$(sed -n '1s/.*edges=\([0-9]\+\).*/\1/p' "$out/$prog.bmap")"
        if [ -z "$edges" ]; then
            echo "USE_BRANCH_MAP: no edges= in $out/$prog.bmap header" >&2
            exit 1
        fi
        if [ "$edges" -gt "$MAP_SIZE" ]; then
            MAP_SIZE="$edges"
        fi
    done

    echo "$MAP_SIZE" > "$OUT_ROOT/afl/map_size"
)}

# Build the cmplog baseline target.
build_cmplog() {(
    export AFL_PATH="$FUZZER/aflpp"
    export CC="$FUZZER/aflpp/afl-clang-fast"
    export CXX="$FUZZER/aflpp/afl-clang-fast++"
    export AFL_LLVM_CMPLOG=1

    DYNAMIC_TARGETS=(poppler)
    if [[ ! " ${DYNAMIC_TARGETS[*]} " =~ " $TARGET_NAME " ]]; then
        export LIBS="$LIBS $FUZZER/aflpp/utils/aflpp_driver/libAFLDriver.a"
    fi
    export FUZZER_LIB="$FUZZER/aflpp/utils/aflpp_driver/libAFLDriver.a"

    DYNAMIC_TARGETS=(php openssl)
    if [[ " ${DYNAMIC_TARGETS[*]} " =~ " $TARGET_NAME " ]]; then
        export AFL_LLVM_MAP_DYNAMIC=1
    fi

    export OUT="$OUT/cmplog"
    export LDFLAGS="$LDFLAGS -L$OUT"

    "$MAGMA/build.sh"
    "$TARGET/build.sh"

    # This arm is a per-TU AFL build, so it counts ids a different way than the
    # LTO one and there is no reason for the two totals to agree: php's merged
    # module ends at 256792 edges and the same code compiled per TU at 275710.
    # The fuzzer allocates one map for all of its stages, so the map has to be
    # the widest of them -- a stage whose target wants more than was allocated
    # does not degrade, symsan-fuzz stops with IllegalState before it fuzzes.
    #
    # Ask the binary rather than guess.  afl-compiler-rt prints the count from
    # __sanitizer_cov_trace_pc_guard_init, a constructor, so it comes out
    # before main and needs neither input nor the arguments the program
    # expects.  Rounded up to 64 because that is what the runtime reports and
    # what the fuzzer then compares against.
    local prog loc size
    size="$(cat "$OUT_ROOT/afl/map_size" 2>/dev/null || echo 0)"
    for prog in "${PROGRAMS[@]}"; do
        loc="$(AFL_DEBUG=1 AFL_NO_FORKSRV=1 timeout 60 "$OUT/$prog" </dev/null 2>&1 >/dev/null |
               sed -n 's/.*__afl_final_loc = \([0-9]\+\).*/\1/p' | tail -1)"
        if [ -z "$loc" ]; then
            echo "cmplog: no __afl_final_loc from $OUT/$prog; the map stays at" \
                 "$size and this arm stops if it turns out to want more." >&2
            continue
        fi
        loc=$(( (loc + 63) / 64 * 64 ))
        [ "$loc" -gt "$size" ] && size="$loc"
    done
    echo "$size" > "$OUT_ROOT/afl/map_size"
)}

build_afl
if [ "$USE_SYMSAN" != "0" ]; then
    if [ -n "$USE_BRANCH_MAP" ]; then
        build_symsan_lto
    else
        build_symsan
    fi
else
    # The havoc floor: coverage build only, so symsan-fuzz runs LibAFL's own
    # scheduler and mutators and nothing else.  Note what this is and is not a
    # baseline for -- it holds the fuzzer, the map and the harness fixed and
    # varies only the stage, so it answers "does the concolic stage earn its
    # keep here".  It is not stock AFL++, and a claim of the form "SymSan beats
    # AFL++" needs that separate fuzzer, not this.
    #
    # The marker is what makes the absence legible to run.sh, which otherwise
    # cannot tell a deliberately-dropped arm from a build that fell over.
    mkdir -p "$OUT_ROOT"
    touch "$OUT_ROOT/no_symsan"
fi
if [ "$USE_CMPLOG" != "0" ]; then
    build_cmplog
fi
