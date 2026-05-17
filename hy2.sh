#!/bin/bash
# Hysteria2 一键安装脚本 - 自动输出节点分享链接

set -e

echo "=== Hysteria2 一键安装脚本启动 ==="

# 更新系统并安装依赖
apt update && apt install -y curl wget openssl net-tools ufw

# 自动获取公网IP
IP=$(curl -fsSL https://api.ipify.org 2>/dev/null || curl -fsSL https://ifconfig.me 2>/dev/null)
echo "检测到本机IP: $IP"

# 安装 Hysteria2 官方版
bash <(curl -fsSL https://get.hy2.sh/)

# 生成自签名证书
CERT_DIR="/etc/hysteria/certs"
mkdir -p $CERT_DIR
cd $CERT_DIR

openssl genrsa -out server.key 2048
openssl req -new -key server.key -subj "/CN=$IP" -out server.csr
openssl x509 -req -days 3650 -in server.csr -signkey server.key -out server.crt

# 生成随机强密码
PASSWORD=$(openssl rand -hex 20)

# 创建配置（固定443端口）
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

bandwidth:
  up: 1gbps
  down: 1gbps

disableUDP: false
EOF

# 防火墙配置
ufw allow 443/tcp 2>/dev/null || true
ufw allow 443/udp 2>/dev/null || true
ufw --force enable 2>/dev/null || true

iptables -I INPUT -p udp --dport 443 -j ACCEPT 2>/dev/null || true

# 启动服务
systemctl enable --now hysteria-server
systemctl restart hysteria-server

# ==================== 输出节点链接 ====================
echo "============================================"
echo "✅ Hysteria2 安装成功！"
echo "服务器地址: $IP:443"
echo "密码: $PASSWORD"
echo ""
echo "📋 一键导入节点链接（推荐）："
echo "hysteria2://$PASSWORD@$IP:443/?insecure=1"
echo ""
echo "🔗 备用短链接："
echo "hy2://$PASSWORD@$IP:443/?insecure=1"
echo "============================================"
echo "客户端使用提示："
echo "• 必须开启【忽略证书验证 / Allow Insecure】"
echo "• 直接复制上面链接到客户端即可导入"
echo "============================================"

echo "日志查看: journalctl -u hysteria-server -f"
