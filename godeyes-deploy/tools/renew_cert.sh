#! /bin/bash

certbot renew  --webroot -w /opt/godeyes/nginx/www/

cp /etc/letsencrypt/live/portal.godeyes.vn/* /opt/godeyes/nginx/certs/

cd /opt/godeyes/ && docker compose restart godeyes-nginx
