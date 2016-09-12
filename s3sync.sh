#!/bin/bash

check_command s3cmd
check_command awk

: ${AWS_ACCESS_KEY:=}
: ${AWS_SECRET_KEY:=}
: ${AWS_S3_BUCKET:=}
: ${AWS_S3_BUCKET_PATH:=}

s3sync() {
    is_enabled() {
        # if any AWS S3 tingz are set, then they all should be set
        if [ -n "${AWS_ACCESS_KEY}${AWS_SECRET_KEY}${AWS_S3_BUCKET}" ]; then
            if [ -z "${AWS_ACCESS_KEY}" -o -z "${AWS_SECRET_KEY}" -o -z "${AWS_S3_BUCKET}" ]; then
                bail "s3sync: Not all AWS S3 config values are specified"
            fi
            return 0;
        fi
        
        return 1;
    }

    init() {
        sed "s~{{AWS_ACCESS_KEY}}~${AWS_ACCESS_KEY}~g; s~{{AWS_SECRET_KEY}}~${AWS_SECRET_KEY}~g;" /app/s3cfg.ini.tpl > /app/s3cfg.ini

        if [ -n "${AWS_S3_BUCKET_PATH}" ]; then
            AWS_S3_BUCKET_PATH=$(readlink -m "/${AWS_S3_BUCKET_PATH}/")
        fi
    }

    up() {
        init
        s3cmd --config=/app/s3cfg.ini sync $ENCRYPTED_PATH/ s3://${AWS_S3_BUCKET}${AWS_S3_BUCKET_PATH}/
    }

    down() {
        init
        if [ "$#" -gt 0 ]; then
            for item in "$@"; do
                if [ -e "$ENCRYPTED_PATH/$item" ]; then
                    debug "$ENCRYPTED_PATH/$item already exists; not downloading from S3"
                else
                    s3cmd --config=/app/s3cfg.ini get s3://${AWS_S3_BUCKET}${AWS_S3_BUCKET_PATH}/$item $ENCRYPTED_PATH/$item
                fi
            done
        else
            s3cmd --config=/app/s3cfg.ini sync s3://${AWS_S3_BUCKET}${AWS_S3_BUCKET_PATH}/ $ENCRYPTED_PATH/
        fi
    }

    list() {
        init
        s3cmd --config=/app/s3cfg.ini ls s3://${AWS_S3_BUCKET}${AWS_S3_BUCKET_PATH}/ | \
            awk -F ${AWS_S3_BUCKET_PATH}/ '{print $NF}'
    }

    cmd="$1"; shift
    case "$cmd" in
        up|down|list|is_enabled)
            $cmd "$@"
            ;;

        *)
            bail "s3sync: Invalid invocation"
            ;;
    esac
}
