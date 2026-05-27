#!/bin/bash
set -e
clear

echo "=========================================================="
echo "    Cloudflare 避风港：Sing-Box VLESS-WS-TLS 满血完全体"
echo "=========================================================="
echo " 1. 安装/更新 VLESS-WS-TLS 节点 (智能记忆 + 域名精准对账)"
echo " 2. 查看当前已建节点链接汇总 (快捷命令: sd)"
echo " 3. 彻底卸载节点服务"
echo "=========================================================="
read -p "请选择操作 [1-3]: " CHOICE

# 铁律第一步：物理创建核心账本目录
mkdir -p /etc/cf_vless
mkdir -p /root/cert
mkdir -p /etc/sing-box

# 激活并提取历史持久化缓存
CONFIG_FILE="/etc/cf_vless/last_cfg.conf"
if [ -f "$CONFIG_FILE" ]; then source "$CONFIG_FILE"; fi

IP=$(curl -sS4 https://ifconfig.me || curl -sS4 https://api.ipify.org)
UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "6a82e704-9ac8-4fb8-bef1-6c9d7d7e390a")

deploy_shortcut() {
    echo '#!/bin/bash' > /usr/local/bin/sd
    echo 'CF_CONF="/etc/cf_vless/last_cfg.conf"' >> /usr/local/bin/sd
    echo 'if [ -f "$CF_CONF" ]; then' >> /usr/local/bin/sd
    echo '    source "$CF_CONF"' >> /usr/local/bin/sd
    echo '    clear' >> /usr/local/bin/sd
    echo '    echo "=========================================================="' >> /usr/local/bin/sd
    echo '    echo " 📋 双引流节点汇总（可直接两行全选，一次性批量复制导入）"' >> /usr/local/bin/sd
    echo '    echo "=========================================================="' >> /usr/local/bin/sd
    echo '    echo "vless://$LAST_UUID@$LAST_DOMAIN:$LAST_PORT?encryption=none&security=tls&sni=$LAST_DOMAIN&type=ws&host=$LAST_DOMAIN&path=$LAST_ENCODED_PATH#CF-Domain-$LAST_PORT"' >> /usr/local/bin/sd
    echo '    echo "vless://$LAST_UUID@104.16.0.1:$LAST_PORT?encryption=none&security=tls&sni=$LAST_DOMAIN&type=ws&host=$LAST_DOMAIN&path=$LAST_ENCODED_PATH#CF-Optimized-$LAST_PORT"' >> /usr/local/bin/sd
    echo '    echo "=========================================================="' >> /usr/local/bin/sd
    echo 'fi' >> /usr/local/bin/sd
    chmod +x /usr/local/bin/sd
}

