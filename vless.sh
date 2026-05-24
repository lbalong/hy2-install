#!/bin/bash

# 检查是否为 Root 用户
if [ "$EUID" -ne 0 ]; then
  echo "错误：请使用 root 用户运行此脚本！"
  exit 1
fi

echo "=========================================================="
echo " VLESS + REALITY + Vision 域名对齐+双轨测速可视化完全体 V9.1"
echo "=========================================================="

# 1. 获取 VPS 本机公网 IP 并智能识别服务器厂商
IP=$(curl -sS4 https://ifconfig.me || curl -sS4 https://ipinfo.io/ip || curl -sS4 https://api.ipify.org)
if [ -z "$IP" ]; then
  echo "❌ 错误：无法获取服务器公网 IP，请检查 network 连接。"
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

# 3. 核心速度黑科技：BBR + 16MB 巨型缓冲区 + TCP Fast Open
echo "▶ 步骤 3: 正在向内核注入网络超频补丁 (BBR + 16MB缓存)..."
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

# 4. 防火墙一键清洗并精准放行
echo "▶ 步骤 4: 正在清洗本地防火墙残留，开放 TCP 端口: $PORT ..."
if command -v ufw > /dev/null; then ufw allow $PORT/tcp >/dev/null 2>&1 && ufw disable >/dev/null 2>&1; fi
if command -v firewall-cmd > /dev/null; then firewall-cmd --zone=public --add-port=$PORT/tcp --permanent >/dev/null 2>&1 && firewall-cmd --reload >/dev/null 2>&1; fi
iptables -F && iptables -X
iptables -P INPUT ACCEPT && iptables -P FORWARD ACCEPT && iptables -P OUTPUT ACCEPT
iptables -I INPUT -p tcp --dport $PORT -j ACCEPT

# 5. 安装基础依赖与最新版 Xray 核心
echo "▶ 步骤 5: 正在调度系统包管理器，并拉取 Xray 官方最新核心..."
if command -v apt-get >/dev/null; then
  apt-get update && apt-get install -y curl wget jq uuid-runtime iptables socat
elif command -v yum >/dev/null; then
  yum makecache && yum install -y curl wget jq uuid-runtime iptables socat
fi
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)"

# 6. 核心黑科技：动态生成 REALITY 密钥对
echo "▶ 步骤 6: 正在底层强开 x25519 引擎，动态计算 REALITY 专属安全密钥对..."
UUID=$(cat /proc/sys/kernel/random/uuid)
SHORT_ID=$(openssl rand -hex 8)
XRAY_KEYS=$(/usr/local/bin/xray x25519)
PRIVATE_KEY=$(echo "$XRAY_KEYS" | grep "Private key:" | awk '{print $3}')
PUBLIC_KEY=$(echo "$XRAY_KEYS" | grep "Public key:" | awk '{print $3}')
DEST_SERVER="www.microsoft.com"

# 7. 写入标准的 VLESS + REALITY + XTLS Vision 配置文件
echo "▶ 步骤 7: 正在将对账参数精准写入 Xray 主账本 (config.json)..."
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
echo "▶ 步骤 8: 正在重载 systemd 守护进程，并尝试重启 Xray 服务..."
chmod 644 /usr/local/etc/xray/config.json
chown -R nobody:nogroup /usr/local/etc/xray 2>/dev/null || chown -R nobody:nobody /usr/local/etc/xray 2>/dev/null
systemctl daemon-reload
systemctl enable xray
systemctl restart xray

echo "⏳ 等待系统网络栈响应对账状态..."
sleep 2

