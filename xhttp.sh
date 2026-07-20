#!/bin/bash

# 检查是否为 Root 用户
if [ "$EUID" -ne 0 ]; then
  echo "❌ 错误：请使用 root 用户运行此脚本！"
  exit 1
fi

# ================= 卸载节点功能 =================
uninstall_node() {
  echo "=========================================================="
  echo "  正在卸载 Xray 节点及相关证书配置..."
  echo "=========================================================="
  
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

  echo "✅ 卸载完成！"
  exit 0
}

# ================= 安装节点功能 =================
install_node() {
  echo "=========================================================="
  echo "  VLESS + HTTPUpgrade/xHTTP + TLS (CDN ALPN 修复版)"
  echo "=========================================================="

  IP=$(curl -sS4 https://ifconfig.me || curl -sS4 https://api.ipify.org)
  read -p "👉 请输入已解析的域名 (确保在 CF 中已点亮小黄云): " DOMAIN
  if [ -z "$DOMAIN" ]; then echo "❌ 错误：域名不能为空！"; exit 1; fi

  # 强制提示 CF 支持的端口
  echo "⚠️  注意：套用 Cloudflare CDN 必须使用特定的端口，否则会被 CF 直接拦截！"
  echo "推荐端口: 443, 2053, 2083, 2087, 2096, 8443"
  
  read -p "👉 请输入 HTTPUpgrade 监听端口 (默认 443): " PORT_HU
  [ -z "$PORT_HU" ] && PORT_HU=443

  read -p "👉 请输入 xHTTP 监听端口 (默认 8443): " PORT_XH
  [ -z "$PORT_XH" ] && PORT_XH=8443

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
    ufw allow $PORT_HU/tcp >/dev/null 2>&1
    ufw allow $PORT_XH/tcp >/dev/null 2>&1
  fi
  iptables -I INPUT -p tcp --dport 80 -j ACCEPT
  iptables -I INPUT -p tcp --dport $PORT_HU -j ACCEPT
  iptables -I INPUT -p tcp --dport $PORT_XH -j ACCEPT

  # 申请证书
  echo "🔐 正在通过 Acme.sh 申请证书..."
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
      echo "❌ 致命错误：证书申请失败！"
      echo "由于你开启了小黄云，CF 可能会拦截 80 端口的验证请求。请临时关闭小黄云（改为仅DNS），重新运行脚本安装，安装成功后再开启小黄云！"
      exit 1
  fi

  # 修复点2：严格修复证书权限，防止 Xray (nobody用户) 无法读取导致崩溃
  chmod 644 /usr/local/etc/xray/server.crt
  chmod 644 /usr/local/etc/xray/server.key
  chown nobody:nogroup /usr/local/etc/xray/server.crt /usr/local/etc/xray/server.key 2>/dev/null || chown nobody:nobody /usr/local/etc/xray/server.crt /usr/local/etc/xray/server.key 2>/dev/null

  UUID=$(cat /proc/sys/kernel/random/uuid)
  PATH_HU="/httpupgrade"
  PATH_XH="/xhttp"

  # 写入配置 (修复点1：加入了 ALPN 限制)
  cat <<EOF > /usr/local/etc/xray/config.json
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
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
          "certificates": [
            {
              "certificateFile": "/usr/local/etc/xray/server.crt",
              "keyFile": "/usr/local/etc/xray/server.key"
            }
          ]
        },
        "httpupgradeSettings": {
          "path": "$PATH_HU",
          "host": "$DOMAIN"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      }
    },
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

  # 修复点3：增加服务端存活硬校验
  if ! systemctl is-active --quiet xray; then
      echo "=========================================="
      echo "❌ 致命错误：Xray 核心启动失败！"
      echo "服务端内部报错，可能是端口冲突或配置异常。最后 20 行报错日志如下："
      journalctl -u xray -n 20 --no-pager
      exit 1
  fi

  echo "=========================================="
  echo " ✅ 配置成功运行！您的 CDN 专属节点已就绪："
  echo "=========================================="
  
  echo "👇 节点 1：VLESS + HTTPUpgrade + TLS (端口 $PORT_HU)"
  echo "vless://$UUID@$DOMAIN:$PORT_HU?type=httpupgrade&security=tls&sni=$DOMAIN&path=$PATH_HU&host=$DOMAIN&alpn=http%2F1.1#VLESS-HTTPUpgrade"
  echo ""
  
  echo "👇 节点 2：VLESS + xHTTP + TLS (端口 $PORT_XH)"
  echo "vless://$UUID@$DOMAIN:$PORT_XH?type=xhttp&security=tls&sni=$DOMAIN&path=$PATH_XH&host=$DOMAIN&mode=auto#VLESS-xHTTP"
  echo "=========================================="
}

# ================= 主菜单 =================
echo "=========================================================="
echo "    VLESS + HTTPUpgrade/xHTTP + TLS 修复版"
echo "=========================================================="
echo "  1. 安装双协议节点"
echo "  2. 卸载节点及清理证书"
echo "  0. 退出"
echo "=========================================================="
read -p "👉 请输入数字选择操作 [0-2]: " MENU_CHOICE

case $MENU_CHOICE in
  1) install_node ;;
  2) uninstall_node ;;
  0) exit 0 ;;
  *) exit 1 ;;
esac
