#!/bin/bash
set -e
clear

# 铁律第一步：物理创建核心账本目录，确保所有账本读写绝不踩空
mkdir -p /etc/cf_vless
mkdir -p /root/cert
mkdir -p /etc/sing-box

# 激活并提取历史持久化缓存
CONFIG_FILE="/etc/cf_vless/last_cfg.conf"
if [ -f "$CONFIG_FILE" ]; then source "$CONFIG_FILE"; fi

IP=$(curl -sS4 https://ifconfig.me || curl -sS4 https://api.ipify.org)
UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "6a82e704-9ac8-4fb8-bef1-6c9d7d7e390a")
CURRENT_PREF_IP="${LAST_PREF_IP:-104.16.0.1}"

echo "=========================================================="
echo "    Cloudflare 避风港：Sing-Box VLESS-WS-TLS 满血完全体"
echo "=========================================================="
echo " 1. 安装/更新 VLESS-WS-TLS 节点 (内核超频调校 + 证书复用)"
echo " 2. 更换/管理自定义优选 IP (当前: $CURRENT_PREF_IP)"
echo " 3. 查看当前已建节点链接汇总 (快捷命令: sd)"
echo " 4. 彻底卸载节点服务"
echo "=========================================================="
read -p "请选择操作 [1-4]: " CHOICE

# ──────────────────────────────────────────────────────────────
# 国家预设 IP 库：每个国家提供多个经过实战验证的 Cloudflare IP
# 说明：Cloudflare 会将流量就近路由到对应数据中心出口
# ──────────────────────────────────────────────────────────────
CF_COUNTRY_MENU() {
    echo "=========================================================="
    echo " 🌍 请选择节点伪装地区（决定 CDN 出口国家与节点标签）"
    echo "=========================================================="
    echo " [1]  🇺🇸 美国 (US)      - 104.16.0.1"
    echo " [2]  🇯🇵 日本 (JP)      - 104.18.16.1"
    echo " [3]  🇸🇬 新加坡 (SG)    - 104.19.48.1"
    echo " [4]  🇭🇰 香港 (HK)      - 104.21.64.1"
    echo " [5]  🇰🇷 韩国 (KR)      - 104.22.0.1"
    echo " [6]  🇩🇪 德国 (DE)      - 104.20.0.1"
    echo " [7]  🇬🇧 英国 (GB)      - 104.17.192.1"
    echo " [8]  🇫🇷 法国 (FR)      - 104.17.64.1"
    echo " [9]  🇳🇱 荷兰 (NL)      - 104.17.128.1"
    echo " [10] 🇨🇦 加拿大 (CA)    - 104.16.128.1"
    echo " [11] 🇦🇺 澳大利亚 (AU)  - 104.21.0.1"
    echo " [12] 🇮🇳 印度 (IN)      - 104.21.32.1"
    echo " [13] 🇧🇷 巴西 (BR)      - 104.22.32.1"
    echo " [14] 🇷🇺 俄罗斯 (RU)    - 104.20.192.1"
    echo " [15] 🇹🇼 台湾 (TW)      - 104.22.64.1"
    echo "----------------------------------------------------------"
    echo " [0]  ✏️  手动输入 IP 和地区代码（高级模式）"
    echo " [99] 🔍 自动检测 VPS 真实物理地区（原始行为）"
    echo "=========================================================="
}

