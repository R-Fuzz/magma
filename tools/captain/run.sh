#!/bin/bash -e

##
# Pre-requirements:
# + $1: path to captainrc (default: ./captainrc)
##

if [ -z $1 ]; then
    set -- "./captainrc"
fi

# load the configuration file (captainrc)
set -a
source "$1"
set +a

if [ -z $WORKDIR ] || [ -z $REPEAT ]; then
    echo '$WORKDIR and $REPEAT must be specified as environment variables.'
    exit 1
fi
MAGMA=${MAGMA:-"$(cd "$(dirname "${BASH_SOURCE[0]}")/../../" >/dev/null 2>&1 \
    && pwd)"}
export MAGMA
source "$MAGMA/tools/captain/common.sh"

if [ -z "$WORKER_POOL" ]; then
    WORKER_MODE=${WORKER_MODE:-1}
    WORKERS_ALL=($(lscpu -b -p | sed '/^#/d' | sort -u -t, -k ${WORKER_MODE}g | cut -d, -f1))
    WORKERS=${WORKERS:-${#WORKERS_ALL[@]}}
    export WORKER_POOL="${WORKERS_ALL[@]:0:WORKERS}"
fi
export CAMPAIGN_WORKERS=${CAMPAIGN_WORKERS:-1}

TMPFS_SIZE=${TMPFS_SIZE:-50g}
export POLL=${POLL:-5}
export TIMEOUT=${TIMEOUT:-1m}

WORKDIR="$(realpath "$WORKDIR")"
export ARDIR="$WORKDIR/ar"
export CACHEDIR="$WORKDIR/cache"
export LOGDIR="$WORKDIR/log"
export POCDIR="$WORKDIR/poc"
export LOCKDIR="$WORKDIR/lock"
mkdir -p "$ARDIR"
mkdir -p "$CACHEDIR"
mkdir -p "$LOGDIR"
mkdir -p "$POCDIR"
mkdir -p "$LOCKDIR"

shopt -s nullglob
rm -f "$LOCKDIR"/*
shopt -u nullglob

export MUX_TAR=magma_tar
export MUX_CID=magma_cid

get_next_cid()
{
    ##
    # Pre-requirements:
    # - $1: the directory where campaigns are stored
    ##
    shopt -s nullglob
    campaigns=("$1"/*)
    if [ ${#campaigns[@]} -eq 0 ]; then
        echo 0
        dir="$1/0"
    else
        cids=($(sort -n < <(basename -a "${campaigns[@]}")))
        for ((i=0;;i++)); do
            if [ -z ${cids[i]} ] || [ ${cids[i]} -ne $i ]; then
                echo $i
                dir="$1/$i"
                break
            fi
        done
    fi
    # ensure the directory is created to prevent races
    mkdir -p "$dir"
    while [ ! -d "$dir" ]; do sleep 1; done
}
export -f get_next_cid

get_missing_campaigns()
{
    ##
    # Pre-requirements:
    # - $1: the directory where campaigns are stored
    # - $2: the number of campaigns that should be completed
    ##
    local campaign_dir="$1"
    local expected_count="$2"
    
    if [ ! -d "$campaign_dir" ]; then
        # If directory doesn't exist, all campaigns are missing
        echo "0"
        return
    fi
    
    shopt -s nullglob
    campaigns=("$campaign_dir"/*)
    shopt -u nullglob
    
    local actual_count=${#campaigns[@]}
    
    if [ $actual_count -eq 0 ]; then
        # No campaigns exist, start from 0
        echo "0"
        return
    fi
    
    # Get existing campaign numbers
    local existing_campaigns=($(sort -n < <(basename -a "${campaigns[@]}")))
    
    # Find the first missing campaign number
    for ((i=0; i<$expected_count; i++)); do
        local found=0
        for existing in "${existing_campaigns[@]}"; do
            if [ "$existing" -eq "$i" ]; then
                found=1
                break
            fi
        done
        if [ $found -eq 0 ]; then
            echo "$i"
            return
        fi
    done
    
    # If we reach here, all campaigns are completed
    echo "completed"
}
export -f get_missing_campaigns

mutex()
{
    ##
    # Pre-requirements:
    # - $1: the mutex ID (file descriptor)
    # - $2..N: command to run
    ##
    trap 'rm -f "$LOCKDIR/$mux"' EXIT
    mux=$1
    shift
    (
      flock -xF 200 &> /dev/null
      "${@}"
    ) 200>"$LOCKDIR/$mux"
}
export -f mutex

start_campaign()
{
    launch_campaign()
    {
        export SHARED="$CAMPAIGN_CACHEDIR/$CACHECID"
        mkdir -p "$SHARED" && chmod 777 "$SHARED"
        if [ -n "$BUGID" ]; then
            echo_time "Container $FUZZER/$TARGET/$PROGRAM/${BUGID}/$ARCID started on CPU $AFFINITY"
            "$MAGMA"/tools/captain/start.sh &> \
                "${LOGDIR}/${FUZZER}_${TARGET}_${PROGRAM}_${BUGID}_${ARCID}_container.log"
        else
            echo_time "Container $FUZZER/$TARGET/$PROGRAM/$ARCID started on CPU $AFFINITY"
            "$MAGMA"/tools/captain/start.sh &> \
                "${LOGDIR}/${FUZZER}_${TARGET}_${PROGRAM}_${ARCID}_container.log"
        fi
        echo_time "Container $FUZZER/$TARGET/$PROGRAM/$ARCID stopped"

        if [ ! -z $POC_EXTRACT ]; then
            "$MAGMA"/tools/captain/extract.sh
        fi

        dest_dir="${CAMPAIGN_ARDIR}/${ARCID}"
        mkdir -p "$dest_dir"

        if [ -z "$NO_ARCHIVE" ]; then
            # only one tar job runs at a time, to prevent out-of-storage errors
            mutex "$MUX_TAR" \
            tar -cf "${dest_dir}/${TARBALL_BASENAME}.tar" -C "$SHARED" . &>/dev/null && \
            rm -rf "$SHARED"
        else
            # overwrite empty $ARCID directory with the $SHARED directory
            mv -T "$SHARED" "$dest_dir"
        fi
    }
    export -f launch_campaign

    while : ; do
        if [ -n "$BUGID" ]; then
            export CAMPAIGN_CACHEDIR="$CACHEDIR/$FUZZER/$TARGET/$PROGRAM/$BUGID"
            export CAMPAIGN_ARDIR="$ARDIR/$FUZZER/$TARGET/$PROGRAM/$BUGID"
        else
            export CAMPAIGN_CACHEDIR="$CACHEDIR/$FUZZER/$TARGET/$PROGRAM"
            export CAMPAIGN_ARDIR="$ARDIR/$FUZZER/$TARGET/$PROGRAM"
        fi
        export CACHECID=$(mutex $MUX_CID get_next_cid "$CAMPAIGN_CACHEDIR")
        export ARCID=$(mutex $MUX_CID get_next_cid "$CAMPAIGN_ARDIR")

        errno_lock=69
        SHELL=/bin/bash flock -xnF -E $errno_lock "${CAMPAIGN_CACHEDIR}/${CACHECID}" \
            flock -xnF -E $errno_lock "${CAMPAIGN_ARDIR}/${ARCID}" \
                -c launch_campaign || \
        if [ $? -eq $errno_lock ]; then
            continue
        fi
        break
    done
}
export -f start_campaign

start_ex()
{
    release_workers()
    {
        IFS=','
        read -a workers <<< "$AFFINITY"
        unset IFS
        for i in "${workers[@]}"; do
            rm -rf "$LOCKDIR/magma_cpu_$i"
        done
    }
    trap release_workers EXIT

    start_campaign
    if [[ "$RUN_SEQUENTIALLY" != "1" ]]; then
        exit 0
    fi
}
export -f start_ex

allocate_workers()
{
    ##
    # Pre-requirements:
    # - env NUMWORKERS
    # - env WORKERSET
    ##
    cleanup()
    {
        IFS=','
        read -a workers <<< "$WORKERSET"
        unset IFS
        for i in "${workers[@]:1}"; do
            rm -rf "$LOCKDIR/magma_cpu_$i"
        done
        exit 0
    }
    trap cleanup SIGINT

    while [ $NUMWORKERS -gt 0 ]; do
        for i in $WORKER_POOL; do
            if ( set -o noclobber; > "$LOCKDIR/magma_cpu_$i" ) &>/dev/null; then
                export WORKERSET="$WORKERSET,$i"
                export NUMWORKERS=$(( NUMWORKERS - 1 ))
                allocate_workers
                return
            fi
        done
        # This times-out every 1 second to force a refresh, since a worker may
        #   have been released by the time inotify instance is set up.
        inotifywait -qq -t 1 -e delete "$LOCKDIR" &> /dev/null
    done
    cut -d',' -f2- <<< $WORKERSET
}
export -f allocate_workers

# set up a RAM-backed fs for fast processing of canaries and crashes
if [ -z $CACHE_ON_DISK ]; then
    echo_time "Obtaining sudo permissions to mount tmpfs"
    if mountpoint -q -- "$CACHEDIR"; then
        sudo umount -f "$CACHEDIR"
    fi
    sudo mount -t tmpfs -o size=$TMPFS_SIZE,uid=$(id -u $USER),gid=$(id -g $USER) \
        tmpfs "$CACHEDIR"
fi

cleanup()
{
    trap 'echo Cleaning up...' SIGINT
    echo_time "Waiting for jobs to finish"
    for job in `jobs -p`; do
        if ! wait $job; then
            continue
        fi
    done

    find "$LOCKDIR" -type f | while read lock; do
        if inotifywait -qq -e delete_self "$lock" &> /dev/null; then
            continue
        fi
    done

    if [ -z $CACHE_ON_DISK ]; then
        echo_time "Obtaining sudo permissions to umount tmpfs"
        sudo umount "$CACHEDIR"
    fi
}

if [[ "$RUN_SEQUENTIALLY" != "1" ]]; then
    trap cleanup EXIT
fi

# schedule campaigns
for FUZZER in "${FUZZERS[@]}"; do
    export FUZZER

    TARGETS=($(get_var_or_default $FUZZER 'TARGETS'))
    for TARGET in "${TARGETS[@]}"; do
        export TARGET

        export FUZZARGS="$(get_var_or_default $FUZZER $TARGET 'FUZZARGS')"

        # build the Docker image
        IMG_NAME="magma/$FUZZER/$TARGET"
        if docker image inspect "$IMG_NAME" > /dev/null 2>&1; then
            echo_time "Docker image $IMG_NAME already exists. Skipping build."
        else
            echo_time "Building $IMG_NAME"
            # If FUZZER starts with llm, set DOCKERFILE_PATH
            if [[ "$FUZZER" == *llm* ]]; then
                # Check if magma/aflgo_mazerunner/$TARGET exists
                if ! docker image inspect "magma/aflgo_mazerunner/${TARGET}" > /dev/null 2>&1; then
                    echo_time "ERROR: Please build the required image magma/aflgo_mazerunner/${TARGET} first. Skipping $FUZZER/$TARGET."
                    continue
                fi
                export DOCKERFILE_PATH="$MAGMA/docker/Dockerfile.mr"
            else
                unset DOCKERFILE_PATH
            fi
            if ! "$MAGMA"/tools/captain/build.sh &> \
                "${LOGDIR}/${FUZZER}_${TARGET}_build.log"; then
                echo_time "Failed to build $IMG_NAME. Check build log for info."
                continue
            fi
        fi

        PROGRAMS=($(get_var_or_default $FUZZER $TARGET 'PROGRAMS'))
        for PROGRAM in "${PROGRAMS[@]}"; do
            export PROGRAM
            export ARGS="$(get_var_or_default $FUZZER $TARGET $PROGRAM 'ARGS')"

            # Get bug IDs for the current program
            BUG_DIR="$MAGMA/targets/$TARGET/patches/bugs"
            BUGIDS=()
            if [ -d "$BUG_DIR" ]; then
                BUGIDS=($(basename -a "$BUG_DIR"/*.patch | sed 's/\.patch$//'))
                # If WHITELIST is defined and non-empty, filter BUGIDS to only those in WHITELIST
                if [ -n "${WHITELIST+x}" ] && [ ${#WHITELIST[@]} -gt 0 ]; then
                    # Build an associative array for quick lookup
                    declare -A wl_map
                    for w in "${WHITELIST[@]}"; do wl_map["$w"]=1; done
                    filtered=()
                    for b in "${BUGIDS[@]}"; do
                        if [ -n "${wl_map[$b]}" ]; then
                            filtered+=("$b")
                        fi
                    done
                    BUGIDS=("${filtered[@]}")
                fi
                # If BLACKLIST is defined, remove any blacklisted IDs from BUGIDS
                if [ -n "${BLACKLIST+x}" ] && [ ${#BLACKLIST[@]} -gt 0 ]; then
                    declare -A bl_map
                    for bl in "${BLACKLIST[@]}"; do bl_map["$bl"]=1; done
                    filtered2=()
                    for b in "${BUGIDS[@]}"; do
                        if [ -z "${bl_map[$b]}" ]; then
                            filtered2+=("$b")
                        fi
                    done
                    BUGIDS=("${filtered2[@]}")
                fi
            fi
            echo_time "Found ${#BUGIDS[@]} bugs for $PROGRAM in $BUG_DIR"
            for BUGID in "${BUGIDS[@]}"; do
                if [ -n "${BLACKLIST+x}" ]; then
                    skip=0
                    for b in "${BLACKLIST[@]}"; do
                        if [ "$b" = "$BUGID" ]; then
                            echo_time "Skipping blacklisted BUGID $BUGID for $FUZZER/$TARGET/$PROGRAM"
                            skip=1
                            break
                        fi
                    done
                    if [ $skip -eq 1 ]; then
                        continue
                    fi
                fi
                export BUGID
                # Set campaign directories for this specific bug
                CAMPAIGN_ARDIR="$ARDIR/$FUZZER/$TARGET/$PROGRAM/$BUGID"
                # Check if campaigns are already completed for this bug
                missing_start=$(get_missing_campaigns "$CAMPAIGN_ARDIR" "$REPEAT")
                if [ "$missing_start" = "completed" ]; then
                    echo_time "Campaigns already completed for $FUZZER/$TARGET/$PROGRAM/$BUGID. Skipping."
                    continue
                fi
                echo_time "Starting campaigns. cmd=<$PROGRAM $ARGS>, bug=${BUGID}, starting from campaign $missing_start"
                for ((i=missing_start; i<$REPEAT; i++)); do
                    unset NUMWORKERS
                    unset AFFINITY
                    if [[ "$RUN_SEQUENTIALLY" == "1" ]]; then
                        start_ex
                    else
                        # export NUMWORKERS="$(get_var_or_default $FUZZER 'CAMPAIGN_WORKERS')"
                        # export AFFINITY=$(allocate_workers)
                        sleep 30
                        start_ex &
                    fi
                done
            done
        done

        if [[ "$RUN_SEQUENTIALLY" != "1" ]]; then
            echo_time "Waiting for all campaigns of $FUZZER/$TARGET to finish..."
            wait
        fi
        # echo_time "Finished scheduling $FUZZER/$TARGET, sleep 10min"
        # sleep 600

    done
done
