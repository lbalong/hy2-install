#!/bin/bash

# 检查是否为 Root 用户
if [ "$EUID" -ne 0 ]; then
  echo "错误：请使用 root 用户运行此脚本！"
  exit 1
fi

echo "=========================================================="
echo "    Hysteria 2 & TUIC v5 独立模块化全能一键脚本 V4.5"
echo "=========================================================="
echo " 1. 安装 Hysteria 2 (纯 IP 自签名版)"
echo " 2. 安装 Hysteria 2 (域名正规证书版)"
echo " 3. 安装 TUIC v5    (纯 IP 自签名版)"
echo " 4. 安装 TUIC v5    (域名正规证书版)"
echo " 5. 彻底卸载服务并清空 VPS 环境"
echo "=========================================================="
read -p "请选择需要调试安装的节点模块 [1-5]: " CHOICE

# 提取公共核心变量
IP=$(curl -sS4 https://ifconfig.me || curl -sS4 https://ipinfo.io/ip || curl -sS4 https://api.ipify.org)
PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "8e21e704-9ac8-4fb8-bef1-6c9d7d7e390b")

if [ -z "$IP" ] && [ "$CHOICE" -ne 5 ]; then
  echo "❌ 错误：无法获取服务器公网 IP，请检查网络连接。"
  exit 1
fi

# 核心防火墙与依赖放行函数
init_env() {
    local target_port=$1
    local is_tcp=$2
    
    echo "正在注入内核加速参数（优化 UDP 缓冲区）..."
    cat <<EOF > /etc/sysctl.d/99-connectivity-tuning.conf
net.core.rmem_max=8388608
net.core.wmem_max=8388608
EOF
    sysctl --system >/dev/null 2>&1

    echo "正在打通本地防火墙通信通道，精准放行端口: $target_port ..."
    if command -v ufw > /dev/null; then
        [ "$is_tcp" = "true" ] && ufw allow 80/tcp >/dev/null 2>&1
        ufw allow $target_port/udp >/dev/null 2>&1
        ufw reload >/dev/null 2>&1
        ufw disable >/dev/null 2>&1
    fi
    if command -v firewall-cmd > /dev/null; then
        [ "$is_tcp" = "true" ] && firewall-cmd --zone=public --add-port=80/tcp --permanent >/dev/null 2>&1
        firewall-cmd --zone=public --add-port=$target_port/udp --permanent >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
    fi
    iptables -I INPUT -p udp --dport $target_port -j ACCEPT
    [ "$is_tcp" = "true" ] && iptables -I INPUT -p tcp --dport 80 -j ACCEPT

    if command -v apt-get >/dev/null; then
      apt-get update && apt-get install -y curl openssl wget iptables socat cron
    elif command -v yum >/dev/null; then
      yum makecache && yum install -y curl openssl wget iptables socat crontabs
    fi
}

# 智能域名校验与 ACME 申请函数
request_cert() {
    local cert_dir=$1
    while true; do
        read -p "👉 请输入已解析到本机的完整域名 (例如 sg.099889.xyz): " DOMAIN
        if [ -z "$DOMAIN" ]; then
            echo "❌ 域名不能为空，请重新输入！"
            continue
        fi
        echo "🔄 正在请求多路公网 DNS 校验域名解析..."
        local domain_ip=$(curl -s4 "https://1.1.1.1/dns-query?name=$DOMAIN" -H "accept: application/dns-json" | grep -oE '"data":"[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}"' | head -n 1 | awk -F'"' '{print $4}')
        [ -z "$domain_ip" ] && domain_ip=$(getent ahosts "$DOMAIN" | awk '{print $1}' | head -n 1)

        if [ "$domain_ip" = "$IP" ]; then
            echo "✅ 对账成功！域名 [$DOMAIN] 已精准绑定本机公网 IP ($IP)"
            break
        else
            echo "❌ 校验失败：当前域名解析出的 IP 为 [$domain_ip]，与本机 IP [$IP] 不符！"
            echo "=========================================="
        fi
    done

    echo "🔄 正在唤醒 acme.sh 并申请 Let's Encrypt 正规证书..."
    curl -sSL https://get.acme.sh | sh -s email=myhy2tuic@gmail.com
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
    systemctl stop nginx 2>/dev/null
    ~/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone
    
    if [ $? -eq 0 ]; then
        ~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" --key-file "$cert_dir/server.key" --fullchain-file "$cert_dir/server.crt"
        echo "✅ 正规证书下发并挂载成功！"
    else
        echo "❌ 证书签发卡死！自动降级为 10 年期自签名证书保底..."
        openssl req -x509 -nodes -newkey rsa:2048 -keyout "$cert_dir/server.key" -out "$cert_dir/server.crt" -days 3650 -subj "/CN=$DOMAIN"
    fi
}

