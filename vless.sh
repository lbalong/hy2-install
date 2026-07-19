#!/bin/bash

# 检查是否为 Root 用户
if [ "$EUID" -ne 0 ]; then
  echo "❌ 错误：请使用 root 用户运行此脚本！"
  exit 1
fi

# ================= 卸载节点功能 =================
uninstall_node() {
  echo "=========================================================="
  echo "  正在卸载 VLESS + Reality 节点及相关配置..."
  echo "=========================================================="
  
  # 1. 停止并禁用 Xray 服务
  if systemctl is-active --quiet xray; then
      systemctl stop xray
      systemctl disable xray
  fi

  # 2. 调用 Xray 官方脚本执行卸载 (若官方文件存在)
  if command -v curl >/dev/null; then
      bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove >/dev/null 2>&1
  fi

  # 3. 深度清理可能残留的 Xray 文件
  rm -rf /usr/local/bin/xray
  rm -rf /usr/local/etc/xray
  rm -rf /usr/local/share/xray
  rm -rf /var/log/xray
  rm -f /etc/systemd/system/xray.service
  rm -f /etc/systemd/system/xray@.service
  rm -f /lib/systemd/system/xray.service
  rm -f /lib/systemd/system/xray@.service
  systemctl daemon-reload

  # 4. 清理本脚本生成的独有配置和快捷命令
  rm -f /etc/sd_vless_last.conf
  rm -f /usr/local/bin/sd
  rm -f /etc/sysctl.d/99-vless-reality-passwall.conf
  sysctl --system >/dev/null 2>&1

  echo "✅ 卸载完成！Xray 核心、配置文件及相关快捷命令已全部清除。"
  exit 0
}

# ================= 安装节点功能 =================
install_node() {
  echo "=========================================================="
  echo "    VLESS + Reality 纯净智能双模账本 (带智能记忆版)"
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

  # 8. 防火墙一键清洗
  if command -v ufw > /dev/null; then ufw allow $PORT/tcp >/dev/null 2>&1 && ufw reload >/dev/null 2>&1 && ufw disable >/dev/null 2>&1; fi
  if command -v firewall-cmd > /dev/null; then firewall-cmd --zone=public --add-port=$PORT/tcp --permanent >/dev/null 2>&1 && firewall-cmd --reload >/dev/null 2>&1; fi
  iptables -F && iptables -X
  iptables -P INPUT ACCEPT && iptables -P FORWARD ACCEPT && iptables -P OUTPUT ACCEPT
  iptables -I INPUT -p tcp --dport $PORT -j ACCEPT

  # 9. 安装基础依赖与最新版 Xray 核心
  if command -v apt-get >/dev/null; then
    apt-get update && apt-get install -y curl wget jq uuid-runtime iptables socat
  elif command -v yum >/dev/null; then
    yum makecache && yum install -y curl wget jq uuid-runtime iptables socat
  fi
  bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)"

  # 10. 核心参数硬编码（沿用测速不报错的固定公私钥组合）
  UUID=$(cat /proc/sys/kernel/random/uuid)
  SHORT_ID=$(openssl rand -hex 8)
  PRIVATE_KEY="OHiRUZqq1Yfo5JA6FataI9RzKTE7WPrUoeteBLUpTWc"
  PUBLIC_KEY="8mYkd-02gEB5H0P_d0EcrhXt009P4jBKxba5A1AbE0I"
  DEST_SERVER="www.microsoft.com"

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

  # 14. 输出成果
  /usr/local/bin/sd
}

# ================= 主菜单逻辑 =================
echo "=========================================================="
echo "    VLESS + Reality 纯净智能双模账本管理脚本"
echo "=========================================================="
echo "  1. 安装或更新 VLESS + Reality 节点"
echo "  2. 卸载节点及清理所有配置"
echo "  0. 退出脚本"
echo "=========================================================="
read -p "👉 请输入数字选择操作 [0-2]: " MENU_CHOICE

case $MENU_CHOICE in
  1)
    install_node
    ;;
  2)
    uninstall_node
    ;;
  0)
    echo "已退出脚本。"
    exit 0
    ;;
  *)
    echo "❌ 错误：无效的选择，脚本已退出。"
    exit 1
    ;;
esac
