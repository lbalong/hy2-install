#!/bin/bash

# 检查是否为 Root 用户
if [ "$EUID" -ne 0 ]; then
  echo "❌ 错误：请使用 root 用户运行此脚本！"
  exit 1
fi

CONFIG_FILE="/etc/sd_vless_tls_last.conf"

# 初始化账本状态
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# ================= 核心：动态生成配置文件 =================
rebuild_xray_config() {
    local INBOUNDS_JSON=""
    
    append_inbound() {
        if [ -n "$INBOUNDS_JSON" ]; then
            INBOUNDS_JSON+=","
        fi
        INBOUNDS_JSON+="$1"
    }

    # 1. xHTTP 模块
    if [ "$NODE_XH_EN" == "1" ]; then
        append_inbound "$(cat <<EOF
    {
      "port": $PORT_XH,
      "protocol": "vless",
      "settings": {"clients": [{"id": "$UUID", "level": 0}], "decryption": "none"},
      "streamSettings": {
        "network": "xhttp",
        "security": "tls",
        "tlsSettings": {"alpn": ["h2", "http/1.1"], "certificates": [{"certificateFile": "/usr/local/etc/xray/server.crt", "keyFile": "/usr/local/etc/xray/server.key"}]},
        "xhttpSettings": {"path": "/xhttp", "host": "$DOMAIN", "mode": "auto"}
      },
      "sniffing": {"enabled": true, "destOverride": ["http", "tls", "quic"]}
    }
EOF
)"
    fi

    # 2. HTTPUpgrade 模块
    if [ "$NODE_HU_EN" == "1" ]; then
        append_inbound "$(cat <<EOF
    {
      "port": $PORT_HU,
      "protocol": "vless",
      "settings": {"clients": [{"id": "$UUID", "level": 0}], "decryption": "none"},
      "streamSettings": {
        "network": "httpupgrade",
        "security": "tls",
        "tlsSettings": {"alpn": ["http/1.1"], "certificates": [{"certificateFile": "/usr/local/etc/xray/server.crt", "keyFile": "/usr/local/etc/xray/server.key"}]},
        "httpupgradeSettings": {"path": "/httpupgrade", "host": "$DOMAIN"}
      },
      "sniffing": {"enabled": true, "destOverride": ["http", "tls", "quic"]}
    }
EOF
)"
    fi

    # 3. WS (WebSocket) 模块
    if [ "$NODE_WS_EN" == "1" ]; then
        append_inbound "$(cat <<EOF
    {
      "port": $PORT_WS,
      "protocol": "vless",
      "settings": {"clients": [{"id": "$UUID", "level": 0}], "decryption": "none"},
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {"alpn": ["http/1.1"], "certificates": [{"certificateFile": "/usr/local/etc/xray/server.crt", "keyFile": "/usr/local/etc/xray/server.key"}]},
        "wsSettings": {"path": "/ws", "headers": {"Host": "$DOMAIN"}}
      },
      "sniffing": {"enabled": true, "destOverride": ["http", "tls", "quic"]}
    }
EOF
)"
    fi

    # 如果所有节点都被卸载了，写入一个空的 INBOUNDS 防止 Xray 崩溃
    if [ -z "$INBOUNDS_JSON" ]; then
        echo "⚠️ 当前没有任何启用的节点。"
    fi

    cat <<EOF > /usr/local/etc/xray/config.json
{
  "log": {"loglevel": "warning"},
  "inbounds": [
$INBOUNDS_JSON
  ],
  "outbounds": [{"protocol": "freedom"}]
}
EOF

    systemctl daemon-reload && systemctl enable xray && systemctl restart xray
    sleep 2
}

