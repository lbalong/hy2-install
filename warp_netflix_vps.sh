#!/bin/bash

# =================================================================
# 脚本名称: Cloudflare WARP 奈飞全自动一键解锁脚本 (VPS 轻量安全版)
# =================================================================

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
echo -e "${YELLOW}🚀 正在安装基础依赖组件...${PLAIN}"
echo "=================================================="

# 安装基础工具
if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y -qq && apt-get install -y -qq curl jq wget > /dev/null 2>&1
elif command -v yum >/dev/null 2>&1; then
    yum install -y -q curl jq wget > /dev/null 2>&1
fi

# 清理可能残留的旧进程
killall warp-go > /dev/null 2>&1

echo -e "${YELLOW}[*] 正在下载并配置轻量化 WARP 核心...${PLAIN}"
# 自动检测架构下载 warp-go
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    WARP_GO_URL="https://github.com/bepass-org/warp-go/releases/latest/download/warp-go-linux-amd64"
elif [ "$ARCH" = "aarch64" ]; then
    WARP_GO_URL="https://github.com/bepass-org/warp-go/releases/latest/download/warp-go-linux-arm64"
else
    echo -e "${RED}[-][错误] 暂不支持的架构: $ARCH${PLAIN}"
    exit 1
fi

wget -qO warp-go "$WARP_GO_URL" && chmod +x warp-go

# 注册 WARP 账户生成本地密钥
echo -e "${YELLOW}[*] 正在向 Cloudflare 注册新账户...${PLAIN}"
./warp-go register --config=warp.conf > /dev/null 2>&1

if [ ! -f "warp.conf" ]; then
    echo -e "${RED}[-][错误] WARP 注册失败，请检查 VPS 能否正常连接外网！${PLAIN}"
    exit 1
fi

echo "=================================================="
echo -e "${YELLOW}🔍 开始循环筛选解锁奈飞非自制剧的 IP...${PLAIN}"
echo "=================================================="

while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
    # 启动后台临时代理 (socks5 端口定为 40000)
    ./warp-go run --config=warp.conf --listen=127.0.0.1:40000 > /dev/null 2>&1 &
    WARP_PID=$!
    
    # 给代理建立连接留出 3 秒缓冲时间
    sleep 3
    
    # 测试通过本地 40000 端口请求奈飞
    STATUS_CODE=$(curl -s -o /dev/null --socks5-hostname 127.0.0.1:40000 -w "%{http_code}" --user-agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" "https://www.netflix.com/title/${NETFLIX_ID}")
    
    if [ "$STATUS_CODE" -eq 200 ]; then
        echo -e "${GREEN}[+] 第 ${ATTEMPT} 次尝试：🎉 成功刷到解锁 IP！(HTTP 200)${PLAIN}"
        SUCCESS=1
        break
    else
        if [ "$STATUS_CODE" -eq 000 ]; then
            echo -e "${RED[-] 第 ${ATTEMPT} 次尝试：核心未就绪 (HTTP 000)。正在重新拉起...${PLAIN}"
        else
            echo -e "${RED[-] 第 ${ATTEMPT} 次尝试：只能看自制剧 (HTTP ${STATUS_CODE})。正在刷新 IP...${PLAIN}"
        fi
        # 杀掉当前进程，下次循环会自动分配新 IP
        kill -9 $WARP_PID > /dev/null 2>&1
        sleep 1
    fi
    ATTEMPT=$((ATTEMPT + 1))
done

if [ $SUCCESS -eq 1 ]; then
    echo "=================================================="
    echo -e "${GREEN} 🎉 奈飞非自制剧解锁成功！${PLAIN}"
    echo "=================================================="
    
    # 提取节点信息
    IP_INFO=$(curl -s --socks5-hostname 127.0.0.1:40000 https://ifconfig.co/json)
    WAN_IP=$(echo $IP_INFO | jq -r .ip)
    COUNTRY=$(echo $IP_INFO | jq -r .country_iso)
    
    echo -e "${GREEN}[WARP 留驻代理端口]:${PLAIN} SOCKS5://127.0.0.1:40000"
    echo -e "${GREEN}[出口公网 IP]:${PLAIN} ${WAN_IP}"
    echo -e "${GREEN}[解锁区域]:${PLAIN} ${COUNTRY}"
    echo -e "${YELLOW}[注意]: 脚本已在后台为你保持该可用 IP 的运行。你可以直接去 Hysteria2 / Xray 配置出站分流了。${PLAIN}"
else
    echo -e "${RED}❌ 刷了 ${MAX_ATTEMPTS} 次仍未成功，该 VPS 区域被封锁严重，请稍后重试。${PLAIN}"
    kill -9 $WARP_PID > /dev/null 2>&1
    exit 1
fi
