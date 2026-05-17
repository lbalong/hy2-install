#!/bin/bash

# 检查是否为 Root 用户
if [ "$EUID" -ne 0 ]; then
  echo "错误：请使用 root 用户运行此脚本！"
  exit 1
fi

echo "=========================================="
echo "    VLESS + Reality 速度狂飙特调脚本 V2.0"
echo "=========================================="

# 1. 获取 VPS 本机公网 IP
IP=$(curl -sS4 https://ifconfig.me || curl -sS4 https://ipinfo.io/ip || curl -sS4 https://api.ipify.org)
if [ -z "$IP" ]; then
  echo "❌ 错误：无法获取服务器公网 IP，请检查网络连接。"
  exit 1
fi

# 2. 自定义端口
DEFAULT_PORT=$(shuf -i 10000-65000 -n 1)
echo "💡 提示：如果填 443 报错，说明 443 TCP 端口已被其他服务（如 Nginx/面板）霸占，请换用其他高位端口。"
read -p "👉 请输入节点监听端口 (直接回车使用随机端口 $DEFAULT_PORT): " PORT
if [ -z "$PORT" ]; then
    PORT=$DEFAULT_PORT
fi

# 3. 核心速度黑科技：极限榨干 Linux 内核 TCP 吞吐
echo "🚀 正在向内核注入 TCP 速度补丁 (BBR + 16MB 窗口扩容)..."
cat <<EOF > /etc/sysctl.d/99-vless-reality-speedup.conf
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
echo "正在清空本地防火墙拦截规则..."
if command -v ufw > /dev/null; then
    ufw disable >/dev/null 2>&1
fi
iptables -F
iptables -X
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

# 5. 安装依赖与核心
echo "正在安装基础依赖..."
if command -v apt-get >/dev/null; then
  apt-get update && apt-get install -y curl wget jq uuid-runtime iptables
elif command -v yum >/dev/null; then
  yum makecache && yum install -y curl wget jq uuid-runtime iptables
fi

echo "正在调用官方脚本安装最新版 Xray 核心..."
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)"

# 6. 动态生成 Reality 专用的极速暗号
UUID=$(cat /proc/sys/kernel/random/uuid)
SHORT_ID=$(openssl rand -hex 8)

X25519_KEYS=$(/usr/local/bin/xray x25519)
PRIVATE_KEY=$(echo "$X25519_KEYS" | grep "Private key:" | awk '{print $3}')
PUBLIC_KEY=$(echo "$X25519_KEYS" | grep "Public key:" | awk '{print $3}')

# 7. 写入 Xray 配置文件
DEST_SERVER="www.microsoft.com"
mkdir -p /usr/local/etc/xray
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
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "$DEST_SERVER:443",
          "xver": 0,
          "serverNames": [
            "$DEST_SERVER"
          ],
          "privateKey": "$PRIVATE_KEY",
          "shortIds": [
            "$SHORT_ID"
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

# 🌟 核心修复：强破权限黑幕，确保 nobody 用户有权读取配置
echo "⚙️ 正在无缝修复文件权限..."
chmod 644 /usr/local/etc/xray/config.json
chown -R nobody:nogroup /usr/local/etc/xray 2>/dev/null || chown -R nobody:nobody /usr/local/etc/xray 2>/dev/null

# 8. 启动 Xray 服务
systemctl daemon-reload
systemctl enable xray
systemctl restart xray

sleep 2

# 9. 输出结果
echo "=========================================="
echo "你的特调版 VLESS 节点配置参数如下："
echo "=========================================="
echo "🔑 UUID: $UUID"
echo "📡 公钥 (pbk): $PUBLIC_KEY"
echo "🆔 短 ID (sid): $SHORT_ID"
echo "🌐 伪装域名 (SNI): $DEST_SERVER"
echo "=========================================="
echo "👇 你的通用一键导入链接："
echo ""
echo "vless://$UUID@$IP:$PORT?security=reality&sni=$DEST_SERVER&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID&flow=xtls-rprx-vision#Oracle_VLESS_Reality_$PORT"
echo ""
echo "=========================================="

if systemctl is-active --quiet xray; then
    echo " 🎉 Xray 服务已成功在端口 $PORT 启动！"
else
    echo "❌ 警告：服务虽未成功启动（通常由于端口冲突），但配置与链接已如上生成。"
    echo "💡 排查建议：请更换端口重新运行脚本，或运行 '/usr/local/bin/xray test -c /usr/local/etc/xray/config.json' 查看原因。"
fi
echo "=========================================="