# 端口输入函数
get_port() {
    local default_p=$(shuf -i 10000-60000 -n 1)
    read -p "👉 请输入节点监听端口 (直接回车使用随机端口 $default_p): " INPUT_PORT
    echo "${INPUT_PORT:-$default_p}"
}

# ==================== 核心执行流程控制 ====================
case $CHOICE in
    1)
        PORT=$(get_port)
        init_env "$PORT" "false"
        mkdir -p /etc/hysteria
        bash <(curl -fsSL https://get.hy2.sh)
        openssl req -x509 -nodes -newkey rsa:2048 -keyout /etc/hysteria/server.key -out /etc/hysteria/server.crt -days 3650 -subj "/CN=www.bing.com"
        cat <<EOF > /etc/hysteria/config.yaml
listen: :$PORT
tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key
auth:
  type: password
  password: $PASSWORD
EOF
        systemctl daemon-reload && systemctl enable hysteria-server && systemctl restart hysteria-server
        clear
        echo "🎉 Hysteria 2 自签名版部署成功！"
        echo "👉 分享链接: hy2://$PASSWORD@$IP:$PORT?insecure=1&sni=www.bing.com#Hy2_IP_自签"
        ;;
        
    2)
        PORT=$(get_port)
        init_env "$PORT" "true"
        mkdir -p /etc/hysteria
        bash <(curl -fsSL https://get.hy2.sh)
        request_cert "/etc/hysteria"
        cat <<EOF > /etc/hysteria/config.yaml
listen: :$PORT
tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key
auth:
  type: password
  password: $PASSWORD
EOF
        systemctl daemon-reload && systemctl enable hysteria-server && systemctl restart hysteria-server
        clear
        echo "🎉 Hysteria 2 正规证书版部署成功！"
        echo "👉 分享链接: hy2://$PASSWORD@$DOMAIN:$PORT?sni=$DOMAIN#Hy2_Domain_正规"
        ;;

    3)
        PORT=$(get_port)
        init_env "$PORT" "false"
        mkdir -p /etc/tuic
        openssl req -x509 -nodes -newkey rsa:2048 -keyout /etc/tuic/server.key -out /etc/tuic/server.crt -days 3650 -subj "/CN=www.bing.com"
        
        echo "🚀 正在下载 TUIC v5 服务端核心..."
        TUIC_ARCH="x86_64-unknown-linux-gnu"
        [ "$(uname -m)" = "aarch64" ] && TUIC_ARCH="aarch64-unknown-linux-gnu"
        wget -qO /usr/local/bin/tuic-server "https://github.com/tuic-protocol/tuic/releases/download/tuic-server-1.0.0/tuic-server-1.0.0-${TUIC_ARCH}" || wget -qO /usr/local/bin/tuic-server "https://mirror.ghproxy.com/https://github.com/tuic-protocol/tuic/releases/download/tuic-server-1.0.0/tuic-server-1.0.0-${TUIC_ARCH}"
        chmod +x /usr/local/bin/tuic-server

        cat <<EOF > /etc/tuic/config.json
{
  "server": "[::]:$PORT",
  "users": { "$UUID": "$PASSWORD" },
  "certificate": "/etc/tuic/server.crt",
  "private_key": "/etc/tuic/server.key",
  "congestion_control": "bbr",
  "alpn": ["h3"],
  "udp_relay_ipv6": true,
  "zero_rtt_handshake": false,
  "auth_timeout": "3s"
}
EOF
        cat <<EOF > /etc/systemd/system/tuic.service
