#!/bin/bash

# ==========================================
# Sing-box VLESS-Reality 纯净一键部署脚本
# 适用系统：Debian / Ubuntu
# ==========================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# 1. 检查 root 权限
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}错误：请使用 root 用户运行此脚本${NC}"
  exit 1
fi

# 2. 交互式配置参数
echo -e "${GREEN}=== Sing-box VLESS-Reality 配置 ===${NC}"

# 获取伪装域名
read -p "请输入伪装域名 (默认 www.apple.com，直接回车使用默认值): " INPUT_DEST
DEST=${INPUT_DEST:-www.apple.com}

# 获取监听端口
read -p "请输入节点端口 (默认 443，直接回车使用默认值): " INPUT_PORT
PORT=${INPUT_PORT:-443}

echo -e "${YELLOW}配置确认 -> 端口: $PORT | 伪装域名: $DEST${NC}"
echo -e "${GREEN}=====================================${NC}"
sleep 2

# 3. 安装官方环境
echo -e "${YELLOW}正在清理旧版本并安装最新版 Sing-box 核心...${NC}"
bash <(curl -fsSL https://sing-box.app/deb-install.sh) >/dev/null 2>&1

# 4. 生成密钥与参数
echo -e "${YELLOW}正在本地生成强加密密钥...${NC}"
UUID=$(sing-box generate uuid)
KEYS=$(sing-box generate reality-keypair)
PRIVATE_KEY=$(echo "$KEYS" | awk '/PrivateKey/ {print $2}')
PUBLIC_KEY=$(echo "$KEYS" | awk '/PublicKey/ {print $2}')
SHORT_ID=$(sing-box generate rand --hex 8)

# 获取服务器公网 IP
SERVER_IP=$(curl -s4 https://api.ipify.org)
if [ -z "$SERVER_IP" ]; then
    SERVER_IP=$(curl -s6 https://api64.ipify.org)
fi

# 5. 生成配置文件
echo -e "${YELLOW}正在重写配置文件...${NC}"
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

# 6. 重启服务
echo -e "${YELLOW}正在启动服务并设置开机自启...${NC}"
systemctl daemon-reload
systemctl enable --now sing-box
systemctl restart sing-box

# 7. 检查状态并输出链接
if systemctl is-active --quiet sing-box; then
    # 对节点名称进行简单的 URL 编码 (处理空格)
    REMARK="SingBox_${SERVER_IP}"
    
    # 拼接标准的 VLESS 分享链接
    SHARE_LINK="vless://${UUID}@${SERVER_IP}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${DEST}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&headerType=none#${REMARK}"

    echo ""
    echo -e "${GREEN}==================================================${NC}"
    echo -e "${GREEN}✅ Sing-box VLESS-Reality 部署成功！${NC}"
    echo -e "${GREEN}==================================================${NC}"
    echo -e "服务器 IP    : ${YELLOW}$SERVER_IP${NC}"
    echo -e "节点端口     : ${YELLOW}$PORT${NC}"
    echo -e "伪装域名     : ${YELLOW}$DEST${NC}"
    echo -e "${GREEN}==================================================${NC}"
    echo -e "${YELLOW}👇 请复制以下链接，直接导入 v2rayN 或 PassWall 👇${NC}"
    echo ""
    echo -e "${GREEN}${SHARE_LINK}${NC}"
    echo ""
    echo -e "${GREEN}==================================================${NC}"
else
    echo -e "${RED}❌ 启动失败，请使用命令 'journalctl -u sing-box --no-pager -e' 检查报错日志，或者检查端口是否被占用。${NC}"
fi
