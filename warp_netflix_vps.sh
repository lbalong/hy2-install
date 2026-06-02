#!/bin/bash

# =================================================================
# 脚本名称: Cloudflare 官方 WARP 奈飞全自动一键解锁脚本 (终极修复版)
# =================================================================

# 强制非交互模式
export DEBIAN_FRONTEND=noninteractive

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

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
echo -e "${YELLOW}🚀 正在配置并安装 Cloudflare 官方 WARP 客户端...${PLAIN}"
echo "=================================================="

# 1. 自动安装官方源及所需的所有系统依赖
if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y -qq
    apt-get install -y -qq curl jq wireguard-tools lsb-release gnupg gpg psmisc > /dev/null 2>&1
    
    # 导入官方 GPG 密钥与软件源
    curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/cloudflare-client.list
    
    apt-get update -y -qq
    apt-get install cloudflare-warp -y -qq
    
elif command -v yum >/dev/null 2>&1; then
    yum install -y -q epel-release > /dev/null 2>&1
    yum install -y -q curl jq wireguard-tools psmisc > /dev/null 2>&1
    curl -fsSL https://pkg.cloudflareclient.com/cloudflare-warp-ascii.repo | tee /etc/yum.repos.disabled/cloudflare-warp.repo
    yum install cloudflare-warp -y -q > /dev/null 2>&1
fi

# 2. 强力重启并确保官方后台服务完全就绪
echo -e "${YELLOW}[*] 正在拉起后台守护进程 (warp-svc)...${PLAIN}"
systemctl daemon-reload
systemctl stop warp-svc > /dev/null 2>&1
systemctl enable --now warp-svc > /dev/null 2>&1
sleep 4 # 给守护进程充足的启动时间

# 3. 核心修复：针对新版 warp-cli 强制要求接受服务条款、注册账户、切换模式
echo -e "${YELLOW}[*] 正在初始化官方账户并切入代理分流模式...${PLAIN}"
sudo -u warp warp-cli --accept-tos registration register > /dev/null 2>&1 || warp-cli --accept-tos registration register
warp-cli --accept-tos mode proxy
warp-cli --accept-tos proxy port 40000
warp-cli --accept-tos connect
sleep 5 # 等待首次连接分配 IP

echo "=================================================="
echo -e "${YELLOW}🔍 开始循环筛选解锁奈飞非自制剧的 IP...${PLAIN}"
echo "=================================================="

while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
    # 通过官方指定的 40000 端口测试连接
    STATUS_CODE=$(curl -s -o /dev/null --socks5-hostname 127.0.0.1:40000 -w "%{http_code}" --user-agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" "https://www.netflix.com/title/${NETFLIX_ID}")
    
    if [ "$STATUS_CODE" -eq 200 ]; then
        echo -e "${GREEN}[+] 第 ${ATTEMPT} 次尝试：🎉 成功刷到解锁 IP！(HTTP 200)${PLAIN}"
        SUCCESS=1
        break
    else
        if [ "$STATUS_CODE" -eq 000 ]; then
            echo -e "${RED[-] 第 ${ATTEMPT} 次尝试：官方连接未就绪 (HTTP 000)。正在尝试强制重连...${PLAIN}"
            warp-cli --accept-tos connect > /dev/null 2>&1
        else
            echo -e "${RED[-] 第 ${ATTEMPT} 次尝试：只能看自制剧 (HTTP ${STATUS_CODE})。正在轮换 IP...${PLAIN}"
        fi
        
        # 官方客户端最快捷的刷 IP 姿势：直接令其重置虚拟网络连接
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
    echo -e "${GREEN}[WARP 官方代理端口]:${PLAIN} SOCKS5://127.0.0.1:40000"
    echo -e "${GREEN}[出口公网 IP]:${PLAIN} $(echo $IP_INFO | jq -r .ip)"
    echo -e "${GREEN}[解锁区域]:${PLAIN} $(echo $IP_INFO | jq -r .country_iso)"
else
    echo -e "${RED}❌ 刷了 ${MAX_ATTEMPTS} 次仍未成功，请稍后重新运行此脚本。${PLAIN}"
    exit 1
fi
