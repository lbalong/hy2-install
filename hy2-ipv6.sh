#!/bin/bash

set -e

PASSWORD=$(openssl rand -base64 16)
PORT=8443

echo "Installing Hysteria2..."

bash <(curl -fsSL https://get.hy2.sh/)

mkdir -p /etc/hysteria

cat > /etc/hysteria/config.yaml <<EOF
listen: :${PORT}

tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key

auth:
  type: password
  password: ${PASSWORD}

masquerade:
  type: proxy
  proxy:
    url: https://www.cloudflare.com
    rewriteHost: true
EOF

openssl req -x509 -nodes -newkey rsa:2048 \
-keyout /etc/hysteria/server.key \
-out /etc/hysteria/server.crt \
-days 3650 \
-subj "/CN=bing.com"

systemctl enable hysteria-server
systemctl restart hysteria-server

IPV6=$(curl -6 -s https://api64.ipify.org)

echo
echo "=================================="
echo "IPv6 Address:"
echo "${IPV6}"
echo
echo "Password:"
echo "${PASSWORD}"
echo
echo "HY2 URI:"
echo "hysteria2://${PASSWORD}@[${IPV6}]:${PORT}/?insecure=1&sni=bing.com#HY2-IPv6"
echo "=================================="