# ================= 依赖与证书检查 =================
check_and_install_env() {
    # 基础依赖
    if command -v apt-get >/dev/null; then
        apt-get update -y && apt-get install -y curl socat cron jq uuid-runtime iptables
    elif command -v yum >/dev/null; then
        yum makecache && yum install -y curl socat cron jq uuid-runtime iptables
    fi
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

    # 证书申请 (LE + ZeroSSL 容错)
    mkdir -p /usr/local/etc/xray
    if [ ! -f /usr/local/etc/xray/server.crt ]; then
        systemctl stop nginx 2>/dev/null
        systemctl stop apache2 2>/dev/null
        iptables -I INPUT -p tcp --dport 80 -j ACCEPT
        
        curl -sL https://get.acme.sh | sh
        ~/.acme.sh/acme.sh --upgrade --auto-upgrade
        ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
        
        if ! ~/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone -k ec-256; then
            echo "⚠️ Let's Encrypt 失败，自动切换 ZeroSSL..."
            ~/.acme.sh/acme.sh --register-account -m "admin@$DOMAIN" --server zerossl
            if ! ~/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone -k ec-256 --server zerossl; then
                echo "❌ 证书申请全线失败！请检查域名解析和 CDN 状态。"
                exit 1
            fi
        fi
        ~/.acme.sh/acme.sh --installcert -d "$DOMAIN" --fullchainpath /usr/local/etc/xray/server.crt --keypath /usr/local/etc/xray/server.key --ecc
    fi
    chown nobody:nogroup /usr/local/etc/xray/server.crt /usr/local/etc/xray/server.key 2>/dev/null || chown nobody:nobody /usr/local/etc/xray/server.crt /usr/local/etc/xray/server.key 2>/dev/null
}

# ================= 打印分享链接 =================
show_links() {
    echo "=========================================="
    echo " ✅ 当前运行中的节点链接："
    echo "=========================================="
    if [ "$NODE_XH_EN" == "1" ]; then
        echo "👇 [VLESS + xHTTP + TLS]"
        echo "vless://$UUID@$DOMAIN:$PORT_XH?type=xhttp&security=tls&sni=$DOMAIN&path=/xhttp&host=$DOMAIN&mode=auto#VLESS-xHTTP"
        echo ""
    fi
    if [ "$NODE_HU_EN" == "1" ]; then
        echo "👇 [VLESS + HTTPUpgrade + TLS]"
        echo "vless://$UUID@$DOMAIN:$PORT_HU?type=httpupgrade&security=tls&sni=$DOMAIN&path=/httpupgrade&host=$DOMAIN&alpn=http%2F1.1#VLESS-HTTPUpgrade"
        echo ""
    fi
    if [ "$NODE_WS_EN" == "1" ]; then
        echo "👇 [VLESS + WS + TLS]"
        echo "vless://$UUID@$DOMAIN:$PORT_WS?type=ws&security=tls&sni=$DOMAIN&path=/ws&host=$DOMAIN#VLESS-WS"
        echo ""
    fi
    echo "=========================================="
}

# ================= 安装菜单 =================
install_menu() {
    echo "=========================================="
    echo "  请选择要【添加/启用】的节点："
    echo "  1. 启用 xHTTP 节点"
    echo "  2. 启用 HTTPUpgrade 节点"
    echo "  3. 启用 WebSocket (WS) 节点"
    echo "  4. 一键启用全部三节点"
    echo "  0. 返回主菜单"
    echo "=========================================="
    read -p "👉 选项: " ADD_CHOICE

    if [[ ! "$ADD_CHOICE" =~ ^[1-4]$ ]]; then return; fi

    if [ -z "$DOMAIN" ]; then
        read -p "👉 请输入已解析的域名 (需过 CF 小黄云): " DOMAIN
        [ -z "$DOMAIN" ] && exit 1
    fi

    if [ -z "$UUID" ]; then
        UUID=$(cat /proc/sys/kernel/random/uuid)
    fi

    echo "⚠️ 提示：CF 支持端口为 443, 2053, 2083, 2087, 2096, 8443"

    if [[ "$ADD_CHOICE" == "1" || "$ADD_CHOICE" == "4" ]]; then
        read -p "👉 请输入 xHTTP 端口 (默认 2083): " IN_PORT
        PORT_XH=${IN_PORT:-2083}; NODE_XH_EN=1
        iptables -I INPUT -p tcp --dport $PORT_XH -j ACCEPT
    fi
    if [[ "$ADD_CHOICE" == "2" || "$ADD_CHOICE" == "4" ]]; then
        read -p "👉 请输入 HTTPUpgrade 端口 (默认 2087): " IN_PORT
        PORT_HU=${IN_PORT:-2087}; NODE_HU_EN=1
        iptables -I INPUT -p tcp --dport $PORT_HU -j ACCEPT
    fi
    if [[ "$ADD_CHOICE" == "3" || "$ADD_CHOICE" == "4" ]]; then
        read -p "👉 请输入 WS 端口 (默认 2096): " IN_PORT
        PORT_WS=${IN_PORT:-2096}; NODE_WS_EN=1
        iptables -I INPUT -p tcp --dport $PORT_WS -j ACCEPT
    fi

    # 保存状态
    echo "DOMAIN=\"$DOMAIN\"" > "$CONFIG_FILE"
    echo "UUID=\"$UUID\"" >> "$CONFIG_FILE"
    echo "NODE_XH_EN=$NODE_XH_EN" >> "$CONFIG_FILE"
    echo "PORT_XH=$PORT_XH" >> "$CONFIG_FILE"
    echo "NODE_HU_EN=$NODE_HU_EN" >> "$CONFIG_FILE"
    echo "PORT_HU=$PORT_HU" >> "$CONFIG_FILE"
    echo "NODE_WS_EN=$NODE_WS_EN" >> "$CONFIG_FILE"
    echo "PORT_WS=$PORT_WS" >> "$CONFIG_FILE"

    check_and_install_env
    rebuild_xray_config
    show_links
}

