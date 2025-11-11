#!/bin/sh

# Запускаем fcgiwrap в фоне
/usr/bin/fcgiwrap -s tcp:0.0.0.0:9000 &

# Запускаем Nginx
exec nginx -g "daemon off;"
