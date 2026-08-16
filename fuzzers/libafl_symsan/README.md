# `libafl_symsan`

Coverage-guided SymSan, via the LibAFL front-end (`symsan-fuzz`).

## How this differs from `aflplusplus_symsan`

`aflplusplus_symsan` is a **directed** setup. Everything distinctive about it —
kernel-analyzer computing per-bug basic-block distances, the
`clang -flto` → `opt -passes=taint` → `llc` pipeline that exists so
`${BC}_distance.bc` can be spliced in between, `-taint-trace-annotated-bb=true`,
and AFL++ driving SymSan as a *custom mutator* — serves that distance metric.

This one is **coverage-guided**, so none of it applies:

| | `aflplusplus_symsan` | `libafl_symsan` |
|---|---|---|
| fuzzer | `afl-fuzz` | `symsan-fuzz` (LibAFL) |
| SymSan enters as | custom mutator (`libSymSanMutator.so`) | a LibAFL **stage** |
| instrumentation | bitcode → `opt` → `llc`, with distances | `ko-clang` directly |
| guidance | bug distances | edge coverage |
| LLVM | 14 | 18 |
| AFL++ | v4.32c | v5.02c, patched |
| builds per target | 2 (`afl`, `symsan`) | 3 (`afl`, `symsan`, `cmplog`) |

A stage rather than a mutator is the substantive difference, not a packaging
one: a mutator never learns what became of the bytes it produced, so the old
driver inferred it by diffing queue filenames afterwards. The stage calls
`evaluate_filtered` itself and feeds the answer back through `report_result`,
which is what escalates an unsolved task to the next rung of the solver ladder
(i2s → jigsaw → z3) and retires a solved one.

## The third build

`--cmplog` runs LibAFL's own colorization + RedQueen pipeline against a
cmplog-instrumented build. It is the baseline the whole exercise is measured
against: cmplog reaches input-to-state by observation where SymSan reaches it by
symbolic execution, and "SymSan found bugs" only means something next to "and
cmplog did not". Both flags live behind one binary, so the four arms differ only
in the stage list — comparing against `afl-fuzz -c` instead would confound the
technique with the scheduler, the mutator and the feedback.

`run.sh` picks the arm up from what `instrument.sh` built:

| arm | how |
|---|---|
| symsan + cmplog | the default |
| symsan only | `USE_CMPLOG=0` at build time |
| cmplog only | `FUZZARGS=--symsan-no-i2s --symsan-no-jigsaw` (traces, solves nothing) |
| havoc floor | `USE_SYMSAN=0 USE_CMPLOG=0` at build time |

The havoc floor is *this* fuzzer with no extra stage, not a different one. That
is deliberate: it holds the scheduler, the mutators, the map and the harness
fixed and varies only the stage, so it answers "does the concolic stage earn its
keep here". It is not a stock AFL++ comparable, and a claim of the form "SymSan
beats AFL++" needs a separate `fuzzers/aflplusplus`, which this checkout does
not have. (`fuzzers/aflplusplus_symsan` is not one either — it hardcodes
`AFL_CUSTOM_MUTATOR_LIBRARY=libSymSanMutator.so`, so it is a symsan arm too.)

Unlike the other two, `USE_SYMSAN=0` also leaves `$OUT/no_symsan` in the image.
`run.sh` needs it: a missing concolic binary is otherwise indistinguishable from
a build that fell over, and quietly measuring the floor for 24 hours under the
name of the symsan arm is the most expensive mistake available here. Without the
marker, `run.sh` refuses to start.

## Usage

fetch.sh clones `github.com/r-fuzz/symsan` fresh on every build (branch `main`
by default; override with `SYMSAN_BRANCH` in `src/instrumentrc`, or via
`tools/magma/campaign.sh --branch` in the symsan repo, which is the easier way
to drive this end to end). Testing an unpushed change means pushing it to a
branch first.

```bash
FUZZER=libafl_symsan TARGET=libpng ./tools/captain/build.sh
./tools/captain/run.sh tools/captain/libafl_symsan.rc
```

`tools/captain/libafl_symsan.rc` is a local campaign config — `run.sh` takes the
rc path as `$1`, so the tracked `captainrc` stays untouched.

### Environment

Build time (`instrument.sh`), set in `src/instrumentrc` — copy
`src/instrumentrc.example` and rebuild. A file rather than an environment
variable because captain forwards a fixed list of `--build-arg`s and anything
else would need a change to the shared `docker/Dockerfile`; `src/` is already
COPYd into the image before `fetch.sh` runs.

- `USE_CMPLOG=0` — skip the cmplog build.
- `USE_BRANCH_MAP=1` — build for the coverage/concolic branch-map join. Forces
  `afl-clang-lto` and `-g` on *both* builds, and writes
  `$OUT/afl/<program>.map`, which `run.sh` then finds by name. Refuses on a
  target that builds more than one program: the LTO pass numbers edges per
  link, so one document-ids file cannot be attributed to any single binary, and
  a mis-attributed map fails *silently* — it reports a perfect mapped ratio
  while telling the stage everything is already covered. Audit a new one with
  `covcheck` and one run under `--validate-branch-map` before believing it.

Run time (`run.sh`):

- `AFL_MAP_SIZE` — overrides the size `instrument.sh` recorded in
  `$OUT/afl/map_size` (65536, or 256000 for php, openssl and poppler). Note
  that captain forwards only `PROGRAM`, `ARGS`, `FUZZARGS`, `POLL`, `TIMEOUT`
  and `BUGID` into the container, so setting this on the host does nothing
  during a campaign — change the table in `instrument.sh` and rebuild.
- `EXEC_TIMEOUT` — per-execution timeout in ms, default 5000.
- `FUZZARGS` — passed through to `symsan-fuzz`.

## Notes

- **One session per process.** SymSan's launcher keeps its configuration in a C
  file-global, so a second `SymSanStage` in the same process is an error rather
  than a corruption. Magma allocates one worker per campaign by default, so this
  is a fit; raising `CAMPAIGN_WORKERS` would need LibAFL's `Launcher`.
- **Native zlib.** `ko-clang` models zlib through `zlib_abilist.txt` against the
  system `-lz` unless `KO_NO_NATIVE_ZLIB` is set, which is why none of the
  reference's instrumented-zlib/readline/termcap building is here.
- **libc++ is not rebuilt.** The taint-instrumented archives are committed to
  the SymSan repo under `libcxx/build_taint/lib/` and `make install` places
  them where `ko-clang++` looks. Rebuilding needs a 2.1 GB LLVM checkout that
  is not in the tarball.
- **`ulimit -c 0`.** `core_pattern` is the host's even inside the container, so
  an apport handler on the host charges about a second to every crash.
