#!/bin/bash

exec 1>&2

# die on failure
set -e

source /app/functions.sh
source /app/gpgcrypt.sh
source /app/s3sync.sh

load_settings_file
set_debug

: "${SOURCE_REMOVE_PLAIN:=0}"
: "${SOURCE_FILE_PATTERN:=}"
: "${SOURCE_FILE_MODIFIED_MINUTES_AGO:=30}"
: "${SOURCE_PATH:=/data/plain}"
: "${ENCRYPTED_PATH:=/data/encrypted}"

backup() {
    # source-path must be a directory and be readable and searchable
    test_all drx "${SOURCE_PATH}" ||
        bail "Cannot read from source-path (SOURCE_PATH='$SOURCE_PATH' $(stat -c %A "${SOURCE_PATH}"))"
    # if plain file is to be removed after 'backup', source-path must be writable
    ( [ "${SOURCE_REMOVE_PLAIN}" = 0 ] || [ -w "${SOURCE_PATH}" ] ) || {
        bail "Cannot write to source-path (Cannot remove plain file; SOURCE_REMOVE_PLAIN='$SOURCE_REMOVE_PLAIN', SOURCE_PATH='${SOURCE_PATH}' $(stat -c %A "${SOURCE_PATH}"))"
    }
    # destination/encrypted-path must be a directory and be writable and searchable
    test_all drwx "${ENCRYPTED_PATH}" ||
        bail "Cannot write to encrypted-path (ENCRYPTED_PATH=${ENCRYPTED_PATH})"

    local all_backups=( $(list-backups --batch-mode) )

    find_opts=("$SOURCE_PATH")
    find_opts+=(-mindepth 1)
    find_opts+=(-maxdepth 1)
    find_opts+=(-type f)
    [ -z "$SOURCE_FILE_PATTERN" ] || \
        find_opts+=(-name "$SOURCE_FILE_PATTERN")
    if is_number "$SOURCE_FILE_MODIFIED_MINUTES_AGO" && [ "$SOURCE_FILE_MODIFIED_MINUTES_AGO" -gt 0 ]; then
        find_opts+=(-mmin +"$SOURCE_FILE_MODIFIED_MINUTES_AGO")
    fi

    find "${find_opts[@]}" | while read file; do
        # If file is already present either in ENCRYPTED_PATH or in S3 bucket, skip it
        if in_array "${file}.gpg" "${all_backups[@]}"; then
            debug "'$file' already backed up; skipping"
            continue;
        fi

        debug "Encrypting '${file}'"
        gpg encrypt "$file" "${ENCRYPTED_PATH}"

        if [ "0$SOURCE_REMOVE_PLAIN" -eq 1 ] &>/dev/null; then
            debug "Removing '${file}'"
            rm "$file"
        fi
    done

    if s3sync is_enabled; then
        debug "Syncing up to ${AWS_S3_BUCKET}/${AWS_S3_BUCKET_PATH} ..."
        s3sync up
    fi
}

restore() {
    [ -n "$1" ] || bail "No GPG file specified"
    [[ "$1" =~ \.gpg$ ]] || bail "Given file does not have '.gpg' extension"

    # destination/encrypted-path must be a directory and be readable and searchable
    test_all drx "${ENCRYPTED_PATH}" ||
        bail "Cannot read from encrypted-path (ENCRYPTED_PATH='${ENCRYPTED_PATH}' $(stat -c %A "${ENCRYPTED_PATH}"))"
    # source-path to which the file is restored, must be a directory and be writable and searchable
    test_all drwx "${SOURCE_PATH}" ||
        bail "Cannot write to source-path (SOURCE_PATH='$SOURCE_PATH' $(stat -c %A "${SOURCE_PATH}"))"

    local gpg_file="$ENCRYPTED_PATH/$1"

    # make sure we can proceed before syncing and decrypting
    local plain_file_path="${SOURCE_PATH}/$(basename "${gpg_file%%.gpg}")";
    bail_file_exists "$plain_file_path"

    if file_not_exists "$gpg_file"; then
        if s3sync is_enabled; then
            # Inorder for sync-down to work, the encrypted path must be writable
            [ -w "${ENCRYPTED_PATH}" ] ||
                bail "Cannot write to encrypted-path (ENCRYPTED_PATH='${ENCRYPTED_PATH}' $(stat -c %A "${ENCRYPTED_PATH}"))"

            debug "Syncing down from ${AWS_S3_BUCKET}/${AWS_S3_BUCKET_PATH} ... $*"
            s3sync down "$@"

            if file_not_exists "$gpg_file"; then
                bail "Specified GPG file could not be found (after sync-down)"
            fi
        else
            bail "Specified GPG file could not be found (no sync attempted)"
        fi
    fi

    debug "Decrypting '$gpg_file'"
    gpg decrypt "$gpg_file" "${plain_file_path}"
}

list-backups() {
    # source-path must be a directory and be readable and searchable
    test_all drx "${SOURCE_PATH}" ||
        bail "Source path could not be found (SOURCE_PATH='$SOURCE_PATH' $(stat -c %A "${SOURCE_PATH}"))"
    # destination/encrypted-path must be a directory and be readable and searchable
    test_all drx "${ENCRYPTED_PATH}" ||
        bail "Encrypted path could not be found (ENCRYPTED_PATH='${ENCRYPTED_PATH}' $(stat -c %A "${ENCRYPTED_PATH}"))"

    local batch_mode=$([[ "$1" = "--batch-mode" ]] && echo true || echo false)
    local files_in_s3=();
    if s3sync is_enabled; then
        files_in_s3=( $(s3sync list) )
    fi
    local files_local=( $(find "$ENCRYPTED_PATH" -type f -printf "%f\n") );

    in_s3() {
        in_array "$1" "${files_in_s3[@]}" && echo " [s3]"
    }

    in_local() {
        in_array "$1" "${files_local[@]}" && echo " [local]"
    }

    # get a list of all files, with no duplicates
    local all_files=( $(for file in "${files_in_s3[@]}" "${files_local[@]}"; do echo "$file"; done | sort | uniq) )

    local file;
    for file in "${all_files[@]}"; do
        if $batch_mode; then
            # print just the file name; no frills
            echo "$file"
        else
            # print status for each file
            echo "$file$(in_s3 "$file")$(in_local "$file")"
        fi
    done
}

# Quit if the AWS S3 config values are improperly specified
s3sync is_enabled || info "AWS S3 sync not enabled"

info "SOURCE_PATH: '$SOURCE_PATH' $(stat -c %A "${SOURCE_PATH}")"
info "ENCRYPTED_PATH: '$ENCRYPTED_PATH' $(stat -c %A "${ENCRYPTED_PATH}")"

cmd="$1"; shift
case "$cmd" in
    backup|restore|list-backups)
        $cmd "$@"
        ;;

    *)
        bail "entrypoint: Invalid invocation"
        ;;
esac
