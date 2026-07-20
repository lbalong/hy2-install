#!/bin/bash

# 检查是否为 Root 用户
if [ "$EUID" -ne 0 ]; then
  echo "❌ 错误：请使用 root 用户运行此脚本！"
  exit 1
fi

# ================= 卸载功能 =================
uninstall_node() {
  echo "=========================================="
  echo "  正在卸载单节点配置及证书..."
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
  echo "  VLESS + xHTTP + TLS 单节点测试版"
  echo "=========================================="

  IP=$(curl -sS4 https://ifconfig.me || curl -sS4 https://api.ipify.org)
  read -p "👉 请输入已解析的域名 (需在 CF 中点亮小黄云): " DOMAIN
  if [ -z "$DOMAIN" ]; then echo "❌ 错误：域名不能为空！"; exit 1; fi
  
  read -p "👉 请输入监听端口 (默认使用干净的 2083): " PORT
  [ -z "$PORT" ] && PORT=2083

  # 安装依赖与核心
  if command -v apt-get >/dev/null; then
      apt-get update -y && apt-get install -y curl socat cron jq uuid-runtime iptables
  elif command -v yum >/dev/null; then
      yum makecache && yum install -y curl socat cron jq uuid-runtime iptables
  fi
  bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

  # 防火墙放行
  if command -v ufw > /dev/null; then 
    ufw allow 80/tcp >/dev/null 2>&1
    ufw allow $PORT/tcp >/dev/null 2>&1
  fi
  iptables -I INPUT -p tcp --dport 80 -j ACCEPT
  iptables -I INPUT -p tcp --dport $PORT -j ACCEPT

  # 申请证书
  echo "🔐 正在申请域名证书..."
  systemctl stop nginx 2>/dev/null
  systemctl stop apache2 2>/dev/null
  
  curl -sL https://get.acme.sh | sh
  ~/.acme.sh/acme.sh --upgrade --auto-upgrade
  ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
  ~/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone -k ec-256
  
  mkdir -p /usr/local/etc/xray
  ~/.acme.sh/acme.sh --installcert -d "$DOMAIN" \
    --fullchainpath /usr/local/etc/xray/server.crt \
    --keypath /usr/local/etc/xray/server.key \
    --ecc

  if [ ! -f /usr/local/etc/xray/server.crt ]; then
      echo "❌ 证书申请失败！请临时关闭小黄云后重试。"
      exit 1
  fi

  chmod 644 /usr/local/etc/xray/server.crt
  chmod 644 /usr/local/etc/xray/server.key
  chown nobody:nogroup /usr/local/etc/xray/server.crt /usr/local/etc/xray/server.key 2>/dev/null || chown nobody:nobody /usr/local/etc/xray/server.crt /usr/local/etc/xray/server.key 2>/dev/null

  UUID=$(cat /proc/sys/kernel/random/uuid)
  PATH_XH="/xhttp"

  # 写入单节点配置 (支持 CDN 的 ALPN)
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
        "clients": [{"id": "$UUID", "level": 0}],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "tls",
        "tlsSettings": {
          "alpn": ["h2", "http/1.1"],
          "certificates": [
            {
              "certificateFile": "/usr/local/etc/xray/server.crt",
              "keyFile": "/usr/local/etc/xray/server.key"
            }
          ]
        },
        "xhttpSettings": {
          "path": "$PATH_XH",
          "host": "$DOMAIN",
          "mode": "auto"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
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

  chmod 644 /usr/local/etc/xray/config.json
  systemctl daemon-reload && systemctl enable xray && systemctl restart xray
  sleep 2

  if ! systemctl is-active --quiet xray; then
      echo "❌ Xray 启动失败！日志如下："
      journalctl -u xray -n 10 --no-pager
      exit 1
  fi

  echo "=========================================="
  echo " ✅ 单节点配置成功！"
  echo "=========================================="
  echo "vless://$UUID@$DOMAIN:$PORT?type=xhttp&security=tls&sni=$DOMAIN&path=$PATH_XH&host=$DOMAIN&mode=auto#VLESS-xHTTP"
  echo "=========================================="
}

# ================= 主菜单 =================
echo "=========================================="
echo "    VLESS + xHTTP + TLS (单节点测试版)"
echo "=========================================="
echo "  1. 安装 xHTTP 单节点"
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
