#!/bin/bash
set -e

apt-get update && \
    apt-get install -y \
    	make \
	build-essential \
	git \
	wget \
	curl \
	libcap-dev \
	cmake \
        libncurses5-dev \
	python-minimal \
	python-pip \
	unzip \
	libtcmalloc-minimal4 \
        libgoogle-perftools-dev \
	libsqlite3-dev \
	doxygen \
        cmake \
	bison \
	flex \
	libboost-all-dev \
	perl \
	zlib1g-dev \
	minisat \
	libc6-dev-i386 \
	llvm-14-dev \
	clang-14

pip install --upgrade wllvm

update-alternatives \
  --install /usr/lib/llvm              llvm             /usr/lib/llvm-14  20 \
  --slave   /usr/bin/llvm-config       llvm-config      /usr/bin/llvm-config-14  \
    --slave   /usr/bin/llvm-ar           llvm-ar          /usr/bin/llvm-ar-14 \
    --slave   /usr/bin/llvm-as           llvm-as          /usr/bin/llvm-as-14 \
    --slave   /usr/bin/llvm-bcanalyzer   llvm-bcanalyzer  /usr/bin/llvm-bcanalyzer-14 \
    --slave   /usr/bin/llvm-c-test       llvm-c-test      /usr/bin/llvm-c-test-14 \
    --slave   /usr/bin/llvm-cov          llvm-cov         /usr/bin/llvm-cov-14 \
    --slave   /usr/bin/llvm-diff         llvm-diff        /usr/bin/llvm-diff-14 \
    --slave   /usr/bin/llvm-dis          llvm-dis         /usr/bin/llvm-dis-14 \
    --slave   /usr/bin/llvm-dwarfdump    llvm-dwarfdump   /usr/bin/llvm-dwarfdump-14 \
    --slave   /usr/bin/llvm-extract      llvm-extract     /usr/bin/llvm-extract-14 \
    --slave   /usr/bin/llvm-link         llvm-link        /usr/bin/llvm-link-14 \
    --slave   /usr/bin/llvm-mc           llvm-mc          /usr/bin/llvm-mc-14 \
    --slave   /usr/bin/llvm-nm           llvm-nm          /usr/bin/llvm-nm-14 \
    --slave   /usr/bin/llvm-objdump      llvm-objdump     /usr/bin/llvm-objdump-14 \
    --slave   /usr/bin/llvm-ranlib       llvm-ranlib      /usr/bin/llvm-ranlib-14 \
    --slave   /usr/bin/llvm-readobj      llvm-readobj     /usr/bin/llvm-readobj-14 \
    --slave   /usr/bin/llvm-rtdyld       llvm-rtdyld      /usr/bin/llvm-rtdyld-14 \
    --slave   /usr/bin/llvm-size         llvm-size        /usr/bin/llvm-size-14 \
    --slave   /usr/bin/llvm-stress       llvm-stress      /usr/bin/llvm-stress-14 \
    --slave   /usr/bin/llvm-symbolizer   llvm-symbolizer  /usr/bin/llvm-symbolizer-14 \
    --slave   /usr/bin/llvm-tblgen       llvm-tblgen      /usr/bin/llvm-tblgen-14

update-alternatives \
  --install /usr/bin/clang                 clang                  /usr/bin/clang-14     20 \
  --slave   /usr/bin/clang++               clang++                /usr/bin/clang++-14 \
  --slave   /usr/bin/clang-cpp             clang-cpp              /usr/bin/clang-cpp-14

# remove stack size limit (needed for STP on large binaries)
echo "magma    soft    stack    unlimited" >> /etc/security/limits.conf
echo "magma    soft    nofile   unlimited" >> /etc/security/limits.conf
