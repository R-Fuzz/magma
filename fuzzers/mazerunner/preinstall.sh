#!/bin/bash
set -e

apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y \
    make cmake libc++-12-dev libc++abi-12-dev \
    python3 python3-pip python3-dev python-is-python3\
    zlib1g-dev git wget vim libunwind-dev \
    build-essential lsb-release software-properties-common \
    binutils-gold binutils-dev autoconf automake libtool-bin \
    curl ninja-build libz3-dev \
    libboost-dev libboost-container-dev libboost-program-options-dev libboost-graph-dev

curl -O https://apt.llvm.org/llvm.sh \
    && chmod +x llvm.sh \
    && ./llvm.sh 14

if [ ${LLVM_VERSION:-14} != "14" ]; then
    apt-get update && apt-get install -y clang-${LLVM_VERSION} llvm-${LLVM_VERSION} lld-${LLVM_VERSION}
    sudo update-alternatives --install /usr/bin/clang clang /usr/bin/clang-${LLVM_VERSION} 100
    sudo update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-${LLVM_VERSION} 100
fi

ln -s /usr/bin/llvm-config-${LLVM_VERSION} /usr/bin/llvm-config
sudo update-alternatives --install /usr/bin/clang clang /usr/bin/clang-14 50
sudo update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-14 50

# Install LLVMgold in bfd-plugins
mkdir -p /usr/lib/bfd-plugins
cp /usr/lib/llvm-${LLVM_VERSION}/lib/LLVMgold.so /usr/lib/bfd-plugins
cp /usr/lib/llvm-${LLVM_VERSION}/lib/libLTO.so /usr/lib/bfd-plugins
