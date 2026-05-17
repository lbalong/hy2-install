#!/bin/bash
# Hysteria2 一键自动安装脚本 - 支持任意 VPS，自动识别 IP
# 保存为 hy2.sh 并上传到 GitHub

set -e

echo "=== Hysteria2 自动安装脚本 ==="

# 1. 安装依赖
apt update && apt install -y curl wget openssl net-tools

# 2. 自动获取公网 IP
IP=$(curl -fsSL https://api.ipify.org || curl -fsSL https://ifconfig.me)
if [ -z "$IP" ]; then
    echo "无法获取公网 IP，请检查网络"
    exit 1
fi
echo "检测到 VPS 公网 IP: $IP"

# 3. 安装 Hysteria2 官方版本
bash <(curl -fsSL https://get.hy2.sh/)

# 4. 生成自签名证书（有效期 3 年）
CERT_DIR="/etc/hysteria/certs"
mkdir -p $CERT_DIR
cd $CERT_DIR

openssl genrsa -out ca.key 2048
openssl req -x509 -new -nodes -key ca.key -subj "/CN=Hysteria CA" -days 1095 -out ca.crt
openssl genrsa -out server.key 2048
openssl req -new -key server.key -subj "/CN=$IP" -out server.csr
openssl x509 -req -days 1095 -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out server.crt -extfile <(echo "subjectAltName=IP:$IP")

chmod 644 server.crt ca.crt
chmod 600 server.key

# 5. 生成随机强密码
PASSWORD=$(openssl rand -hex 16)

# 6. 创建配置
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

quic:
  maxIdleTimeout: 30s

disableUDP: false
EOF

# 7. 防火墙配置（适配大多数 VPS）
ufw allow 22/tcp 2>/dev/null || true
ufw allow 443/tcp 2>/dev/null || true
ufw allow 443/udp 2>/dev/null || true
ufw --force enable 2>/dev/null || true

# iptables 备用
iptables -I INPUT -p udp --dport 443 -j ACCEPT 2>/dev/null || true
iptables -I INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null || true

# 8. 重启服务
systemctl enable --now hysteria-server
systemctl restart hysteria-server

echo "============================================"
echo "✅ Hysteria2 安装完成！"
echo "服务器地址: $IP:443"
echo "密码: $PASSWORD"
echo "客户端设置："
echo "   - 开启 '忽略证书验证' (insecure: true)"
echo "   - SNI 可留空"
echo "============================================"
echo "日志查看: journalctl -u hysteria-server -f"
echo "重启命令: systemctl restart hysteria-server"