#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
: "${LLVM_VERSION:=14}"

# System deps
apt-get update
apt-get upgrade -y
apt-get install -y \
    make cmake \
    python3 python3-pip python3-dev python-is-python3\
    zlib1g-dev git wget vim tmux \
    build-essential lsb-release software-properties-common \
    binutils-gold binutils-dev autoconf automake libtool-bin \
    curl ninja-build libz3-dev libzstd-dev\
    libboost-dev libboost-container-dev libboost-program-options-dev libboost-graph-dev

# Faster Python builds
python -m pip install -U --no-cache-dir pip wheel setuptools

# LLM SDKs
pip install -U --no-cache-dir \
  google-auth google-genai openai anthropic

# Binary crafting toolbelt
# PNG/TIFF: pillow, pypng, tifffile, imagecodecs
# PDF/Poppler: reportlab, PyPDF2, pdfrw, pikepdf, img2pdf
# Audio/libsndfile: soundfile, pydub (via ffmpeg), audioread
# Crypto/OpenSSL: cryptography, pycryptodome, pyOpenSSL
# Generic binary builders: construct, bitstring, kaitaistruct
pip install -U --no-cache-dir \
    numpy opencv-python pillow pypng tifffile imagecodecs pytesseract \
    reportlab PyPDF2 pdfrw pikepdf img2pdf \
    soundfile pydub audioread \
    cryptography pycryptodome pyopenssl \
    asn1 asn1crypto asn1tools pyasn1 pyasn1-modules \
    crcmod construct bitstring kaitaistruct

pip install --no-cache-dir \
    pydantic mcp dap-mcp dap-types \
    cxxfilt wllvm psutil \
    pytest pytest-asyncio \
    tree-sitter tree-sitter-c tree-sitter-cpp tree-sitter-languages libclang

# we need llvm-20 for lldb, LLVM_VERSION is 14 by default
# we need llvm-14 for building magma targets
curl -O https://apt.llvm.org/llvm.sh && chmod +x llvm.sh
./llvm.sh 14 all
./llvm.sh 20 all

ln -s /usr/bin/clang-14 /usr/local/bin/clang
ln -s /usr/bin/clang++-14 /usr/local/bin/clang++