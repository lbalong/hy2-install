#!/bin/bash

set -e

echo "======================================"
echo " Sing-box + Cloudflare 一键完整节点"
echo "======================================"

read -p "请输入域名: " DOMAIN
read -p "请输入端口(默认8443): " PORT
PORT=${PORT:-8443}

read -p "请输入WS路径(默认/ray): " PATH
PATH=${PATH:-/ray}

read -p "是否开启Cloudflare防直扫(1=开 0=关 默认1): " LOCK
LOCK=${LOCK:-1}

UUID=$(cat /proc/sys/kernel/random/uuid)

echo ""
echo "安装依赖..."
apt update -y
apt install -y curl wget socat unzip tar cron iptables-persistent

echo ""
echo "安装 sing-box..."
bash <(curl -fsSL https://sing-box.app/deb-install.sh)

mkdir -p /root/cert
mkdir -p /etc/sing-box

echo ""
echo "安装 acme..."
curl https://get.acme.sh | sh
source ~/.bashrc || true

systemctl stop nginx 2>/dev/null || true
systemctl stop apache2 2>/dev/null || true

echo ""
echo "申请证书..."
~/.acme.sh/acme.sh --issue -d $DOMAIN --standalone --keylength ec-256 --force

~/.acme.sh/acme.sh --install-cert -d $DOMAIN \
--ecc \
--fullchain-file /root/cert/fullchain.cer \
--key-file /root/cert/private.key

echo ""
echo "写入 sing-box 配置..."
cat > /etc/sing-box/config.json <<EOF
{
  "log": { "level": "info" },
  "inbounds": [
    {
      "type": "vless",
      "listen": "::",
      "listen_port": $PORT,
      "users": [
        { "uuid": "$UUID" }
      ],
      "transport": {
        "type": "ws",
        "path": "$PATH"
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
    { "type": "direct" }
  ]
}
EOF

echo ""
echo "启动 sing-box..."
systemctl restart sing-box
systemctl enable sing-box

sleep 2

STATUS=$(systemctl is-active sing-box)

ENCODED_PATH=$(printf '%s' "$PATH" | sed 's/\//%2F/g')

LINK="vless://${UUID}@${DOMAIN}:${PORT}?encryption=none&security=tls&type=ws&host=${DOMAIN}&path=${ENCODED_PATH}#singbox"

echo ""
echo "======================================"
echo " 状态: $STATUS"
echo "======================================"
echo ""
echo "节点链接:"
echo "$LINK"
echo ""

# ===== 防直扫（可选） =====
if [ "$LOCK" = "1" ]; then

    echo ""
    echo "启用 Cloudflare 白名单防护..."

    CF_V4=$(curl -s https://www.cloudflare.com/ips-v4)

    iptables -F
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT ACCEPT

    iptables -A INPUT -i lo -j ACCEPT
    iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    iptables -A INPUT -p tcp --dport 22 -j ACCEPT

    for ip in $CF_V4; do
        iptables -A INPUT -p tcp -s $ip --dport $PORT -j ACCEPT
    done

    netfilter-persistent save

    echo "防直扫已开启"
fi

echo ""
echo "======================================"
echo " 完成"
echo "======================================"
