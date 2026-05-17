#!/bin/bash

# 检查是否为 Root 用户
if [ "$EUID" -ne 0 ]; then
  echo "错误：请使用 root 用户运行此脚本！"
  exit 1
fi

echo "=========================================="
echo "    VLESS + TLS + Vision 域名正规证书脚本"
echo "=========================================="

# 1. 获取 VPS 本机公网 IP
IP=$(curl -sS4 https://ifconfig.me || curl -sS4 https://ipinfo.io/ip || curl -sS4 https://api.ipify.org)
UUID=$(cat /proc/sys/kernel/random/uuid)

# 2. 用户输入基本信息
read -p "👉 请输入已解析到本机的完整域名 (例如 sg.099889.xyz): " DOMAIN
if [ -z "$DOMAIN" ]; then echo "❌ 错误：域名不能为空！"; exit 1; fi

DEFAULT_PORT=$(shuf -i 10000-65000 -n 1)
echo "------------------------------------------"
echo "💡 提示：请输入你网页后台放行的固定 TCP 端口（建议不要用 443，防止被其他网页服务占用）。"
read -p "👉 请输入节点监听端口 (直接回车使用随机端口 $DEFAULT_PORT): " PORT
if [ -z "$PORT" ]; then PORT=$DEFAULT_PORT; fi

read -p "👉 请输入邮箱 (用于申请证书，直接回车默认 admin@$DOMAIN): " EMAIL
if [ -z "$EMAIL" ]; then EMAIL="admin@$DOMAIN"; fi
echo "------------------------------------------"

# 3. 注入内核速度补丁 (BBR + 16MB 窗口扩容)
echo "🚀 正在向内核注入 TCP 速度补丁..."
cat <<EOF > /etc/sysctl.d/99-vless-tls-speedup.conf
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.core.rmem_max=16772160
net.core.wmem_max=16772160
net.ipv4.tcp_rmem=4096 87380 16772160
net.ipv4.tcp_wmem=4096 65536 16772160
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_fin_timeout=15
net.ipv4.tcp_keepalive_time=600
EOF
sysctl --system >/dev/null 2>&1

# 4. 防火墙优化
iptables -F && iptables -X
iptables -P INPUT ACCEPT && iptables -P FORWARD ACCEPT && iptables -P OUTPUT ACCEPT

# 5. 安装依赖与 Xray 核心
apt-get update && apt-get install -y curl wget jq uuid-runtime iptables socat
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)"

# 6. 使用正统 acme.sh 独立模式申请 100% 正规安全证书
echo "⏱️ 正在向 Let's Encrypt 申请正规域名证书，请稍候..."
mkdir -p /usr/local/etc/xray
curl https://get.acme.sh | sh -s email=$EMAIL
~/.acme.sh/acme.sh --upgrade --auto-upgrade
~/.acme.sh/acme.sh --issue -d $DOMAIN --standalone --insecure
~/.acme.sh/acme.sh --install-cert -d $DOMAIN \
    --key-file /usr/local/etc/xray/server.key \
    --fullchain-file /usr/local/etc/xray/server.crt

# 7. 写入标准的 VLESS + TLS + XTLS Vision 配置文件 (无公钥污染)
cat <<EOF > /usr/local/etc/xray/config.json
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": $PORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "/usr/local/etc/xray/server.crt",
              "keyFile": "/usr/local/etc/xray/server.key"
            }
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
EOF

# 8. 修复权限并启动服务
chmod 644 /usr/local/etc/xray/config.json
chown -R nobody:nogroup /usr/local/etc/xray 2>/dev/null || chown -R nobody:nobody /usr/local/etc/xray 2>/dev/null
systemctl daemon-reload && systemctl enable xray && systemctl restart xray

sleep 3

# 9. 完美输出
echo "=========================================="
echo " 🎉 VLESS + TLS 域名满血版部署成功！"
echo "=========================================="
echo "⚠️  谷歌云/甲骨文网页后台放行提示 ⚠️"
echo " 1. IP 协议: TCP, 目标端口: 80 (用于证书自动续签)"
echo " 2. IP 协议: TCP, 目标端口: $PORT (你的节点通信端口)"
echo "=========================================="
echo "👇 你的通用一键导入链接 (完全没有公钥和短ID，纯净无比)："
echo ""
echo "vless://$UUID@$DOMAIN:$PORT?security=tls&flow=xtls-rprx-vision#Google_VLESS_TLS_$PORT"
echo ""
echo "=========================================="
