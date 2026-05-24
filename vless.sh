#!/bin/bash

# 检查是否为 Root 用户
if [ "$EUID" -ne 0 ]; then
  echo "错误：请使用 root 用户运行此脚本！"
  exit 1
fi

echo "=========================================="
echo " VLESS + REALITY + Vision 纯血超频完全体"
echo "=========================================="

# 1. 获取 VPS 本机公网 IP 并智能识别服务器厂商
IP=$(curl -sS4 https://ifconfig.me || curl -sS4 https://ipinfo.io/ip || curl -sS4 https://api.ipify.org)
if [ -z "$IP" ]; then
  echo "❌ 错误：无法获取服务器公网 IP，请检查网络连接。"
  exit 1
fi

PROVIDER="通用云服务器 / 未知机房"
if [ -f /sys/class/dmi/id/sys_vendor ] || [ -f /sys/class/dmi/id/bios_vendor ] || [ -f /sys/class/dmi/id/product_name ]; then
    DMI_STR=$(cat /sys/class/dmi/id/sys_vendor /sys/class/dmi/id/bios_vendor /sys/class/dmi/id/product_name 2>/dev/null | tr '[:upper:]' '[:lower:]')
    if [[ "$DMI_STR" == *"oracle"* ]]; then PROVIDER="甲骨文云 (Oracle Cloud)";
    elif [[ "$DMI_STR" == *"amazon"* || "$DMI_STR" == *"aws"* ]]; then PROVIDER="亚马逊云 (AWS)";
    elif [[ "$DMI_STR" == *"google"* ]]; then PROVIDER="谷歌云 (GCP)";
    elif [[ "$DMI_STR" == *"alibaba"* || "$DMI_STR" == *"aliyun"* ]]; then PROVIDER="阿里云 (Alibaba Cloud)";
    elif [[ "$DMI_STR" == *"tencent"* ]]; then PROVIDER="腾讯云 (Tencent Cloud)";
    elif [[ "$DMI_STR" == *"digitalocean"* ]]; then PROVIDER="DigitalOcean";
    elif [[ "$DMI_STR" == *"vultr"* ]]; then PROVIDER="Vultr";
    elif [[ "$DMI_STR" == *"linode"* ]]; then PROVIDER="Linode";
    elif [[ "$DMI_STR" == *"qemu"* || "$DMI_STR" == *"kvm"* ]]; then PROVIDER="常规 KVM 虚拟化机房"; fi
fi
echo "🖥️  系统检测当前运行环境为: $PROVIDER"

# 2. 允许用户自定义端口
DEFAULT_PORT=$(shuf -i 10000-65000 -n 1)
echo "💡 提示：可以直接输入你面板放行的固定 TCP 端口（如 443 或其他高位端口）。"
read -p "👉 请输入节点监听端口 (直接回车使用随机端口 $DEFAULT_PORT): " PORT
if [ -z "$PORT" ]; then 
    PORT=$DEFAULT_PORT
    echo "🎲 检测到输入为空，已为您无缝启用自动随机端口: $PORT"
fi

# 3. 注入内核速度补丁 (BBR + 16MB 巨型缓冲区 + TCP Fast Open)
echo "🚀 正在向内核注入网络超频补丁..."
cat <<EOF > /etc/sysctl.d/99-vless-reality-tuning.conf
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

# 4. 防火墙一键清洗
echo "正在清空本地防火墙残留规则并建立通信通道..."
if command -v ufw > /dev/null; then ufw allow $PORT/tcp >/dev/null 2>&1 && ufw disable >/dev/null 2>&1; fi
if command -v firewall-cmd > /dev/null; then firewall-cmd --zone=public --add-port=$PORT/tcp --permanent >/dev/null 2>&1 && firewall-cmd --reload >/dev/null 2>&1; fi
iptables -F && iptables -X
iptables -P INPUT ACCEPT && iptables -P FORWARD ACCEPT && iptables -P OUTPUT ACCEPT
iptables -I INPUT -p tcp --dport $PORT -j ACCEPT

# 5. 安装基础依赖与最新版 Xray 核心
if command -v apt-get >/dev/null; then
  apt-get update && apt-get install -y curl wget jq uuid-runtime iptables
elif command -v yum >/dev/null; then
  yum makecache && yum install -y curl wget jq uuid-runtime iptables
fi
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)"

# 6. 核心黑科技：动态生成 REALITY 密钥对与参数
UUID=$(cat /proc/sys/kernel/random/uuid)
SHORT_ID=$(openssl rand -hex 8)
XRAY_KEYS=$(/usr/local/bin/xray x25519)
PRIVATE_KEY=$(echo "$XRAY_KEYS" | grep "Private key:" | awk '{print $3}')
PUBLIC_KEY=$(echo "$XRAY_KEYS" | grep "Public key:" | awk '{print $3}')
DEST_SERVER="www.microsoft.com"

# 7. 写入标准的 VLESS + REALITY + XTLS Vision 配置文件
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

# 8. 修复权限并启动服务
chmod 644 /usr/local/etc/xray/config.json
chown -R nobody:nogroup /usr/local/etc/xray 2>/dev/null || chown -R nobody:nobody /usr/local/etc/xray 2>/dev/null
systemctl daemon-reload && systemctl enable xray && systemctl restart xray

# 9. 固化快捷查询命令 【vless】
cat << EOF > /usr/local/bin/vless
#!/bin/bash
echo "=========================================="
echo "📋 您的 VLESS-Reality 节点参数"
echo "=========================================="
echo "协议 (Protocol):   VLESS"
echo "地址 (Address):    $IP"
echo "端口 (Port):       $PORT"
echo "用户ID (UUID):     $UUID"
echo "流控 (Flow):       xtls-rprx-vision"
echo "传输协议 (Net):    tcp"
echo "加密 (Security):   reality"
echo "伪装域名 (SNI):    $DEST_SERVER"
echo "公钥 (PublicKey):  $PUBLIC_KEY"
echo "短 ID (Short ID):  $SHORT_ID"
echo "指纹 (fp):         chrome"
echo "=========================================="
echo "👇 通用一键导入链接："
echo "vless://$UUID@$IP:$PORT?security=reality&sni=$DEST_SERVER&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID&flow=xtls-rprx-vision#Reality_SpeedUp_$PORT"
echo "=========================================="
EOF
chmod +x /usr/local/bin/vless

# 10. 完工输出
clear
/usr/local/bin/vless
