#!/bin/bash

apt-get update && \
    apt-get install -y git make autoconf autogen automake build-essential \
  libtool pkg-config python3 python-is-python3

# For now, do not install the following libraries (as they won't be in the
# final image):
# libasound2-dev libflac-dev libogg-dev libopus-dev libvorbis-dev
# libmp3lame-dev libmpg123-dev
