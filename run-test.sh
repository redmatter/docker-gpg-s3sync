#!/bin/bash

: ${SOURCE_REMOVE_PLAIN:=0}
: ${SOURCE_PATH:=/data/plain}
: ${ENCRYPTED_PATH:=/data/encrypted}

source /app/functions.sh
source /app/s3sync.sh

set_debug

create_test_files() {
    md5sums="${SOURCE_PATH}/data.md5sums"
    file_exists "$md5sums" && rm "$md5sums"
    for i in $(seq 1 10); do
        local file="${SOURCE_PATH}/data-$(printf %02d $i).txt"
        dd if=/dev/urandom of=$file bs=1M count=1 &>/dev/null
        md5sum "$file" >> "$md5sums"
    done
}

verify_test_file() {
    local pattern="$1"; shift
    md5sum -c <(grep "$pattern" "${SOURCE_PATH}/data.md5sums")
}

run() {
    create_test_files
    /app/entrypoint.sh backup
    for i in $(seq 1 5); do
        local filepath="${SOURCE_PATH}/data-$(printf %02d $i).txt"
        local filename=$(basename "$filepath")

        if is_number "$SOURCE_REMOVE_PLAIN" && [ "$SOURCE_REMOVE_PLAIN" -eq 1 ]; then
            bail_file_exists "$filepath";
        fi

        # if s3sync is enabled, then remove local encrypted files so that they are pulled down from S3
        if s3sync is_enabled; then
            rm "${ENCRYPTED_PATH}/"*.txt.gpg
        fi

        /app/entrypoint.sh restore "${filename}.gpg"
        verify_test_file "$filename"
    done

    # Using the last file from the above set of tests, which has already been restored into SOURCE_PATH, check if the
    # restore will fail if the destination file already exists. If the command succeeds, i.e the file was overwritten,
    # then it is treated as a failure.
    if /app/entrypoint.sh restore "data-01.txt.gpg"; then
        error "File in SOURCE_PATH overwritten!"
        return 1;
    fi

    return 0;
}

run
