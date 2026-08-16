#!/bin/bash

##
# Pre-requirements:
# - env SHARED: path to directory shared with host (to store results)
##

CRASH_DIR="$SHARED/findings/crashes"

if [ ! -d "$CRASH_DIR" ]; then
    exit 1
fi

# Not `-name 'id:*'` as the AFL++ fuzzers use: this is LibAFL's OnDiskCorpus,
# which does not use AFL's naming, so that filter would quietly match nothing
# and every campaign would look crash-free.  The dotfile exclusion drops the
# .metadata sidecars OnDiskCorpus writes next to each input.
find "$CRASH_DIR" -type f ! -name '.*'
