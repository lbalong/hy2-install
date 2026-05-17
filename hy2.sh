#!/bin/bash
# Hysteria2 Oracle 专用安全版 - 已修复 ufw 问题

set -e

echo "=== Hysteria2 安全安装脚本 (Oracle ARM64 优化版) ==="

# 安装依赖
apt update && apt install -y curl wget openssl net-tools ufw

IP=$(curl -fsSL https://api.ipify.org)
echo "VPS IP: $IP"

# 安装 Hysteria2
bash <(curl -fsSL https://get.hy2.sh/)

# 自签名证书
CERT_DIR="/etc/hysteria/certs"
mkdir -p $CERT_DIR
cd $CERT_DIR
openssl req -x509 -nodes -newkey rsa:2048 -keyout server.key -out server.crt -days 3650 -subj "/CN=$IP" 2>/dev/null

# 随机强密码
PASSWORD=$(openssl rand -hex 24)

# 配置
cat > /etc/hysteria/config.yaml <<EOF
listen: :443

tls:
  cert: $CERT_DIR/server.crt
  key: $CERT_DIR/server.key

auth:
  type: password
  password: $PASSWORD

masquerade:
  type: proxy
  proxy:
    url: https://www.bing.com
    rewriteHost: true

disableUDP: false
EOF

# 防火墙（兼容处理）
ufw allow 22/tcp >/dev/null 2>&1 || true
ufw allow 443/tcp >/dev/null 2>&1 || true
ufw allow 443/udp >/dev/null 2>&1 || true
ufw --force enable >/dev/null 2>&1 || true

# 启动
systemctl enable --now hysteria-server
systemctl restart hysteria-server

echo "============================================"
echo "✅ 安装完成！"
echo "服务器地址: $IP:443"
echo "密码: $PASSWORD"
echo ""
echo "📋 一键导入链接："
echo "hysteria2://$PASSWORD@$IP:443/?insecure=1"
echo "============================================"
