#!/bin/bash

set -e

clear

echo "================================="
echo " Cloudflare VLESS-WS-TLS 一键脚本"
echo "================================="
echo ""

read -p "请输入域名: " DOMAIN
read -p "请输入WS路径(例如/ray): " WSPATH

UUID=$(cat /proc/sys/kernel/random/uuid)

apt update -y
apt install -y curl wget socat cron unzip tar openssl ufw

# 安装 sing-box
bash <(curl -fsSL https://sing-box.app/deb-install.sh)

mkdir -p /root/cert

# 安装 acme.sh
curl https://get.acme.sh | sh

source ~/.bashrc || true

# 停止可能占用80端口的服务
systemctl stop nginx 2>/dev/null || true
systemctl stop apache2 2>/dev/null || true

# 申请证书
~/.acme.sh/acme.sh --issue -d $DOMAIN --standalone --keylength ec-256

# 安装证书
~/.acme.sh/acme.sh --install-cert -d $DOMAIN \
--ecc \
--fullchain-file /root/cert/fullchain.cer \
--key-file /root/cert/private.key

mkdir -p /etc/sing-box

cat > /etc/sing-box/config.json <<EOF
{
  "log": {
    "level": "info"
  },
  "inbounds": [
    {
      "type": "vless",
      "listen": "::",
      "listen_port": 443,
      "users": [
        {
          "uuid": "$UUID"
        }
      ],
      "transport": {
        "type": "ws",
        "path": "$WSPATH"
      },
      "tls": {
        "enabled": true,
        "server_name": "$DOMAIN",
        "certificate_path": "/root/cert/fullchain.cer",
        "key_path": "/root/cert/private.key"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct"
    }
  ]
}
EOF

# 开启BBR
cat >> /etc/sysctl.conf <<EOF

net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF

sysctl -p

# 防火墙
ufw allow 443/tcp || true

systemctl enable sing-box
systemctl restart sing-box

ENCODED_PATH=$(printf '%s' "$WSPATH" | sed 's/\//%2F/g')

LINK="vless://${UUID}@${DOMAIN}:443?encryption=none&security=tls&type=ws&host=${DOMAIN}&path=${ENCODED_PATH}#CF-WS"

clear

echo "================================="
echo " 安装完成"
echo "================================="
echo ""
echo "节点链接："
echo ""
echo "$LINK"
echo ""
echo "================================="
echo ""
echo "Cloudflare 必须："
echo ""
echo "1. 小云朵开启橙色"
echo "2. SSL模式选择 Full"
echo ""
echo "否则节点无法使用"
echo ""