[Unit]
Description=TUIC V5 Service
After=network.target
[Service]
Type=simple
User=root
WorkingDirectory=/etc/tuic
ExecStart=/usr/local/bin/tuic-server -c /etc/tuic/config.json
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload && systemctl enable tuic && systemctl restart tuic
        clear
        echo "🎉 TUIC v5 自签名版部署成功！"
        echo "👉 客户端参数: 地址:$IP \| 端口:$PORT \| UUID:$UUID \| 密码:$PASSWORD \| ALPN:h3 \| 允许不安全:true"
        echo "👉 分享链接: tuic://$UUID:$PASSWORD@$IP:$PORT?congestion_control=bbr&alpn=h3&sni=www.bing.com&allow_insecure=1#TUIC_IP_自签"
        ;;

    4)
        PORT=$(get_port)
        init_env "$PORT" "true"
        mkdir -p /etc/tuic
        request_cert "/etc/tuic"
        
        echo "🚀 正在下载 TUIC v5 服务端核心..."
        TUIC_ARCH="x86_64-unknown-linux-gnu"
        [ "$(uname -m)" = "aarch64" ] && TUIC_ARCH="aarch64-unknown-linux-gnu"
        wget -qO /usr/local/bin/tuic-server "https://github.com/tuic-protocol/tuic/releases/download/tuic-server-1.0.0/tuic-server-1.0.0-${TUIC_ARCH}" || wget -qO /usr/local/bin/tuic-server "https://mirror.ghproxy.com/https://github.com/tuic-protocol/tuic/releases/download/tuic-server-1.0.0/tuic-server-1.0.0-${TUIC_ARCH}"
        chmod +x /usr/local/bin/tuic-server

        cat <<EOF > /etc/tuic/config.json
{
  "server": "[::]:$PORT",
  "users": { "$UUID": "$PASSWORD" },
  "certificate": "/etc/tuic/server.crt",
  "private_key": "/etc/tuic/server.key",
  "congestion_control": "bbr",
  "alpn": ["h3"],
  "udp_relay_ipv6": true,
  "zero_rtt_handshake": false,
  "auth_timeout": "3s"
}
EOF
        cat <<EOF > /etc/systemd/system/tuic.service
[Unit]
Description=TUIC V5 Service
After=network.target
[Service]
Type=simple
User=root
WorkingDirectory=/etc/tuic
ExecStart=/usr/local/bin/tuic-server -c /etc/tuic/config.json
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload && systemctl enable tuic && systemctl restart tuic
        clear
        echo "🎉 TUIC v5 正规证书版部署成功！"
        echo "👉 客户端参数: 地址:$DOMAIN \| 端口:$PORT \| UUID:$UUID \| 密码:$PASSWORD \| ALPN:h3"
        echo "👉 分享链接: tuic://$UUID:$PASSWORD@$DOMAIN:$PORT?congestion_control=bbr&alpn=h3&sni=$DOMAIN#TUIC_Domain_正规"
        ;;

    5)
        echo "🧹 正在强行剥离所有后台进程与残留环境..."
        systemctl stop hysteria-server tuic 2>/dev/null
        systemctl disable hysteria-server tuic 2>/dev/null
        rm -f /etc/systemd/system/hysteria-server.service /etc/systemd/system/tuic.service
        systemctl daemon-reload
        rm -f /usr/local/bin/hysteria /usr/local/bin/tuic-server
        rm -rf /etc/hysteria /etc/tuic
        echo "✅ VPS 已经彻底洗干净，纯净如新！"
        ;;
    *)
        echo "❌ 输入错误，脚本退出。"
        exit 1
        ;;
esac
