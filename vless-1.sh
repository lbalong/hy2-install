#!/bin/bash

set -e

clear

echo "===================================="
echo " Cloudflare VLESS-WS-TLS 一键脚本"
echo "===================================="
echo ""

read -p "请输入域名: " DOMAIN
read -p "请输入WS路径(例如/ray): " WSPATH

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
echo "安装官方 sing-box..."
echo ""

export DEBIAN_FRONTEND=noninteractive

bash <(curl -fsSL https://sing-box.app/deb-install.sh)

mkdir -p /root/cert
mkdir -p /etc/sing-box

echo ""
echo "安装 acme.sh..."
echo ""

curl https://get.acme.sh | sh

source ~/.bashrc || true

echo ""
echo "停止可能占用80端口的服务..."
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
echo "写入 sing-box 配置..."
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

echo ""
echo "开启 BBR..."
echo ""

grep -q "tcp_congestion_control=bbr" /etc/sysctl.conf || cat >> /etc/sysctl.conf <<EOF

net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF

sysctl -p

echo ""
echo "开放防火墙..."
echo ""

ufw allow 443/tcp 2>/dev/null || true

echo ""
echo "重启 sing-box..."
echo ""

systemctl daemon-reload
systemctl enable sing-box
systemctl restart sing-box

sleep 3

echo ""
echo "检测 sing-box 状态..."
echo ""

systemctl is-active --quiet sing-box && STATUS="运行成功" || STATUS="启动失败"

ENCODED_PATH=$(printf '%s' "$WSPATH" | sed 's/\//%2F/g')

LINK="vless://${UUID}@${DOMAIN}:443?encryption=none&security=tls&type=ws&host=${DOMAIN}&path=${ENCODED_PATH}#CF-WS"

echo ""
echo "===================================="
echo " 部署完成"
echo "===================================="
echo ""
echo "sing-box 状态: $STATUS"
echo ""
echo "节点链接:"
echo ""
echo "$LINK"
echo ""
echo "===================================="
echo ""
echo "Cloudflare 必须设置:"
echo ""
echo "1. 小云朵开启橙色"
echo "2. SSL/TLS 选择 Full"
echo ""
echo "否则节点无法使用"
echo ""