if [ "$CHOICE" -eq 1 ]; then
    echo "正在优化内核网络缓冲区，榨干千兆 TCP 流速..."
    echo "net.core.default_qdisc = fq" > /etc/sysctl.d/99-cf-vless-bbr.conf
    echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.d/99-cf-vless-bbr.conf
    echo "net.core.rmem_max = 16772160" >> /etc/sysctl.d/99-cf-vless-bbr.conf
    echo "net.core.wmem_max = 16772160" >> /etc/sysctl.d/99-cf-vless-bbr.conf
    echo "net.ipv4.tcp_rmem = 4096 87380 16772160" >> /etc/sysctl.d/99-cf-vless-bbr.conf
    echo "net.ipv4.tcp_wmem = 4096 65536 16772160" >> /etc/sysctl.d/99-cf-vless-bbr.conf
    sysctl --system >/dev/null 2>&1

    apt update -y && apt install -y curl wget socat cron unzip tar openssl ufw jq

    systemctl stop sing-box 2>/dev/null || true
    systemctl stop xray 2>/dev/null || true

    if [ -n "$LAST_DOMAIN" ]; then
        read -p " 请输入域名 (直接回车复用历史域名 [$LAST_DOMAIN]): " DOMAIN_INPUT
        DOMAIN=${DOMAIN_INPUT:-$LAST_DOMAIN}
    else
        while true; do
            read -p " 请输入你在 Cloudflare 解析好的完整域名 (例如 us9.099889.xyz): " DOMAIN
            if [ -n "$DOMAIN" ]; then break; fi
        done
    fi

    echo "正在请求公网 DNS 校验域名解析账目..."
    DOMAIN_IP=$(curl -s4 "https://1.1.1.1/dns-query?name=$DOMAIN" -H "accept: application/dns-json" | grep -oE '"data":"[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}"' | head -n 1 | awk -F'"' '{print $4}')
    
    if [ -n "$DOMAIN_IP" ] && [ "$DOMAIN_IP" != "$IP" ]; then
        echo "----------------------------------------------------------"
        echo " 提示：检测到当前域名解析 IP 为 [$DOMAIN_IP]，本机 IP 为 [$IP]"
        echo " 如果您在 Cloudflare 后台已经开启了【橙色小云朵】Proxy 保护，属于完全正常现象。"
        echo "----------------------------------------------------------"
        read -p " 是否确认域名绑定无误并强行继续？[Y/n]: " IP_CONFIRM
        if [ "$IP_CONFIRM" = "n" ] || [ "$IP_CONFIRM" = "N" ]; then exit 1; fi
    fi

    if [ -n "$LAST_WSPATH" ]; then
        read -p " 请输入WS路径 (直接回车复用历史路径 [$LAST_WSPATH]): " WSPATH_INPUT
        WSPATH=${WSPATH_INPUT:-$LAST_WSPATH}
    else
        read -p " 请输入WS路径(默认 /ray): " WSPATH_INPUT
        WSPATH=${WSPATH_INPUT:-/ray}
    fi

    while true; do
        if [ -n "$LAST_PORT" ]; then
            read -p " 请输入端口号 (直接回车复用历史端口 [$LAST_PORT]): " PORT_INPUT
            PORT=${PORT_INPUT:-$LAST_PORT}
        else
            read -p " 请输入端口号(默认 8443): " PORT_INPUT
            PORT=${PORT_INPUT:-8443}
        fi
        if [ "$PORT" = "443" ] || [ "$PORT" = "2053" ] || [ "$PORT" = "2083" ] || [ "$PORT" = "2087" ] || [ "$PORT" = "2096" ] || [ "$PORT" = "8443" ]; then break; fi
        echo " 错误：输入的端口不在允许列表中，请重新输入！"
    done

    ENCODED_PATH=$(printf '%s' "$WSPATH" | sed 's/\//%2F/g')

    echo "LAST_DOMAIN=\"$DOMAIN\"" > "$CONFIG_FILE"
    echo "LAST_WSPATH=\"$WSPATH\"" >> "$CONFIG_FILE"
    echo "LAST_PORT=\"$PORT\"" >> "$CONFIG_FILE"
    echo "LAST_UUID=\"$UUID\"" >> "$CONFIG_FILE"
    echo "LAST_ENCODED_PATH=\"$ENCODED_PATH\"" >> "$CONFIG_FILE"

    bash <(curl -fsSL https://sing-box.app/deb-install.sh)

    if [ ! -f "/root/.acme.sh/acme.sh" ]; then curl https://get.acme.sh | sh || true; fi
    ~/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone --keylength ec-256 --force
    ~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" --ecc --fullchain-file /root/cert/fullchain.cer --key-file /root/cert/private.key

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
    echo "        \"path\": \"$WSPATH\"" >> "$SB_CONFIG"
    echo '      },' >> "$SB_CONFIG"
    echo '      "tls": { ' >> "$SB_CONFIG"
    echo '        "enabled": true,' >> "$SB_CONFIG"
    echo "        \"server_name\": \"$DOMAIN\"," >> "$SB_CONFIG"
    echo '        "certificate_path": "/root/cert/fullchain.cer",' >> "$SB_CONFIG"
    echo '        "key_path": "/root/cert/private.key"' >> "$SB_CONFIG"
    echo '      }' >> "$SB_CONFIG"
    echo '    }' >> "$SB_CONFIG"
    echo '  ],' >> "$SB_CONFIG"
    echo '  "outbounds": [ { "type": "direct" } ]' >> "$SB_CONFIG"
    echo '}' >> "$SB_CONFIG"

    ufw allow $PORT/tcp 2>/dev/null || true
    systemctl daemon-reload && systemctl enable sing-box && systemctl restart sing-box

    deploy_shortcut
    clear
    /usr/local/bin/sd

elif [ "$CHOICE" -eq 2 ]; then
    if [ -f "/usr/local/bin/sd" ]; then /usr/local/bin/sd; else echo " 未找到节点配置！"; fi
elif [ "$CHOICE" -eq 3 ]; then
    systemctl stop sing-box 2>/dev/null || true
    rm -rf /etc/cf_vless /etc/sing-box /usr/local/bin/sd /root/cert
    echo " 卸载清洗完成！"
else
    exit 1
fi
