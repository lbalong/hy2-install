#!/bin/bash

# ==========================================
# Sing-box VLESS-Reality 纯净交互式一键部署脚本
# ==========================================

# 强行夺回标准输入控制权，解决 curl 执行时无法交互的问题！
exec < /dev/tty

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}错误：请使用 root 用户运行此脚本${NC}"
  exit 1
fi

echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}=== Sing-box VLESS-Reality 交互配置 ===${NC}"
echo -e "${GREEN}=====================================${NC}"

# 获取服务器公网 IP
SERVER_IP=$(curl -s4 https://api.ipify.org)

# 1. 交互询问：域名
echo ""
echo -e "${YELLOW}第一步：请输入你的域名 (例如: node.yourdomain.com)${NC}"
read -p "如果还没有域名，直接按回车将使用本机IP ($SERVER_IP): " INPUT_DOMAIN
CUSTOM_DOMAIN=${INPUT_DOMAIN:-$SERVER_IP}

# 2. 交互询问：端口
echo ""
echo -e "${YELLOW}第二步：请输入节点监听端口${NC}"
read -p "建议使用自定义端口，直接按回车将默认使用 443: " INPUT_PORT
PORT=${INPUT_PORT:-443}

# 3. 后台随机选取高质量大厂伪装域名 (SNI)
DOMAINS=("www.apple.com" "www.microsoft.com" "www.amazon.com" "dl.google.com")
DEST=${DOMAINS[$RANDOM % ${#DOMAINS[@]}]}

echo ""
echo -e "${GREEN}=====================================${NC}"
echo -e "你的连接地址将是 : ${YELLOW}$CUSTOM_DOMAIN${NC}"
echo -e "你的节点端口将是 : ${YELLOW}$PORT${NC}"
echo -e "后台自动伪装域名 : ${YELLOW}$DEST${NC}"
echo -e "${GREEN}=====================================${NC}"
echo -e "${YELLOW}开始部署，请稍候...${NC}"
echo ""
sleep 2

# 安装官方内核
bash <(curl -fsSL https://sing-box.app/deb-install.sh) >/dev/null 2>&1

# 生成密钥
UUID=$(sing-box generate uuid)
KEYS=$(sing-box generate reality-keypair)
PRIVATE_KEY=$(echo "$KEYS" | awk '/PrivateKey/ {print $2}')
PUBLIC_KEY=$(echo "$KEYS" | awk '/PublicKey/ {print $2}')
SHORT_ID=$(sing-box generate rand --hex 8)

# 写入配置 (注意：inbounds 里的 listen_port 是你的自定义端口，但 reality 里的 server_port 必须是苹果/微软官方的 443，绝不能改)
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

# 重启服务
systemctl daemon-reload
systemctl enable --now sing-box
systemctl restart sing-box

# 输出结果
if systemctl is-active --quiet sing-box; then
    REMARK="SingBox_${CUSTOM_DOMAIN}"
    SHARE_LINK="vless://${UUID}@${CUSTOM_DOMAIN}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${DEST}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&headerType=none#${REMARK}"

    echo ""
    echo -e "${GREEN}✅ 部署成功！${NC}"
    echo -e "${YELLOW}👇 请复制以下链接导入客户端 👇${NC}"
    echo ""
    echo -e "${GREEN}${SHARE_LINK}${NC}"
    echo ""
    
    # 提醒云服务器防火墙
    if [ "$PORT" != "443" ]; then
        echo -e "${RED}⚠️ 重要提醒：你使用了自定义端口 ${PORT}！${NC}"
        echo -e "${YELLOW}请务必去云服务商（如 GCP/AWS）的网页控制台 -> 防火墙/安全组，放行 TCP ${PORT} 端口，否则节点绝对连不上！${NC}"
    fi
else
    echo -e "${RED}❌ 启动失败，请检查你的端口 ${PORT} 是否被占用。${NC}"
fi
