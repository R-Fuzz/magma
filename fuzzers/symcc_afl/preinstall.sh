#!/bin/bash
set -e

apt-get update && \
    apt-get install -y \
        cargo \
        cmake \
        g++ \
        git \
        libz3-dev \
        ninja-build \
        python2 \
        python3-pip \
	wget \
	gnupg \
	libz3-dev \
	lsb-release \
	software-properties-common \
        zlib1g-dev

(
    wget https://apt.llvm.org/llvm.sh
    chmod +x llvm.sh
    ./llvm.sh 14
    rm -f llvm.sh
)

# Installl CMake from Kitware apt repository
wget -O - https://apt.kitware.com/keys/kitware-archive-latest.asc 2>/dev/null | \
    gpg --dearmor - | \
    tee /usr/share/keyrings/kitware-archive-keyring.gpg >/dev/null
echo 'deb [signed-by=/usr/share/keyrings/kitware-archive-keyring.gpg] https://apt.kitware.com/ubuntu/ bionic main' | \
    tee /etc/apt/sources.list.d/kitware.list >/dev/null
apt-get update && \
    apt-get install -y cmake

pip install lit

update-alternatives \
  --install /usr/lib/llvm              llvm             /usr/lib/llvm-17  20 \
  --slave   /usr/bin/llvm-config       llvm-config      /usr/bin/llvm-config-17  \
    --slave   /usr/bin/llvm-ar           llvm-ar          /usr/bin/llvm-ar-17 \
    --slave   /usr/bin/llvm-as           llvm-as          /usr/bin/llvm-as-17 \
    --slave   /usr/bin/llvm-bcanalyzer   llvm-bcanalyzer  /usr/bin/llvm-bcanalyzer-17 \
    --slave   /usr/bin/llvm-c-test       llvm-c-test      /usr/bin/llvm-c-test-17 \
    --slave   /usr/bin/llvm-cov          llvm-cov         /usr/bin/llvm-cov-17 \
    --slave   /usr/bin/llvm-diff         llvm-diff        /usr/bin/llvm-diff-17 \
    --slave   /usr/bin/llvm-dis          llvm-dis         /usr/bin/llvm-dis-17 \
    --slave   /usr/bin/llvm-dwarfdump    llvm-dwarfdump   /usr/bin/llvm-dwarfdump-17 \
    --slave   /usr/bin/llvm-extract      llvm-extract     /usr/bin/llvm-extract-17 \
    --slave   /usr/bin/llvm-link         llvm-link        /usr/bin/llvm-link-17 \
    --slave   /usr/bin/llvm-mc           llvm-mc          /usr/bin/llvm-mc-17 \
    --slave   /usr/bin/llvm-nm           llvm-nm          /usr/bin/llvm-nm-17 \
    --slave   /usr/bin/llvm-objdump      llvm-objdump     /usr/bin/llvm-objdump-17 \
    --slave   /usr/bin/llvm-ranlib       llvm-ranlib      /usr/bin/llvm-ranlib-17 \
    --slave   /usr/bin/llvm-readobj      llvm-readobj     /usr/bin/llvm-readobj-17 \
    --slave   /usr/bin/llvm-rtdyld       llvm-rtdyld      /usr/bin/llvm-rtdyld-17 \
    --slave   /usr/bin/llvm-size         llvm-size        /usr/bin/llvm-size-17 \
    --slave   /usr/bin/llvm-stress       llvm-stress      /usr/bin/llvm-stress-17 \
    --slave   /usr/bin/llvm-symbolizer   llvm-symbolizer  /usr/bin/llvm-symbolizer-17 \
    --slave   /usr/bin/llvm-tblgen       llvm-tblgen      /usr/bin/llvm-tblgen-17

update-alternatives \
  --install /usr/bin/clang                 clang                  /usr/bin/clang-17     20 \
  --slave   /usr/bin/clang++               clang++                /usr/bin/clang++-17 \
  --slave   /usr/bin/clang-cpp             clang-cpp              /usr/bin/clang-cpp-17
