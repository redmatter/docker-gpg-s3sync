FROM debian:jessie

ENV TZ="Europe/London" \
    SOURCE_PATH=/data/plain \
    ENCRYPTED_PATH=/data/encrypted \
    GNUPGHOME=/app/.gnupg

COPY * /app/

RUN ( \
    export DEBIAN_FRONTEND=noninteractive; \
    BUILD_DEPS=""; \
    APP_DEPS="ca-certificates s3cmd"; \

    # so that each command can be seen clearly in the build output
    set -e -x; \

    # update to pull package list from apt sources
    apt-get update; \
    apt-get install --no-install-recommends -y $BUILD_DEPS $APP_DEPS ; \

    for path in $SOURCE_PATH $ENCRYPTED_PATH $GNUPGHOME; do \
        mkdir -p $path && chmod go-rwx $path; \
    done; \

    # remove packages that we don't need
    apt-get remove -y $BUILD_DEPS ; \
    apt-get autoremove -y ; \
    apt-get clean; \
    rm -rf /var/lib/apt/ /var/lib/dpkg/ /var/lib/cache/ /var/lib/log/; \
)

WORKDIR /app

ENTRYPOINT [ "/app/entrypoint.sh" ]
CMD [ "backup" ]
