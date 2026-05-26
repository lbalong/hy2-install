#!/usr/bin/env bash

set -e

echo "======================================"
echo " AnyTLS + sing-box 高性能安装脚本"
echo "======================================"

if [[ $EUID -ne 0 ]]; then
    echo "请使用 root 运行"
    exit 1
fi

read -p "请输入监听端口(默认443): " PORT
PORT=${PORT:-443}

ARCH=$(uname -m)

if [[ "$ARCH" == "x86_64" ]]; then
    SB_ARCH="amd64"
elif [[ "$ARCH" == "aarch64" ]]; then
    SB_ARCH="arm64"
else
    echo "不支持的架构"
    exit 1
fi

echo
echo "安装依赖..."
apt update
apt install -y curl wget tar jq openssl

echo
echo "开启BBR..."

cat > /etc/sysctl.d/99-custom.conf <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr

net.core.rmem_max=67108864
net.core.wmem_max=67108864

net.ipv4.tcp_rmem=4096 87380 67108864
net.ipv4.tcp_wmem=4096 65536 67108864

net.ipv4.tcp_fastopen=3
net.ipv4.tcp_mtu_probing=1
net.ipv4.tcp_window_scaling=1

net.ipv4.tcp_fin_timeout=15
net.ipv4.tcp_keepalive_time=600

fs.file-max=1048576
EOF

sysctl --system

echo
echo "优化 limits..."

cat >> /etc/security/limits.conf <<EOF
* soft nofile 1048576
* hard nofile 1048576
EOF

mkdir -p /etc/systemd/system/sing-box.service.d

cat > /etc/systemd/system/sing-box.service.d/limit.conf <<EOF
[Service]
LimitNOFILE=1048576
EOF

echo
echo "下载 sing-box..."

cd /tmp

LATEST=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | jq -r .tag_name)

wget -O sing-box.tar.gz \
https://github.com/SagerNet/sing-box/releases/download/${LATEST}/sing-box-${LATEST#v}-linux-${SB_ARCH}.tar.gz

tar -xzf sing-box.tar.gz

cd sing-box-*

install -m 755 sing-box /usr/local/bin/sing-box

mkdir -p /etc/sing-box

IP=$(curl -s ipv4.ip.sb)

PASSWORD=$(openssl rand -base64 24 | tr -d "=+/" | cut -c1-24)

echo
echo "生成配置..."

cat > /etc/sing-box/config.json <<EOF
{
  "log": {
    "level": "warn"
  },
  "inbounds": [
    {
      "type": "anytls",
      "tag": "anytls-in",
      "listen": "::",
      "listen_port": ${PORT},
      "users": [
        {
          "name": "user",
          "password": "${PASSWORD}"
        }
      ],
      "padding_scheme": [
        "stop=8"
      ]
    }
  ],
  "outbounds": [
    {
      "type": "direct"
    }
  ]
}
EOF

echo
echo "创建 systemd 服务..."

cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
Description=sing-box service
After=network.target

[Service]
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=on-failure
RestartSec=10
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable sing-box
systemctl restart sing-box

echo
echo "开放防火墙..."

if command -v ufw >/dev/null 2>&1; then
    ufw allow ${PORT}/tcp
fi

NODE_LINK="anytls://${PASSWORD}@${IP}:${PORT}?security=tls&sni=www.microsoft.com#AnyTLS"

echo
echo "======================================"
echo " 安装完成"
echo "======================================"

echo
echo "服务器IP: ${IP}"
echo "端口: ${PORT}"
echo "随机密码: ${PASSWORD}"

echo
echo "AnyTLS 节点链接："
echo
echo "${NODE_LINK}"

echo
echo "BBR状态："
sysctl net.ipv4.tcp_congestion_control
