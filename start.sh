#!/bin/sh
# shellcheck disable=SC2016
envsubst '${STAGE_NAME} ${APP_VERSION} ${HOSTNAME}' \
  < /usr/share/nginx/html/index.html.template \
  > /usr/share/nginx/html/index.html
exec nginx -g 'daemon off;'
