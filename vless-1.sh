#!/bin/bash

set -e

echo "========================================"
echo "  Sing-box + Cloudflare 完整一键部署"
echo "========================================"
echo ""

read -p "请输入域名 (如 jp1.099889.xyz): " DOMAIN
read -p "请输入WS路径 (默认 /ray): " WSPATH_INPUT
read -p "请输入端口 (默认 8443): " PORT_INPUT
read -p "是否开启防直扫模式(1=开启 0=关闭 默认1): " LOCK_INPUT

WSPATH=${WSPATH_INPUT:-/ray}
PORT=${PORT_INPUT:-8443}
LOCK=${LOCK_INPUT:-1}

UUID=$(cat /proc/sys/kernel/random/uuid)

echo ""
echo "安装依赖..."
apt update -y
apt install -y curl wget socat cron unzip tar openssl ufw iptables-persistent

echo ""
echo "停止旧服务..."
systemctl stop sing-box 2>/dev/null || true

echo ""
echo "安装 sing-box..."
bash <(curl -fsSL https://sing-box.app/deb-install.sh)

mkdir -p /root/cert
mkdir -p /etc/sing-box

echo ""
echo "安装 acme.sh..."
curl https://get.acme.sh | sh
source ~/.bashrc || true

echo ""
echo "关闭可能占用80端口服务..."
systemctl stop nginx 2>/dev/null || true
systemctl stop apache2 2>/dev/null || true

echo ""
echo "申请证书..."
~/.acme.sh/acme.sh --issue -d $DOMAIN --standalone --keylength ec-256 --force

echo ""
echo "安装证书..."
~/.acme.sh/acme.sh --install-cert -d $DOMAIN \
--ecc \
--fullchain-file /root/cert/fullchain.cer \
--key-file /root/cert/private.key

echo ""
echo "写入 sing-box 配置..."
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
echo "开启 BBR..."
grep -q "tcp_congestion_control=bbr" /etc/sysctl.conf || cat >> /etc/sysctl.conf <<EOF

net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF

sysctl -p

echo ""
echo "开放端口..."
ufw allow $PORT/tcp 2>/dev/null || true

systemctl daemon-reload
systemctl enable sing-box

echo ""
echo "启动 sing-box..."
systemctl restart sing-box

sleep 3

STATUS=$(systemctl is-active sing-box)

echo ""
echo "========================================"
echo " sing-box 状态: $STATUS"
echo "========================================"

ENCODED_PATH=$(printf '%s' "$WSPATH" | sed 's/\//%2Fg')

LINK="vless://${UUID}@${DOMAIN}:${PORT}?encryption=none&security=tls&type=ws&host=${DOMAIN}&path=${ENCODED_PATH}#CF-WS"

echo ""
echo "节点链接："
echo ""
echo "$LINK"
echo ""

echo "========================================"
echo " Cloudflare 必须设置："
echo "- 橙云开启"
echo "- SSL模式 Full 或 Full(strict)"
echo "========================================"

echo ""
echo "是否启用防直扫模式？: $LOCK"

if [ "$LOCK" = "1" ]; then
    echo ""
    echo "拉取 Cloudflare IP..."

    CF_V4=$(curl -s https://www.cloudflare.com/ips-v4)
    CF_V6=$(curl -s https://www.cloudflare.com/ips-v6)

    echo "清理防火墙..."
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

    echo "放行 SSH..."
    iptables -A INPUT -p tcp --dport 22 -j ACCEPT
    ip6tables -A INPUT -p tcp --dport 22 -j ACCEPT

    echo "放行业务端口（仅Cloudflare）..."

    for ip in $CF_V4; do
        iptables -A INPUT -p tcp -s $ip --dport $PORT -j ACCEPT
    done

    for ip in $CF_V6; do
        ip6tables -A INPUT -p tcp -s $ip --dport $PORT -j ACCEPT
    done

    netfilter-persistent save

    echo "防直扫已开启"
else
    echo "未开启防直扫"
fi

echo ""
echo "========================================"
echo " 部署完成"
echo "========================================"
