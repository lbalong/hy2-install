# 1. 提取你之前已经在账本里定好的端口和密码，不搞丢资产
PORT=$(grep -oE '"listen_port": [0-9]+' /etc/sing-box/config.json | head -n 1 | awk '{print $2}')
PASSWORD=$(grep -oE '"password": "[^"]+"' /etc/sing-box/config.json | head -n 1 | cut -d'"' -f4)
IP=$(curl -sS4 https://ifconfig.me || curl -sS4 https://api.ipify.org)
SHORT_ID=$(openssl rand -hex 8)

# 2. 修正关键词（使用无空格的 PrivateKey/PublicKey）提取真实密钥
KEYPAIR=$(/usr/local/bin/sing-box generate reality-keypair)
PRIVATE_KEY=$(echo "$KEYPAIR" | awk '/PrivateKey/ {print $2}')
PUBLIC_KEY=$(echo "$KEYPAIR" | awk '/PublicKey/ {print $2}')

# 3. 100% 还原并覆写符合官方原生规范的 config.json
cat << EOF > /etc/sing-box/config.json
{
  "log": {
    "level": "info"
  },
  "inbounds": [
    {
      "type": "anytls",
      "tag": "anytls-in",
      "listen": "::",
      "listen_port": $PORT,
      "users": [
        {
          "name": "qiutonglin",
          "password": "$PASSWORD"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "addons.mozilla.org",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "addons.mozilla.org",
            "server_port": 443
          },
          "private_key": "$PRIVATE_KEY",
          "short_id": [
            "$SHORT_ID"
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
EOF

# 4. 让官方内核重新验账
sing-box check -c /etc/sing-box/config.json
