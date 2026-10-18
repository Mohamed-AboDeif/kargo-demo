# Unprivileged nginx: runs as UID 101, listens on 8080, no root required.
FROM nginxinc/nginx-unprivileged:1.27-alpine

# nginx-unprivileged already defines USER 101. Switch to root only to copy
# files and set permissions, then drop back to the non-root user.
USER root
# Patch OS packages so the image does not ship known-fixed CVEs from the
# base image's package set.
RUN apk upgrade --no-cache

# Bake the template outside the html dir; it is rendered to /tmp/html at
# startup so the content survives a read-only root filesystem.
COPY index.html /opt/index.html.template
COPY start.sh /start.sh
# Serve from /tmp/html on port 8080 (see default.conf).
COPY default.conf /etc/nginx/conf.d/default.conf
# Ensure the unprivileged user can read the config and execute the script
# under a read-only root filesystem.
RUN chmod +x /start.sh \
  && chmod 0644 /etc/nginx/conf.d/default.conf \
  && chmod 0644 /opt/index.html.template

USER 101

EXPOSE 8080
CMD ["/start.sh"]
