#!/bin/bash

set -e

clear

echo "===================================="
echo " Cloudflare VLESS-WS-TLS 一键脚本"
echo "===================================="
echo ""

read -p "请输入域名: " DOMAIN
read -p "请输入WS路径(默认 /ray): " WSPATH_INPUT
read -p "请输入端口(默认 8443): " PORT_INPUT

# 默认值处理
WSPATH=${WSPATH_INPUT:-/ray}
PORT=${PORT_INPUT:-8443}

UUID=$(cat /proc/sys/kernel/random/uuid)

echo ""
echo "安装依赖..."
echo ""

apt update -y
apt install -y curl wget socat cron unzip tar openssl ufw

echo ""
echo "停止旧 sing-box..."
echo ""

systemctl stop sing-box 2>/dev/null || true

echo ""
echo "安装 sing-box..."
echo ""

bash <(curl -fsSL https://sing-box.app/deb-install.sh)

mkdir -p /root/cert
mkdir -p /etc/sing-box

echo ""
echo "安装 acme.sh..."
echo ""

curl https://get.acme.sh | sh
source ~/.bashrc || true

echo ""
echo "关闭占用80端口服务..."
echo ""

systemctl stop nginx 2>/dev/null || true
systemctl stop apache2 2>/dev/null || true

echo ""
echo "申请证书..."
echo ""

~/.acme.sh/acme.sh --issue -d $DOMAIN --standalone --keylength ec-256 --force

echo ""
echo "安装证书..."
echo ""

~/.acme.sh/acme.sh --install-cert -d $DOMAIN \
--ecc \
--fullchain-file /root/cert/fullchain.cer \
--key-file /root/cert/private.key

echo ""
echo "写入配置..."
echo ""

cat > /etc/sing-box/config.json <<EOF
{
  "log": {
    "level": "info"
  },
  "inbounds": [
    {
      "type": "vless",
      "listen": "::",
      "listen_port": $PORT,
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

echo ""
echo "开启BBR..."
echo ""

grep -q "tcp_congestion_control=bbr" /etc/sysctl.conf || cat >> /etc/sysctl.conf <<EOF

net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF

sysctl -p

echo ""
echo "开放端口..."
echo ""

ufw allow $PORT/tcp 2>/dev/null || true

echo ""
echo "重启 sing-box..."
echo ""

systemctl daemon-reload
systemctl enable sing-box
systemctl restart sing-box

sleep 3

STATUS=$(systemctl is-active sing-box)

ENCODED_PATH=$(printf '%s' "$WSPATH" | sed 's/\//%2F/g')

LINK="vless://${UUID}@${DOMAIN}:${PORT}?encryption=none&security=tls&type=ws&host=${DOMAIN}&path=${ENCODED_PATH}#CF-WS"

echo ""
echo "===================================="
echo " 部署完成"
echo "===================================="
echo ""
echo "状态: $STATUS"
echo ""
echo "节点链接:"
echo ""
echo "$LINK"
echo ""
echo "===================================="
echo ""
echo "Cloudflare设置："
echo ""
echo "1. 小云朵必须橙色"
echo "2. SSL模式必须 Full / Full(strict)"
echo ""
echo "推荐端口：8443 / 2053 / 2083 / 2087"
echo ""
