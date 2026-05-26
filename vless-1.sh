#!/bin/bash

set -e

echo "========================================"
echo " Sing-box + Cloudflare 完整部署（修正版）"
echo "========================================"
echo ""

# ====== 输入区域（修复重点） ======
read -p "请输入域名 (例如 jp1.099889.xyz): " DOMAIN
if [ -z "$DOMAIN" ]; then
  echo "域名不能为空"
  exit 1
fi

read -p "请输入端口 (默认 8443): " PORT
PORT=${PORT:-8443}

read -p "请输入WS路径 (默认 /ray): " WSPATH
WSPATH=${WSPATH:-/ray}

read -p "是否开启防直扫模式 (1=开启 / 0=关闭，默认1): " LOCK
LOCK=${LOCK:-1}

echo ""
echo "========== 输入确认 =========="
echo "域名: $DOMAIN"
echo "端口: $PORT"
echo "WS路径: $WSPATH"
echo "防直扫: $LOCK"
echo "==============================="
echo ""

UUID=$(cat /proc/sys/kernel/random/uuid)

# ====== 安装依赖 ======
apt update -y
apt install -y curl wget socat cron unzip tar openssl ufw iptables-persistent

# ====== 停旧服务 ======
systemctl stop sing-box 2>/dev/null || true

# ====== 安装 sing-box ======
bash <(curl -fsSL https://sing-box.app/deb-install.sh)

mkdir -p /root/cert
mkdir -p /etc/sing-box

# ====== acme ======
curl https://get.acme.sh | sh
source ~/.bashrc || true

systemctl stop nginx 2>/dev/null || true
systemctl stop apache2 2>/dev/null || true

# ====== 证书 ======
~/.acme.sh/acme.sh --issue -d $DOMAIN --standalone --keylength ec-256 --force

~/.acme.sh/acme.sh --install-cert -d $DOMAIN \
--ecc \
--fullchain-file /root/cert/fullchain.cer \
--key-file /root/cert/private.key

# ====== sing-box 配置 ======
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

# ====== BBR ======
grep -q "bbr" /etc/sysctl.conf || cat >> /etc/sysctl.conf <<EOF

net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF

sysctl -p

# ====== 防火墙基础 ======
ufw allow $PORT/tcp 2>/dev/null || true

systemctl daemon-reload
systemctl enable sing-box
systemctl restart sing-box

sleep 3

STATUS=$(systemctl is-active sing-box)

# ====== 节点链接 ======
ENCODED_PATH=$(printf '%s' "$WSPATH" | sed 's/\//%2F/g')

LINK="vless://${UUID}@${DOMAIN}:${PORT}?encryption=none&security=tls&type=ws&host=${DOMAIN}&path=${ENCODED_PATH}#CF-WS"

echo ""
echo "========================================"
echo " sing-box 状态: $STATUS"
echo "========================================"
echo ""
echo "节点链接:"
echo "$LINK"
echo ""

# ====== 防直扫 ======
if [ "$LOCK" = "1" ]; then

    echo ""
    echo "启用 Cloudflare 防直扫..."

    CF_V4=$(curl -s https://www.cloudflare.com/ips-v4)
    CF_V6=$(curl -s https://www.cloudflare.com/ips-v6)

    iptables -F
    iptables -X
    ip6tables -F
    ip6tables -X

    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT ACCEPT

    ip6tables -P INPUT DROP
    ip6tables -P FORWARD DROP
    ip6tables -P OUTPUT ACCEPT

    iptables -A INPUT -i lo -j ACCEPT
    iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

    ip6tables -A INPUT -i lo -j ACCEPT
    ip6tables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

    iptables -A INPUT -p tcp --dport 22 -j ACCEPT
    ip6tables -A INPUT -p tcp --dport 22 -j ACCEPT

    for ip in $CF_V4; do
        iptables -A INPUT -p tcp -s $ip --dport $PORT -j ACCEPT
    done

    for ip in $CF_V6; do
        ip6tables -A INPUT -p tcp -s $ip --dport $PORT -j ACCEPT
    done

    netfilter-persistent save

    echo "防直扫已启用"
fi

echo ""
echo "========================================"
echo " 部署完成"
echo "========================================"
