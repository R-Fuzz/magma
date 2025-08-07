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

curl -O https://apt.llvm.org/llvm.sh \
    && chmod +x llvm.sh \
    && ./llvm.sh $LLVM_VERSION

# For building aflgo
apt-get install -y clang-12 llvm-12 lld-12
update-alternatives --install /usr/bin/clang clang /usr/bin/clang-12 10
update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-12 10

ln -s /usr/bin/llvm-config-${LLVM_VERSION} /usr/bin/llvm-config
update-alternatives --install /usr/bin/clang clang /usr/bin/clang-${LLVM_VERSION} 20
update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-${LLVM_VERSION} 20

# Install LLVMgold in bfd-plugins
mkdir -p /usr/lib/bfd-plugins
cp /usr/lib/llvm-${LLVM_VERSION}/lib/LLVMgold.so /usr/lib/bfd-plugins
cp /usr/lib/llvm-${LLVM_VERSION}/lib/libLTO.so /usr/lib/bfd-plugins

# ugly fix for installing symsan python solver lib
chmod 777 /usr/local/lib/python*/dist-packages

# install pip packages
pip install \
    kiwisolver \
    lit \
    numpy \
    packaging \
    psutil \
    python-dateutil \
    pyparsing \
    z3-solver==4.13.0.0 \
    --no-cache-dir

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
