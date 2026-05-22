cat << 'EOF_OUTER' > /tmp/hy2_tuic.sh
#!/bin/bash

# 检查是否为 Root 用户
if [ "$EUID" -ne 0 ]; then
  echo "错误：请使用 root 用户运行此脚本！"
  exit 1
fi

echo "=========================================================="
echo "    Hysteria 2 & TUIC v5 智能地理标签与快捷查询版 V8.3"
echo "=========================================================="
echo " 1. 安装 Hysteria 2 (自动识别服务商与地区)"
echo " 2. 安装 TUIC v5    (自动识别服务商与地区)"
echo " 3. 查看当前已建节点链接汇总"
echo " 4. 彻底卸载服务并清空 VPS 环境"
echo "=========================================================="
read -p "请选择操作 [1-4]: " CHOICE

# 提取公共核心变量
IP=$(curl -sS4 https://ifconfig.me || curl -sS4 https://ipinfo.io/ip || curl -sS4 https://api.ipify.org)
PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "8e21e704-9ac8-4fb8-bef1-6c9d7d7e390b")

if [ -z "$IP" ] && [ "$CHOICE" -ne 4 ] && [ "$CHOICE" -ne 3 ]; then
  echo "❌ 错误：无法获取服务器公网 IP，请检查网络连接。"
  exit 1
fi

