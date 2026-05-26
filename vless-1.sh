#!/bin/bash

# 检查是否为 Root 用户
if [ "$EUID" -ne 0 ]; then
  echo "错误：请使用 root 用户运行此脚本！"
  exit 1
fi

# 铁律第一步：开局直接物理创建核心目录，确保所有账本读写绝不踩空
mkdir -p /usr/local/etc/xray
mkdir -p /etc/cf_vless

echo "=========================================================="
echo "    Cloudflare 避风港：VLESS + WS + TLS 纯净一键版 V11.3"
echo "=========================================================="
echo " 1. 安装/更新 VLESS-WS-TLS 节点 (内核超频 + 历史智能记忆版)"
echo " 2. 查看当前已建节点链接汇总 (快捷命令: sd)"
echo " 3. 彻底卸载节点服务"
echo "=========================================================="
read -p "请选择操作 [1-3]: " CHOICE

# 提取并激活历史缓存账本
CONFIG_FILE="/etc/cf_vless/last_cfg.conf"
if [ -f "$CONFIG_FILE" ]; then source "$CONFIG_FILE"; fi

IP=$(curl -sS4 https://ifconfig.me || curl -sS4 https://api.ipify.org)
UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "6a82e704-9ac8-4fb8-bef1-6c9d7d7e390a")

if [ -z "$IP" ] && [ "$CHOICE" -eq 1 ]; then
  echo "错误：无法获取服务器公网 IP，请检查网络连接。"
  exit 1
fi

