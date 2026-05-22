#!/bin/bash
# Minimal AnyTLS TLS Node Deployment

# 检查 root
if [ "$EUID" -ne 0 ]; then
  echo "请使用 root 用户运行"
  exit 1
fi

# 获取公网 IP
IP=$(curl -s https://ifconfig.me || curl -s https://ipinfo.io/ip)
echo "公网 IP: $IP"

# 安装依赖
apt update -y && apt install -y curl wget socat net-tools openssl
# 或者 yum: yum install -y curl wget socat net-tools openssl

# 创建目录
mkdir -p /etc/anytls

# 随机生成密码
PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
echo "节点密码: $PASSWORD"

# 设置端口
PORT=443

# 申请 TLS 证书 (standalone)
read -p "请输入已解析到本机的域名: " DOMAIN
apt install -y socat
curl -sSL https://get.acme.sh | sh
~/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone
~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" \
  --key-file /etc/anytls/server.key \
  --fullchain-file /etc/anytls/server.crt

# 下载 AnyTLS Server
wget -O /usr/local/bin/anytls-server https://github.com/anytls/anytls-go/releases/latest/download/anytls-server-linux-amd64
chmod +x /usr/local/bin/anytls-server

# 写配置
cat <<EOF > /etc/anytls/config.json
{
  "listen": "0.0.0.0:$PORT",
  "users": {
    "$PASSWORD": ""
  },
  "cert": "/etc/anytls/server.crt",
  "key": "/etc/anytls/server.key"
}
EOF

# systemd 服务
cat <<EOF > /etc/systemd/system/anytls.service
[Unit]
Description=AnyTLS Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/anytls-server -c /etc/anytls/config.json
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable anytls
systemctl start anytls

echo "✅ AnyTLS 节点部署完成"
echo "链接示例: anytls://$PASSWORD@$DOMAIN:$PORT"
