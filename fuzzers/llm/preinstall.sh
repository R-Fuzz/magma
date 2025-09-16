#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
: "${LLVM_VERSION:=16}"

# System deps
apt-get update
apt-get upgrade -y
apt-get install -y \
  make cmake ninja-build build-essential pkg-config \
  libc++-${LLVM_VERSION}-dev libc++abi-${LLVM_VERSION}-dev libunwind-${LLVM_VERSION}-dev \
  python3 python3-pip python3-dev python3-venv python-is-python3 \
  zlib1g-dev libz3-dev git wget curl vim tmux \
  binutils-gold binutils-dev autoconf automake libtool-bin \
  libboost-dev libboost-container-dev libboost-program-options-dev libboost-graph-dev \
  # format encoders / manipulators
  openssl \
  qpdf poppler-utils mupdf-tools \
  libpng-tools libtiff-tools exiftool tesseract-ocr \
  ffmpeg sox flac vorbis-tools opus-tools lame \
  libsndfile1 libsndfile1-dev sndfile-tools \
  kaitai-struct-compiler

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
  numpy opencv-python \
  pillow pypng tifffile imagecodecs \
  reportlab PyPDF2 pdfrw pikepdf img2pdf \
  soundfile pydub audioread \
  cryptography pycryptodome pyopenssl \
  asn1 asn1crypto asn1tools pyasn1 pyasn1-modules \
  crcmod pytesseract \
  construct bitstring kaitaistruct

pip install --no-cache-dir \
    tree-sitter tree-sitter-languages libclang pytest dap-mcp dap-types

# we need llvm-20 for lldb, LLVM_VERSION is 14 by default
# we need llvm-14 for building magma targets
curl -O https://apt.llvm.org/llvm.sh \
    && chmod +x llvm.sh \
    && ./llvm.sh 20 && ./llvm.sh $LLVM_VERSION