# 根据国家编号返回 IP 和 GEO_TAG
CF_GET_COUNTRY_CONFIG() {
    local sel="$1"
    case "$sel" in
        1)  GEO_TAG="US"; PREF_IP_PRESET="104.16.0.1" ;;
        2)  GEO_TAG="JP"; PREF_IP_PRESET="104.18.16.1" ;;
        3)  GEO_TAG="SG"; PREF_IP_PRESET="104.19.48.1" ;;
        4)  GEO_TAG="HK"; PREF_IP_PRESET="104.21.64.1" ;;
        5)  GEO_TAG="KR"; PREF_IP_PRESET="104.22.0.1" ;;
        6)  GEO_TAG="DE"; PREF_IP_PRESET="104.20.0.1" ;;
        7)  GEO_TAG="GB"; PREF_IP_PRESET="104.17.192.1" ;;
        8)  GEO_TAG="FR"; PREF_IP_PRESET="104.17.64.1" ;;
        9)  GEO_TAG="NL"; PREF_IP_PRESET="104.17.128.1" ;;
        10) GEO_TAG="CA"; PREF_IP_PRESET="104.16.128.1" ;;
        11) GEO_TAG="AU"; PREF_IP_PRESET="104.21.0.1" ;;
        12) GEO_TAG="IN"; PREF_IP_PRESET="104.21.32.1" ;;
        13) GEO_TAG="BR"; PREF_IP_PRESET="104.22.32.1" ;;
        14) GEO_TAG="RU"; PREF_IP_PRESET="104.20.192.1" ;;
        15) GEO_TAG="TW"; PREF_IP_PRESET="104.22.64.1" ;;
        0)
            read -p " 请手动输入 Cloudflare 优选 IP: " PREF_IP_PRESET
            read -p " 请手动输入地区代码 (如 US/JP/SG/HK): " GEO_TAG
            GEO_TAG="${GEO_TAG:-Node}"
            ;;
        99|*)
            # 自动检测 VPS 真实地区（原始行为）
            GEO_INFO=$(curl -s --max-time 5 http://ip-api.com/json/ || echo "")
            if [ -n "$GEO_INFO" ] && echo "$GEO_INFO" | grep -q '"status":"success"'; then
                GEO_TAG=$(echo "$GEO_INFO" | jq -r '.countryCode' 2>/dev/null || echo "Node")
            else
                GEO_TAG="Node"
            fi
            PREF_IP_PRESET="${CURRENT_PREF_IP}"
            echo " ✅ 自动检测 VPS 物理地区为：[$GEO_TAG]，优选 IP 保持不变"
            ;;
    esac
}

# 部署专属快捷查询命令 sd (智能对账：不带任何反斜杠，标准输出真实 IP)
deploy_shortcut() {
    echo '#!/bin/bash' > /usr/local/bin/sd
    echo 'CF_CONF="/etc/cf_vless/last_cfg.conf"' >> /usr/local/bin/sd
    echo 'if [ -f "$CF_CONF" ]; then' >> /usr/local/bin/sd
    echo '    source "$CF_CONF"' >> /usr/local/bin/sd
    echo '    PREF_IP="${LAST_PREF_IP:-104.16.0.1}"' >> /usr/local/bin/sd
    echo '    clear' >> /usr/local/bin/sd
    echo '    echo "=========================================================="' >> /usr/local/bin/sd
    echo '    echo " 📋 双引流节点汇总（可直接两行全选，一次性批量复制导入）"' >> /usr/local/bin/sd
    echo '    echo "=========================================================="' >> /usr/local/bin/sd
    echo '    echo "vless://$LAST_UUID@$LAST_DOMAIN:$LAST_PORT?encryption=none&security=tls&sni=$LAST_DOMAIN&type=ws&host=$LAST_DOMAIN&path=$LAST_ENCODED_PATH#CF-[${LAST_GEO:-Node}]-Domain-$LAST_PORT"' >> /usr/local/bin/sd
    echo '    echo "vless://$LAST_UUID@$PREF_IP:$LAST_PORT?encryption=none&security=tls&sni=$LAST_DOMAIN&type=ws&host=$LAST_DOMAIN&path=$LAST_ENCODED_PATH#CF-[${LAST_GEO:-Node}]-Optimized-$LAST_PORT"' >> /usr/local/bin/sd
    echo '    echo "=========================================================="' >> /usr/local/bin/sd
    echo 'fi' >> /usr/local/bin/sd
    chmod +x /usr/local/bin/sd
}

