FROM nginx:1.27-alpine

RUN apk add --no-cache openssl \
    && mkdir -p /etc/nginx/ssl \
    && openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
         -keyout /etc/nginx/ssl/nginx.key \
         -out    /etc/nginx/ssl/nginx.crt \
         -subj   "/C=RU/ST=Moscow/L=Moscow/O=Blog/CN=contextbot.ru"