# 智能获取服务商与地理位置标签
get_geo_tag() {
    local geo_info=$(curl -s --max-time 3 http://ip-api.com/json/)
    if [ -n "$geo_info" ] && echo "$geo_info" | grep -q '"status":"success"'; then
        local isp=$(echo "$geo_info" | grep -oE '"isp":"[^"]+"' | cut -d '"' -f4 | awk '{print $1}')
        local country=$(echo "$geo_info" | grep -oE '"country":"[^"]+"' | cut -d '"' -f4 | tr -d ' ')
        isp=$(echo "$isp" | tr -cd 'A-Za-z0-9_')
        country=$(echo "$country" | tr -cd 'A-Za-z0-9_')
        echo "${isp}_${country}"
    else
        echo "VPS_Node"
    fi
}

# 核心环境清洗与 TCP/BBR 深度性能超频 (16MB 巨型缓冲区)
init_env() {
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

    echo "正在清洗基础网络并安装基础组件..."
    if command -v apt-get >/dev/null; then
      apt-get update -qq && apt-get install -y -qq curl jq uuid-runtime iptables socat net-tools
    elif command -v yum >/dev/null; then
      yum makecache && yum install -y curl jq uuid-runtime iptables socat net-tools
    fi

    echo "正在物理放行内部防火墙端口..."
    if command -v ufw > /dev/null; then ufw disable >/dev/null 2>&1; fi
    if command -v systemctl > /dev/null; then systemctl stop firewalld >/dev/null 2>&1 && systemctl disable firewalld >/dev/null 2>&1; fi
    iptables -F && iptables -X
    iptables -P INPUT ACCEPT && iptables -P FORWARD ACCEPT && iptables -P OUTPUT ACCEPT
}

# 部署专属快捷查询命令 sd (链接靠拢，一键全选双带走)
deploy_shortcut() {
    echo '#!/bin/bash' > /usr/local/bin/sd
    echo 'CF_CONF="/etc/cf_vless/last_cfg.conf"' >> /usr/local/bin/sd
    echo 'if [ -f "$CF_CONF" ]; then' >> /usr/local/bin/sd
    echo '    source "$CF_CONF"' >> /usr/local/bin/sd
    echo '    clear' >> /usr/local/bin/sd
    echo '    echo "=========================================================="' >> /usr/local/bin/sd
    echo '    echo " 📋 下方为核心双引流节点（可直接两行全选，一次性批量复制）"' >> /usr/local/bin/sd
    echo '    echo "=========================================================="' >> /usr/local/bin/sd
    echo '    echo "vless://$LAST_UUID@$LAST_CF_DOMAIN:$LAST_PORT?encryption=none&security=tls&sni=$LAST_CF_DOMAIN&type=ws&path=/ #CF-Domain-$LAST_PORT"' >> /usr/local/bin/sd
    echo '    echo "vless://$LAST_UUID@104.16.132.229:$LAST_PORT?encryption=none&security=tls&sni=$LAST_CF_DOMAIN&type=ws&path=/&host=$LAST_CF_DOMAIN#CF-Optimized-$LAST_PORT"' >> /usr/local/bin/sd
    echo '    echo "=========================================================="' >> /usr/local/bin/sd
    echo 'fi' >> /usr/local/bin/sd
    chmod +x /usr/local/bin/sd
}

# 🌟 彻底清除 case 状态机，改用绝对稳固、100% 畅通的 if-elif 逻辑块
if [ "$CHOICE" -eq 1 ]; then
    init_env
    
    # 智能记忆恢复：域名检测
    if [ -n "$LAST_CF_DOMAIN" ]; then
        read -p " 侦测到历史缓存域名 [$LAST_CF_DOMAIN]，直接回车复用，或输入新域名: " CF_DOMAIN
        CF_DOMAIN=${CF_DOMAIN:-$LAST_CF_DOMAIN}
    else
        while true; do
            read -p " 请输入你在 Cloudflare 解析好的完整域名 (例如 us9.099889.xyz): " CF_DOMAIN
            if [ -n "$CF_DOMAIN" ]; then break; fi
        done
    fi

    # 智能记忆恢复：端口检测，参照截图默认直接推荐 443
    echo "----------------------------------------------------------"
    echo " 提示：套小云朵自定端口，强烈推荐使用 443 端口（如你发来的截图所示）"
    echo " 官方允许的 HTTPS 端口有: [ 443, 2053, 2083, 2087, 2096, 8443 ]"
    echo "----------------------------------------------------------"
    if [ -n "$LAST_PORT" ]; then
        read -p " 请输入端口号 (直接回车复用历史端口 [$LAST_PORT]): " INPUT_PORT
        PORT="${INPUT_PORT:-$LAST_PORT}"
    else
        read -p " 请输入端口号 (直接回车默认使用本命 443 端口): " INPUT_PORT
        PORT="${INPUT_PORT:-443}"
    fi

    WS_PATH="/"
    
    # 纯净单行追加，锁定持久化账本
    echo "LAST_CF_DOMAIN=\"$CF_DOMAIN\"" > "$CONFIG_FILE"
    echo "LAST_UUID=\"$UUID\"" >> "$CONFIG_FILE"
    echo "LAST_PORT=\"$PORT\"" >> "$CONFIG_FILE"
    echo "LAST_WS_PATH=\"$WS_PATH\"" >> "$CONFIG_FILE"

    echo " 正在拉取正规军 Xray 官方二进制核心..."
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)"

    # 清空可能导致多配置内耗的残留文件
    rm -f /usr/local/etc/xray/*.json

    echo " 正在本地秒发 10 年期合规自签名 TLS 证书..."
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
      -keyout "/usr/local/etc/xray/server.key" \
      -out "/usr/local/etc/xray/server.crt" \
      -subj "/CN=$CF_DOMAIN" >/dev/null 2>&1

    # 🌟 终极修正：抛弃任何可能引发断轨的 printf 和 heredoc，改用绝对安全的单行 echo 稳扎稳打
    XRAY_CONFIG="/usr/local/etc/xray/config.json"
    echo '{' > "$XRAY_CONFIG"
    echo '  "log": { "loglevel": "warning" },' >> "$XRAY_CONFIG"
    echo '  "inbounds": [' >> "$XRAY_CONFIG"
    echo '    {' >> "$XRAY_CONFIG"
    echo "      \"port\": $PORT," >> "$XRAY_CONFIG"
    echo '      "listen": "0.0.0.0",' >> "$XRAY_CONFIG"
    echo '      "protocol": "vless",' >> "$XRAY_CONFIG"
    echo '      "settings": {' >> "$XRAY_CONFIG"
    echo '        "clients": [' >> "$XRAY_CONFIG"
    echo '          {' >> "$XRAY_CONFIG"
    echo "            \"id\": \"$UUID\"," >> "$XRAY_CONFIG"
    echo '            "level": 0' >> "$XRAY_CONFIG"
    echo '          }' >> "$XRAY_CONFIG"
    echo '        ]' >> "$XRAY_CONFIG"
    echo '      },' >> "$XRAY_CONFIG"
    echo '      "streamSettings": {' >> "$XRAY_CONFIG"
    echo '        "network": "ws",' >> "$XRAY_CONFIG"
    echo '        "security": "tls",' >> "$XRAY_CONFIG"
    echo '        "tlsSettings": {' >> "$XRAY_CONFIG"
    echo '          "certificates": [' >> "$XRAY_CONFIG"
    echo '            {' >> "$XRAY_CONFIG"
    echo '              "certificateFile": "/usr/local/etc/xray/server.crt",' >> "$XRAY_CONFIG"
    echo '              "keyFile": "/usr/local/etc/xray/server.key"' >> "$XRAY_CONFIG"
    echo '            }' >> "$XRAY_CONFIG"
    echo '          ]' >> "$XRAY_CONFIG"
    echo '        },' >> "$XRAY_CONFIG"
    echo '        "wsSettings": {' >> "$XRAY_CONFIG"
    echo "          \"path\": \"$WS_PATH\"" >> "$XRAY_CONFIG"
    echo '        }' >> "$XRAY_CONFIG"
    echo '      }' >> "$XRAY_CONFIG"
    echo '    }' >> "$XRAY_CONFIG"
    echo '  ],' >> "$XRAY_CONFIG"
    echo '  "outbounds": [{ "protocol": "freedom", "settings": {} }]' >> "$XRAY_CONFIG"
    echo '}' >> "$XRAY_CONFIG"

    # 打通全部非 root 进程的所有权对账
    chmod 644 /usr/local/etc/xray/config.json /usr/local/etc/xray/server.crt
    chmod 600 /usr/local/etc/xray/server.key
    chown -R nobody:nogroup /usr/local/etc/xray 2>/dev/null || chown -R nobody:nobody /usr/local/etc/xray 2>/dev/null || chown -R xray:xray /usr/local/etc/xray 2>/dev/null
    
    systemctl daemon-reload
    systemctl enable xray >/dev/null 2>&1
    systemctl restart xray

    deploy_shortcut
    clear
    /usr/local/bin/sd

elif [ "$CHOICE" -eq 2 ]; then
    if [ -f "/usr/local/bin/sd" ]; then /usr/local/bin/sd; else echo " 未找到节点配置！"; fi

elif [ "$CHOICE" -eq 3 ]; then
    echo " 正在彻底物理剥离服务与清洗环境..."
    systemctl stop xray 2>/dev/null
    systemctl disable xray 2>/dev/null
    rm -rf /usr/local/bin/xray /usr/local/etc/xray /etc/cf_vless /usr/local/bin/sd
    echo " 卸载清洗完成！"
else
    exit 1
fi
