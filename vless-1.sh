#!/bin/bash
set -e
clear

# 铁律第一步：开局直接物理创建核心目录，确保所有账本读写绝不踩空
mkdir -p /usr/local/etc/xray
mkdir -p /etc/cf_vless
mkdir -p /root/cert
mkdir -p /etc/sing-box

CONFIG_FILE="/etc/cf_vless/last_cfg.conf"
if [ -f "$CONFIG_FILE" ]; then source "$CONFIG_FILE"; fi

IP=$(curl -sS4 https://ifconfig.me || curl -sS4 https://api.ipify.org)
UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "6a82e704-9ac8-4fb8-bef1-6c9d7d7e390a")

echo "=========================================================="
echo "    Cloudflare 避风港：Sing-Box VLESS-WS-TLS 满血记忆版"
echo "=========================================================="
echo ""

# 智能智能记忆恢复：域名检测
if [ -n "$LAST_CF_DOMAIN" ]; then
    read -p " 侦测到历史缓存域名 [$LAST_CF_DOMAIN]，直接回车复用，或输入新域名: " CF_DOMAIN
    CF_DOMAIN=${CF_DOMAIN:-$LAST_CF_DOMAIN}
else
    while true; do
        read -p " 请输入你在 Cloudflare 解析好的完整域名 (例如 us9.099889.xyz): " CF_DOMAIN
        if [ -n "$CF_DOMAIN" ]; then break; fi
    done
fi

# 智能智能记忆恢复：路径检测
if [ -n "$LAST_WS_PATH" ]; then
    read -p " 请输入WS路径 (直接回车复用历史路径 [$LAST_WS_PATH]): " WS_PATH
    WS_PATH=${WS_PATH:-$LAST_WS_PATH}
else
    read -p " 请输入WS路径 (直接回车默认使用 /ray): " INPUT_PATH
    WS_PATH=${INPUT_PATH:-/ray}
fi

# 智能智能记忆恢复：端口检测与安全卡关
while true; do
    echo "----------------------------------------------------------"
    echo " 提示：套小云朵自定端口，必须从以下官方允许的 HTTPS 端口中选择："
    echo "    [ 443, 2053, 2083, 2087, 2096, 8443 ]"
    echo "----------------------------------------------------------"
    if [ -n "$LAST_PORT" ]; then
        read -p " 请输入端口号 (直接回车复用历史端口 [$LAST_PORT]): " INPUT_PORT
        PORT="${INPUT_PORT:-$LAST_PORT}"
    else
        read -p " 请输入端口号 (直接回车默认使用 8443): " INPUT_PORT
        PORT="${INPUT_PORT:-8443}"
    fi
    
    if [ "$PORT" = "443" ] || [ "$PORT" = "2053" ] || [ "$PORT" = "2083" ] || [ "$PORT" = "2087" ] || [ "$PORT" = "2096" ] || [ "$PORT" = "8443" ]; then
        break
    else
        echo " 错误：输入的端口不在 Cloudflare 官方 HTTPS 允许列表中，请重新输入！"
    fi
done

# 纯净单行追加，锁定持久化账本
echo "LAST_CF_DOMAIN=\"$CF_DOMAIN\"" > "$CONFIG_FILE"
echo "LAST_UUID=\"$UUID\"" >> "$CONFIG_FILE"
echo "LAST_PORT=\"$PORT\"" >> "$CONFIG_FILE"
echo "LAST_WS_PATH=\"$WS_PATH\"" >> "$CONFIG_FILE"

echo "正在向内核物理注入 BBR + 16MB 满血网络超频补丁..."
echo "net.core.default_qdisc = fq" > /etc/sysctl.d/99-cf-vless-bbr.conf
echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.d/99-cf-vless-bbr.conf
echo "net.core.rmem_max = 16772160" >> /etc/sysctl.d/99-cf-vless-bbr.conf
echo "net.core.wmem_max = 16772160" >> /etc/sysctl.d/99-cf-vless-bbr.conf
echo "net.ipv4.tcp_rmem = 4096 87380 16772160" >> /etc/sysctl.d/99-cf-vless-bbr.conf
echo "net.ipv4.tcp_wmem = 4096 65536 16772160" >> /etc/sysctl.d/99-cf-vless-bbr.conf
echo "net.ipv4.tcp_tw_reuse = 1" >> /etc/sysctl.d/99-cf-vless-bbr.conf
echo "net.ipv4.tcp_fin_timeout = 15" >> /etc/sysctl.d/99-cf-vless-bbr.conf
echo "net.ipv4.tcp_keepalive_time = 600" >> /etc/sysctl.d/99-cf-vless-bbr.conf
echo "net.ipv4.tcp_fastopen = 3" >> /etc/sysctl.d/99-cf-vless-bbr.conf
sysctl --system >/dev/null 2>&1

echo "正在清洗基础 network 并安装基础组件..."
if command -v apt-get >/dev/null; then
  apt-get update -y && apt-get install -y curl wget socat cron unzip tar openssl ufw jq
elif command -v yum >/dev/null; then
  yum makecache && yum install -y curl wget socat crontabs unzip tar openssl ufw jq
