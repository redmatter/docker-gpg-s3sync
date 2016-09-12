#!/bin/bash

: ${SOURCE_REMOVE_PLAIN:=0}
: ${SOURCE_PATH:=/data/plain}
: ${ENCRYPTED_PATH:=/data/encrypted}

source /app/functions.sh

set -e;

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
    for i in $(seq 1 10); do
        local filepath="${SOURCE_PATH}/data-$(printf %02d $i).txt"
        local filename=$(basename "$filepath")

        if is_number "$SOURCE_REMOVE_PLAIN" && [ "$SOURCE_REMOVE_PLAIN" -eq 1 ]; then
            bail_file_exists "$filepath";
        fi

        /app/entrypoint.sh restore "${filename}.gpg"
        verify_test_file "$filename"
    done
    return 0;
}

run