# 9. 🌟 智能固化双轨制快捷查询命令 【vless】
echo "▶ 步骤 9: 正在固化本地全局快捷查询账本命令至 /usr/local/bin/vless ..."
cat << EOF > /usr/local/bin/vless
#!/bin/bash
IP=\$(curl -sS4 https://ifconfig.me || curl -sS4 https://ipinfo.io/ip || curl -sS4 https://api.ipify.org)
PORT=\$(jq '.inbounds[0].port' /usr/local/etc/xray/config.json)
UUID=\$(jq -r '.inbounds[0].settings.clients[0].id' /usr/local/etc/xray/config.json)
SHORT_ID=\$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' /usr/local/etc/xray/config.json)
PUBLIC_KEY="$PUBLIC_KEY"
DEST_SERVER="$DEST_SERVER"

PROVIDER="通用云服务器 / 未知机房"
if [ -f /sys/class/dmi/id/sys_vendor ] || [ -f /sys/class/dmi/id/bios_vendor ] || [ -f /sys/class/dmi/id/product_name ]; then
    DMI_STR=\$(cat /sys/class/dmi/id/sys_vendor /sys/class/dmi/id/bios_vendor /sys/class/dmi/id/product_name 2>/dev/null | tr '[:upper:]' '[:lower:]')
    if [[ "\$DMI_STR" == *"oracle"* ]]; then PROVIDER="甲骨文云 (Oracle Cloud)";
    elif [[ "\$DMI_STR" == *"amazon"* || "\$DMI_STR" == *"aws"* ]]; then PROVIDER="亚马逊云 (AWS)";
    elif [[ "\$DMI_STR" == *"google"* ]]; then PROVIDER="谷歌云 (GCP)";
    elif [[ "\$DMI_STR" == *"alibaba"* || "\$DMI_STR" == *"aliyun"* ]]; then PROVIDER="阿里云 (Alibaba Cloud)";
    elif [[ "\$DMI_STR" == *"tencent"* ]]; then PROVIDER="腾讯云 (Tencent Cloud)";
    elif [[ "\$DMI_STR" == *"digitalocean"* ]]; then PROVIDER="DigitalOcean";
    elif [[ "\$DMI_STR" == *"vultr"* ]]; then PROVIDER="Vultr";
    elif [[ "\$DMI_STR" == *"linode"* ]]; then PROVIDER="Linode";
    elif [[ "\$DMI_STR" == *"qemu"* || "\$DMI_STR" == *"kvm"* ]]; then PROVIDER="常规 KVM 虚拟化机房"; fi
fi

echo "=========================================="
echo "📋 您的 VLESS-Reality 动态双轨制参数 (当前运行中)"
echo "=========================================="
echo " 0. 服务器商 (Provider):   \$PROVIDER"
echo " 1. 协议 (Protocol):       VLESS"
echo " 2. 域名地址 (Domain):     $DOMAIN"
echo " 3. 原生 IP 地址 (IP):     \$IP"
echo " 4. 端口 (Port):           \$PORT"
echo " 5. 用户ID (UUID):         \$UUID"
echo " 6. 流控 (Flow):           xtls-rprx-vision"
echo " 7. 传输协议 (Net):        tcp"
echo " 8. 加密 (Security):       reality"
echo " 9. 伪装域名 (SNI):        \$DEST_SERVER"
echo " 10.公钥 (Public Key):     \$PUBLIC_KEY"
echo " 11.短 ID (Short ID):      \$SHORT_ID"
echo " 12.指纹 (Fingerprint):    chrome"
echo " 13.TCP Fast Open:         勾选/开启"
echo " 14.多路复用 (Mux):        必须关闭"
echo "=========================================="
echo "⚠️  [\$PROVIDER] 网页后台/安全组放行提示 ⚠️"
echo " - IP 协议: TCP, 目标端口: \$PORT"
echo "=========================================="
echo "👇 链接一：域名防封流（强烈推荐！日常主力和全家看双杜比用此链接，安全防阻断）"
echo "vless://\$UUID@$DOMAIN:\$PORT?security=reality&sni=\$DEST_SERVER&fp=chrome&pbk=\$PUBLIC_KEY&sid=\$SHORT_ID&flow=xtls-rprx-vision#Reality_Domain_\$PORT"
echo ""
echo "👇 链接二：IP 测速流（专门用来在 v2rayN 里跑测速，绕过客户端 DNS 缺陷，绝不报错）"
echo "vless://\$UUID@\$IP:\$PORT?security=reality&sni=\$DEST_SERVER&fp=chrome&pbk=\$PUBLIC_KEY&sid=\$SHORT_ID&flow=xtls-rprx-vision#Reality_IP_Test_\$PORT"
echo "=========================================="
EOF
chmod +x /usr/local/bin/vless

# 10. 首次运行屏幕输出 (移除脑残 clear 命令，保留全部上下文日志)
echo "▶ 步骤 10: 正在唤出完全体节点配置单..."
echo ""
/usr/local/bin/vless

# 最终的安全自检
if /usr/local/bin/xray -test -config /usr/local/etc/xray/config.json | grep -q "Configuration OK"; then
    echo " ✅ Xray 核心底层自检：Configuration OK. 配置绝无死角！"
else
    echo " ❌ 警告：自检失败！服务器环境可能发生冲突。"
fi
echo "=========================================="
