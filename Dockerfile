# syntax=docker/dockerfile:1

# lockrot in a container: the released lockrot.phar, verified against its published sha256, on the
# official PHP CLI image with everything a CLI-only analysis never needs removed and the result
# flattened into a single layer. Build arguments come from lockrot.env:
#
#   docker build --build-arg LOCKROT_VERSION=0.2.1 --build-arg LOCKROT_SHA256=<hex> -t lockrot .
#
# The base is pinned by digest on every FROM line; Dependabot proposes digest updates
# (.github/dependabot.yml). The three lines must name the same image.

# --- stage 1: fetch and verify the archive ------------------------------------------------------
FROM php:8.4-cli-alpine@sha256:2f389f933c3cc58cc622bd243bb4ecff7e6553e2de4387a239bca640c988be19 AS download
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]
ARG LOCKROT_VERSION
ARG LOCKROT_SHA256
RUN set -eu; \
    if [ -z "${LOCKROT_VERSION}" ] || [ -z "${LOCKROT_SHA256}" ]; then \
        echo 'build with --build-arg LOCKROT_VERSION=<version> --build-arg LOCKROT_SHA256=<hex>, both from lockrot.env' >&2; \
        exit 1; \
    fi; \
    wget -q -O /lockrot "https://github.com/somework/lockrot/releases/download/v${LOCKROT_VERSION}/lockrot.phar"; \
    echo "${LOCKROT_SHA256}  /lockrot" | sha256sum -c -; \
    chmod 0555 /lockrot; \
    php /lockrot --version | grep -Fx "lockrot ${LOCKROT_VERSION}"

# --- stage 2: prune the runtime -------------------------------------------------------------------
# Kept: the php binary, its shared extensions, the ini directory, busybox and the libraries PHP
# links against (ca-certificates included, for HTTPS). Removed: the PHP source tarball, headers,
# PEAR, php-cgi and phpdbg, the extension build helpers, and the curl/tar/xz/openssl command-line
# tools the base image carries for building extensions.
FROM php:8.4-cli-alpine@sha256:2f389f933c3cc58cc622bd243bb4ecff7e6553e2de4387a239bca640c988be19 AS runtime
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]
RUN set -eux; \
    apk del --no-network curl tar xz openssl; \
    rm -rf /usr/src/php* /usr/local/include /usr/local/php \
        /usr/local/bin/php-cgi /usr/local/bin/phpdbg /usr/local/bin/pear /usr/local/bin/peardev \
        /usr/local/bin/pecl /usr/local/bin/phpize /usr/local/bin/php-config /usr/local/bin/phar \
        /usr/local/bin/phar.phar /usr/local/bin/docker-php-* \
        /var/cache/apk/* /var/www; \
    find /usr/local/lib/php -mindepth 1 -maxdepth 1 ! -name extensions -exec rm -rf {} +; \
    adduser -u 65532 -S -D -H -h /nonexistent -s /sbin/nologin -g lockrot lockrot; \
    mkdir -p /app; \
    php -m > /dev/null

# --- stage 3: one layer, no build history ---------------------------------------------------------
# Copying the pruned tree into an empty image is what makes the removals above count: a layer on
# top of the base would only hide the files, and every pull would still fetch them. 16 MB against
# the base image's 44 MB.
FROM scratch
ARG LOCKROT_VERSION
COPY --from=runtime / /
COPY --from=download /lockrot /usr/local/bin/lockrot

ENV PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    PHP_INI_DIR=/usr/local/etc/php \
    COMPOSER_HOME=/tmp/composer \
    COMPOSER_NO_INTERACTION=1

LABEL org.opencontainers.image.title="lockrot" \
      org.opencontainers.image.description="Finds abandoned, unmaintained and branch-pinned packages in composer.lock." \
      org.opencontainers.image.version="${LOCKROT_VERSION}" \
      org.opencontainers.image.url="https://lockrot.dev" \
      org.opencontainers.image.documentation="https://github.com/somework/lockrot-action#docker-image" \
      org.opencontainers.image.source="https://github.com/somework/lockrot-action" \
      org.opencontainers.image.vendor="somework" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.base.name="docker.io/library/php:8.4-cli-alpine"

# Numeric so `runAsNonRoot` checks can verify it. COMPOSER_HOME under /tmp means any other
# `--user` works too: Composer's metadata cache and lockrot's GitHub cache land there.
USER 65532:65532
WORKDIR /app
ENTRYPOINT ["lockrot"]
