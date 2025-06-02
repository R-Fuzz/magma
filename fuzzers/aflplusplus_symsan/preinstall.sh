#!/bin/bash
set -e

apt-get update
apt-get install -y \
    make build-essential cmake \
    python3-minimal python-is-python3 zlib1g-dev git joe libprotobuf-dev \
    libz3-dev libboost-container-dev python3-dev libgoogle-perftools-dev \
    wget lsb-release software-properties-common gnupg2 curl

curl -O https://apt.llvm.org/llvm.sh \
    && chmod +x llvm.sh \
    && ./llvm.sh 14 all

#update-alternatives --install /usr/bin/clang clang /usr/bin/clang-12 100 \
#    && update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-12 100

