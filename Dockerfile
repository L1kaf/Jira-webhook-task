FROM nginx:alpine

# Устанавливаем зависимости
RUN apk add --no-cache bash jq perl fcgiwrap 

# Копируем конфиг Nginx
COPY nginx/nginx.conf /etc/nginx/nginx.conf

# Копируем скрипты
COPY ./scripts /scripts

# Делаем скрипты исполняемыми
RUN chmod +x /scripts/*.sh

# Запускаем сервисы
CMD ["sh", "-c", "/scripts/entrypoint.sh"]
