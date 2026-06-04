#!/bin/bash

# VLESS + Reality 智能记忆版 V2
# 新增：IPv4 / IPv6 / 双栈支持

if [ "$EUID" -ne 0 ]; then
  echo "错误：请使用 root 用户运行此脚本！"
  exit 1
fi

echo "=========================================================="
echo "      VLESS + Reality 纯净智能双模账本 V2"
echo "=========================================================="

CONFIG_FILE="/etc/sd_vless_last.conf"
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"

# 节点类型
if [ -n "$LAST_NODE_MODE" ]; then
    read -p "👉 节点类型 1.IPv4 2.IPv6 3.双栈 [默认上次:$LAST_NODE_MODE]：" NODE_MODE
    [ -z "$NODE_MODE" ] && NODE_MODE="$LAST_NODE_MODE"
else
    read -p "👉 节点类型 1.IPv4 2.IPv6 3.双栈(默认)：" NODE_MODE
    [ -z "$NODE_MODE" ] && NODE_MODE="3"
fi

IPV4=$(curl -sS4 https://ifconfig.me 2>/dev/null || curl -sS4 https://api.ipify.org)
IPV6=$(curl -sS6 https://ifconfig.me 2>/dev/null || curl -sS6 https://api64.ipify.org)

case "$NODE_MODE" in
  1) IP="$IPV4" ;;
  2) IP="$IPV6" ;;
  *) IP="$IPV4" ;;
esac

# 域名
if [ -n "$LAST_NEED_DOMAIN" ]; then
    read -p "👉 是否需要使用域名连接？[y/N] (上次:$LAST_NEED_DOMAIN): " NEED_DOMAIN
    [ -z "$NEED_DOMAIN" ] && NEED_DOMAIN=$LAST_NEED_DOMAIN
else
    read -p "👉 是否需要使用域名连接？[y/N] : " NEED_DOMAIN
    [ -z "$NEED_DOMAIN" ] && NEED_DOMAIN=n
fi

if [[ "$NEED_DOMAIN" =~ ^[Yy]$ ]]; then
    TYPE="DOMAIN"
    read -p "👉 域名(回车使用上次): " DOMAIN
    [ -z "$DOMAIN" ] && DOMAIN="$LAST_DOMAIN"

    echo "🔍 校验DNS..."

    if [ "$NODE_MODE" = "2" ]; then
        DOMAIN_IP=$(getent ahostsv6 "$DOMAIN" | head -1 | awk '{print $1}')
        CHECK_IP="$IPV6"
    else
        DOMAIN_IP=$(getent ahostsv4 "$DOMAIN" | head -1 | awk '{print $1}')
        CHECK_IP="$IPV4"
    fi

    if [ -n "$DOMAIN_IP" ] && [ "$DOMAIN_IP" != "$CHECK_IP" ]; then
        echo "⚠️ DNS与VPS地址不匹配"
    fi
else
    TYPE="IP"
fi

if [ -n "$LAST_PORT" ]; then
    read -p "👉 端口(上次:$LAST_PORT): " PORT
    [ -z "$PORT" ] && PORT=$LAST_PORT
else
    PORT=443
fi

cat > "$CONFIG_FILE" <<EOF
LAST_NEED_DOMAIN="$NEED_DOMAIN"
LAST_DOMAIN="$DOMAIN"
LAST_PORT="$PORT"
LAST_NODE_MODE="$NODE_MODE"
TYPE="$TYPE"
EOF

apt-get update -y >/dev/null 2>&1 || true
apt-get install -y curl wget jq uuid-runtime socat >/dev/null 2>&1 || true

bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)"

KEYS=$(/usr/local/bin/xray x25519)
PRIVATE_KEY=$(echo "$KEYS" | awk '/Private/{print $3}')
PUBLIC_KEY=$(echo "$KEYS" | awk '/Public/{print $3}')

UUID=$(cat /proc/sys/kernel/random/uuid)
SHORT_ID=$(openssl rand -hex 8)
DEST_SERVER="www.microsoft.com"

mkdir -p /usr/local/etc/xray

cat > /usr/local/etc/xray/config.json <<EOF
{
  "log":{"loglevel":"warning"},
  "inbounds":[{
    "listen":"::",
    "port":$PORT,
    "protocol":"vless",
    "settings":{
      "clients":[{
        "id":"$UUID",
        "flow":"xtls-rprx-vision"
      }],
      "decryption":"none"
    },
    "streamSettings":{
      "network":"tcp",
      "security":"reality",
      "realitySettings":{
        "show":false,
        "dest":"$DEST_SERVER:443",
        "serverNames":["$DEST_SERVER"],
        "privateKey":"$PRIVATE_KEY",
        "shortIds":["$SHORT_ID"]
      }
    }
  }],
  "outbounds":[{"protocol":"freedom"}]
}
EOF

systemctl enable xray >/dev/null 2>&1
systemctl restart xray

cat > /usr/local/bin/sd <<EOF
#!/bin/bash
echo "=============================="
echo "VLESS Reality V2"
echo "=============================="

if [ "$TYPE" = "DOMAIN" ]; then
 echo "域名链接:"
 echo "vless://$UUID@$DOMAIN:$PORT?security=reality&sni=$DEST_SERVER&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID&flow=xtls-rprx-vision"
else
 echo "IPv4:"
 echo "vless://$UUID@$IPV4:$PORT?security=reality&sni=$DEST_SERVER&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID&flow=xtls-rprx-vision"

 if [ -n "$IPV6" ]; then
   echo
   echo "IPv6:"
   echo "vless://$UUID@[$IPV6]:$PORT?security=reality&sni=$DEST_SERVER&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID&flow=xtls-rprx-vision"
 fi
fi
EOF

chmod +x /usr/local/bin/sd
/usr/local/bin/sd
