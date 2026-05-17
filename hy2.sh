#!/bin/bash
# Hysteria2 安全精简版 - 专为 Oracle VPS 优化

set -e

echo "=== Hysteria2 安全安装脚本 (Oracle 优化版) ==="

# 1. 更新系统
apt update && apt install -y curl wget openssl net-tools

# 2. 获取 IP
IP=$(curl -fsSL https://api.ipify.org || echo "IP获取失败")
echo "VPS IP: $IP"

# 3. 安装 Hysteria2 官方版
bash <(curl -fsSL https://get.hy2.sh/)

# 4. 自签名证书
CERT_DIR="/etc/hysteria/certs"
mkdir -p $CERT_DIR
cd $CERT_DIR
openssl req -x509 -nodes -newkey rsa:2048 -keyout server.key -out server.crt -days 3650 -subj "/CN=$IP" 2>/dev/null

# 5. 强随机密码
PASSWORD=$(openssl rand -hex 24)

# 6. 配置（443端口 + 伪装）
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

# 7. 仅使用 ufw（温和方式）
ufw --force reset >/dev/null 2>&1 || true
ufw allow 22/tcp
ufw allow 443/tcp
ufw allow 443/udp
ufw --force enable >/dev/null 2>&1 || true

# 8. 启动服务
systemctl enable --now hysteria-server
systemctl restart hysteria-server

# 9. 输出节点链接
echo "============================================"
echo "✅ 安装完成！"
echo "服务器地址: $IP:443"
echo "密码: $PASSWORD"
echo ""
echo "📋 一键导入节点链接："
echo "hysteria2://$PASSWORD@$IP:443/?insecure=1&masquerade=www.bing.com"
echo ""
echo "⚠️ 客户端必须开启【忽略证书验证】"
echo "============================================"

echo "状态检查命令: systemctl status hysteria-server"
