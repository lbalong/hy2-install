#!/bin/bash

# ==========================================================
#  AnyTLS 一键纯净部署脚本 V1.0
# ==========================================================

# 检查 Root
if [ "$EUID" -ne 0 ]; then
  echo "错误：请使用 root 用户运行此脚本！"
  exit 1
fi

mkdir -p /etc/anytls_manager

echo "=========================================================="
echo "              AnyTLS 纯净部署脚本 V1.0"
echo "=========================================================="
echo " 1. 安装 AnyTLS"
echo " 2. 查看当前节点链接 (快捷命令: sd)"
echo " 3. 彻底卸载 AnyTLS"
echo "=========================================================="

read -p "请选择操作 [1-3]: " CHOICE

IP=$(curl -sS4 https://ifconfig.me || curl -sS4 https://ipinfo.io/ip || curl -sS4 https://api.ipify.org)

PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)

if [ -z "$IP" ] && [ "$CHOICE" -ne 2 ] && [ "$CHOICE" -ne 3 ]; then
  echo "❌ 无法获取公网 IP"
  exit 1
fi

# 地理标签
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

# 初始化环境
init_env() {

    echo "🚀 正在初始化 VPS 环境..."

    cat << 'EOF_SYSCTL' > /etc/sysctl.d/99-connectivity-tuning.conf
net.core.rmem_max=8388608
net.core.wmem_max=8388608
EOF_SYSCTL

    sysctl --system >/dev/null 2>&1

    if command -v ufw > /dev/null; then
        ufw disable >/dev/null 2>&1
    fi

    if command -v systemctl > /dev/null; then
        systemctl stop firewalld >/dev/null 2>&1
        systemctl disable firewalld >/dev/null 2>&1
    fi

    iptables -F
    iptables -X

    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT

    if command -v apt-get >/dev/null; then
        apt-get update
        apt-get install -y curl wget openssl socat cron net-tools
    elif command -v yum >/dev/null; then
        yum makecache
        yum install -y curl wget openssl socat crontabs net-tools
    fi
}

# 快捷查询命令
deploy_shortcut() {

cat << 'EOF_SHOW' > /usr/local/bin/sd
#!/bin/bash

if [ -f "/etc/anytls_manager/saved_links.txt" ]; then

    clear
    echo "=========================================================="
    echo "              当前 AnyTLS 节点信息"
    echo "=========================================================="

    cat /etc/anytls_manager/saved_links.txt

    echo "=========================================================="

else

    echo "❌ 未找到节点信息"

fi
EOF_SHOW

chmod +x /usr/local/bin/sd
}

# 域名检测
get_domain() {

    if [ -f "/etc/anytls_manager/vps_domain.txt" ]; then

        local cached_domain=$(cat /etc/anytls_manager/vps_domain.txt)

        read -p "📋 检测到历史域名 [$cached_domain] 是否复用？[Y/n]: " CONFIRM

        if [ "$CONFIRM" != "n" ] && [ "$CONFIRM" != "N" ]; then
            DOMAIN=$cached_domain
            return 0
        fi
    fi

    while true; do

        read -p "👉 请输入已解析到 VPS 的域名: " DOMAIN

        [ -z "$DOMAIN" ] && continue

        local domain_ip=$(getent ahosts "$DOMAIN" | awk '{print $1}' | head -n 1)

        if [ "$domain_ip" = "$IP" ]; then

            echo "$DOMAIN" > /etc/anytls_manager/vps_domain.txt

            echo "✅ 域名解析正确"

            break

        else

            echo "❌ 域名解析 IP [$domain_ip] 与本机 [$IP] 不符"

        fi
    done
}

# 端口管理
get_port() {

    local cache_file="/etc/anytls_manager/vps_port_anytls.txt"

    local default_p=$(shuf -i 10000-60000 -n 1)

    if [ -f "$cache_file" ]; then

        local cached_port=$(cat "$cache_file")

        read -p "📋 检测到历史端口 [$cached_port] 是否复用？[Y/n]: " CONFIRM

        if [ "$CONFIRM" != "n" ] && [ "$CONFIRM" != "N" ]; then

            echo "$cached_port"

            return 0
        fi
    fi

    read -p "👉 请输入监听端口 (默认 $default_p): " INPUT_PORT

    local final_port="${INPUT_PORT:-$default_p}"

    echo "$final_port" > "$cache_file"

    echo "$final_port"
}

# 证书签发
sync_cert() {

    local target_dir=$1

    get_domain

    echo "🔄 正在申请 Let's Encrypt 证书..."

    systemctl stop nginx apache2 2>/dev/null

    curl -sSL https://get.acme.sh | sh -s email=anytls@gmail.com

    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt

    ~/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone

    if [ $? -ne 0 ]; then
        echo "❌ 证书申请失败"
        exit 1
    fi

    ~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" \
    --key-file "$target_dir/server.key" \
    --fullchain-file "$target_dir/server.crt"

    echo "✅ TLS 证书部署成功"
}

case $CHOICE in

1)

    PORT=$(get_port)

    init_env

    mkdir -p /etc/anytls

    sync_cert "/etc/anytls"

    echo "🚀 正在安装 AnyTLS..."

    bash <(curl -fsSL https://raw.githubusercontent.com/anytls/anytls-go/main/install.sh)

    cat << EOF_JSON > /etc/anytls/config.json
{
  "listen": "0.0.0.0:$PORT",
  "users": {
    "$PASSWORD": ""
  },
  "cert": "/etc/anytls/server.crt",
  "key": "/etc/anytls/server.key"
}
EOF_JSON

cat << EOF_SERVICE > /etc/systemd/system/anytls.service
[Unit]
Description=AnyTLS Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/anytls-server -c /etc/anytls/config.json
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF_SERVICE

    systemctl daemon-reload
    systemctl enable anytls
    systemctl restart anytls

    GEO_TAG=$(get_geo_tag)

    ANYTLS_LINK="anytls://$PASSWORD@$DOMAIN:$PORT?insecure=0&sni=$DOMAIN#AnyTLS_${GEO_TAG}"

    touch /etc/anytls_manager/saved_links.txt

    sed -i '/#AnyTLS_/d' /etc/anytls_manager/saved_links.txt 2>/dev/null

    echo "$ANYTLS_LINK" >> /etc/anytls_manager/saved_links.txt

    deploy_shortcut

    clear

    /usr/local/bin/sd

;;

2)

    if [ -f "/usr/local/bin/sd" ]; then
        /usr/local/bin/sd
    else
        echo "❌ 未找到节点信息"
    fi

;;

3)

    echo "🧹 正在彻底卸载 AnyTLS..."

    systemctl stop anytls 2>/dev/null

    systemctl disable anytls 2>/dev/null

    rm -f /etc/systemd/system/anytls.service

    systemctl daemon-reload

    rm -f /usr/local/bin/anytls-server

    rm -rf /etc/anytls

    rm -rf /etc/anytls_manager

    rm -f /usr/local/bin/sd

    echo "✅ AnyTLS 已彻底卸载"

;;

*)

    exit 1

;;

esac
