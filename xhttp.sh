#!/bin/bash

# 检查是否为 Root 用户
if [ "$EUID" -ne 0 ]; then
  echo "❌ 错误：请使用 root 用户运行此脚本！"
  exit 1
fi

# ================= 卸载功能 =================
uninstall_node() {
  echo "=========================================="
  echo "  正在卸载节点配置及证书..."
  echo "=========================================="
  
  if systemctl is-active --quiet xray; then
      systemctl stop xray
      systemctl disable xray
  fi

  if command -v curl >/dev/null; then
      bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove >/dev/null 2>&1
  fi

  if [ -f ~/.acme.sh/acme.sh ]; then
      ~/.acme.sh/acme.sh --uninstall >/dev/null 2>&1
  fi
  rm -rf ~/.acme.sh /usr/local/etc/xray

  echo "✅ 卸载完成！环境已纯净。"
  exit 0
}

# ================= 安装功能 =================
install_node() {
  echo "=========================================="
  echo "  VLESS CDN 节点部署 (多模式选择版)"
  echo "=========================================="
  echo "  1. 仅搭建 xHTTP 单节点"
  echo "  2. 仅搭建 HTTPUpgrade 单节点"
  echo "  3. 同时搭建双节点 (xHTTP + HTTPUpgrade)"
  echo "=========================================="
  read -p "👉 请选择搭建模式 [1-3]: " BUILD_MODE
  if [[ ! "$BUILD_MODE" =~ ^[1-3]$ ]]; then
      echo "❌ 错误：无效的选项！"
      exit 1
  fi

  IP=$(curl -sS4 https://ifconfig.me || curl -sS4 https://api.ipify.org)
  read -p "👉 请输入已解析的域名 (需在 CF 中点亮小黄云): " DOMAIN
  if [ -z "$DOMAIN" ]; then echo "❌ 错误：域名不能为空！"; exit 1; fi
  
  # 收集所需端口
  if [[ "$BUILD_MODE" == "1" || "$BUILD_MODE" == "3" ]]; then
      read -p "👉 请输入 xHTTP 监听端口 (推荐 2083): " PORT_XH
      [ -z "$PORT_XH" ] && PORT_XH=2083
  fi

  if [[ "$BUILD_MODE" == "2" || "$BUILD_MODE" == "3" ]]; then
      read -p "👉 请输入 HTTPUpgrade 监听端口 (推荐 2087): " PORT_HU
      [ -z "$PORT_HU" ] && PORT_HU=2087
  fi

  # 检查双节点端口是否冲突
  if [[ "$BUILD_MODE" == "3" && "$PORT_XH" == "$PORT_HU" ]]; then
      echo "❌ 错误：双节点模式下，两个端口不能相同！"
      exit 1
  fi

  # 安装依赖与核心
  echo "⚙️ 正在安装依赖和核心..."
  if command -v apt-get >/dev/null; then
      apt-get update -y && apt-get install -y curl socat cron jq uuid-runtime iptables
  elif command -v yum >/dev/null; then
      yum makecache && yum install -y curl socat cron jq uuid-runtime iptables
  fi
  bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

  # 防火墙放行
  if command -v ufw > /dev/null; then 
    ufw allow 80/tcp >/dev/null 2>&1
    [[ -n "$PORT_XH" ]] && ufw allow $PORT_XH/tcp >/dev/null 2>&1
    [[ -n "$PORT_HU" ]] && ufw allow $PORT_HU/tcp >/dev/null 2>&1
  fi
  iptables -I INPUT -p tcp --dport 80 -j ACCEPT
  [[ -n "$PORT_XH" ]] && iptables -I INPUT -p tcp --dport $PORT_XH -j ACCEPT
  [[ -n "$PORT_HU" ]] && iptables -I INPUT -p tcp --dport $PORT_HU -j ACCEPT

  # 申请证书
  echo "🔐 正在检查/申请域名证书..."
  mkdir -p /usr/local/etc/xray
  
  # 如果证书不存在，则尝试申请
  if [ ! -f /usr/local/etc/xray/server.crt ]; then
      systemctl stop nginx 2>/dev/null
      systemctl stop apache2 2>/dev/null
      curl -sL https://get.acme.sh | sh
      ~/.acme.sh/acme.sh --upgrade --auto-upgrade
      ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
      ~/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone -k ec-256
      
      ~/.acme.sh/acme.sh --installcert -d "$DOMAIN" \
        --fullchainpath /usr/local/etc/xray/server.crt \
        --keypath /usr/local/etc/xray/server.key \
        --ecc

      if [ ! -f /usr/local/etc/xray/server.crt ]; then
          echo "❌ 证书申请失败！请临时关闭小黄云后重试。"
          exit 1
      fi
  else
      echo "✅ 检测到已有证书，直接复用。"
  fi

  chmod 644 /usr/local/etc/xray/server.crt
  chmod 644 /usr/local/etc/xray/server.key
  chown nobody:nogroup /usr/local/etc/xray/server.crt /usr/local/etc/xray/server.key 2>/dev/null || chown nobody:nobody /usr/local/etc/xray/server.crt /usr/local/etc/xray/server.key 2>/dev/null

  UUID=$(cat /proc/sys/kernel/random/uuid)
  PATH_XH="/xhttp"
  PATH_HU="/httpupgrade"

  # 动态生成 JSON 配置的 Inbounds 数组
  INBOUNDS_JSON=""

  # 构建 xHTTP 模块
  if [[ "$BUILD_MODE" == "1" || "$BUILD_MODE" == "3" ]]; then
      INBOUNDS_JSON+="$(cat <<EOF
    {
      "port": $PORT_XH,
      "protocol": "vless",
      "settings": {
        "clients": [{"id": "$UUID", "level": 0}],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "tls",
        "tlsSettings": {
          "alpn": ["h2", "http/1.1"],
          "certificates": [{"certificateFile": "/usr/local/etc/xray/server.crt", "keyFile": "/usr/local/etc/xray/server.key"}]
        },
        "xhttpSettings": {"path": "$PATH_XH", "host": "$DOMAIN", "mode": "auto"}
      },
      "sniffing": {"enabled": true, "destOverride": ["http", "tls", "quic"]}
    }
EOF
)"
  fi

  # 如果是双节点，需要加一个逗号分隔
  if [[ "$BUILD_MODE" == "3" ]]; then
      INBOUNDS_JSON+=","
  fi

  # 构建 HTTPUpgrade 模块
  if [[ "$BUILD_MODE" == "2" || "$BUILD_MODE" == "3" ]]; then
      INBOUNDS_JSON+="$(cat <<EOF
    {
      "port": $PORT_HU,
      "protocol": "vless",
      "settings": {
        "clients": [{"id": "$UUID", "level": 0}],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "httpupgrade",
        "security": "tls",
        "tlsSettings": {
          "alpn": ["http/1.1"],
          "certificates": [{"certificateFile": "/usr/local/etc/xray/server.crt", "keyFile": "/usr/local/etc/xray/server.key"}]
        },
        "httpupgradeSettings": {"path": "$PATH_HU", "host": "$DOMAIN"}
      },
      "sniffing": {"enabled": true, "destOverride": ["http", "tls", "quic"]}
    }
EOF
)"
  fi

  # 拼装完整配置文件
  cat <<EOF > /usr/local/etc/xray/config.json
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
$INBOUNDS_JSON
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
EOF

  chmod 644 /usr/local/etc/xray/config.json
  systemctl daemon-reload && systemctl enable xray && systemctl restart xray
  sleep 2

  if ! systemctl is-active --quiet xray; then
      echo "❌ Xray 启动失败！这说明配置有误或端口被占用（如 3x-ui）。日志如下："
      journalctl -u xray -n 10 --no-pager
      exit 1
  fi

  echo "=========================================="
  echo " ✅ 节点部署成功！"
  echo "=========================================="
  
  if [[ "$BUILD_MODE" == "1" || "$BUILD_MODE" == "3" ]]; then
      echo "👇 [VLESS + xHTTP 节点链接]"
      echo "vless://$UUID@$DOMAIN:$PORT_XH?type=xhttp&security=tls&sni=$DOMAIN&path=$PATH_XH&host=$DOMAIN&mode=auto#VLESS-xHTTP"
      echo ""
  fi

  if [[ "$BUILD_MODE" == "2" || "$BUILD_MODE" == "3" ]]; then
      echo "👇 [VLESS + HTTPUpgrade 节点链接]"
      echo "vless://$UUID@$DOMAIN:$PORT_HU?type=httpupgrade&security=tls&sni=$DOMAIN&path=$PATH_HU&host=$DOMAIN&alpn=http%2F1.1#VLESS-HTTPUpgrade"
      echo ""
  fi
  echo "=========================================="
}

# ================= 主菜单 =================
echo "=========================================="
echo "  VLESS 模块化管理 (xHTTP / HTTPUpgrade)"
echo "=========================================="
echo "  1. 安装节点"
echo "  2. 彻底卸载清理"
echo "  0. 退出"
echo "=========================================="
read -p "👉 请输入操作选项 [0-2]: " MENU_CHOICE

case $MENU_CHOICE in
  1) install_node ;;
  2) uninstall_node ;;
  0) exit 0 ;;
  *) exit 1 ;;
esac
