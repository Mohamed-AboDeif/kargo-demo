#!/bin/sh
set -e
# Render the page into a writable directory under /tmp. /tmp is always
# writable by the unprivileged user, both under Kubernetes emptyDir and
# Docker --tmpfs, regardless of volume ownership.
# shellcheck disable=SC2016
mkdir -p /tmp/html
envsubst '${STAGE_NAME} ${APP_VERSION} ${HOSTNAME}' \
  < /opt/index.html.template \
  > /tmp/html/index.html
exec nginx -g 'daemon off;'
