#!/bin/bash

# ==========================================
# Sing-box VLESS-Reality 纯净参数化部署脚本
# ==========================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}错误：请使用 root 用户运行此脚本${NC}"
  exit 1
fi

# 1. 强制读取命令行参数
CUSTOM_DOMAIN=$1
PORT=$2

# 如果没带参数，直接停止执行并报错提示
if [ -z "$CUSTOM_DOMAIN" ] || [ -z "$PORT" ]; then
    echo -e "${RED}错误：参数不完整！管道执行吃掉了输入，请使用带参数的方式运行。${NC}"
    echo -e "正确执行命令格式："
    echo -e "${YELLOW}bash <(curl -sL https://你的github脚本地址) 你的域名 你的端口${NC}"
    echo -e "本地文件执行格式："
    echo -e "${YELLOW}bash vless.sh 你的域名 你的端口${NC}"
    exit 1
fi

echo -e "${GREEN}=== 开始部署 Sing-box ===${NC}"
echo -e "${YELLOW}连接域名: $CUSTOM_DOMAIN | 监听端口: $PORT${NC}"

# 后台随机选取大厂伪装域名 (SNI)
DOMAINS=("www.apple.com" "www.microsoft.com" "www.amazon.com" "dl.google.com")
DEST=${DOMAINS[$RANDOM % ${#DOMAINS[@]}]}
echo -e "${YELLOW}已自动抽取伪装域名 (SNI): $DEST${NC}"
sleep 2

# 安装官方内核
bash <(curl -fsSL https://sing-box.app/deb-install.sh) >/dev/null 2>&1

# 生成密钥
UUID=$(sing-box generate uuid)
KEYS=$(sing-box generate reality-keypair)
PRIVATE_KEY=$(echo "$KEYS" | awk '/PrivateKey/ {print $2}')
PUBLIC_KEY=$(echo "$KEYS" | awk '/PublicKey/ {print $2}')
SHORT_ID=$(sing-box generate rand --hex 8)

# 写入配置
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

# 输出结果
if systemctl is-active --quiet sing-box; then
    SERVER_IP=$(curl -s4 https://api.ipify.org)
    REMARK="SingBox_${CUSTOM_DOMAIN}"
    SHARE_LINK="vless://${UUID}@${CUSTOM_DOMAIN}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${DEST}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&headerType=none#${REMARK}"

    echo ""
    echo -e "${GREEN}✅ 部署成功！${NC}"
    echo -e "连接地址 (Address) : ${YELLOW}$CUSTOM_DOMAIN${NC}"
    echo -e "节点端口 (Port)    : ${YELLOW}$PORT${NC}"
    echo -e "伪装域名 (SNI)     : ${YELLOW}$DEST${NC}"
    echo -e "${YELLOW}👇 请复制以下链接导入 👇${NC}"
    echo -e "${GREEN}${SHARE_LINK}${NC}"
else
    echo -e "${RED}❌ 启动失败，请检查端口是否冲突。${NC}"
fi
