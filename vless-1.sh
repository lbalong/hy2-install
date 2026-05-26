#!/bin/bash
set -e
clear

echo "=========================================================="
echo "    Cloudflare 避风港：Sing-Box VLESS-WS-TLS 纯净一键版"
echo "=========================================================="
echo ""

# 铁律第一步：物理创建核心账本目录
mkdir -p /etc/cf_vless
mkdir -p /root/cert
mkdir -p /etc/sing-box

# 激活历史只能记忆检测
CONFIG_FILE="/etc/cf_vless/last_cfg.conf"
if [ -f "$CONFIG_FILE" ]; then 
    source "$CONFIG_FILE"
fi

# 智能记忆恢复：域名检测
if [ -n "$LAST_DOMAIN" ]; then
    read -p " 请输入域名 (直接回车复用上次的 [$LAST_DOMAIN]): " DOMAIN_INPUT
    DOMAIN=${DOMAIN_INPUT:-$LAST_DOMAIN}
else
    read -p " 请输入域名: " DOMAIN
fi

# 智能记忆恢复：WS路径检测
if [ -n "$LAST_WSPATH" ]; then
    read -p " 请输入WS路径 (直接回车复用上次的 [$LAST_WSPATH]): " WSPATH_INPUT
    WSPATH=${WSPATH_INPUT:-$LAST_WSPATH}
else
    read -p " 请输入WS路径(默认 /ray): " WSPATH_INPUT
    WSPATH=${WSPATH_INPUT:-/ray}
fi

# 智能记忆恢复：端口检测
if [ -n "$LAST_PORT" ]; then
    read -p " 请输入端口 (直接回车复用上次的 [$LAST_PORT]): " PORT_INPUT
    PORT=${PORT_INPUT:-$LAST_PORT}
else
    read -p " 请输入端口(强烈推荐 443 或 2053/8443): " PORT_INPUT
    PORT=${PORT_INPUT:-8443}
fi

UUID=$(cat /proc/sys/kernel/random/uuid)

# 纯净单行追加，锁定持久化记忆账本
echo "LAST_DOMAIN=\"$DOMAIN\"" > "$CONFIG_FILE"
echo "LAST_WSPATH=\"$WSPATH\"" >> "$CONFIG_FILE"
echo "LAST_PORT=\"$PORT\"" >> "$CONFIG_FILE"

echo ""
echo "正在安装系统依赖基础组件..."
echo ""
apt update -y
apt install -y curl wget socat cron unzip tar openssl ufw jq

echo ""
echo "强力清洗残留服务内耗..."
echo ""
systemctl stop sing-box 2>/dev/null || true
systemctl stop xray 2>/dev/null || true
systemctl stop nginx 2>/dev/null || true
systemctl stop apache2 2>/dev/null || true

echo ""
echo "安装 sing-box 官方正规军内核..."
echo ""
bash <(curl -fsSL https://sing-box.app/deb-install.sh)

echo ""
echo "配置 acme.sh 自动化正规证书环境..."
echo ""
if [ ! -f "/root/.acme.sh/acme.sh" ]; then
    curl https://get.acme.sh | sh || true
fi

echo ""
echo "正在向 Let's Encrypt 官方摇号签发合规域名证书..."
echo ""
~/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone --keylength ec-256 --force

echo ""
echo "配置证书本地路径并强打读取提权..."
echo ""
~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" \
  --ecc \
  --fullchain-file /root/cert/fullchain.cer \
  --key-file /root/cert/private.key

chmod 644 /root/cert/fullchain.cer
chmod 644 /root/cert/private.key

echo ""
echo "正在写入 Sing-Box 官方规范入站账本..."
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
echo "向内核物理注入 BBR + 16MB 满血流速超频补丁..."
echo ""
grep -q "tcp_congestion_control=bbr" /etc/sysctl.conf || cat >> /etc/sysctl.conf <<EOF

net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.core.rmem_max=16772160
net.core.wmem_max=16772160
net.ipv4.tcp_rmem=4096 87380 16772160
net.ipv4.tcp_wmem=4096 65536 16772160
net.ipv4.tcp_fastopen=3
EOF
sysctl -p || true

echo ""
echo "放行内部网络阻断防火墙..."
echo ""
ufw allow $PORT/tcp 2>/dev/null || true
if command -v iptables >/dev/null 2>&1; then iptables -I INPUT -p tcp --dport $PORT -j ACCEPT 2>/dev/null || true; fi

echo ""
echo "重启并挂起后台正规军系统守护..."
echo ""
systemctl daemon-reload
systemctl enable sing-box
systemctl restart sing-box

sleep 3
STATUS=$(systemctl is-active sing-box)
ENCODED_PATH=$(printf '%s' "$WSPATH" | sed 's/\//%2F/g')

# 🌟 终极对账修复：在 URL 中注入强力补齐的 sni 与 host 参数，背靠背并列输出，解决批量复制痛点
LINK1="vless://${UUID}@${DOMAIN}:${PORT}?encryption=none&security=tls&sni=${DOMAIN}&type=ws&host=${DOMAIN}&path=${ENCODED_PATH}#CF-Domain"
LINK2="vless://${UUID}@104.16.132.229:${PORT}?encryption=none&security=tls&sni=${DOMAIN}&type=ws&host=${DOMAIN}&path=${ENCODED_PATH}#CF-Optimized"

echo ""
echo "===================================="
echo " 部署完成"
echo "===================================="
echo ""
echo "内核状态: $STATUS"
echo ""
echo "下方为双核心引流节点（可直接两行全选，一次性批量复制）:"
echo "=========================================================="
echo "$LINK1"
echo "$LINK2"
echo "=========================================================="
echo ""
