#!/bin/bash

# 检查是否为 Root 用户
if [ "$EUID" -ne 0 ]; then
  echo "错误：请使用 root 用户运行此脚本！"
  exit 1
fi

echo "=========================================================="
echo "    Hysteria 2 & TUIC v5 纯血域名证书完美对账版 V5.3"
echo "=========================================================="
echo " 1. 安装 Hysteria 2 (域名正规证书版)"
echo " 2. 安装 TUIC v5    (域名正规证书版)"
echo " 3. 彻底卸载服务并清空 VPS 环境"
echo "=========================================================="
read -p "请选择需要调试安装的节点模块 [1-3]: " CHOICE

# 提取公共核心变量
IP=$(curl -sS4 https://ifconfig.me || curl -sS4 https://ipinfo.io/ip || curl -sS4 https://api.ipify.org)
PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "8e21e704-9ac8-4fb8-bef1-6c9d7d7e390b")

if [ -z "$IP" ] && [ "$CHOICE" -ne 3 ]; then
  echo "❌ 错误：无法获取服务器公网 IP，请检查网络连接。"
  exit 1
fi

# 核心环境与防火墙初始化
init_env() {
    local target_port=$1
    echo "正在注入内核加速参数（优化 UDP 缓冲区）..."
    printf "net.core.rmem_max=8388608\nnet.core.wmem_max=8388608\n" > /etc/sysctl.d/99-connectivity-tuning.conf
    sysctl --system >/dev/null 2>&1

    echo "正在打通本地防火墙通信通道，精准放行端口: $target_port 与 80/tcp..."
    if command -v ufw > /dev/null; then
        ufw allow 80/tcp >/dev/null 2>&1
        ufw allow $target_port/udp >/dev/null 2>&1
        ufw reload >/dev/null 2>&1
        ufw disable >/dev/null 2>&1
    fi
    if command -v firewall-cmd > /dev/null; then
        firewall-cmd --zone=public --add-port=80/tcp --permanent >/dev/null 2>&1
        firewall-cmd --zone=public --add-port=$target_port/udp --permanent >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
    fi
    iptables -I INPUT -p udp --dport $target_port -j ACCEPT
    iptables -I INPUT -p tcp --dport 80 -j ACCEPT

    if command -v apt-get >/dev/null; then
      apt-get update && apt-get install -y curl openssl wget iptables socat cron
    elif command -v yum >/dev/null; then
      yum makecache && yum install -y curl openssl wget iptables socat crontabs
    fi
}

# 🔒 智能域名读取与对账函数（确保 DOMAIN 全局百分百有效）
get_domain() {
    if [ -f "/etc/vps_domain.txt" ]; then
        DOMAIN=$(cat /etc/vps_domain.txt)
        echo "📋 自动从本地缓存账本读取域名: $DOMAIN"
    else
        while true; do
            read -p "👉 请输入已解析到本机的完整域名 (例如 sg.099889.xyz): " DOMAIN
            if [ -z "$DOMAIN" ]; then continue; fi
            echo "🔄 正在请求多路公网 DNS 校验域名解析..."
            local domain_ip=$(curl -s4 "https://1.1.1.1/dns-query?name=$DOMAIN" -H "accept: application/dns-json" | grep -oE '"data":"[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}"' | head -n 1 | awk -F'"' '{print $4}')
            [ -z "$domain_ip" ] && domain_ip=$(getent ahosts "$DOMAIN" | awk '{print $1}' | head -n 1)
            
            if [ "$domain_ip" = "$IP" ]; then
                echo "$DOMAIN" > /etc/vps_domain.txt
                echo "✅ 对账成功！域名 [$DOMAIN] 已精准绑定本机 IP ($IP)"
                break
            else
                echo "❌ 校验失败：当前域名解析出的 IP 为 [$domain_ip]，与本机 IP [$IP] 不符！"
                echo "=========================================="
            fi
        done
    fi
}

# 共享级证书同步（绝不重复向 Let's Encrypt 刷单）
sync_cert() {
    local target_dir=$1
    get_domain
    
    if [ -f "/etc/tuic/server.crt" ] && [ "$target_dir" != "/etc/tuic" ]; then
        echo "📥 检测到隔壁 TUIC 已持有正规证书，正在执行无缝复制复用..."
        cp /etc/tuic/server.crt "$target_dir/server.crt"
        cp /etc/tuic/server.key "$target_dir/server.key"
        return 0
    elif [ -f "/etc/hysteria/server.crt" ] && [ "$target_dir" != "/etc/hysteria" ]; then
        echo "📥 检测到隔壁 Hysteria 2 已持有正规证书，正在执行无缝复制复用..."
        cp /etc/hysteria/server.crt "$target_dir/server.crt"
        cp /etc/hysteria/server.key "$target_dir/server.key"
        return 0
    fi

    echo "🔄 正在唤醒 acme.sh 并向 Let's Encrypt 申请正式合规证书..."
    curl -sSL https://get.acme.sh | sh -s email=myhy2tuic@gmail.com
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
    systemctl stop nginx 2>/dev/null
    ~/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone
    
    if [ $? -eq 0 ]; then
        ~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" --key-file "$target_dir/server.key" --fullchain-file "$target_dir/server.crt"
        echo "✅ 正规域名证书下发成功！"
    else
        echo "❌ 证书签发卡死！自动降级为 10 年期自签名证书保底..."
        openssl req -x509 -nodes -newkey rsa:2048 -keyout "$target_dir/server.key" -out "$target_dir/server.crt" -days 3650 -subj "/CN=$DOMAIN"
    fi
}

