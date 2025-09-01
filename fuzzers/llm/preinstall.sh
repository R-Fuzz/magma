#!/bin/bash
set -e

apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y \
    make cmake libc++-${LLVM_VERSION}-dev libc++abi-${LLVM_VERSION}-dev \
    python3 python3-pip python3-dev python-is-python3\
    zlib1g-dev git wget vim libunwind-${LLVM_VERSION}-dev \
    build-essential lsb-release software-properties-common \
    binutils-gold binutils-dev autoconf automake libtool-bin \
    curl ninja-build libz3-dev \
    libboost-dev libboost-container-dev libboost-program-options-dev libboost-graph-dev

pip install --no-cache-dir \
    google-auth \
    google-genai \
    openai \
    anthropic

# Install common external libs
pip install --no-cache-dir \
    asn1 \
    asn1crypto \
    asn1tools \
    crcmod \
    cryptography \
    numpy \
    opencv-python \
    pdfrw \
    PyPDF2 \
    pillow \
    pypng \
    pyasn1 \
    pyasn1-modules \
    pycryptodome \
    pytesseract \
    reportlab

pip install --no-cache-dir \
    tree-sitter tree-sitter-languages libclang pytest dap-mcp dap-types
# Andrew TODO: Find other dependencies and add them here

# we need llvm-20 for lldb, LLVM_VERSION is 14 by default
# we need llvm-14 for building magma targets
curl -O https://apt.llvm.org/llvm.sh \
    && chmod +x llvm.sh \
    && ./llvm.sh 20 && ./llvm.sh $LLVM_VERSION