# ================= 卸载菜单 =================
uninstall_menu() {
    echo "=========================================="
    echo "  请选择要【单独卸载/停用】的节点："
    echo "  1. 停用 xHTTP 节点"
    echo "  2. 停用 HTTPUpgrade 节点"
    echo "  3. 停用 WebSocket (WS) 节点"
    echo "  9. 🔴 毁灭级：卸载所有节点并清空 Xray/证书"
    echo "  0. 返回主菜单"
    echo "=========================================="
    read -p "👉 选项: " RM_CHOICE

    if [[ "$RM_CHOICE" == "1" ]]; then NODE_XH_EN=0; echo "✅ 已停用 xHTTP"; fi
    if [[ "$RM_CHOICE" == "2" ]]; then NODE_HU_EN=0; echo "✅ 已停用 HTTPUpgrade"; fi
    if [[ "$RM_CHOICE" == "3" ]]; then NODE_WS_EN=0; echo "✅ 已停用 WS"; fi

    if [[ "$RM_CHOICE" =~ ^[1-3]$ ]]; then
        sed -i "s/^NODE_XH_EN=.*/NODE_XH_EN=$NODE_XH_EN/" "$CONFIG_FILE"
        sed -i "s/^NODE_HU_EN=.*/NODE_HU_EN=$NODE_HU_EN/" "$CONFIG_FILE"
        sed -i "s/^NODE_WS_EN=.*/NODE_WS_EN=$NODE_WS_EN/" "$CONFIG_FILE"
        rebuild_xray_config
        show_links
        return
    fi

    if [[ "$RM_CHOICE" == "9" ]]; then
        systemctl stop xray && systemctl disable xray
        bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove >/dev/null 2>&1
        [ -f ~/.acme.sh/acme.sh ] && ~/.acme.sh/acme.sh --uninstall >/dev/null 2>&1
        rm -rf ~/.acme.sh /usr/local/etc/xray "$CONFIG_FILE"
        echo "✅ 彻底卸载清理完毕！"
        exit 0
    fi
}

# ================= 主菜单 =================
while true; do
    echo "=========================================="
    echo "  VLESS 模块化多协议融合版 (支持热插拔)"
    echo "=========================================="
    echo "  当前状态: "
    [ "$NODE_XH_EN" == "1" ] && echo "  - xHTTP: 启用 (端口 $PORT_XH)"
    [ "$NODE_HU_EN" == "1" ] && echo "  - HTTPUpgrade: 启用 (端口 $PORT_HU)"
    [ "$NODE_WS_EN" == "1" ] && echo "  - WebSocket: 启用 (端口 $PORT_WS)"
    echo "=========================================="
    echo "  1. ➕ 增加 / 启用节点"
    echo "  2. ➖ 卸载 / 停用节点"
    echo "  3. 📋 查看当前节点配置链接"
    echo "  0. 退出脚本"
    echo "=========================================="
    read -p "👉 请输入选项: " MAIN_CHOICE

    case $MAIN_CHOICE in
        1) install_menu ;;
        2) uninstall_menu ;;
        3) show_links ;;
        0) exit 0 ;;
        *) echo "❌ 无效输入" ;;
    esac
done
