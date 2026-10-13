#!/bin/sh
envsubst '${STAGE_NAME} ${APP_VERSION} ${HOSTNAME}' \
  < /usr/share/nginx/html/index.html.template \
  > /usr/share/nginx/html/index.html
exec nginx -g 'daemon off;'
