#!/bin/bash

# ==========================================
# Sing-box VLESS-Reality 纯净一键部署脚本
# 适用系统：Debian / Ubuntu
# ==========================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}错误：请使用 root 用户运行此脚本${NC}"
  exit 1
fi

echo -e "${GREEN}=== Sing-box VLESS-Reality 配置 ===${NC}"

# 1. 获取服务器公网 IP
SERVER_IP=$(curl -s4 https://api.ipify.org)

# 2. 交互输入：用户自定义域名
read -p "请输入你解析到本机的域名 (直接回车则使用本机IP $SERVER_IP): " INPUT_DOMAIN
CUSTOM_DOMAIN=${INPUT_DOMAIN:-$SERVER_IP}

# 3. 交互输入：端口
read -p "请输入节点监听端口 (默认 443): " INPUT_PORT
PORT=${INPUT_PORT:-443}

# 4. 后台随机选取高质量大厂伪装域名 (SNI)
DOMAINS=("www.apple.com" "www.microsoft.com" "www.amazon.com" "dl.google.com")
DEST=${DOMAINS[$RANDOM % ${#DOMAINS[@]}]}

echo -e "${YELLOW}配置确认 -> 连接地址: $CUSTOM_DOMAIN | 端口: $PORT | 伪装域名(SNI): $DEST${NC}"
sleep 2

bash <(curl -fsSL https://sing-box.app/deb-install.sh) >/dev/null 2>&1

UUID=$(sing-box generate uuid)
KEYS=$(sing-box generate reality-keypair)
PRIVATE_KEY=$(echo "$KEYS" | awk '/PrivateKey/ {print $2}')
PUBLIC_KEY=$(echo "$KEYS" | awk '/PublicKey/ {print $2}')
SHORT_ID=$(sing-box generate rand --hex 8)

cat > /etc/sing-box/config.json <<EOF
{
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "::",
      "listen_port": $PORT,
      "users": [
        {
          "uuid": "$UUID",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "$DEST",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "$DEST",
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

systemctl daemon-reload
systemctl enable --now sing-box
systemctl restart sing-box

if systemctl is-active --quiet sing-box; then
    REMARK="SingBox_${CUSTOM_DOMAIN}"
    
    # 拼接链接：使用用户输入的域名作为连接地址
    SHARE_LINK="vless://${UUID}@${CUSTOM_DOMAIN}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${DEST}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&headerType=none#${REMARK}"

    echo ""
    echo -e "${GREEN}✅ 部署成功！${NC}"
    echo -e "连接地址 (Address) : ${YELLOW}$CUSTOM_DOMAIN${NC}"
    echo -e "节点端口 (Port)    : ${YELLOW}$PORT${NC}"
    echo -e "伪装域名 (SNI)     : ${YELLOW}$DEST${NC}"
    echo -e "${YELLOW}👇 请复制以下链接导入客户端 👇${NC}"
    echo -e "${GREEN}${SHARE_LINK}${NC}"
else
    echo -e "${RED}❌ 启动失败。${NC}"
fi
