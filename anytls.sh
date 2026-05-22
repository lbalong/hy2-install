#!/bin/bash

# 检查是否为 Root 用户
if [ "$EUID" -ne 0 ]; then
    echo "错误：请使用 root 用户运行此脚本！"
    exit 1
fi

# 创建核心目录
mkdir -p /etc/anytls

echo "=========================================================="
echo " AnyTLS 纯血一键部署脚本 V1.0 (参照 Hy2/TUIC 风格)"
echo "=========================================================="
echo " 1. 安装 AnyTLS 节点 (支持域名证书智能复用)"
echo " 2. 查看当前节点链接 (快捷命令: sd)"
echo " 3. 彻底卸载服务并清空环境"
echo "=========================================================="
read -p "请选择操作 [1-3]: " CHOICE

# 提取公共核心变量
IP=$(curl -sS4 https://ifconfig.me || curl -sS4 https://ipinfo.io/ip || curl -sS4 https://api.ipify.org)
PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 20)

if [ -z "$IP" ] && [ "$CHOICE" -ne 3 ] && [ "$CHOICE" -ne 2 ]; then
    echo "❌ 错误：无法获取服务器公网 IP，请检查网络连接。"
    exit 1
fi

# 智能获取服务商与地理位置标签
get_geo_tag() {
    local geo_info=$(curl -s --max-time 3 http://ip-api.com/json/)
    if [ -n "$geo_info" ] && echo "$geo_info" | grep -q '"status":"success"'; then
        local isp=$(echo "$geo_info" | grep -oE '"isp":"[^"]+"' | cut -d'"' -f4 | awk '{print $1}')
        local country=$(echo "$geo_info" | grep -oE '"country":"[^"]+"' | cut -d'"' -f4 | tr -d ' ')
        isp=$(echo "$isp" | tr -cd 'A-Za-z0-9_')
        country=$(echo "$country" | tr -cd 'A-Za-z0-9_')
        echo "${isp}_${country}"
    else
        echo "VPS_Node"
    fi
}

# 核心环境初始化
init_env() {
    echo "正在优化内核 UDP 缓冲区..."
    cat << 'EOF_SYSCTL' > /etc/sysctl.d/99-connectivity-tuning.conf
net.core.rmem_max=8388608
net.core.wmem_max=8388608
EOF_SYSCTL
    sysctl --system >/dev/null 2>&1

    echo "正在清洗防火墙..."
    if command -v ufw > /dev/null; then ufw disable >/dev/null 2>&1; fi
    if command -v systemctl > /dev/null; then systemctl stop firewalld >/dev/null 2>&1 && systemctl disable firewalld >/dev/null 2>&1; fi
    iptables -F && iptables -X
    iptables -P INPUT ACCEPT && iptables -P FORWARD ACCEPT && iptables -P OUTPUT ACCEPT

    if command -v apt-get >/dev/null; then
        apt-get update && apt-get install -y curl openssl wget socat cron net-tools unzip
    elif command -v yum >/dev/null; then
        yum makecache && yum install -y curl openssl wget socat crontabs net-tools unzip
    fi
}

# 部署快捷命令 sd
deploy_shortcut() {
    cat << 'EOF_SHOW' > /usr/local/bin/sd
#!/bin/bash
if [ -f "/etc/anytls/saved_links.txt" ]; then
    clear
    echo "=========================================================="
    echo "📋 当前 VPS AnyTLS 节点链接"
    echo "=========================================================="
    cat /etc/anytls/saved_links.txt
    echo "=========================================================="
else
    echo "❌ 未找到节点信息，请先创建节点！"
fi
EOF_SHOW
    chmod +x /usr/local/bin/sd
}

# 智能域名锁定
get_domain() {
    if [ -f "/etc/anytls/vps_domain.txt" ]; then
        local cached_domain=$(cat /etc/anytls/vps_domain.txt)
        read -p "📋 检测到历史域名 [$cached_domain]，是否复用？[Y/n]: " CONFIRM
        if [ "$CONFIRM" = "n" ] || [ "$CONFIRM" = "N" ]; then
            rm -f /etc/anytls/vps_domain.txt
        else
            DOMAIN=$cached_domain
            return 0
        fi
    fi

    while true; do
        read -p "👉 请输入完整域名 (例如 us2.099889.xyz): " DOMAIN
        [ -z "$DOMAIN" ] && continue

        echo "🔄 正在校验域名解析..."
        local domain_ip=$(curl -s4 "https://1.1.1.1/dns-query?name=$DOMAIN" -H "accept: application/dns-json" | grep -oE '"data":"[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}"' | head -n 1 | awk -F'"' '{print $4}')
        [ -z "$domain_ip" ] && domain_ip=$(getent ahosts "$DOMAIN" | awk '{print $1}' | head -n 1)

        if [ "$domain_ip" = "$IP" ]; then
            echo "$DOMAIN" > /etc/anytls/vps_domain.txt
            echo "✅ 域名 [$DOMAIN] 绑定成功！"
            break
        else
            echo "❌ 解析 IP [$domain_ip] 与本机 IP [$IP] 不匹配！"
        fi
    done
}

# 端口选择
get_port() {
    local cache_file="/etc/anytls/vps_port.txt"
    local cached_port=""

    if [ -f "$cache_file" ]; then
        cached_port=$(cat "$cache_file")
    fi

    local default_p=$(shuf -i 10000-60000 -n 1)

    if [ -n "$cached_port" ]; then
        read -p "📋 检测到历史端口 [$cached_port]，是否复用？[Y/n]: " CONFIRM
        if [ "$CONFIRM" != "n" ] && [ "$CONFIRM" != "N" ]; then
            echo "$cached_port" > "$cache_file"
            echo "$cached_port"
            return 0
        fi
    fi

    read -p "👉 请输入监听端口 (回车使用随机 $default_p): " INPUT_PORT
    local final_port="${INPUT_PORT:-$default_p}"
    echo "$final_port" > "$cache_file"
    echo "$final_port"
}

# 证书管理（支持复用）
sync_cert() {
    get_domain

    # 优先复用已有证书（与 Hy2/TUIC 共享）
    if [ -f "/etc/hysteria/server.crt" ]; then
        echo "📥 检测到 Hysteria2 证书，正在复用..."
        cp /etc/hysteria/server.crt /etc/anytls/server.crt
        cp /etc/hysteria/server.key /etc/anytls/server.key
        return 0
    elif [ -f "/etc/tuic/server.crt" ]; then
        echo "📥 检测到 TUIC 证书，正在复用..."
        cp /etc/tuic/server.crt /etc/anytls/server.crt
        cp /etc/tuic/server.key /etc/anytls/server.key
        return 0
    fi

    echo "🔄 申请 Let's Encrypt 证书..."
    systemctl stop nginx apache2 2>/dev/null
    curl -sSL https://get.acme.sh | sh -s email=myanytls@gmail.com
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt

    ~/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone
    if [ $? -eq 0 ]; then
        ~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" \
            --key-file /etc/anytls/server.key \
            --fullchain-file /etc/anytls/server.crt
        echo "✅ 证书签发/复用成功！"
    else
        echo "❌ 证书签发失败，请确保 80 端口可用！"
        exit 1
    fi
}

case $CHOICE in
1)
    PORT=$(get_port)
    init_env
    sync_cert

    echo "🚀 下载 AnyTLS 服务端核心..."
    ARCH="amd64"
    [ "$(uname -m)" = "aarch64" ] && ARCH="arm64"
    wget -qO /usr/local/bin/anytls-server "https://github.com/anytls/anytls-go/releases/latest/download/anytls-server-linux-${ARCH}" || {
        echo "下载失败，使用备用源..."
        wget -qO /usr/local/bin/anytls-server "https://mirror.ghproxy.com/https://github.com/anytls/anytls-go/releases/latest/download/anytls-server-linux-${ARCH}"
    }
    chmod +x /usr/local/bin/anytls-server

    # 创建 systemd 服务
    cat << EOF_ANYTLS_SERVICE > /etc/systemd/system/anytls.service
