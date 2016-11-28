#!/bin/bash

: "${SOURCE_REMOVE_PLAIN:=0}"
: "${SOURCE_PATH:=/data/plain}"
: "${ENCRYPTED_PATH:=/data/encrypted}"

source /app/functions.sh
source /app/s3sync.sh

set_debug

set -e

n_files=10

cleanup() {
    local path="$1"; shift
    info "Cleaning up $path ..."
    find "$path" -mindepth 1 -maxdepth 1 -type f -delete
}

create_test_files() {
    debug "SOURCE_PATH: $(ls -ld "${SOURCE_PATH}")"

    cleanup "${SOURCE_PATH}"

    md5sums="${SOURCE_PATH}/data.md5sums"
    file_exists "$md5sums" && rm "$md5sums"
    for i in $(seq 1 "$n_files"); do
        local file="${SOURCE_PATH}/data-$(printf %02d "$i").txt"
        debug "Creating '$file'"
        dd if=/dev/urandom of="$file" bs=100K count=1 &>/dev/null ||
            bail "Failed to create '$file'"
        # cd into the location before generating the MD5 so that path change wouldn't affect verify later on
        ( cd "$(dirname "$file")" && md5sum "$(basename "$file")" >> "$md5sums" )
    done

    # For debug purpose pass additional arg ('yes' or '1') to create_test_files
    # Plumbed in via the docker-compose.test.yml by honoring the env var 'wait_after_create_test_files'
    #
    # Example invocation:
    #   wait_after_create_test_files=yes docker-compose -f docker-compose.test.yml up
    while [[ "$1" = '1' || "$1" = 'yes' ]]; do
        sleep 1;
        ls -ld "${SOURCE_PATH}";
    done
}

verify_test_file() {
    local pattern="$1"; shift
    (
        cd "$SOURCE_PATH" && md5sum -c <(grep "$pattern" "data.md5sums")
    )
}

run_test() {
    cleanup "${ENCRYPTED_PATH}"

    # Poorman's synchronisation; giving test-data-generator service (create_test_files) a chance to complete.
    sleep 2

    # perform backup
    /app/entrypoint.sh backup

    # Verify that SOURCE_REMOVE_PLAIN option takes effect
    for i in $(seq 1 "$n_files"); do
        local filepath="${SOURCE_PATH}/data-$(printf '%02d' "$i").txt"
        if [ "$SOURCE_REMOVE_PLAIN" = 1 ]; then
            bail_file_exists "$filepath"
        else
            bail_file_not_exists "$filepath"
        fi
    done

    # Restore each file only if the SOURCE_PATH is writable.
    # SOURCE_PATH can be made read-only via settings given to volume options
    # This test makes sure that gpg-s3sync honours these and does not fall apart.
    if [ -w "${SOURCE_PATH}" ]; then
        for i in $(seq 1 "$n_files"); do
            local filepath="${SOURCE_PATH}/data-$(printf '%02d' "$i").txt"
            local filename=$(basename "$filepath")

            # Using one file from the above set of tests, which has already been restored into SOURCE_PATH, check if
            # the restore will fail if the destination file already exists. If the command succeeds, i.e the file was
            # overwritten, then it is treated as a failure.
            if /app/entrypoint.sh restore "${filename}.gpg"; then
                error "File in SOURCE_PATH overwritten!"
                return 1;
            fi

            # remove the file before restore; otherwise 'restore' will bail seeing the file
            rm -f "$filepath";

            # if s3sync is enabled, then remove local encrypted files so that they are pulled down from S3, during
            # restore attempts below
            if s3sync is_enabled; then
                rm -f "${ENCRYPTED_PATH}/"*.txt.gpg
            fi

            # restore the specific file
            /app/entrypoint.sh restore "${filename}.gpg"
            verify_test_file "$filename"
        done
    fi

    return 0;
}

cmd="$1"; shift
case "$cmd" in
    run_test|create_test_files|cleanup)
        "$cmd" "$@"
        ;;
    *)
        bail "Unknown command '$cmd'"
        ;;
esac
