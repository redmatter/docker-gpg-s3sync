#!/bin/bash

exec 1>&2

# die on failure
set -e

source /app/functions.sh
source /app/gpgcrypt.sh
source /app/s3sync.sh

load_settings_file
set_debug

: ${SOURCE_REMOVE_PLAIN:=0}
: ${SOURCE_FILE_PATTERN:=}
: ${SOURCE_FILE_MODIFIED_MINUTES_AGO:=30}
: ${SOURCE_PATH:=/data/plain}
: ${ENCRYPTED_PATH:=/data/encrypted}

is_aws_s3_enabled() {
    [ -n "${AWS_ACCESS_KEY}${AWS_SECRET_KEY}" ]
}

backup() {
    in_array() {
        local haystack=${1}[@]
        local needle=${2}
        for i in ${!haystack}; do
            [[ ${i} == ${needle} ]] && return 0
        done

        return 1
    }

    local all_backups=( $(list-backups --batch-mode) )

    find_opts=($SOURCE_PATH)
    find_opts+=(-mindepth 1)
    find_opts+=(-maxdepth 1)
    find_opts+=(-type f)
    [ -z "$SOURCE_FILE_PATTERN" ] || \
        find_opts+=(-name "$SOURCE_FILE_PATTERN")
    if is_number "$SOURCE_FILE_MODIFIED_MINUTES_AGO" && [ $SOURCE_FILE_MODIFIED_MINUTES_AGO -gt 0 ]; then
        find_opts+=(-mmin +$SOURCE_FILE_MODIFIED_MINUTES_AGO)
    fi

    find "${find_opts[@]}" | while read file; do
        # If file is already present either in ENCRYPTED_PATH or in S3 bucket, skip it
        if ! in_array all_backups "${file}.gpg"; then
            debug "$file already backed up; skipping"
            continue;
        fi

        debug "Encrypting $file"
        gpg encrypt $file

        local local_path="${ENCRYPTED_PATH}/$(basename "${file}.gpg")";
        if [ "$(readlink -f "${file}.gpg")" != "$(readlink -f "${local_path}")" ]; then
            debug "Moving ${file}.gpg to $ENCRYPTED_PATH"
            mv ${file}.gpg $ENCRYPTED_PATH/.
        fi

        if [ "0$SOURCE_REMOVE_PLAIN" -eq 1 ] &>/dev/null; then
            debug "Removing ${file}"
            rm $file
        fi
    done

    if ! is_aws_s3_enabled; then
        info "AWS_ACCESS_KEY and AWS_SECRET_KEY not defined; NOT syncing to Amazon S3"
    else
        debug "Syncing up to ${AWS_S3_BUCKET}/${AWS_S3_BUCKET_PATH} ..."
        s3sync up
    fi
}

restore() {
    [ -n "$1" ] || bail "No GPG file specified"
    [[ "$1" =~ \.gpg$ ]] || bail "Given file does not have '.gpg' extension"

    local gpg_file="$ENCRYPTED_PATH/$1"
    if file_not_exists "$gpg_file"; then
        if is_aws_s3_enabled; then
            debug "Syncing down from ${AWS_S3_BUCKET}/${AWS_S3_BUCKET_PATH} ..."
            s3sync down

            if file_not_exists "$gpg_file"; then
                bail "Specified GPG file could not be found (after sync-down)"
            fi
        else
            bail "Specified GPG file could not be found (no sync attempted)"
        fi
    fi

    debug "Decrypting $gpg_file"
    gpg decrypt "$gpg_file"

    local plain_file_path="${SOURCE_PATH}/$(basename "${gpg_file%%.gpg}")";
    bail_file_exists "$plain_file_path"

    debug "Moving ${gpg_file%%.gpg} to ${plain_file_path}"
    mkdir -p "${SOURCE_PATH}" || bail "Couldn't create plain file destination directory (${SOURCE_PATH})"
    mv "${gpg_file%%.gpg}" "${plain_file_path}"
}

list-backups() {
    local batch_mode=$([[ "$1" = "--batch-mode" ]] && echo true || echo false)
    local files_in_s3=();
    if is_aws_s3_enabled; then
        files_in_s3=( $(s3sync list) )
    fi
    local files_local=( $(find $ENCRYPTED_PATH -type f -printf "%f\n") );

    in_array() {
        local haystack=${1}[@]
        local needle=${2}
        for i in ${!haystack}; do
            [[ ${i} == ${needle} ]] && return 0
        done

        return 1
    }

    in_s3() {
        in_array files_in_s3 "$1" && echo " [s3]"
    }

    in_local() {
        in_array files_local "$1" && echo " [local]"
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

cmd="$1"; shift
case "$cmd" in
    backup|restore|list-backups)
        $cmd "$@"
        ;;

    *)
        bail "entrypoint: Invalid invocation"
        ;;
esac
