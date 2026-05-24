#!/bin/bash

# 检查是否为 Root 用户
if [ "$EUID" -ne 0 ]; then
  echo "错误：请使用 root 用户运行此脚本！"
  exit 1
fi

# 1. 预先读取历史对账文件
CONFIG_FILE="/etc/sd_vless_last.conf"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# 2. 获取 VPS 本机公网 IP
IP=$(curl -sS4 https://ifconfig.me || curl -sS4 https://ipinfo.io/ip || curl -sS4 https://api.ipify.org)
if [ -z "$IP" ]; then
  echo "❌ 错误：无法获取服务器公网 IP，请检查网络连接。"
  exit 1
fi

echo "=========================================================="
echo " VLESS + Reality 纯净 IP / 域名双模合一终极账本 (带配置记忆)"
echo "=========================================================="

# 3. 🌟 核心菜单（就是这里！确保复制完整）
echo "👉 请选择你要部署的版本："
echo " 1. 安装 VLESS + Reality 纯 IP 版 (v2rayN 测速绝对不报错)"
echo " 2. 安装 VLESS + Reality 域名版 (防封锁首选，测速需在客户端将核心切为 Xray)"
echo "----------------------------------------------------------"
read -p "请选择 [1 或 2] (直接回车默认使用上次或 1): " OPTION
[ -z "$OPTION" ] && OPTION=${LAST_OPTION:-"1"}

# 4. 根据模式收集变量（带自动检测和回显）
if [ "$OPTION" == "2" ]; then
    TYPE="DOMAIN"
    if [ -n "$LAST_DOMAIN" ]; then
        read -p "👉 请输入已解析的完整域名 (直接回车自动使用上次的: $LAST_DOMAIN): " DOMAIN
        [ -z "$DOMAIN" ] && DOMAIN=$LAST_DOMAIN
    else
        read -p "👉 请输入已解析的完整域名 (例如 sg.099889.xyz): " DOMAIN
        if [ -z "$DOMAIN" ]; then echo "❌ 错误：域名不能为空！"; exit 1; fi
    fi

    # 域名 DNS 精准对齐校验
    echo "🔍 正在校验域名 DNS 解析状态..."
    DOMAIN_IP=$(getent ahosts "$DOMAIN" | head -n 1 | awk '{print $1}')
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
else
    TYPE="IP"
fi

# 端口收集（带自动检测和回显）
if [ -n "$LAST_PORT" ]; then
    read -p "👉 请输入节点监听端口 (直接回车自动使用上次的: $LAST_PORT): " PORT
    [ -z "$PORT" ] && PORT=$LAST_PORT
else
    DEFAULT_PORT=$(shuf -i 10000-65000 -n 1)
    read -p "👉 请输入节点监听端口 (直接回车使用随机端口 $DEFAULT_PORT): " PORT
    [ -z "$PORT" ] && PORT=$DEFAULT_PORT
fi

# 5. 持久化保存本次数据，供下次运行自动检测
echo "LAST_OPTION=\"$OPTION\"" > "$CONFIG_FILE"
echo "LAST_DOMAIN=\"$DOMAIN\"" >> "$CONFIG_FILE"
echo "LAST_PORT=\"$PORT\"" >> "$CONFIG_FILE"
echo "TYPE=\"$TYPE\"" >> "$CONFIG_FILE"

# 6. 核心速度黑科技：BBR + 16MB 巨型缓冲区 + TCP Fast Open
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

# 7. 防火墙一键清洗
if command -v ufw > /dev/null; then ufw allow $PORT/tcp >/dev/null 2>&1 && ufw reload >/dev/null 2>&1 && ufw disable >/dev/null 2>&1; fi
if command -v firewall-cmd > /dev/null; then firewall-cmd --zone=public --add-port=$PORT/tcp --permanent >/dev/null 2>&1 && firewall-cmd --reload >/dev/null 2>&1; fi
iptables -F && iptables -X
iptables -P INPUT ACCEPT && iptables -P FORWARD ACCEPT && iptables -P OUTPUT ACCEPT
iptables -I INPUT -p tcp --dport $PORT -j ACCEPT

# 8. 安装基础依赖与最新版 Xray 核心
if command -v apt-get >/dev/null; then
  apt-get update && apt-get install -y curl wget jq uuid-runtime iptables socat
elif command -v yum >/dev/null; then
  yum makecache && yum install -y curl wget jq uuid-runtime iptables socat
fi
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)"

# 9. 核心参数硬编码
UUID=$(cat /proc/sys/kernel/random/uuid)
SHORT_ID=$(openssl rand -hex 8)
PRIVATE_KEY="OHiRUZqq1Yfo5JA6FataI9RzKTE7WPrUoeteBLUpTWc"
PUBLIC_KEY="8mYkd-02gEB5H0P_d0EcrhXt009P4jBKxba5A1AbE0I"
DEST_SERVER="www.microsoft.com"

# 10. 写入配置
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

# 11. 重启服务
chmod 644 /usr/local/etc/xray/config.json
chown -R nobody:nogroup /usr/local/etc/xray 2>/dev/null || chown -R nobody:nobody /usr/local/etc/xray 2>/dev/null
systemctl daemon-reload && systemctl enable xray && systemctl restart xray

sleep 2

# 12. 🌟 固化快捷查询命令 【sd】
cat << 'EOF' > /usr/local/bin/sd
#!/bin/bash
CONFIG_FILE="/etc/sd_vless_last.conf"
if [ ! -f /usr/local/etc/xray/config.json ] || [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ 错误：未检测到正常的节点账本配置，请重新运行主脚本安装！"
    exit 1
fi

source "$CONFIG_FILE"
IP=$(curl -sS4 https://ifconfig.me || curl -sS4 https://ipinfo.io/ip || curl -sS4 https://api.ipify.org)
PORT=$(jq '.inbounds[0].port' /usr/local/etc/xray/config.json)
UUID=$(jq -r '.inbounds[0].settings.clients[0].id' /usr/local/etc/xray/config.json)
SHORT_ID=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' /usr/local/etc/xray/config.json)
PUBLIC_KEY="8mYkd-02gEB5H0P_d0EcrhXt009P4jBKxba5A1AbE0I"
DEST_SERVER="www.microsoft.com"

echo "=========================================="
echo " 📋 您当前激活的 VLESS-Reality 配置单"
echo "=========================================="
echo " 运行模式:  $TYPE"
echo " 端口 (Port): $PORT"
echo "=========================================="

if [ "$TYPE" == "DOMAIN" ]; then
    echo "👇 您的通用一键导入链接（域名满血版）："
    echo "vless://$UUID@$LAST_DOMAIN:$PORT?security=reality&sni=$DEST_SERVER&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID&flow=xtls-rprx-vision#Reality_Domain_$PORT"
else
    echo "👇 您的通用一键导入链接（纯 IP 测速不报错版）："
    echo "vless://$UUID@$IP:$PORT?security=reality&sni=$DEST_SERVER&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID&flow=xtls-rprx-vision#Reality_IP_Fixed_$PORT"
fi
echo "=========================================="
EOF
chmod +x /usr/local/bin/sd

# 13. 输出成果
/usr/local/bin/sd
