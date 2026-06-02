#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
NETFLIX_ID="81280942"
MAX_ATTEMPTS=50
ATTEMPT=1
SUCCESS=0

if [ "$(id -u)" -ne 0 ]; then
    echo "请使用 root 用户运行！"
    exit 1
fi

if ! command -v warp-cli >/dev/null 2>&1; then
    echo "[*] 正在安装官方 WARP..."
    apt-get update -y -qq && apt-get install -y -qq curl jq lsb-release gnupg gpg psmisc > /dev/null 2>&1
    curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/cloudflare-client.list
    apt-get update -y -qq && apt-get install cloudflare-warp -y -qq
fi

systemctl daemon-reload && systemctl enable --now warp-svc > /dev/null 2>&1
sleep 3

warp-cli --accept-tos registration new > /dev/null 2>&1
warp-cli --accept-tos mode proxy
warp-cli --accept-tos proxy port 40000
warp-cli --accept-tos connect > /dev/null 2>&1
sleep 4

echo "🔍 开始循环筛选解锁奈飞非自制剧的 IP..."
while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
    STATUS_CODE=$(curl -s -o /dev/null --socks5-hostname 127.0.0.1:40000 -w "%{http_code}" -A "Mozilla" "https://www.netflix.com/title/$NETFLIX_ID")
    if [ "$STATUS_CODE" -eq 200 ]; then
        echo "[+] 第 ${ATTEMPT} 次尝试：🎉 成功刷到解锁 IP！"
        SUCCESS=1
        break
    else
        if [ "$STATUS_CODE" -eq 000 ]; then
            echo "[-] 第 ${ATTEMPT} 次尝试：代理未完全就绪，正在重连..."
            warp-cli --accept-tos connect > /dev/null 2>&1
            sleep 2
        else
            echo "[-] 第 ${ATTEMPT} 次尝试：只能看自制剧 (HTTP $STATUS_CODE)。正在轮换..."
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
    echo " 🎉 奈飞非自制剧解锁成功！"
    echo "=================================================="
    echo "👉 WARP 官方代理端口: SOCKS5://127.0.0.1:40000"
else
    echo "❌ 刷了 $MAX_ATTEMPTS 次仍未成功，请稍后重试。"
    exit 1
fi
