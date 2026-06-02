#!/bin/bash

# =================================================================
# 脚本名称: Cloudflare WARP 奈飞非自制剧全自动一键解锁脚本 (VPS专用版)
# =================================================================

# 强制非交互模式
export DEBIAN_FRONTEND=noninteractive

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

# 奈飞非自制剧特征 ID (Squid Game)
NETFLIX_ID="81280942"
MAX_ATTEMPTS=50
ATTEMPT=1
SUCCESS=0

# 检查是否为 Root 用户
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}[-][错误] 请使用 root 用户或通过 sudo 运行此脚本！${PLAIN}"
    exit 1
fi

echo "=================================================="
echo -e "${YELLOW}🚀 正在安装官方 WARP 客户端及依赖...${PLAIN}"
echo "=================================================="

# 自动检测包管理器并安装基础依赖
if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y -qq
    apt-get install -y -qq curl jq wireguard-tools lsb-release gnupg > /dev/null 2>&1
    
    # 安装 Cloudflare WARP 官方源
    curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/cloudflare-client.list
    apt-get update -y -qq && apt-get install cloudflare-warp -y -qq > /dev/null 2>&1
    
elif command -v yum >/dev/null 2>&1; then
    yum install -y -q epel-release > /dev/null 2>&1
    yum install -y -q curl jq wireguard-tools > /dev/null 2>&1
    curl -fsSL https://pkg.cloudflareclient.com/cloudflare-warp-ascii.repo | tee /etc/yum.repos.disabled/cloudflare-warp.repo
    yum install cloudflare-warp -y -q > /dev/null 2>&1
fi

# 确保后台服务跑起来
systemctl daemon-reload
systemctl enable --now warp-svc > /dev/null 2>&1
sleep 3

# 初始化并配置 WARP 代理模式
warp-cli --accept-tos registration register > /dev/null 2>&1
warp-cli --accept-tos mode proxy > /dev/null 2>&1
warp-cli --accept-tos connect > /dev/null 2>&1
sleep 4

echo "=================================================="
echo -e "${YELLOW}🔍 开始循环筛选解锁奈飞非自制剧的 IP...${PLAIN}"
echo "=================================================="

while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
    # 测试通过 40000 端口请求奈飞
    STATUS_CODE=$(curl -s -o /dev/null --socks5-hostname 127.0.0.1:40000 -w "%{http_code}" --user-agent "Mozilla/5.0" "https://www.netflix.com/title/${NETFLIX_ID}")
    
    if [ "$STATUS_CODE" -eq 200 ]; then
        echo -e "${GREEN}[+] 第 ${ATTEMPT} 次尝试：🎉 成功刷到解锁 IP！${PLAIN}"
        SUCCESS=1
        break
    else
        echo -e "${RED[-] 第 ${ATTEMPT} 次尝试：未解锁 (HTTP ${STATUS_CODE})。正在刷新 IP...${PLAIN}"
        warp-cli --accept-tos disconnect > /dev/null 2>&1
        sleep 1
        warp-cli --accept-tos connect > /dev/null 2>&1
        sleep 4
    fi
    ATTEMPT=$((ATTEMPT + 1))
done

if [ $SUCCESS -eq 1 ]; then
    echo "=================================================="
    echo -e "${GREEN} 🎉 奈飞非自制剧解锁成功！${PLAIN}"
    echo "=================================================="
    IP_INFO=$(curl -s --socks5-hostname 127.0.0.1:40000 https://ifconfig.co/json)
    echo -e "${GREEN}[WARP 本地代理端口]:${PLAIN} SOCKS5://127.0.0.1:40000"
    echo -e "${GREEN}[出口公网 IP]:${PLAIN} $(echo $IP_INFO | jq -r .ip)"
    echo -e "${GREEN}[当前解锁区域]:${PLAIN} $(echo $IP_INFO | jq -r .country_iso)"
else
    echo -e "${RED}❌ 刷了 ${MAX_ATTEMPTS} 次仍未成功，请稍后重新运行任务重试。${PLAIN}"
    exit 1
fi
