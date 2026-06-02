cat << 'EOF' > /root/warp_netflix_final.sh
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'
NETFLIX_ID="81280942"
MAX_ATTEMPTS=50
ATTEMPT=1
SUCCESS=0

if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}[-][错误] 请使用 root 用户运行！${PLAIN}"
    exit 1
fi

echo "=================================================="
echo -e "${YELLOW}🚀 正在配置并安装 Cloudflare 官方 WARP...${PLAIN}"
echo "=================================================="

if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y -qq
    apt-get install -y -qq curl jq wireguard-tools lsb-release gnupg gpg psmisc > /dev/null 2>&1
    curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/cloudflare-client.list
    apt-get update -y -qq && apt-get install cloudflare-warp -y -qq
fi

echo -e "${YELLOW}[*] 正在拉起后台守护进程 (warp-svc)...${PLAIN}"
systemctl daemon-reload
systemctl enable --now warp-svc > /dev/null 2>&1
sleep 4

echo -e "${YELLOW}[*] 正在初始化官方账户并切入代理分流模式...${PLAIN}"
# 兼容 2026 最新官方版语法命令
warp-cli --accept-tos registration new > /dev/null 2>&1
warp-cli --accept-tos mode proxy
warp-cli --accept-tos proxy port 40000
warp-cli --accept-tos connect > /dev/null 2>&1
sleep 5

echo "=================================================="
echo -e "${YELLOW}🔍 开始循环筛选解锁奈飞非自制剧的 IP...${PLAIN}"
echo "=================================================="

while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
    STATUS_CODE=$(curl -s -o /dev/null --socks5-hostname 127.0.0.1:40000 -w "%{http_code}" --user-agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" "https://www.netflix.com/title/${NETFLIX_ID}")
    
    if [ "$STATUS_CODE" -eq 200 ]; then
        echo -e "${GREEN}[+] 第 ${ATTEMPT} 次尝试：🎉 成功刷到解锁 IP！(HTTP 200)${PLAIN}"
        SUCCESS=1
        break
    else
        if [ "$STATUS_CODE" -eq 000 ]; then
            echo -e "${RED[-] 第 ${ATTEMPT} 次尝试：连接未就绪 (HTTP 000)。重连中...${PLAIN}"
            warp-cli --accept-tos connect > /dev/null 2>&1
            sleep 3
        else
            echo -e "${RED[-] 第 ${ATTEMPT} 次尝试：只能看自制剧 (HTTP ${STATUS_CODE})。正在重置注册更换 IP...${PLAIN}"
        fi
        warp-cli --accept-tos registration delete > /dev/null 2>&1
        sleep 1
        warp-cli --accept-tos registration new > /dev/null 2>&1
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
    echo -e "${RED}❌ 刷了 ${MAX_ATTEMPTS} 次仍未成功，请重新运行。${PLAIN}"
    exit 1
fi
EOF
bash /root/warp_netflix_final.sh
