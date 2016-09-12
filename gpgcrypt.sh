#!/bin/bash

: ${GPG_BIN:=/usr/bin/gpg}

check_command ${GPG_BIN}

gpg() {
    check_encryption_options() {
        if [[ -z ${GPG_PASSPHRASE} ]]; then
            bail "In order to encrypt files, you must set the 'GPG_PASSPHRASE' configuration variable"
        fi
    }

    encrypt() {
        check_encryption_options

        local path="$1"; shift
        local gpg_path
        if [ -z "$1" ]; then
            gpg_path="${path}.gpg";
            debug "encrypt: Destination path not specified; encrypting to '$gpg_path'"
        elif [ -d "$1" ]; then
            gpg_path="$1/$(basename "$gpg_path")"; shift
            debug "encrypt: Destination path is a directory; encrypting to '$gpg_path'"
        else
            gpg_path="$1"; shift
        fi

        bail_file_not_exists "$path"
        bail_file_exists "$gpg_path"

        info "encrypt: Encrypting $path into $gpg_path"
        $GPG_BIN --quiet --cipher-algo AES256 --symmetric --no-tty --passphrase-file <(echo -n "${GPG_PASSPHRASE}") \
            --output "$gpg_path" "$path"
    }

    decrypt() {
        check_encryption_options

        local gpg_path="$1"; shift
        local path
        if [ -z "$1" ]; then
            if [[ "$gpg_path" =~ \.gpg$ ]]; then
                path="${gpg_path%%.gpg}"
                debug "decrypt: Destination path not specified; decrypting to '$path'"
            else
                bail "decrypt: decrypted-output-file not specified and could not be figured out"
            fi
        elif [ -d "$1" ]; then
            if [[ "$gpg_path" =~ \.gpg$ ]]; then
                path="$1/$(basename "${gpg_path%%.gpg}")"
                debug "decrypt: Destination path is a directory; decrypting to '$path'"
            else
                bail "decrypt: decrypted-output-file specified is a directory; could not figure out the file name"
            fi
        else
            path="$1"; shift
        fi

        bail_file_not_exists "$gpg_path"
        bail_file_exists "$path"

        info "decrypt: Decrypting $gpg_path into $path"
        $GPG_BIN --quiet --decrypt --no-tty --passphrase-file <(echo -n "${GPG_PASSPHRASE}") \
            --output "$path" "$gpg_path"
    }

    cmd="$1"; shift
    case "$cmd" in
        encrypt|decrypt)
            $cmd "$@"
            ;;

        *)
            bail "gpgcrypt: Invalid invocation"
            ;;
    esac
}
