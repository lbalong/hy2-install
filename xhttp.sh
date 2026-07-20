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

  # 调用官方卸载脚本
  if command -v curl >/dev/null; then
      bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove >/dev/null 2>&1
  fi

  # 深度清理 Acme.sh 证书和配置文件夹
  if [ -f ~/.acme.sh/acme.sh ]; then
      ~/.acme.sh/acme.sh --uninstall >/dev/null 2>&1
  fi
  rm -rf ~/.acme.sh
  rm -rf /usr/local/etc/xray

  echo "✅ 卸载完成！Xray 核心及 TLS 证书已全部清除。"
  exit 0
}

# ================= 安装节点功能 =================
install_node() {
  echo "=========================================================="
  echo "  VLESS + HTTPUpgrade/xHTTP + TLS 安装 (基于官方核心)"
  echo "=========================================================="

  # 1. 获取公网 IP 和输入域名
  IP=$(curl -sS4 https://ifconfig.me || curl -sS4 https://api.ipify.org)
  read -p "👉 请输入已解析到本机 ($IP) 的完整域名 (例如 sg.abc.xyz): " DOMAIN
  if [ -z "$DOMAIN" ]; then echo "❌ 错误：域名不能为空！"; exit 1; fi

  # 验证域名解析是否准确 (申请证书必须)
  echo "🔍 正在校验域名 DNS 解析状态..."
  DOMAIN_IP=$(getent ahosts "$DOMAIN" | head -n 1 | awk '{print $1}')
  if [ "$DOMAIN_IP" != "$IP" ]; then
      echo "⚠️  警告：域名解析 IP ($DOMAIN_IP) 与本机 IP ($IP) 不一致！这会导致 TLS 证书申请失败。"
      read -p "👉 是否确认 DNS 已生效并强行继续？(y/N): " FORCE
      if [[ ! "$FORCE" =~ ^[Yy]$ ]]; then exit 1; fi
  fi

  # 2. 端口交互输入
  read -p "👉 请输入 VLESS + HTTPUpgrade 监听端口 (默认 4431): " PORT_HU
  [ -z "$PORT_HU" ] && PORT_HU=4431

  read -p "👉 请输入 VLESS + xHTTP 监听端口 (默认 4432): " PORT_XH
  [ -z "$PORT_XH" ] && PORT_XH=4432

  # 安装基础环境依赖
  echo "⚙️ 正在安装基础依赖和 Xray 官方核心..."
  if command -v apt-get >/dev/null; then
      apt-get update -y && apt-get install -y curl socat cron jq uuid-runtime iptables
  elif command -v yum >/dev/null; then
      yum makecache && yum install -y curl socat cron jq uuid-runtime iptables
  fi
  
  # 调用官方脚本安装最新 Xray
  bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

  # 放行防火墙 (80用于申请证书，后续端口用于代理)
  if command -v ufw > /dev/null; then 
    ufw allow 80/tcp >/dev/null 2>&1
    ufw allow $PORT_HU/tcp >/dev/null 2>&1
    ufw allow $PORT_XH/tcp >/dev/null 2>&1
  fi
  iptables -I INPUT -p tcp --dport 80 -j ACCEPT
  iptables -I INPUT -p tcp --dport $PORT_HU -j ACCEPT
  iptables -I INPUT -p tcp --dport $PORT_XH -j ACCEPT

  # 3. 申请并安装 TLS 证书 (Standalone 模式)
  echo "🔐 正在通过 Acme.sh 申请 Let's Encrypt 证书，请确保 80 端口未被其他程序(如 Nginx)占用..."
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
      echo "❌ 证书申请失败，请检查域名解析是否正确，或 80 端口是否被占用。"
      exit 1
  fi
  chown nobody:nogroup /usr/local/etc/xray/server.crt /usr/local/etc/xray/server.key 2>/dev/null || chown nobody:nobody /usr/local/etc/xray/server.crt /usr/local/etc/xray/server.key 2>/dev/null

  # 4. 动态生成参数
  UUID=$(cat /proc/sys/kernel/random/uuid)
  PATH_HU="/httpupgrade"
  PATH_XH="/xhttp"

  # 5. 写入双节点 Xray 配置文件
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

  # 6. 打印输出链接
  echo "=========================================="
  echo " 📋 配置完成！您的双协议节点已就绪："
  echo "=========================================="
  
  echo "👇 节点 1：VLESS + HTTPUpgrade + TLS (端口 $PORT_HU)"
  echo "vless://$UUID@$DOMAIN:$PORT_HU?type=httpupgrade&security=tls&sni=$DOMAIN&path=$PATH_HU&host=$DOMAIN#VLESS-HTTPUpgrade"
  echo ""
  
  echo "👇 节点 2：VLESS + xHTTP + TLS (端口 $PORT_XH)"
  echo "vless://$UUID@$DOMAIN:$PORT_XH?type=xhttp&security=tls&sni=$DOMAIN&path=$PATH_XH&host=$DOMAIN&mode=auto#VLESS-xHTTP"
  echo "=========================================="
}

# ================= 主菜单逻辑 =================
echo "=========================================================="
echo "    VLESS + HTTPUpgrade/xHTTP + TLS 官方纯净安装脚本"
echo "=========================================================="
echo "  1. 安装双协议节点 (请提前做好域名解析)"
echo "  2. 卸载节点及清理证书"
echo "  0. 退出"
echo "=========================================================="
read -p "👉 请输入数字选择操作 [0-2]: " MENU_CHOICE

case $MENU_CHOICE in
  1) install_node ;;
  2) uninstall_node ;;
  0) exit 0 ;;
  *) echo "❌ 输入错误，已退出。"; exit 1 ;;
esac
