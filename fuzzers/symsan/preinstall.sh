#!/bin/bash
set -e

apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y \
    make cmake libc++-12-dev libc++abi-12-dev \
    python3 python-pip python3-dev python-is-python3\
    zlib1g-dev git libprotobuf-dev protobuf-compiler libunwind-dev \
    build-essential wget lsb-release software-properties-common gnupg2 \
    curl subversion ninja-build cargo inotify-tools libz3-dev libboost-dev libboost-container-dev
apt-get install -y libz3-dev libgoogle-perftools-dev

apt-get update && apt-get install -y clang-12 llvm-12 lld-12
ln -s /usr/bin/llvm-config-12 /usr/bin/llvm-config
update-alternatives --install /usr/bin/clang clang /usr/bin/clang-12 100 \
    && update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-12 100
