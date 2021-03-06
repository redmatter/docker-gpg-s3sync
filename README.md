# Docker Container for GPG+S3Sync

This is the source for [`redmatter/gpg-s3sync`](https://hub.docker.com/r/redmatter/gpg-s3sync) docker image.

## What does it do?

Provides a script that would GPG encrypt files from one directory and place it into another. Then the S3 sync
functionality would sync it up to a configured AWS S3 bucket (with an optional path prefix).

## How to run it?

The image is designed to be run as a "one-shot" command on a cron / systemd-timer. The below command would encrypt and
sync to AWS S3.

    docker run \
        -v /path/to/plain-files-dir:/data/plain \
        -v /path/to/encrypted-files-dir:/data/encrypted \
        -e SOURCE_FILE_PATTERN='*.zip' \
        -e SOURCE_REMOVE_PLAIN=1 \
        -e GPG_PASSPHRASE=xxxx-PASSWORD-xxxx \
        -e AWS_ACCESS_KEY=__AWS_ACCESS_KEY__ \
        -e AWS_SECRET_KEY=__AWS_SECRET_KEY__ \
        -e AWS_S3_BUCKET=__AWS_S3_BUCKET__ \
        -e AWS_S3_BUCKET_PATH=__AWS_S3_BUCKET_PATH__ \
        redmatter/gpg-s3sync

To restore a file from AWS S3, you need to run the below command.

    docker run \
        -v /path/to/plain-files-dir:/data/plain \
        -v /path/to/encrypted-files-dir:/data/encrypted \
        -e GPG_PASSPHRASE=xxxx-PASSWORD-xxxx \
        -e AWS_ACCESS_KEY=__AWS_ACCESS_KEY__ \
        -e AWS_SECRET_KEY=__AWS_SECRET_KEY__ \
        -e AWS_S3_BUCKET=__AWS_S3_BUCKET__ \
        -e AWS_S3_BUCKET_PATH=__AWS_S3_BUCKET_PATH__ \
        redmatter/gpg-s3sync restore file-name.zip.gpg

## Supported environment variables

* `SOURCE_FILE_PATTERN`

  Shell pattern to select specific files.

* `SOURCE_FILE_MODIFIED_MINUTES_AGO` (default `30`)

  Specify number of minutes to lapse, before it is picked up by the container for encryption and sync. Tune this value
  based on how long it takes for the file to get created (for example, a TAR backup of an entire git repo might take a
  long time).

* `SOURCE_REMOVE_PLAIN` (default `0`)

  Set to 1, if plain copy of files are to be removed after encryption.

* `GPG_PASSPHRASE`

  Passphrase to be used for encrypting files, before uploading to AWS S3.

* `AWS_S3_BUCKET`

  AWS S3 bucket to which data is to be uploaded.

* `AWS_ACCESS_KEY`

  AWS S3 bucket access key.

* `AWS_SECRET_KEY`

  AWS S3 bucket secret key.

* `AWS_S3_BUCKET_PATH` (optional)

  Path within AWS S3 bucket into which the files are to be put.

* `SYSLOG_TAG` (optional)

  Set to the name to be used in syslog as tag; if set, logging will go to syslog rather than console.

* `SYSLOG_FACILITY` (default `local0`)

  Syslog facility to which logs must go (only applicable if SYSLOG_TAG is set).

* `DEBUG` (default `0`)

  Set to `1` if you want to see a step-by-step bash debug, as commands are executed within the script.

* `LOG_DEBUG` (default `0`)

  Set to `1` if debug lines are to be logged (to console or syslog)

## Config file

The above environment variables can be defined in a file and be mounted in as shown in the below example. The path has
to be `/app/settings.env` within the container.

    # settings.env
    SOURCE_FILE_PATTERN='*.zip'
    SOURCE_REMOVE_PLAIN=1
    GPG_PASSPHRASE=xxxx-PASSWORD-xxxx
    AWS_ACCESS_KEY=__AWS_ACCESS_KEY__
    AWS_SECRET_KEY=__AWS_SECRET_KEY__
    AWS_S3_BUCKET=__AWS_S3_BUCKET__
    AWS_S3_BUCKET_PATH=__AWS_S3_BUCKET_PATH__

Docker commands can be as below.

    docker run \
        -v /path/to/settings.env:/app/settings.env \
        -v /path/to/plain-files-dir:/data/plain \
        -v /path/to/encrypted-files-dir:/data/encrypted \
        redmatter/gpg-s3sync

    docker run \
        -v /path/to/settings.env:/app/settings.env \
        -v /path/to/plain-files-dir:/data/plain \
        -v /path/to/encrypted-files-dir:/data/encrypted \
        redmatter/gpg-s3sync restore file-name.zip.gpg

## Tests

Tests are setup to work with docker-hub. If you would like to run these tests, you need to install docker-compose and
run the below command.

```
docker-compose -f docker-compose.test.yml run sut
```

If you would like to run a full test involving an AWS-S3 endpoint, you can do so by specifying the details via
environment variables `ACCESS_KEY`, `SECRET_KEY` & `BUCKET`. More debug can be obtained by specifying `DEBUG=1`. See
example usage below.

```
DEBUG=1 ACCESS_KEY=aws-access-key SECRET_KEY='aws-secret-key' BUCKET=aws-s3-bucket \
      docker-compose -f docker-compose.test.yml run sut
```

## License

This code is licensed under MIT license. See [LICENSE](LICENSE) for more details.
