#!/bin/bash

check_command s3cmd

: ${AWS_ACCESS_KEY:?"AWS Access key not specified (AWS_ACCESS_KEY)"}
: ${AWS_SECRET_KEY:?"AWS Secret key not specified (AWS_SECRET_KEY)"}
: ${AWS_S3_BUCKET:?"AWS Bucket name not specified (AWS_S3_BUCKET)"}
: ${AWS_S3_BUCKET_PATH:=}

s3sync() {
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

    cmd="$1"; shift
    case "$cmd" in
        up|down)
            $cmd "$@"
            ;;

        *)
            bail "s3sync: Invalid invocation"
            ;;
    esac
}