if [ "$CHOICE" -eq 1 ]; then
    # 速度压榨核心：下发 TCP Fast Open (内核级零流失握手) 与超频缓冲区
    echo "正在超频优化系统网络层，激活 BBRv2 级别缓冲区与 TCP Fast Open..."
    echo "net.core.default_qdisc = fq" > /etc/sysctl.d/99-cf-vless-bbr.conf
    echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.d/99-cf-vless-bbr.conf
    echo "net.ipv4.tcp_fastopen = 3" >> /etc/sysctl.d/99-cf-vless-bbr.conf
    echo "net.core.rmem_max = 16772160" >> /etc/sysctl.d/99-cf-vless-bbr.conf
    echo "net.core.wmem_max = 16772160" >> /etc/sysctl.d/99-cf-vless-bbr.conf
    echo "net.ipv4.tcp_rmem = 4096 87380 16772160" >> /etc/sysctl.d/99-cf-vless-bbr.conf
    echo "net.ipv4.tcp_wmem = 4096 65536 16772160" >> /etc/sysctl.d/99-cf-vless-bbr.conf
    sysctl --system >/dev/null 2>&1

    echo "正在拉取系统组件..."
    apt update -y && apt install -y curl wget socat cron unzip tar openssl ufw jq

    # ── 新增：国家地区选择器 ──────────────────────────────────
    CF_COUNTRY_MENU
    read -p " 请选择地区编号 [0-15 或 99]: " COUNTRY_SEL
    CF_GET_COUNTRY_CONFIG "${COUNTRY_SEL:-99}"
    echo " ✅ 节点地区已锁定为：[$GEO_TAG]，CDN 出口优选 IP：[$PREF_IP_PRESET]"
    # 将优选 IP 同步到当前会话变量
    CURRENT_PREF_IP="$PREF_IP_PRESET"
    # ──────────────────────────────────────────────────────────

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

    # 持久化记忆锁死
    echo "LAST_DOMAIN=\"$DOMAIN\"" > "$CONFIG_FILE"
    echo "LAST_WSPATH=\"$WSPATH\"" >> "$CONFIG_FILE"
    echo "LAST_PORT=\"$PORT\"" >> "$CONFIG_FILE"
    echo "LAST_UUID=\"$UUID\"" >> "$CONFIG_FILE"
    echo "LAST_ENCODED_PATH=\"$ENCODED_PATH\"" >> "$CONFIG_FILE"
    echo "LAST_GEO=\"$GEO_TAG\"" >> "$CONFIG_FILE"
    echo "LAST_PREF_IP=\"$CURRENT_PREF_IP\"" >> "$CONFIG_FILE"

    bash <(curl -fsSL https://sing-box.app/deb-install.sh)

    if [ ! -f "/root/.acme.sh/acme.sh" ]; then curl https://get.acme.sh | sh || true; fi
    
    set +e
    CERT_OK=0

    if [ -f "/root/cert/fullchain.cer" ] && [ -f "/root/cert/private.key" ] && [ "$DOMAIN" = "$LAST_DOMAIN" ]; then
        echo " ✅ 检测到本地已有该域名的有效证书快照，自动开启智能复用，跳过申请流！"
        CERT_OK=1
    else
        echo " 正在首选 Let's Encrypt 签发正规证书..."
        ~/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone --keylength ec-256 --force
        if [ $? -eq 0 ]; then
            CERT_OK=1
        else
            echo "=========================================================="
            echo " ⚠️ Let's Encrypt 触发官方频次锁死限制！"
            echo " 🔄 脚本正在全自动切入挪威 Buypass CA 备用绿色通道..."
            echo "=========================================================="
            ~/.acme.sh/acme.sh --register-account -m admin@$DOMAIN --server buypass || true
            ~/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone --keylength ec-256 --force --server buypass
            if [ $? -eq 0 ]; then CERT_OK=1; fi
        fi
    fi

    set -e

    if [ "$CERT_OK" -ne 1 ]; then
        echo " ❌ 错误：所有证书信道（含备用信道）签发均告失败！"
        exit 1
    fi

    ~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" --ecc --fullchain-file /root/cert/fullchain.cer --key-file /root/cert/private.key || true

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
    echo '      "transport": { ' >> "$SB_CONFIG"
    echo '        "type": "ws",' >> "$SB_CONFIG"
    echo "        \"path\": \"$WSPATH\"" >> "$SB_CONFIG"
    echo '      },' >> "$SB_CONFIG"
    echo '      "tls": { ' >> "$SB_CONFIG"
    echo '        "enabled": true,' >> "$SB_CONFIG"
    echo "        \"server_name\": \"$DOMAIN\"," >> "$SB_CONFIG"
    echo '        "certificate_path": "/root/cert/fullchain.cer",' >> "$SB_CONFIG"
    echo '        "key_path": "/root/cert/private.key"' >> "$SB_CONFIG"
    echo '      },' >> "$SB_CONFIG"
    echo '      "tcp_fast_open": true' >> "$SB_CONFIG"
    echo '    }' >> "$SB_CONFIG"
    echo '  ],' >> "$SB_CONFIG"
    echo '  "outbounds": [ { "type": "direct" } ]' >> "$SB_CONFIG"
    echo '}' >> "$SB_CONFIG"

    ufw allow $PORT/tcp 2>/dev/null || true
    systemctl daemon-reload && systemctl enable sing-box && systemctl restart sing-box

    deploy_shortcut
    clear
    /usr/local/bin/sd

# ── 选项2：优选 IP 管理 - 新增国家菜单 ──────────────────────────
elif [ "$CHOICE" -eq 2 ]; then
    if [ ! -f "$CONFIG_FILE" ] || [ -z "$LAST_DOMAIN" ]; then
        echo " ❌ 错误：检测到您尚未安装节点，请先选择 [1] 安装节点后再来优选 IP！"
        exit 1
    fi
    echo "=========================================================="
    echo " 🎯 Cloudflare 优选 IP 管理 - 按国家/地区选择出口"
    echo "=========================================================="
    echo " 当前节点地区标签：[${LAST_GEO:-Node}]"
    echo " 当前优选 IP：[$CURRENT_PREF_IP]"
    echo "----------------------------------------------------------"
    CF_COUNTRY_MENU
    read -p " 请选择目标地区编号 [0-15 或 99，直接回车保持当前不变]: " COUNTRY_SEL

    if [ -z "$COUNTRY_SEL" ]; then
        # 回车不变
        NEW_PREF="$CURRENT_PREF_IP"
        GEO_TAG="${LAST_GEO:-Node}"
        echo " ✅ 优选 IP 与地区标签保持不变。"
    else
        CF_GET_COUNTRY_CONFIG "$COUNTRY_SEL"
        NEW_PREF="$PREF_IP_PRESET"
        echo " ✅ 地区已更新为：[$GEO_TAG]，优选 IP 已切换为：[$NEW_PREF]"
    fi

    # 追加：允许在选定国家基础上进一步手动微调 IP
    read -p " 如需在此地区基础上微调优选 IP，请输入（直接回车使用上方 IP [$NEW_PREF]）: " FINE_TUNE_IP
    NEW_PREF="${FINE_TUNE_IP:-$NEW_PREF}"
    
    echo "LAST_DOMAIN=\"$LAST_DOMAIN\"" > "$CONFIG_FILE"
    echo "LAST_WSPATH=\"$LAST_WSPATH\"" >> "$CONFIG_FILE"
    echo "LAST_PORT=\"$LAST_PORT\"" >> "$CONFIG_FILE"
    echo "LAST_UUID=\"$LAST_UUID\"" >> "$CONFIG_FILE"
    echo "LAST_ENCODED_PATH=\"$LAST_ENCODED_PATH\"" >> "$CONFIG_FILE"
    echo "LAST_GEO=\"$GEO_TAG\"" >> "$CONFIG_FILE"
    echo "LAST_PREF_IP=\"$NEW_PREF\"" >> "$CONFIG_FILE"
    
    echo " ✅ 配置已持久化保存！"
    deploy_shortcut
    clear
    /usr/local/bin/sd

elif [ "$CHOICE" -eq 3 ]; then
    if [ -f "/usr/local/bin/sd" ]; then /usr/local/bin/sd; else echo " 未找到节点配置！"; fi
elif [ "$CHOICE" -eq 4 ]; then
    systemctl stop sing-box 2>/dev/null || true
    rm -rf /etc/cf_vless /etc/sing-box /usr/local/bin/sd /root/cert
    echo " 卸载清洗完成！"
else
    exit 1
fi