# 智能获取服务商与地理位置标签
get_geo_tag() {
    local geo_info=$(curl -s --max-time 3 http://ip-api.com/json/)
    if [ -n "$geo_info" ] && echo "$geo_info" | grep -q '"status":"success"'; then
        local isp=$(echo "$geo_info" | grep -oE '"isp":"[^"]+"' | cut -d'"' -f4 | awk '{print $1}')
        local country=$(echo "$geo_info" | grep -oE '"country":"[^"]+"' | cut -d'"' -f4 | tr -d ' ')
        # 剔除特殊字符确保符合 URL 规范
        isp=$(echo "$isp" | tr -cd 'A-Za-z0-9_')
        country=$(echo "$country" | tr -cd 'A-Za-z0-9_')
        echo "${isp}_${country}"
    else
        echo "VPS_Node"
    fi
}

# 核心环境与系统防火墙一键物理洗地
init_env() {
    echo "正在优化内核 UDP 缓冲区..."
    cat << 'EOF_SYSCTL' > /etc/sysctl.d/99-connectivity-tuning.conf
net.core.rmem_max=8388608
net.core.wmem_max=8388608
EOF_SYSCTL
    sysctl --system >/dev/null 2>&1

    echo "正在物理清洗内部防火墙残留（全开接单状态）..."
    if command -v ufw > /dev/null; then ufw disable >/dev/null 2>&1; fi
    if command -v systemctl > /dev/null; then systemctl stop firewalld >/dev/null 2>&1 && systemctl disable firewalld >/dev/null 2>&1; fi
    iptables -F && iptables -X
    iptables -P INPUT ACCEPT && iptables -P FORWARD ACCEPT && iptables -P OUTPUT ACCEPT

    if command -v apt-get >/dev/null; then
      apt-get update && apt-get install -y curl openssl wget iptables socat cron net-tools
    elif command -v yum >/dev/null; then
      yum makecache && yum install -y curl openssl wget iptables socat crontabs net-tools
    fi
    mkdir -p /etc/hy2_tuic
}

# 部署专属快捷查询命令
deploy_shortcut() {
    cat << 'EOF_SHOW' > /usr/local/bin/shownode
#!/bin/bash
if [ -f "/etc/hy2_tuic/saved_links.txt" ]; then
    clear
    echo "=========================================================="
    echo "📋 当前 VPS 已保存的节点链接汇总 (Hy2 vs TUIC)"
    echo "=========================================================="
    cat /etc/hy2_tuic/saved_links.txt
    echo "=========================================================="
else
    echo "❌ 未找到已保存的节点信息，请先使用脚本创建节点！"
fi
EOF_SHOW
    chmod +x /usr/local/bin/shownode
}

# 智能域名锁定
get_domain() {
    if [ -f "/etc/hy2_tuic/vps_domain.txt" ]; then
        local cached_domain=$(cat /etc/hy2_tuic/vps_domain.txt)
        read -p "📋 检测到历史缓存域名 [$cached_domain]，是否直接复用？[Y/n]: " CONFIRM
        if [ "$CONFIRM" = "n" ] || [ "$CONFIRM" = "N" ]; then
            rm -f /etc/hy2_tuic/vps_domain.txt
        else
            DOMAIN=$cached_domain
            return 0
        fi
    fi

    while true; do
        read -p "👉 请输入您当前解析好的完整域名 (例如 us2.099889.xyz): " DOMAIN
        if [ -z "$DOMAIN" ]; then continue; fi
        echo "🔄 正在请求多路公网 DNS 校验域名解析..."
        local domain_ip=$(curl -s4 "https://1.1.1.1/dns-query?name=$DOMAIN" -H "accept: application/dns-json" | grep -oE '"data":"[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}"' | head -n 1 | awk -F'"' '{print $4}')
        [ -z "$domain_ip" ] && domain_ip=$(getent ahosts "$DOMAIN" | awk '{print $1}' | head -n 1)
        
        if [ "$domain_ip" = "$IP" ]; then
            echo "$DOMAIN" > /etc/hy2_tuic/vps_domain.txt
            echo "✅ 对账成功！域名 [$DOMAIN] 已精准绑定本机 IP ($IP)"
            break
        else
            echo "❌ 校验失败：当前域名解析出的 IP 为 [$domain_ip]，与本机 IP [$IP] 不符！"
            echo "=========================================="
        fi
    done
}

# 共享级证书同步
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

    echo "🔄 正在向 Let's Encrypt 申请正式合规证书..."
    systemctl stop nginx apache2 2>/dev/null
    curl -sSL https://get.acme.sh | sh -s email=myhy2tuic@gmail.com
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
    ~/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone
    
    if [ $? -eq 0 ]; then
        ~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" --key-file "$target_dir/server.key" --fullchain-file "$target_dir/server.crt"
        echo "✅ 正规域名证书下发成功！"
    else
        echo "❌ 证书签发失败！"
        exit 1
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
        init_env
        mkdir -p /etc/hysteria
        bash <(curl -fsSL https://get.hy2.sh)
        sync_cert "/etc/hysteria"
        
        cat << EOF_HY2_YAML > /etc/hysteria/config.yaml
listen: :$PORT
tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key
auth:
  type: password
  password: $PASSWORD
EOF_HY2_YAML

        chown -R hysteria:hysteria /etc/hysteria
        chmod 755 /etc/hysteria
        chmod 644 /etc/hysteria/server.crt
        chmod 600 /etc/hysteria/server.key

        systemctl daemon-reload && systemctl enable hysteria-server && systemctl restart hysteria-server
        
        # 动态计算标签并入账
        GEO_TAG=$(get_geo_tag)
        HY2_LINK="hy2://$PASSWORD@$DOMAIN:$PORT?sni=$DOMAIN#Hy2_${GEO_TAG}"
        touch /etc/hy2_tuic/saved_links.txt
        sed -i '/#Hy2_/d' /etc/hy2_tuic/saved_links.txt 2>/dev/null
        echo "$HY2_LINK" >> /etc/hy2_tuic/saved_links.txt
        deploy_shortcut

        clear
        /usr/local/bin/shownode
        ;;

    2)
        PORT=$(get_port)
        init_env
        mkdir -p /etc/tuic
        sync_cert "/etc/tuic"
        
        echo "🚀 正在下载 TUIC v5 服务端核心..."
        TUIC_ARCH="x86_64-unknown-linux-gnu"
        [ "$(uname -m)" = "aarch64" ] && TUIC_ARCH="aarch64-unknown-linux-gnu"
        wget -qO /usr/local/bin/tuic-server "https://github.com/tuic-protocol/tuic/releases/download/tuic-server-1.0.0/tuic-server-1.0.0-${TUIC_ARCH}" || wget -qO /usr/local/bin/tuic-server "https://mirror.ghproxy.com/https://github.com/tuic-protocol/tuic/releases/download/tuic-server-1.0.0/tuic-server-1.0.0-${TUIC_ARCH}"
        chmod +x /usr/local/bin/tuic-server

        cat << EOF_TUIC_JSON > /etc/tuic/config.json
{
  "server": "0.0.0.0:$PORT",
  "users": {
    "$UUID": "$PASSWORD"
  },
  "certificate": "/etc/tuic/server.crt",
  "private_key": "/etc/tuic/server.key",
  "congestion_control": "bbr",
  "alpn": ["h3"]
}
EOF_TUIC_JSON

        cat << EOF_TUIC_SERVICE > /etc/systemd/system/tuic.service
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
EOF_TUIC_SERVICE

        systemctl daemon-reload && systemctl enable tuic && systemctl restart tuic
        
        # 动态计算标签并入账
        GEO_TAG=$(get_geo_tag)
        TU
