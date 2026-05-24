#!/bin/bash

# 检查是否为 Root 用户
if [ "$EUID" -ne 0 ]; then
  echo "错误：请使用 root 用户运行此脚本！"
  exit 1
fi

echo "=========================================="
echo " VLESS + REALITY + Vision 域名对齐满血版"
echo "=========================================="

# 1. 获取 VPS 本机公网 IP
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

# 2. 用户输入域名并进行强力对账校验
read -p "👉 请输入已解析到本机的完整域名 (例如 sg.099889.xyz): " DOMAIN
if [ -z "$DOMAIN" ]; then echo "❌ 错误：域名不能为空！"; exit 1; fi

echo "🔍 正在校验域名 DNS 解析状态..."
DOMAIN_IP=$(getent ahosts "$DOMAIN" | head -n 1 | awk '{print $1}')

if [ -z "$DOMAIN_IP" ] || [[ ! "$DOMAIN_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "❌ 致命错误：无法解析该域名，请检查 DNS 控制台 A 记录是否生效！"
    exit 1
fi

if [ "$DOMAIN_IP" != "$IP" ]; then
    echo "=========================================="
    echo "⚠️  核心警告：域名解析 IP 与当前 VPS 公网 IP 不匹配！"
    echo "   - 当前 VPS 本机公网 IP: $IP"
    echo "   - 你的域名当前解析到的 IP: $DOMAIN_IP"
    echo "=========================================="
    read -p "👉 是否确认解析已改，并强行继续安装？(y/N): " FORCE_INSTALL
    if [[ ! "$FORCE_INSTALL" =~ ^[Yy]$ ]]; then
        echo "❌ 已安全终止安装。"
        exit 1
    fi
else
    echo "✅ 完美对齐！域名已精准指向当前 VPS ($IP)，通过安全验证。"
fi

DEFAULT_PORT=$(shuf -i 10000-65000 -n 1)
echo "------------------------------------------"
read -p "👉 请输入节点监听端口 (直接回车使用随机端口 $DEFAULT_PORT): " PORT
if [ -z "$PORT" ]; then PORT=$DEFAULT_PORT; fi

# 3. 注入内核速度补丁 (BBR + 16MB 巨型缓冲区)
echo "🚀 正在向内核注入 TCP 速度补丁..."
cat <<EOF > /etc/sysctl.d/99-vless-reality.conf
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

# 4. 防火墙优化
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

# 6. 核心黑科技：动态生成 REALITY 密钥对与参数（不需要申请个人证书）
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

# 9. 固化快捷查询命令 【vless】（完美用域名替换原始 IP）
cat << EOF > /usr/local/bin/vless
#!/bin/bash
echo "=========================================="
echo "📋 您的 VLESS-Reality 域名满血版参数"
echo "=========================================="
echo "协议 (Protocol):   VLESS"
echo "地址 (Address):    $DOMAIN"
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
echo "👇 通用一键导入链接 (已无缝绑定您的域名)："
echo "vless://$UUID@$DOMAIN:$PORT?security=reality&sni=$DEST_SERVER&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID&flow=xtls-rprx-vision#Reality_Domain_$PORT"
echo "=========================================="
EOF
chmod +x /usr/local/bin/vless

# 10. 完工输出
clear
/usr/local/bin/vless