fi

echo "停止旧代干扰服务..."
systemctl stop sing-box 2>/dev/null || true
systemctl stop xray 2>/dev/null || true
systemctl stop nginx 2>/dev/null || true
systemctl stop apache2 2>/dev/null || true

echo "安装 sing-box 官方正规核心..."
bash <(curl -fsSL https://sing-box.app/deb-install.sh)

echo "安装 acme.sh 并现场向 Let's Encrypt 摇号申请正规证书..."
if [ ! -f "/root/.acme.sh/acme.sh" ]; then
    curl https://get.acme.sh | sh || true
fi

# 强行下发正规军签发指令
~/.acme.sh/acme.sh --issue -d "$CF_DOMAIN" --standalone --keylength ec-256 --force

~/.acme.sh/acme.sh --install-cert -d "$CF_DOMAIN" \
  --ecc \
  --fullchain-file /root/cert/fullchain.cer \
  --key-file /root/cert/private.key

chmod 644 /root/cert/fullchain.cer
chmod 600 /root/cert/private.key

echo "正在用绝对安全的一行式追加拼装 Sing-Box 官方规范账本..."
SB_CONFIG="/etc/sing-box/config.json"
echo '{' > "$SB_CONFIG"
echo '  "log": { "level": "info" },' >> "$SB_CONFIG"
echo '  "inbounds": [' >> "$SB_CONFIG"
echo '    {' >> "$SB_CONFIG"
echo '      "type": "vless",' >> "$SB_CONFIG"
echo '      "listen": "::",' >> "$SB_CONFIG"
echo "      \"listen_port\": $PORT," >> "$SB_CONFIG"
echo '      "users": [ { ' >> "$SB_CONFIG"
echo "        \"uuid\": \"$UUID\"" >> "$SB_CONFIG"
echo '      } ],' >> "$SB_CONFIG"
echo '      "transport": {' >> "$SB_CONFIG"
echo '        "type": "ws",' >> "$SB_CONFIG"
echo "        \"path\": \"$WS_PATH\"" >> "$SB_CONFIG"
echo '      },' >> "$SB_CONFIG"
echo '      "tls": { ' >> "$SB_CONFIG"
echo '        "enabled": true,' >> "$SB_CONFIG"
echo "        \"server_name\": \"$CF_DOMAIN\"," >> "$SB_CONFIG"
echo '        "certificate_path": "/root/fullchain.cer",' >> "$SB_CONFIG"
echo '        "key_path": "/root/cert/private.key"' >> "$SB_CONFIG"
echo '      }' >> "$SB_CONFIG"
echo '    }' >> "$SB_CONFIG"
echo '  ],' >> "$SB_CONFIG"
echo '  "outbounds": [ { "type": "direct" } ]' >> "$SB_CONFIG"
echo '}' >> "$SB_CONFIG"

# 物理修复：将证书移籍并软链接对齐，确保后台绝对畅通读取
cp /root/cert/fullchain.cer /root/fullchain.cer

# 放行系统内部阻断
ufw allow $PORT/tcp 2>/dev/null || true
if command -v iptables >/dev/null 2>&1; then iptables -I INPUT -p tcp --dport $PORT -j ACCEPT 2>/dev/null || true; fi

systemctl daemon-reload
systemctl enable sing-box
systemctl restart sing-box

# 部署专属快捷查询命令 sd (两条链接彻底靠拢紧挨，方便老哥一次性批量复制)
echo '#!/bin/bash' > /usr/local/bin/sd
echo 'CF_CONF="/etc/cf_vless/last_cfg.conf"' >> /usr/local/bin/sd
echo 'if [ -f "$CF_CONF" ]; then' >> /usr/local/bin/sd
echo '    source "$CF_CONF"' >> /usr/local/bin/sd
echo '    clear' >> /usr/local/bin/sd
echo '    ENCODED_PATH=$(printf "%s" "$LAST_WS_PATH" | sed "s/\//%2F/g")' >> /usr/local/bin/sd
echo '    echo "=========================================================="' >> /usr/local/bin/sd
echo '    echo " 📋 双引流节点汇总（背靠背排列，可直接两行全选一刀流复制）"' >> /usr/local/bin/sd
echo '    echo "=========================================================="' >> /usr/local/bin/sd
echo '    echo "vless://$LAST_UUID@$LAST_CF_DOMAIN:$LAST_PORT?encryption=none&security=tls&type=ws&host=$LAST_CF_DOMAIN&path=$ENCODED_PATH#CF-Domain-$LAST_PORT"' >> /usr/local/bin/sd
echo '    echo "vless://$LAST_UUID@104.16.132.229:$LAST_PORT?encryption=none&security=tls&type=ws&host=$LAST_CF_DOMAIN&path=$ENCODED_PATH#CF-Optimized-$LAST_PORT"' >> /usr/local/bin/sd
echo '    echo "=========================================================="' >> /usr/local/bin/sd
echo 'fi' >> /usr/local/bin/sd
chmod +x /usr/local/bin/sd

clear
/usr/local/bin/sd
