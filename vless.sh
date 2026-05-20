#!/bin/bash

# 检查是否为 Root 用户
if [ "$EUID" -ne 0 ]; then
  echo "错误：请使用 root 用户运行此脚本！"
  exit 1
fi

echo "=========================================="
echo "    VLESS + TLS + Vision 域名证书智能校验版"
echo "=========================================="

# 1. 获取 VPS 本机公网 IP 并智能识别服务器厂商
IP=$(curl -sS4 https://ifconfig.me || curl -sS4 https://ipinfo.io/ip || curl -sS4 https://api.ipify.org)
UUID=$(cat /proc/sys/kernel/random/uuid)

if [ -z "$IP" ]; then
  echo "❌ 错误：无法获取服务器公网 IP，请检查网络连接。"
  exit 1
fi

# 智能识别服务器商家雷达
PROVIDER="通用云服务器 / 未知机房"
if [ -f /sys/class/dmi/id/sys_vendor ] || [ -f /sys/class/dmi/id/bios_vendor ] || [ -f /sys/class/dmi/id/product_name ]; then
    DMI_STR=$(cat /sys/class/dmi/id/sys_vendor /sys/class/dmi/id/bios_vendor /sys/class/dmi/id/product_name 2>/dev/null | tr '[:upper:]' '[:lower:]')
    if [[ "$DMI_STR" == *"oracle"* ]]; then
        PROVIDER="甲骨文云 (Oracle Cloud)"
    elif [[ "$DMI_STR" == *"amazon"* || "$DMI_STR" == *"aws"* ]]; then
        PROVIDER="亚马逊云 (AWS)"
    elif [[ "$DMI_STR" == *"google"* ]]; then
        PROVIDER="谷歌云 (GCP)"
    elif [[ "$DMI_STR" == *"alibaba"* || "$DMI_STR" == *"aliyun"* ]]; then
        PROVIDER="阿里云 (Alibaba Cloud)"
    elif [[ "$DMI_STR" == *"tencent"* ]]; then
        PROVIDER="腾讯云 (Tencent Cloud)"
    elif [[ "$DMI_STR" == *"digitalocean"* ]]; then
        PROVIDER="DigitalOcean"
    elif [[ "$DMI_STR" == *"vultr"* ]]; then
        PROVIDER="Vultr"
    elif [[ "$DMI_STR" == *"linode"* ]]; then
        PROVIDER="Linode"
    elif [[ "$DMI_STR" == *"qemu"* || "$DMI_STR" == *"kvm"* ]]; then
        PROVIDER="常规 KVM 虚拟化机房"
    fi
fi
echo "🖥️  系统检测当前运行环境为: $PROVIDER"

# 2. 用户输入基本信息
read -p "👉 请输入已解析到本机的完整域名 (例如 sg.099889.xyz): " DOMAIN
if [ -z "$DOMAIN" ]; then echo "❌ 错误：域名不能为空！"; exit 1; fi

# 🌟 核心升级：智能域名 IP 自动对齐校验
echo "🔍 正在校验域名 DNS 解析状态..."
# 利用系统原生的 getent 离线抓取域名 A 记录 IP
DOMAIN_IP=$(getent ahosts "$DOMAIN" | head -n 1 | awk '{print $1}')

if [ -z "$DOMAIN_IP" ] || [[ ! "$DOMAIN_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "=========================================="
    echo "❌ 致命错误：无法解析该域名！"
    echo "   请检查：1. 域名是否拼写错误？"
    echo "           2. DNS 服务商处是否添加了 A 记录？"
    echo "           3. CF 的小云朵（CDN Proxy）是否开启？(建议先关闭保持纯 DNS 解析)"
    echo "=========================================="
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
        echo "❌ 已安全终止安装。请先去 DNS 控制台将 A 记录精准指向 $IP"
        exit 1
    fi
else
    echo "✅ 完美对齐！域名已精准指向当前 VPS ($IP)，通过安全验证。"
fi

DEFAULT_PORT=$(shuf -i 10000-65000 -n 1)
echo "------------------------------------------"
echo "💡 提示：请输入网页后台放行的固定 TCP 端口（建议不要用 443）。"
read -p "👉 请输入节点监听端口 (直接回车使用随机端口 $DEFAULT_PORT): " PORT
if [ -z "$PORT" ]; then 
    PORT=$DEFAULT_PORT
    echo "🎲 检测到输入为空，已为您无缝启用自动随机端口: $PORT"
fi

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

# 4. 防火墙优化（彻底清空本地残留，并精准双向放行核心节点端口与 80 端口）
echo "正在清空本地防火墙残留规则并建立通信通道..."

# 如果启用了 UFW，放行对应的通信 TCP 端口和 80 端口，随后关闭主拦截
if command -v ufw > /dev/null; then
    ufw allow $PORT/tcp >/dev/null 2>&1
    ufw allow 80/tcp >/dev/null 2>&1
    ufw reload >/dev/null 2>&1
    ufw disable >/dev/null 2>&1
fi

# 如果启用了 Firewalld，放行指定/随机 TCP 端口和 80 端口
if command -v firewall-cmd > /dev/null; then
    firewall-cmd --zone=public --add-port=$PORT/tcp --permanent >/dev/null 2>&1
    firewall-cmd --zone=public --add-port=80/tcp --permanent >/dev/null 2>&1
    firewall-cmd --reload >/dev/null 2>&1
fi

# 原生 iptables 规则彻底清空并策略放行
iptables -F && iptables -X
iptables -P INPUT ACCEPT && iptables -P FORWARD ACCEPT && iptables -P OUTPUT ACCEPT

# 强行在 iptables 最前端挂载刚刚生成/输入的特定通信端口和 80 续签端口
iptables -I INPUT -p tcp --dport $PORT -j ACCEPT
iptables -I INPUT -p tcp --dport 80 -j ACCEPT

# 5. 安装依赖与 Xray 核心 (智能适配多系统架构)
echo "正在安装基础依赖..."
if command -v apt-get >/dev/null; then
  apt-get update && apt-get install -y curl wget jq uuid-runtime iptables socat
elif command -v yum >/dev/null; then
  yum makecache && yum install -y curl wget jq uuid-runtime iptables socat
fi
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

# 7. 写入标准的 VLESS + TLS + XTLS Vision 配置文件
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
echo "⚠️  [$PROVIDER] 网页后台/安全组放行提示 ⚠️"
echo " 1. TCP 协议: 80 端口 (用于证书自动续签，必开)"
echo " 2. TCP 协议: $PORT 端口 (你的节点通信端口，必开)"
echo "=========================================="
echo "👇 你的全平台通用导入链接："
echo ""
echo "vless://$UUID@$DOMAIN:$PORT?security=tls&flow=xtls-rprx-vision#VLESS_Vision_${DOMAIN}"
echo ""
echo "=========================================="
