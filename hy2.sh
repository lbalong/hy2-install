#!/bin/bash

# 检查是否为 Root 用户
if [ "$EUID" -ne 0 ]; then
  echo "错误：请使用 root 用户运行此脚本！"
  exit 1
fi

echo "=========================================================="
echo "    Hysteria 2 & TUIC v5 纯血域名证书共享版一键脚本 V5.1"
echo "=========================================================="
echo " 1. 安装 Hysteria 2 (域名正规证书版)"
echo " 2. 安装 TUIC v5    (域名正规证书版)"
echo " 3. 彻底卸载服务并清空 VPS 环境"
echo "=========================================================="
read -p "请选择需要调试安装的节点模块 [1-3]: " CHOICE

IP=$(curl -sS4 https://ifconfig.me || curl -sS4 https://ipinfo.io/ip || curl -sS4 https://api.ipify.org)
PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "8e21e704-9ac8-4fb8-bef1-6c9d7d7e390b")

if [ -z "$IP" ] && [ "$CHOICE" -ne 3 ]; then
  echo "❌ 错误：无法获取服务器公网 IP，请检查网络连接。"
  exit 1
fi

init_env() {
    local target_port=$1
    echo "正在注入内核加速参数（优化 UDP 缓冲区）..."
    cat <<EOF > /etc/sysctl.d/99-connectivity-tuning.conf
net.core.rmem_max=8388608
net.core.wmem_max=8388608
EOF
    sysctl --system >/dev/null 2>&1

    if command -v ufw > /dev/null; then
        ufw allow 80/tcp >/dev/null 2>&1
        ufw allow $target_port/udp >/dev/null 2>&1
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

# 共享级证书申请/复用函数
sync_cert() {
    local target_dir=$1
    # 🌟 核心调优：如果隔壁已经有现成的正规证书，直接拿来对账复用，防止重复申请被锁死
    if [ -f "/etc/tuic/server.crt" ] && [ "$target_dir" != "/etc/tuic" ]; then
        echo "📥 检测到邻居 TUIC 已持有正规证书，正在执行无缝并网复用..."
        cp /etc/tuic/server.crt "$target_dir/server.crt"
        cp /etc/tuic/server.key "$target_dir/server.key"
        return 0
    elif [ -f "/etc/hysteria/server.crt" ] && [ "$target_dir" != "/etc/hysteria" ]; then
        echo "📥 检测到邻居 Hysteria 2 已持有正规证书，正在执行无缝并网复用..."
        cp /etc/hysteria/server.crt "$target_dir/server.crt"
        cp /etc/hysteria/server.key "$target_dir/server.key"
        return 0
    fi

    # 如果两边都没有，才正儿八经走申请流程
    while true; do
        read -p "👉 请输入已解析到本机的完整域名 (例如 sg.099889.xyz): " DOMAIN
        if [ -z "$DOMAIN" ]; then continue; fi
        local domain_ip=$(curl -s4 "https://1.1.1.1/dns-query?name=$DOMAIN" -H "accept: application/dns-json" | grep -oE '"data":"[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}"' | head -n 1 | awk -F'"' '{print $4}')
        [ -z "$domain_ip" ] && domain_ip=$(getent ahosts "$DOMAIN" | awk '{print $1}' | head -n 1)
        if [ "$domain_ip" = "$IP" ]; then break; else echo "❌ 域名解析 IP 与本机不符！"; fi
    done

    echo "🔄 正在唤醒 acme.sh 并向 Let's Encrypt 申请正规证书..."
    curl -sSL https://get.acme.sh | sh -s email=myhy2tuic@gmail.com
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
    systemctl stop nginx 2>/dev/null
    ~/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone
    
    if [ $? -eq 0 ]; then
        ~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" --key-file "$target_dir/server.key" --fullchain-file "$target_dir/server.crt"
        echo "✅ 正规证书下发并挂载成功！"
    else
        echo "❌ 证书签发遇到限制！自动降级为 10 年期自签名证书保底..."
        openssl req -x509 -nodes -newkey rsa:2048 -keyout "$target_dir/server.key" -out "$target_dir/server.crt" -days 3650 -subj "/CN=$DOMAIN"
    fi
}

get_port() {
    local default_p=$(shuf -i 10000-60000 -n 1)
    read -p "👉 请输入节点监听端口 (直接回车使用随机端口 $default_p): " INPUT_PORT
    echo "${INPUT_PORT:-$default_p}"
}

case $CHOICE in
    1)
        PORT=$(get_port)
        init_env "$PORT"
        mkdir -p /etc/hysteria
        bash <(curl -fsSL https://get.hy2.sh)
        sync_cert "/etc/hysteria"
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
        echo "🎉 Hysteria 2 正规证书域名版部署成功！"
        echo "👉 分享链接: hy2://$PASSWORD@${DOMAIN:-$IP}:$PORT?sni=${DOMAIN:-www.bing.com}#Hy2_Domain_正规"
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
        echo "🎉 TUIC v5 正规证书域名版部署成功！"
        echo "👉 分享链接: tuic://$UUID:$PASSWORD@${DOMAIN:-$IP}:$PORT?congestion_control=bbr&alpn=h3&sni=${DOMAIN:-www.bing.com}#TUIC_Domain_正规"
        ;;

    3)
        echo "🧹 正在强行剥离所有后台进程与残留环境..."
        systemctl stop hysteria-server tuic 2>/dev/null
        systemctl disable hysteria-server tuic 2>/dev/null
        rm -f /etc/systemd/system/hysteria-server.service /etc/systemd/system/tuic.service
        systemctl daemon-reload
        rm -f /usr/local/bin/hysteria /usr/local/bin/tuic-server
        rm -rf /etc/hysteria /etc/tuic
        echo "✅ VPS 环境已彻底洗净！"
        ;;
    *)
        exit 1
        ;;
esac
