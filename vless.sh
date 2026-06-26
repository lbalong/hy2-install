#!/bin/bash

# 检查是否为 Root 用户
if [ "$EUID" -ne 0 ]; then
  echo "错误：请使用 root 用户运行此脚本！"
  exit 1
fi

echo "=========================================================="
echo "      VLESS + Reality 纯净智能双模账本 (带智能记忆版) v2.0"
echo "=========================================================="

# 1. 预先读取历史配置
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

    # 智能域名 A 记录匹配检查
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

# 5. 端口收集（带历史回显记忆）
if [ -n "$LAST_PORT" ]; then
    read -p "👉 请输入节点监听端口 (直接回车自动使用上次的: $LAST_PORT): " PORT
    [ -z "$PORT" ] && PORT=$LAST_PORT
else
    DEFAULT_PORT=$(shuf -i 10000-65000 -n 1)
    read -p "👉 请输入节点监听端口 (直接回车使用随机端口 $DEFAULT_PORT): " PORT
    [ -z "$PORT" ] && PORT=$DEFAULT_PORT
fi

# 6. Reality dest 目标选择（替代硬编码的 www.microsoft.com）
echo ""
echo "=========================================="
echo " 🎯 选择 Reality 伪装目标 (dest)"
echo "=========================================="
echo "  1. gateway.icloud.com    (Apple iCloud 网关，推荐)"
echo "  2. itunes.apple.com      (Apple iTunes)"
echo "  3. swdist.apple.com      (Apple 软件分发)"
echo "  4. www.samsung.com       (Samsung 官网)"
echo "  5. www.logitech.com      (Logitech 官网)"
echo "  6. dl.google.com         (Google 下载服务)"
echo "  7. 自定义输入"
echo "=========================================="

DEST_OPTIONS=("gateway.icloud.com" "itunes.apple.com" "swdist.apple.com" "www.samsung.com" "www.logitech.com" "dl.google.com")

if [ -n "$LAST_DEST" ]; then
    read -p "👉 请选择 [1-7] (直接回车自动使用上次的: $LAST_DEST): " DEST_CHOICE
    if [ -z "$DEST_CHOICE" ]; then
        DEST_SERVER="$LAST_DEST"
    else
        if [ "$DEST_CHOICE" -ge 1 ] 2>/dev/null && [ "$DEST_CHOICE" -le 6 ]; then
            DEST_SERVER="${DEST_OPTIONS[$((DEST_CHOICE-1))]}"
        elif [ "$DEST_CHOICE" == "7" ]; then
            read -p "👉 请输入自定义 dest 域名: " CUSTOM_DEST
            if [ -z "$CUSTOM_DEST" ]; then echo "❌ 错误：域名不能为空！"; exit 1; fi
            DEST_SERVER="$CUSTOM_DEST"
        else
            echo "❌ 无效选项！"; exit 1
        fi
    fi
else
    read -p "👉 请选择 [1-7] (直接回车默认 1): " DEST_CHOICE
    [ -z "$DEST_CHOICE" ] && DEST_CHOICE="1"
    if [ "$DEST_CHOICE" -ge 1 ] 2>/dev/null && [ "$DEST_CHOICE" -le 6 ]; then
        DEST_SERVER="${DEST_OPTIONS[$((DEST_CHOICE-1))]}"
    elif [ "$DEST_CHOICE" == "7" ]; then
        read -p "👉 请输入自定义 dest 域名: " CUSTOM_DEST
        if [ -z "$CUSTOM_DEST" ]; then echo "❌ 错误：域名不能为空！"; exit 1; fi
        DEST_SERVER="$CUSTOM_DEST"
    else
        echo "❌ 无效选项！"; exit 1
    fi
fi

# 验证 dest 目标的 TLS 1.3 可用性
echo "🔍 正在验证 $DEST_SERVER 的 TLS 1.3 支持..."
if curl -sI --tlsv1.3 --connect-timeout 5 "https://$DEST_SERVER" >/dev/null 2>&1; then
    echo "✅ $DEST_SERVER 支持 TLS 1.3，验证通过。"
else
    echo "⚠️  警告：$DEST_SERVER 的 TLS 1.3 验证未通过（可能是网络原因）。"
    read -p "👉 是否继续使用该目标？(y/N): " FORCE_DEST
    if [[ ! "$FORCE_DEST" =~ ^[Yy]$ ]]; then
        echo "❌ 已终止安装。"
        exit 1
    fi
fi

