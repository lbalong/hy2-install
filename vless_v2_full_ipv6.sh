#!/bin/bash

# 检查是否为 Root 用户
if [ "$EUID" -ne 0 ]; then
  echo "❌ 错误：请使用 root 用户运行此脚本！"
  exit 1
fi

echo "=========================================================="
echo "    VLESS + Reality 纯净智能双模账本 (双栈 IPv4+IPv6 版)"
echo "=========================================================="

# 1. 预先读取历史配置
CONFIG_FILE="/etc/sd_vless_last.conf"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# 2. 获取 VPS 本机公网 IP (支持双栈)
echo "🔍 正在探测网络环境..."
IP4=$(curl -sS4 https://api.ipify.org || curl -sS4 https://ifconfig.me --connect-timeout 3)
IP6=$(curl -sS6 https://api64.ipify.org || curl -sS6 https://ifconfig.co --connect-timeout 3)

if [ -z "$IP4" ] && [ -z "$IP6" ]; then
  echo "❌ 错误：无法获取服务器公网 IPv4 或 IPv6 地址，请检查网络连接。"
  exit 1
fi

[ -n "$IP4" ] && echo "✅ 探测到 IPv4: $IP4"
[ -n "$IP6" ] && echo "✅ 探测到 IPv6: $IP6"

# 3. 询问是否需要域名 (默认 n)
if [ -n "$LAST_NEED_DOMAIN" ]; then
    read -p "👉 是否需要使用域名连接？[y/N] (直接回车自动使用上次的: $LAST_NEED_DOMAIN): " NEED_DOMAIN
    [ -z "$NEED_DOMAIN" ] && NEED_DOMAIN=$LAST_NEED_DOMAIN
else
    read -p "👉 是否需要使用域名连接？[y/N] (直接回车默认不使用 N): " NEED_DOMAIN
    [ -z "$NEED_DOMAIN" ] && NEED_DOMAIN="n"
fi

# 4. 根据交互进行逻辑分流与 DNS 对账
if [[ "$NEED_DOMAIN" =~ ^[Yy]$ ]]; then
    TYPE="DOMAIN"
    if [ -n "$LAST_DOMAIN" ]; then
        read -p "👉 请输入已解析的完整域名 (直接回车自动使用上次的: $LAST_DOMAIN): " DOMAIN
        [ -z "$DOMAIN" ] && DOMAIN=$LAST_DOMAIN
    else
        read -p "👉 请输入已解析的完整域名 (例如 sg.099889.xyz): " DOMAIN
        if [ -z "$DOMAIN" ]; then echo "❌ 错误：域名不能为空！"; exit 1; fi
    fi

    # 智能域名 A/AAAA 记录匹配检查
    echo "🔍 正在校验域名 DNS 解析状态..."
    DOMAIN_IP4=$(getent ahosts "$DOMAIN" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -n 1 | awk '{print $1}')
    DOMAIN_IP6=$(getent ahosts "$DOMAIN" | grep -E '^[0-9a-fA-F:]+$' | head -n 1 | awk '{print $1}')

    MATCHED=0
    if [ -n "$IP4" ] && [ "$DOMAIN_IP4" == "$IP4" ]; then MATCHED=1; fi
    if [ -n "$IP6" ] && [ "$DOMAIN_IP6" == "$IP6" ]; then MATCHED=1; fi

    if [ $MATCHED -eq 0 ]; then
        echo "=========================================="
        echo "⚠️  核心警告：域名解析 IP 与当前 VPS 公网 IP 不匹配！"
        [ -n "$IP4" ] && echo "   - 当前 VPS IPv4: $IP4"
        [ -n "$IP6" ] && echo "   - 当前 VPS IPv6: $IP6"
        [ -n "$DOMAIN_IP4" ] && echo "   - 域名解析出的 IPv4: $DOMAIN_IP4"
        [ -n "$DOMAIN_IP6" ] && echo "   - 域名解析出的 IPv6: $DOMAIN_IP6"
        echo "=========================================="
        read -p "👉 是否确认解析已生效，并强行继续安装？(y/N): " FORCE_INSTALL
        if [[ ! "$FORCE_INSTALL" =~ ^[Yy]$ ]]; then
            echo "❌ 已安全终止安装。"
            exit 1
        fi
    else
        echo "✅ 完美对齐！域名已精准指向当前 VPS，通过安全验证。"
    fi
else
    TYPE="IP"
fi

# 5. 端口收集（带历史回显记忆）
if [ -n "$LAST_PORT" ]; then
    read -p "👉 请输入节点监听端口 (直接回车自动使用上次的: $LAST_PORT): " PORT
    [ -z "$PORT" ] && PORT=$LAST_PORT
else
    DEFAULT_PORT=$(shuf -i 10000-65000 -n 1)
    read -p "👉 请输入节点监听端口 (直接回车使用随机端口 $DEFAULT_PORT): " PORT
    [ -z "$PORT" ] && PORT=$DEFAULT_PORT
fi

# 6. 持久化保存本次输入，供下次运行自动检测
echo "LAST_NEED_DOMAIN=\"$NEED_DOMAIN\"" > "$CONFIG_FILE"
echo "LAST_DOMAIN=\"$DOMAIN\"" >> "$CONFIG_FILE"
echo "LAST_PORT=\"$PORT\"" >> "$CONFIG_FILE"
echo "TYPE=\"$TYPE\"" >> "$CONFIG_FILE"

# 7. 核心速度黑科技：BBR + 16MB 巨型缓冲区 + TCP Fast Open
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

# 8. 防火墙一键清洗 (双栈)
if command -v ufw > /dev/null; then ufw allow $PORT/tcp >/dev/null 2>&1 && ufw reload >/dev/null 2>&1 && ufw disable >/dev/null 2>&1; fi
if command -v firewall-cmd > /dev/null; then firewall-cmd --zone=public --add-port=$PORT/tcp --permanent >/dev/null 2>&1 && firewall-cmd --reload >/dev/null 2>&1; fi
iptables -F && iptables -X
iptables -P INPUT ACCEPT && iptables -P FORWARD ACCEPT && iptables -P OUTPUT ACCEPT
iptables -I INPUT -p tcp --dport $PORT -j ACCEPT
if command -v ip6tables > /dev/null; then
    ip6tables -F && ip6tables -X
    ip6tables -P INPUT ACCEPT && ip6tables -P FORWARD ACCEPT && ip6tables -P OUTPUT ACCEPT
    ip6tables -I INPUT -p tcp --dport $PORT -j ACCEPT 2>/dev/null
fi

# 9. 安装基础依赖与最新版 Xray 核心
if command -v apt-get >/dev/null; then
  apt-get update && apt-get install -y curl wget jq uuid-runtime iptables socat
elif command -v yum >/dev/null; then
  yum makecache && yum install -y curl wget jq uuid-runtime iptables socat
fi
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)"

# 10. 核心参数硬编码
UUID=$(cat /proc/sys/kernel/random/uuid)
SHORT_ID=$(openssl rand -hex 8)
PRIVATE_KEY="OHiRUZqq1Yfo5JA6FataI9RzKTE7WPrUoeteBLUpTWc"
PUBLIC_KEY="8mYkd-02gEB5H0P_d0EcrhXt009P4jBKxba5A1AbE0I"
DEST_SERVER="www.microsoft.com"

# 动态判断监听地址，有 IPv6 时绑定到 :: 才能同时监听双栈
LISTEN_IP="0.0.0.0"
if [ -n "$IP6" ]; then
    LISTEN_IP="::"
fi

# 11. 写入配置
mkdir -p /usr/local/etc/xray
cat <<EOF > /usr/local/etc/xray/config.json
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": $PORT,
      "listen": "$LISTEN_IP",
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

# 12. 重启服务
chmod 644 /usr/local/etc/xray/config.json
chown -R nobody:nogroup /usr/local/etc/xray 2>/dev/null || chown -R nobody:nobody /usr/local/etc/xray 2>/dev/null
systemctl daemon-reload && systemctl enable xray && systemctl restart xray

sleep 2

# 13. 🌟 固化快捷查询命令 【sd】
cat << 'EOF' > /usr/local/bin/sd
#!/bin/bash
CONFIG_FILE="/etc/sd_vless_last.conf"
if [ ! -f /usr/local/etc/xray/config.json ] || [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ 错误：未检测到正常的节点账本配置，请重新运行主脚本安装！"
    exit 1
fi

source "$CONFIG_FILE"
IP4=$(curl -sS4 https://api.ipify.org --connect-timeout 2 2>/dev/null)
IP6=$(curl -sS6 https://api64.ipify.org --connect-timeout 2 2>/dev/null)
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
    echo "👇 您的通用一键导入链接（域名双栈通杀版）："
    echo "vless://$UUID@$LAST_DOMAIN:$PORT?security=reality&sni=$DEST_SERVER&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID&flow=xtls-rprx-vision#Reality_Domain_$PORT"
else
    if [ -n "$IP4" ]; then
        echo "👇 您的通用一键导入链接（IPv4 测速不报错版）："
        echo "vless://$UUID@$IP4:$PORT?security=reality&sni=$DEST_SERVER&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID&flow=xtls-rprx-vision#Reality_IPv4_$PORT"
        echo ""
    fi
    if [ -n "$IP6" ]; then
        echo "👇 您的通用一键导入链接（IPv6 专属直连版）："
        echo "vless://$UUID@[${IP6}]:$PORT?security=reality&sni=$DEST_SERVER&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID&flow=xtls-rprx-vision#Reality_IPv6_$PORT"
    fi
fi
echo "=========================================="
EOF
chmod +x /usr/local/bin/sd

# 14. 输出成果
/usr/local/bin/sd
