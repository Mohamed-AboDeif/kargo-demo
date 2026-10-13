FROM nginx:1.27-alpine
COPY index.html /usr/share/nginx/html/index.html.template
COPY start.sh /start.sh
RUN chmod +x /start.sh
EXPOSE 80
CMD ["/start.sh"]
