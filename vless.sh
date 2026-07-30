#!/bin/bash

# 强行夺回标准输入控制权
exec < /dev/tty

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}错误：请使用 root 用户运行此脚本${NC}"
  exit 1
fi

# ==========================================
# 卸载功能
# ==========================================
uninstall_node() {
    echo -e "${YELLOW}正在停止 Sing-box 服务...${NC}"
    systemctl stop sing-box 2>/dev/null
    systemctl disable sing-box 2>/dev/null
    
    echo -e "${YELLOW}正在卸载核心程序并清理配置文件...${NC}"
    apt-get remove --purge sing-box -y 2>/dev/null || dpkg -P sing-box 2>/dev/null
    rm -rf /etc/sing-box
    
    echo -e "${GREEN}✅ 卸载完成！系统已清理干净。${NC}"
    exit 0
}

# ==========================================
# 安装功能
# ==========================================
install_node() {
    SERVER_IP=$(curl -s4 https://api.ipify.org)

    echo ""
    echo -e "${YELLOW}第一步：请输入你的域名 (例如: node.yourdomain.com)${NC}"
    read -p "如果还没有域名，直接按回车将使用本机IP ($SERVER_IP): " INPUT_DOMAIN
    CUSTOM_DOMAIN=${INPUT_DOMAIN:-$SERVER_IP}

    echo ""
    echo -e "${YELLOW}第二步：请输入节点监听端口${NC}"
    read -p "建议使用自定义端口，直接按回车将默认使用 443: " INPUT_PORT
    PORT=${INPUT_PORT:-443}

    # ==========================================
    # 自动检测并清空被占用的端口
    # ==========================================
    if ! command -v lsof &> /dev/null; then
        apt-get update -y >/dev/null 2>&1
        apt-get install -y lsof >/dev/null 2>&1
    fi
    PORT_PID=$(lsof -i :$PORT -t)
    if [ -n "$PORT_PID" ]; then
        echo -e "${YELLOW}检测到端口 $PORT 已被占用，正在自动清空相关进程...${NC}"
        kill -9 $PORT_PID >/dev/null 2>&1
        sleep 1
    fi

    # ==========================================
    # 域名解析及 CDN 代理冲突检测
    # ==========================================
    if [ "$CUSTOM_DOMAIN" != "$SERVER_IP" ]; then
        if command -v getent &> /dev/null; then
            RESOLVED_IP=$(getent ahosts "$CUSTOM_DOMAIN" | awk '{ print $1 }' | head -n 1)
            if [ -n "$RESOLVED_IP" ] && [ "$RESOLVED_IP" != "$SERVER_IP" ]; then
                echo -e ""
                echo -e "${RED}======================================================${NC}"
                echo -e "${RED}严重警告：你的域名解析 IP ($RESOLVED_IP) 与本机 IP ($SERVER_IP) 不一致！${NC}"
                echo -e "${YELLOW}注意：如果你在域名托管商处开启了 Cloudflare 的代理（小黄云），节点绝对无法连通！${NC}"
                echo -e "${YELLOW}VLESS-Reality 协议必须直连。如果存在此问题，请立即前往后台关闭代理。${NC}"
                echo -e "${RED}======================================================${NC}"
                sleep 5
            fi
        fi
    fi

    # 剔除可能被墙阻断的伪装域名，替换为最稳的白名单
    DOMAINS=("www.microsoft.com" "www.apple.com" "www.amazon.com")
    DEST=${DOMAINS[$RANDOM % ${#DOMAINS[@]}]}

    echo ""
    echo -e "${GREEN}=====================================${NC}"
    echo -e "你的连接地址将是 : ${YELLOW}$CUSTOM_DOMAIN${NC}"
    echo -e "你的节点端口将是 : ${YELLOW}$PORT${NC}"
    echo -e "后台自动伪装域名 : ${YELLOW}$DEST${NC}"
    echo -e "${GREEN}=====================================${NC}"
    echo -e "${YELLOW}开始部署核心组件，请稍候...${NC}"
    echo ""
    
    # 开启 BBR (安全提速项保留，抛弃危险项)
    if ! grep -q "net.ipv4.tcp_congestion_control" /etc/sysctl.conf; then
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        sysctl -p >/dev/null 2>&1
    fi

    bash <(curl -fsSL https://sing-box.app/deb-install.sh) >/dev/null 2>&1

    UUID=$(sing-box generate uuid)
    KEYS=$(sing-box generate reality-keypair)
    PRIVATE_KEY=$(echo "$KEYS" | awk '/PrivateKey/ {print $2}')
    PUBLIC_KEY=$(echo "$KEYS" | awk '/PublicKey/ {print $2}')
    SHORT_ID=$(sing-box generate rand --hex 8)

    # 还原纯净的配置文件，剔除导致无法启动的 tcp_fast_open
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
        SHARE_LINK="vless://${UUID}@${CUSTOM_DOMAIN}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${DEST}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&headerType=none#${REMARK}"

        echo ""
        echo -e "${GREEN}✅ 部署成功，服务已正常启动！${NC}"
        echo -e "${YELLOW}👇 请复制以下链接导入客户端 👇${NC}"
        echo ""
        echo -e "${GREEN}${SHARE_LINK}${NC}"
        echo ""
        
        if [ "$PORT" != "443" ]; then
            echo -e "${RED}⚠️ 重要提醒：你使用了自定义端口 ${PORT}！${NC}"
            echo -e "${YELLOW}请务必前往云服务器控制台防火墙/安全组，放行 TCP ${PORT} 端口！${NC}"
        fi
    else
        echo -e "${RED}❌ 启动失败，请运行 'journalctl -u sing-box -n 20' 查看具体报错日志。${NC}"
    fi
    exit 0
}

# ==========================================
# 主菜单逻辑
# ==========================================
clear
echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}=== Sing-box VLESS-Reality 管理脚本 ===${NC}"
echo -e "${GREEN}=====================================${NC}"
echo -e " 1. 部署/重置 VLESS-Reality 节点"
echo -e " 2. ${RED}彻底卸载节点及清理配置${NC}"
echo -e " 0. 退出脚本"
echo -e "${GREEN}=====================================${NC}"
echo ""

read -p "请输入数字选择操作 [0-2]: " ACTION_CHOICE

case $ACTION_CHOICE in
    1)
        install_node
        ;;
    2)
        read -p "确定要彻底卸载 Sing-box 吗？[y/N]: " UNINSTALL_CONFIRM
        if [[ "$UNINSTALL_CONFIRM" =~ ^[Yy]$ ]]; then
            uninstall_node
        else
            echo "已取消卸载。"
            exit 0
        fi
        ;;
    0)
        echo "已退出。"
        exit 0
        ;;
    *)
        echo -e "${RED}无效输入，请重新运行脚本并选择 0-2 之间的数字。${NC}"
        exit 1
        ;;
esac