# 7. 持久化保存本次输入，供下次运行自动检测
echo "LAST_NEED_DOMAIN=\"$NEED_DOMAIN\"" > "$CONFIG_FILE"
echo "LAST_DOMAIN=\"$DOMAIN\"" >> "$CONFIG_FILE"
echo "LAST_PORT=\"$PORT\"" >> "$CONFIG_FILE"
echo "TYPE=\"$TYPE\"" >> "$CONFIG_FILE"
echo "LAST_DEST=\"$DEST_SERVER\"" >> "$CONFIG_FILE"

# 8. 核心速度黑科技：BBR + 16MB 巨型缓冲区 + TCP Fast Open
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

# 9. 防火墙放行端口（仅添加规则，不清空已有规则）
if command -v ufw > /dev/null; then
    ufw allow "$PORT/tcp" >/dev/null 2>&1
    ufw reload >/dev/null 2>&1
fi
if command -v firewall-cmd > /dev/null; then
    firewall-cmd --zone=public --add-port="$PORT/tcp" --permanent >/dev/null 2>&1
    firewall-cmd --reload >/dev/null 2>&1
fi
# 确保端口放行（不清空已有规则）
if ! iptables -C INPUT -p tcp --dport "$PORT" -j ACCEPT 2>/dev/null; then
    iptables -I INPUT -p tcp --dport "$PORT" -j ACCEPT
fi

# 10. 安装基础依赖与最新版 Xray 核心
if command -v apt-get >/dev/null; then
  apt-get update && apt-get install -y curl wget jq uuid-runtime iptables socat openssl
elif command -v yum >/dev/null; then
  yum makecache && yum install -y curl wget jq uuid-runtime iptables socat openssl
fi
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)"

# 11. 核心参数生成（每台机器独立密钥对，UUID 可复用）
# UUID：如果上次有保存则复用，否则新生成
if [ -n "$LAST_UUID" ]; then
    read -p "👉 是否复用上次的 UUID？[Y/n] (直接回车复用: ${LAST_UUID:0:8}...): " REUSE_UUID
    if [[ "$REUSE_UUID" =~ ^[Nn]$ ]]; then
        UUID=$(cat /proc/sys/kernel/random/uuid)
        echo "🔑 已生成新 UUID: $UUID"
    else
        UUID="$LAST_UUID"
        echo "🔑 复用已有 UUID: $UUID"
    fi
else
    UUID=$(cat /proc/sys/kernel/random/uuid)
    echo "🔑 已生成新 UUID: $UUID"
fi

SHORT_ID=$(openssl rand -hex 8)

# 生成独立的 x25519 密钥对（不再使用硬编码公钥）
echo "🔐 正在生成本机独立的 x25519 密钥对..."
KEY_OUTPUT=$(/usr/local/bin/xray x25519 2>/dev/null)
if [ -z "$KEY_OUTPUT" ]; then
    echo "❌ 错误：xray x25519 命令执行失败，请检查 Xray 是否正确安装。"
    exit 1
fi
PRIVATE_KEY=$(echo "$KEY_OUTPUT" | grep "Private key:" | awk '{print $3}')
PUBLIC_KEY=$(echo "$KEY_OUTPUT" | grep "Public key:" | awk '{print $3}')

if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
    echo "❌ 错误：密钥对生成失败！"
    exit 1
fi
echo "✅ 密钥对生成成功 (Public Key: ${PUBLIC_KEY:0:16}...)"

# 保存 UUID 和 PUBLIC_KEY 到配置文件
echo "LAST_UUID=\"$UUID\"" >> "$CONFIG_FILE"
echo "LAST_PUBLIC_KEY=\"$PUBLIC_KEY\"" >> "$CONFIG_FILE"

# 12. 写入配置
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

# 13. 重启服务
chmod 644 /usr/local/etc/xray/config.json
chown -R nobody:nogroup /usr/local/etc/xray 2>/dev/null || chown -R nobody:nobody /usr/local/etc/xray 2>/dev/null
systemctl daemon-reload && systemctl enable xray && systemctl restart xray

sleep 2

# 14. 🌟 固化快捷查询命令 【sd】（所有参数从配置文件和 config.json 动态读取）
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
DEST_SERVER=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' /usr/local/etc/xray/config.json)
PUBLIC_KEY="$LAST_PUBLIC_KEY"

if [ -z "$PUBLIC_KEY" ]; then
    echo "❌ 错误：未找到 Public Key，请重新运行主脚本安装！"
    exit 1
fi

echo "=========================================="
echo " 📋 您当前激活的 VLESS-Reality 配置单"
echo "=========================================="
echo " 运行模式:  $TYPE"
echo " 端口 (Port): $PORT"
echo " 伪装目标 (dest): $DEST_SERVER"
echo " Public Key: ${PUBLIC_KEY:0:16}..."
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

# 15. 输出成果
/usr/local/bin/sd
