# Magma: A Ground-Truth Fuzzing Benchmark

This is a fork of the [Magma benchmark](https://hexhive.epfl.ch/magma) (originally from [HexHive/magma](https://github.com/HexHive/magma)), extended to support PBFuzz — an agentic directed fuzzer. The fork adds the `fuzzers/pbfuzz/` and `fuzzers/cursor_pbfuzz_tools/` fuzzer integrations on top of the standard Magma infrastructure.

Full documentation for the upstream Magma benchmark is at [hexhive.epfl.ch/magma](https://hexhive.epfl.ch/magma).

## PBFuzz Usage

To build and run experiments on this benchmark, use the scripts in the repository root rather than invoking Magma's build system directly:

- **`../build_images.sh <target>`** — builds a Docker image for a target, wiring in PBFuzz tooling
- **`../run_static_analysis.sh <target>`** — extracts static analysis data into `fuzzers/pre-built/<target>/`
- **`../run_experiment.sh [--skip-build] [target]`** — runs a directed-fuzzing campaign

Pre-built static analysis results for all 9 targets (lua, poppler, php, libpng, libsndfile, sqlite3, openssl, libtiff, libxml2) are already included in `fuzzers/pre-built/`.