get_port() {
    local default_p=$(shuf -i 10000-60000 -n 1)
    read -p "👉 请输入节点监听端口 (直接回车使用随机端口 $default_p): " INPUT_PORT
    echo "${INPUT_PORT:-$default_p}"
}

# ==================== 核心执行控制 ====================
case $CHOICE in
    1)
        PORT=$(get_port)
        init_env "$PORT"
        mkdir -p /etc/hysteria
        bash <(curl -fsSL https://get.hy2.sh)
        sync_cert "/etc/hysteria"
        
        # 🌟 绝杀优化：使用 printf 彻底替代 heredoc，免疫任何缩进带来的 EOF 语法错误
        printf "listen: :%s\ntls:\n  cert: /etc/hysteria/server.crt\n  key: /etc/hysteria/server.key\nauth:\n  type: password\n  password: %s\n" "$PORT" "$PASSWORD" > /etc/hysteria/server.yaml

        systemctl daemon-reload && systemctl enable hysteria-server && systemctl restart hysteria-server
        clear
        echo "🎉 Hysteria 2 纯血域名证书版完美通关！"
        echo "👉 分享链接 (已锁死正规 SNI): hy2://$PASSWORD@$DOMAIN:$PORT?sni=$DOMAIN#Hy2_Domain_正规"
        ;;

    2)
        PORT=$(get_port)
        init_env "$PORT"
        mkdir -p /etc/tuic
        sync_cert "/etc/tuic"
        
        echo "🚀 正在下载 TUIC v5 服务端核心..."
        TUIC_ARCH="x86_64-unknown-linux-gnu"
        [ "$(uname -m)" = "aarch64" ] && TUIC_ARCH="aarch64-unknown-linux-gnu"
        wget -qO /usr/local/bin/tuic-server "https://github.com/tuic-protocol/tuic/releases/download/tuic-server-1.0.0/tuic-server-1.0.0-${TUIC_ARCH}" || wget -qO /usr/local/bin/tuic-server "https://mirror.ghproxy.com/https://github.com/tuic-protocol/tuic/releases/download/tuic-server-1.0.0/tuic-server-1.0.0-${TUIC_ARCH}"
        chmod +x /usr/local/bin/tuic-server

        # 🌟 绝杀优化：使用 printf 替代 JSON 写入
        printf '{\n  "server": "[::]:%s",\n  "users": {\n    "%s": "%s"\n  },\n  "certificate": "/etc/tuic/server.crt",\n  "private_key": "/etc/tuic/server.key",\n  "congestion_control": "bbr",\n  "alpn": ["h3"],\n  "udp_relay_ipv6": true,\n  "zero_rtt_handshake": false,\n  "auth_timeout": "3s"\n}\n' "$PORT" "$UUID" "$PASSWORD" > /etc/tuic/config.json

        # 🌟 绝杀优化：使用 printf 替代 Service 写入
        printf "[Unit]\nDescription=TUIC V5 Service\nAfter=network.target\n\n[Service]\nType=simple\nUser=root\nWorkingDirectory=/etc/tuic\nExecStart=/usr/local/bin/tuic-server -c /etc/tuic/config.json\nRestart=always\nRestartSec=5\n\n[Install]\nWantedBy=multi-user.target\n" > /etc/systemd/system/tuic.service

        systemctl daemon-reload && systemctl enable tuic && systemctl restart tuic
        clear
        echo "🎉 TUIC v5 纯血域名证书版部署成功！"
        echo "👉 分享链接: tuic://$UUID:$PASSWORD@$DOMAIN:$PORT?congestion_control=bbr&alpn=h3&sni=$DOMAIN#TUIC_Domain_正规"
        ;;

    3)
        echo "🧹 正在强行剥离所有后台进程与残留环境..."
        systemctl stop hysteria-server tuic 2>/dev/null
        systemctl disable hysteria-server tuic 2>/dev/null
        rm -f /etc/systemd/system/hysteria-server.service /etc/systemd/system/tuic.service
        systemctl daemon-reload
        rm -f /usr/local/bin/hysteria /usr/local/bin/tuic-server
        rm -rf /etc/hysteria /etc/tuic /etc/vps_domain.txt
        echo "✅ VPS 环境已彻底洗净！"
        ;;
    *)
        exit 1
        ;;
esac
