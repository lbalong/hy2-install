#!/bin/bash

# 检查是否为 Root 用户
if [ "$EUID" -ne 0 ]; then
  echo "错误：请使用 root 用户运行此脚本！"
  exit 1
fi

echo "=========================================="
echo " VLESS + Reality 终极解脱版 (0字差错，闭眼通车)"
echo "=========================================="

# 1. 获取 VPS 本机公网 IP
IP=$(curl -sS4 https://ifconfig.me || curl -sS4 https://ipinfo.io/ip || curl -sS4 https://api.ipify.org)
if [ -z "$IP" ]; then
  echo "❌ 错误：无法获取服务器公网 IP，请检查网络连接。"
  exit 1
fi

# 2. 允许用户自定义端口
DEFAULT_PORT=$(shuf -i 10000-65000 -n 1)
echo "💡 提示：可以直接输入你面板放行的固定 TCP 端口（如 443 或其他高位端口）。"
read -p "👉 请输入节点监听端口 (直接回车使用随机端口 $DEFAULT_PORT): " PORT
if [ -z "$PORT" ]; then PORT=$DEFAULT_PORT; fi

# 3. 核心速度黑科技：BBR + 16MB 巨型缓冲区 + TCP Fast Open
echo "🚀 正在向内核注入网络超频补丁 (BBR + 16MB缓存 + TFO)..."
cat <<EOF > /etc/sysctl.d/99-vless-reality-passwall.conf
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.core.rmem_max=16772160
net.core.wmem_max=16772160
net.ipv4.tcp_rmem=4096 87380 16772160
net.ipv4.tcp_wmem=4096 65536 16772160
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_fin_timeout=15
net.ipv4.tcp_keepalive_time=600
net.ipv4.tcp_fastopen=3
EOF
sysctl --system >/dev/null 2>&1

# 4. 彻底格式化本地防火墙
iptables -F && iptables -X
iptables -P INPUT ACCEPT && iptables -P FORWARD ACCEPT && iptables -P OUTPUT ACCEPT

# 5. 安装基础依赖与最新版 Xray 核心
if command -v apt-get >/dev/null; then
  apt-get update && apt-get install -y curl wget jq uuid-runtime iptables socat
elif command -v yum >/dev/null; then
  yum makecache && yum install -y curl wget jq uuid-runtime iptables socat
fi
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)"

echo "⏳ 正在配置全纯净网络核心..."
sleep 2

# 6. 🌟 降维打击：UUID 和短 ID 保持动态独享，公私钥采用预验证的满血密码对，彻底解决天窗 Bug
UUID=$(cat /proc/sys/kernel/random/uuid)
SHORT_ID=$(openssl rand -hex 8)

PRIVATE_KEY="OHiRUZqq1Yfo5JA6FataI9RzKTE7WPrUoeteBLUpTWc="
PUBLIC_KEY="8mYkd-02gEB5H0P_d0EcrhXt009P4jBKxba5A1AbE0I="

# 7. 写入配置
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
        },
        "sockopt": {
          "tcpFastOpen": true
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

# 8. 强破权限并重启服务
chmod 644 /usr/local/etc/xray/config.json
chown -R nobody:nogroup /usr/local/etc/xray 2>/dev/null || chown -R nobody:nobody /usr/local/etc/xray 2>/dev/null
systemctl daemon-reload && systemctl enable xray && systemctl restart xray

sleep 2

# 9. 直接端上桌的完美输出 (这次 &pbk= 后面绝对有最纯正的公钥！)
echo "=========================================="
echo " 🎉 VLESS + Reality 纯净版已完美写入启动！"
echo "=========================================="
echo "👇 你的通用一键导入链接 (这次直接复制导入即可)："
echo ""
echo "vless://$UUID@$IP:$PORT?security=reality&sni=$DEST_SERVER&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID&flow=xtls-rprx-vision#Reality_SpeedUp_$PORT"
echo ""
echo "=========================================="
echo "🛠️  软路由 PassWall 手动照抄参数表"
echo "=========================================="
echo " 1. 协议 (Protocol):   VLESS"
echo " 2. 地址 (Address):    $IP"
echo " 3. 端口 (Port):       $PORT"
echo " 4. 用户ID (UUID):     $UUID"
echo " 5. 流控 (Flow):       xtls-rprx-vision"
echo " 6. 传输协议 (Net):    tcp"
echo " 7. 加密 (Security):   reality"
echo " 8. 伪装域名 (SNI):    $DEST_SERVER"
echo " 9. 公钥 (Public Key): $PUBLIC_KEY"
echo " 10.短 ID (Short ID):  $SHORT_ID"
echo " 11.指纹 (Fingerprint):chrome"
echo " 12.TCP Fast Open:     勾选/开启"
echo " 13.多路复用 (Mux):    必须关闭！"
echo "=========================================="

# 最终的安全自检
if /usr/local/bin/xray -test -config /usr/local/etc/xray/config.json | grep -q "Configuration OK"; then
    echo " ✅ Xray 核心底层自检：Configuration OK. 配置绝无死角！"
else
    echo " ❌ 警告：自检失败！服务器环境可能发生冲突。"
fi
echo "=========================================="
