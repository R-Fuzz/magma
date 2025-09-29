FROM ubuntu:22.04

# TODO remove sudo for user "magma" to avoid unwanted priv escalation from
# other attack vectors.

RUN DEBIAN_FRONTEND=noninteractive \
    apt-get update && apt-get install -y sudo

## Magma directory hierarchy
# magma_root is relative to the docker-build's working directory
# The Docker image must be built in the root of the magma directory
ARG magma_root=.

## Path variables inside the container
ENV MAGMA_R=/magma
ENV OUT=/magma_out
ENV SHARED=/magma_shared

ENV CC=/usr/bin/gcc
ENV CXX=/usr/bin/g++
ENV LD=/usr/bin/ld
ENV AR=/usr/bin/ar
ENV AS=/usr/bin/as
ENV NM=/usr/bin/nm
ENV RANLIB=/usr/bin/ranlib

ARG USER_ID=1000
ARG GROUP_ID=1000
ENV USERID=${USER_ID}
ENV GROUPID=${GROUP_ID}
RUN mkdir -p /home && \
	groupadd -g ${GROUPID} magma && \
	useradd -l -u ${USERID} -K UMASK=0000 -d /home -g magma magma && \
	chown magma:magma /home
RUN echo "magma:magma" | chpasswd && usermod -a -G sudo magma

RUN mkdir -p ${SHARED} ${OUT} && \
	chown magma:magma ${SHARED} ${OUT} && \
	chmod 744 ${SHARED} ${OUT}

ARG magma_path=magma
ENV MAGMA=${MAGMA_R}/${magma_path}
USER root:root
RUN mkdir -p ${MAGMA} && chown magma:magma ${MAGMA}

# Install Magma dependencies
COPY --chown=magma:magma ${magma_root}/${magma_path}/preinstall.sh ${MAGMA}
RUN DEBIAN_FRONTEND=noninteractive ${MAGMA}/preinstall.sh

USER magma:magma

COPY --chown=magma:magma ${magma_root}/${magma_path}/prebuild.sh ${MAGMA}
COPY --chown=magma:magma ${magma_root}/${magma_path}/src ${MAGMA}/src
RUN ${MAGMA}/prebuild.sh

ENV LLVM_VERSION=14
ARG fuzzer_name
ARG fuzzer_path=fuzzers/${fuzzer_name}
ENV FUZZER=${MAGMA_R}/${fuzzer_path}
USER root:root
RUN mkdir -p ${FUZZER} && chown -R magma:magma ${FUZZER}

# Install fuzzer dependencies
COPY --chown=magma:magma ${magma_root}/${fuzzer_path}/preinstall.sh ${FUZZER}
RUN ${FUZZER}/preinstall.sh

USER magma:magma

# Fetch fuzzer
ARG GITHUB_TOKEN
COPY --chown=magma:magma ${magma_root}/${fuzzer_path}/fetch.sh ${FUZZER}
COPY --chown=magma:magma ${magma_root}/${fuzzer_path}/src ${FUZZER}/src
RUN ${FUZZER}/fetch.sh

# Build fuzzer
COPY --chown=magma:magma ${magma_root}/${fuzzer_path}/build.sh ${FUZZER}
RUN ${FUZZER}/build.sh

ARG target_name
ARG target_path=targets/${target_name}
ENV TARGET=${MAGMA_R}/${target_path}
USER root:root
RUN mkdir -p ${TARGET} && chown magma:magma ${TARGET}

# Install target dependencies
COPY --chown=magma:magma ${magma_root}/${target_path}/preinstall.sh ${TARGET}
RUN ${TARGET}/preinstall.sh

USER magma:magma

# Get the target
COPY --chown=magma:magma ${magma_root}/${target_path}/fetch.sh ${TARGET}
COPY --chown=magma:magma ${magma_root}/${target_path}/src ${TARGET}/src
RUN ${TARGET}/fetch.sh

# Forward-port bugs
COPY --chown=magma:magma ${magma_root}/${target_path}/patches ${TARGET}/patches
COPY --chown=magma:magma ${magma_root}/${target_path}/src ${TARGET}/src
COPY --chown=magma:magma ${magma_root}/${target_path}/configrc ${TARGET}
COPY --chown=magma:magma ${magma_root}/${magma_path}/apply_patches.sh ${MAGMA}
RUN ${MAGMA}/apply_patches.sh

# Configuration parameters
ARG isan
ARG harden
ARG canaries
ARG fixes

ARG ISAN_FLAG=${isan:+-DMAGMA_FATAL_CANARIES}
ARG HARDEN_FLAG=${harden:+-DMAGMA_HARDEN_CANARIES}
ARG CANARIES_FLAG=${canaries:+-DMAGMA_ENABLE_CANARIES}
ARG FIXES_FLAG=${fixes:+-DMAGMA_ENABLE_FIXES}
ARG BUILD_FLAGS="-include ${MAGMA}/src/canary.h ${CANARIES_FLAG} ${FIXES_FLAG} ${ISAN_FLAG} ${HARDEN_FLAG} -g -O0"

ENV CFLAGS=${BUILD_FLAGS}
ENV CXXFLAGS=${BUILD_FLAGS}
ENV LIBS="-l:magma.a -lrt"
ENV LDFLAGS="-L${OUT} -g"

# Instrument and build the target program
COPY --chown=magma:magma ${magma_root}/${fuzzer_path}/pre-built/${target_name} ${FUZZER}/pre-built
COPY --chown=magma:magma ${magma_root}/${fuzzer_path}/instrument.sh ${FUZZER}
COPY --chown=magma:magma ${magma_root}/${magma_path}/build.sh ${MAGMA}
COPY --chown=magma:magma ${magma_root}/${target_path}/build.sh ${TARGET}
RUN ${FUZZER}/instrument.sh

COPY --chown=magma:magma ${magma_root}/${magma_path}/run.sh ${MAGMA}
COPY --chown=magma:magma ${magma_root}/${magma_path}/runonce.sh ${MAGMA}
COPY --chown=magma:magma ${magma_root}/${fuzzer_path}/run.sh ${FUZZER}
COPY --chown=magma:magma ${magma_root}/${fuzzer_path}/runonce.sh ${FUZZER}
COPY --chown=magma:magma ${magma_root}/${fuzzer_path}/findings.sh ${FUZZER}
COPY --chown=magma:magma ${magma_root}/${target_path}/corpus ${TARGET}/corpus

# Reset building flags
ENV CFLAGS=""
ENV CXXFLAGS=""
ENV LIBS=""
ENV LDFLAGS=""