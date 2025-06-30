#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# Choose your versions here:
LLVM_VERSION=16
GCC_VERSION=11

# 1) Add official LLVM apt repo + key
apt-get update && apt-get install -y --no-install-recommends \
    build-essential make cmake automake meson ninja-build bison flex \
    git xz-utils bzip2 nano bash-completion less vim joe ssh psmisc \
    wget gnupg lsb-release \
    python3 python3-dev python3-pip python-is-python3 \
    libtool libtool-bin libglib2.0-dev \
    gnuplot-nox libpixman-1-dev bc lcov \
    software-properties-common
add-apt-repository -y ppa:ubuntu-toolchain-r/test
(
    wget https://apt.llvm.org/llvm.sh
    chmod +x llvm.sh
    ./llvm.sh $LLVM_VERSION
    rm -f llvm.sh
)

# 2) Update & install core build tools + AFL++ dependencies
apt-get update && apt-get install -y --no-install-recommends \
    gcc-${GCC_VERSION} g++-${GCC_VERSION} gcc-${GCC_VERSION}-plugin-dev \
    clang-${LLVM_VERSION} clang-tools-${LLVM_VERSION} \
    libc++1-${LLVM_VERSION} libc++-${LLVM_VERSION}-dev \
    libc++abi1-${LLVM_VERSION} libc++abi-${LLVM_VERSION}-dev \
    libclang1-${LLVM_VERSION} libclang-${LLVM_VERSION}-dev \
    libclang-common-${LLVM_VERSION}-dev libclang-rt-${LLVM_VERSION}-dev \
    libclang-cpp${LLVM_VERSION} libclang-cpp${LLVM_VERSION}-dev \
    lld-${LLVM_VERSION} llvm-${LLVM_VERSION} llvm-${LLVM_VERSION}-dev \
    llvm-${LLVM_VERSION}-runtime llvm-${LLVM_VERSION}-tools \
    libunwind-${LLVM_VERSION} \
    $([ "$(dpkg --print-architecture)" = "amd64" ] && echo gcc-${GCC_VERSION}-multilib gcc-multilib) \
    $([ "$(dpkg --print-architecture)" = "arm64" ] && echo libcapstone-dev) && \
    rm -rf /var/lib/apt/lists/*

# 3) Register gcc & clang with update-alternatives
update-alternatives --install /usr/bin/gcc  gcc  /usr/bin/gcc-${GCC_VERSION} 100 \
                    --slave   /usr/bin/g++  g++  /usr/bin/g++-${GCC_VERSION}
update-alternatives --install /usr/bin/clang  clang  /usr/bin/clang-${LLVM_VERSION} 100 \
                    --slave   /usr/bin/clang++  clang++  /usr/bin/clang++-${LLVM_VERSION}