[Unit]
Description=AnyTLS Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/anytls
ExecStart=/usr/local/bin/anytls-server -l 0.0.0.0:$PORT -p $PASSWORD --cert /etc/anytls/server.crt --key /etc/anytls/server.key
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF_ANYTLS_SERVICE

    systemctl daemon-reload && systemctl enable anytls && systemctl restart anytls

    GEO_TAG=$(get_geo_tag)
    ANYTLS_LINK="anytls://$PASSWORD@$DOMAIN:$PORT?sni=$DOMAIN&allowInsecure=false#AnyTLS_${GEO_TAG}"

    touch /etc/anytls/saved_links.txt
    sed -i '/#AnyTLS_/d' /etc/anytls/saved_links.txt 2>/dev/null
    echo "$ANYTLS_LINK" >> /etc/anytls/saved_links.txt

    deploy_shortcut

    clear
    /usr/local/bin/sd
    ;;

2)
    if [ -f "/usr/local/bin/sd" ]; then
        /usr/local/bin/sd
    else
        echo "❌ 未找到节点信息！"
    fi
    ;;

3)
    echo "🧹 正在彻底卸载 AnyTLS..."
    systemctl stop anytls 2>/dev/null
    systemctl disable anytls 2>/dev/null
    rm -f /etc/systemd/system/anytls.service
    systemctl daemon-reload
    rm -f /usr/local/bin/anytls-server /usr/local/bin/sd
    rm -rf /etc/anytls
    echo "✅ AnyTLS 已彻底清理干净！"
    ;;

*)
    echo "无效选择，退出。"
    exit 1
    ;;
esac
