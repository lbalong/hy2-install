#!/usr/bin/env bash

set -e

clear

echo "==========================================="
echo "   AnyTLS + sing-box 一键安装脚本"
echo "==========================================="

if [[ $EUID -ne 0 ]]; then
    echo "请使用 root 运行"
    exit 1
fi

echo
read -p "请输入端口（默认443，输入 r 为随机端口）: " PORT

if [[ -z "$PORT" ]]; then
    PORT=443
elif [[ "$PORT" == "r" ]]; then
    PORT=$(shuf -i 20000-60000 -n 1)
fi

ARCH=$(uname -m)

case "$ARCH" in
    x86_64)
        SB_ARCH="amd64"
        ;;
    aarch64|arm64)
        SB_ARCH="arm64"
        ;;
    *)
        echo "不支持的架构: $ARCH"
        exit 1
        ;;
esac

echo
echo "安装依赖..."

apt update

apt install -y \
curl \
wget \
tar \
jq \
openssl \
ca-certificates

echo
echo "开启 BBR 优化..."

cat > /etc/sysctl.d/99-custom.conf <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_mtu_probing=1

net.core.rmem_max=67108864
net.core.wmem_max=67108864

net.ipv4.tcp_rmem=4096 87380 67108864
net.ipv4.tcp_wmem=4096 65536 67108864
EOF

sysctl --system >/dev/null 2>&1

echo
echo "下载 sing-box..."

cd /tmp

LATEST=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | jq -r .tag_name)

wget -q -O sing-box.tar.gz \
https://github.com/SagerNet/sing-box/releases/download/${LATEST}/sing-box-${LATEST#v}-linux-${SB_ARCH}.tar.gz

rm -rf sing-box-* 2>/dev/null || true

tar -xzf sing-box.tar.gz

cd sing-box-*

install -m 755 sing-box /usr/local/bin/sing-box

mkdir -p /etc/sing-box

PASSWORD=$(openssl rand -hex 16)

SNI="www.cloudflare.com"

IP=$(curl -s https://ipv4.ip.sb)

echo
echo "生成 TLS 证书..."

openssl req -x509 -nodes -days 3650 \
-newkey rsa:2048 \
-keyout /etc/sing-box/server.key \
-out /etc/sing-box/server.crt \
-subj "/CN=${SNI}" >/dev/null 2>&1

echo
echo "写入配置..."

cat > /etc/sing-box/config.json <<EOF
{
  "log": {
    "level": "info"
  },

  "inbounds": [
    {
      "type": "anytls",
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
      ],

      "tls": {
        "enabled": true,
        "server_name": "${SNI}",
        "certificate_path": "/etc/sing-box/server.crt",
        "key_path": "/etc/sing-box/server.key"
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

echo
echo "创建 systemd 服务..."

cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
Description=sing-box service
After=network.target

[Service]
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

systemctl enable sing-box >/dev/null 2>&1

systemctl restart sing-box

sleep 2

if command -v ufw >/dev/null 2>&1; then
    ufw allow ${PORT}/tcp >/dev/null 2>&1 || true
fi

NODE_LINK="anytls://${PASSWORD}@${IP}:${PORT}?security=tls&insecure=1&sni=${SNI}#AnyTLS"

clear

echo "==========================================="
echo "             安装完成"
echo "==========================================="

echo
echo "IP: ${IP}"

echo "端口: ${PORT}"

echo "密码: ${PASSWORD}"

echo
echo "节点链接："

echo

echo "${NODE_LINK}"

echo
echo "==========================================="
echo "BBR 状态："
echo "==========================================="

sysctl net.ipv4.tcp_congestion_control

echo
echo "==========================================="
echo "服务状态："
echo "==========================================="

systemctl --no-pager --full status sing-box | head -20
