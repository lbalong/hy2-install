#!/bin/bash

# 检查是否为 Root 用户
if [ "$EUID" -ne 0 ]; then
  echo "错误：请使用 root 用户运行此脚本！"
  exit 1
fi

# 铁律第一步：开局无脑直接创建核心目录，确保所有账本读写绝不踩空
mkdir -p /etc/hy2_tuic

echo "=========================================================="
echo "    Hysteria 2 & TUIC v5 纯血逻辑完全体 (原版极简双栈加持)"
echo "=========================================================="
echo " 1. 安装 Hysteria 2 (全盘扫描端口 + 证书智能复用)"
echo " 2. 安装 TUIC v5    (全盘扫描端口 + 证书智能复用)"
echo " 3. 查看当前已建节点链接汇总 (快捷命令: sd)"
echo " 4. 彻底卸载服务并清空 VPS 环境"
echo "=========================================================="
read -p "请选择操作 [1-4]: " CHOICE

# 提取公共核心变量 (仅增加 IP6 探测)
IP=$(curl -sS4 https://ifconfig.me || curl -sS4 https://ipinfo.io/ip || curl -sS4 https://api.ipify.org)
IP6=$(curl -sS6 https://api64.ipify.org --connect-timeout 3 2>/dev/null)
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

    # 仅增加对 IPv6 防火墙的清洗
    if command -v ip6tables > /dev/null; then
        ip6tables -F && ip6tables -X
        ip6tables -P INPUT ACCEPT && ip6tables -P FORWARD ACCEPT && ip6tables -P OUTPUT ACCEPT
    fi

    if command -v apt-get >/dev/null; then
      apt-get update && apt-get install -y curl openssl wget iptables socat cron net-tools
    elif command -v yum >/dev/null; then
      yum makecache && yum install -y curl openssl wget iptables socat crontabs net-tools
    fi
}

# 部署专属快捷查询命令 sd
deploy_shortcut() {
    cat << 'EOF_SHOW' > /usr/local/bin/sd
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
    chmod +x /usr/local/bin/sd
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
        
        # 增加宽容机制，防止纯双栈域名误判
        if [ "$domain_ip" = "$IP" ] || [ "$domain_ip" = "$IP6" ]; then
            echo "$DOMAIN" > /etc/hy2_tuic/vps_domain.txt
            echo "✅ 对账成功！域名 [$DOMAIN] 已精准绑定本机 IP"
            break
        else
            echo "❌ 校验失败：当前域名解析出的 IP 为 [$domain_ip]，与本机 IP 不符！"
            read -p "👉 是否确认解析已生效，并强行继续？[y/N]: " FORCE
            if [[ "$FORCE" =~ ^[Yy]$ ]]; then
                echo "$DOMAIN" > /etc/hy2_tuic/vps_domain.txt
                break
            fi
            echo "=========================================="
        fi
    done
}

# 全盘扫描本地官方配置，100% 榨出历史端口
get_port() {
    local proto=$1
    local cache_file="/etc/hy2_tuic/vps_port_${proto}.txt"
    local cached_port=""
    
    if [ -f "$cache_file" ]; then
        cached_port=$(cat "$cache_file")
    elif [ "$proto" = "hy2" ] && [ -f "/etc/hysteria/config.yaml" ]; then
        cached_port=$(grep -oE 'listen:\s*:[0-9]+' /etc/hysteria/config.yaml | grep -oE '[0-9]+' | head -n 1)
    elif [ "$proto" = "tuic" ] && [ -f "/etc/tuic/config.json" ]; then
        cached_port=$(grep -oE '"server":\s*"[^"]+"' /etc/tuic/config.json | grep -oE '[0-9]+' | head -n 1)
    fi
    
    local default_p=$(shuf -i 10000-60000 -n 1)
    
    if [ -n "$cached_port" ]; then
        read -p "📋 检测到历史缓存 ${proto} 端口 [$cached_port]，是否直接复用？[Y/n]: " CONFIRM
        if [ "$CONFIRM" != "n" ] && [ "$CONFIRM" != "N" ]; then
            echo "$cached_port" > "$cache_file"
            echo "$cached_port"
            return 0
        fi
    fi
    
    read -p "👉 请输入节点监听端口 (直接回车使用随机端口 $default_p): " INPUT_PORT
    local final_port="${INPUT_PORT:-$default_p}"
    echo "$final_port" > "$cache_file"
    echo "$final_port"
}

# 智能防御型证书管理，绝不卡死
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
    local issue_res=$?
    
    if [ $issue_res -ne 0 ]; then
        if [ -d "/root/.acme.sh/${DOMAIN}_ecc" ] || [ -d "/root/.acme.sh/${DOMAIN}" ]; then
            echo "📋 侦测到本地签发历史中已存有合法合规证书文件，判定为缓存复用通车！"
            issue_res=0
        fi
    fi
    
    if [ $issue_res -eq 0 ]; then
        local cert_dir="${DOMAIN}_ecc"
        [ ! -d "/root/.acme.sh/$cert_dir" ] && cert_dir="$DOMAIN"
        
        ~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" --key-file "$target_dir/server.key" --fullchain-file "$target_dir/server.crt"
        echo "✅ 正规域名证书下发/复用成功！"
    else
        echo "❌ 证书签发彻底失败，请检查 80 端口是否被物理占用！"
        exit 1
    fi
}

case $CHOICE in
    1)
        PORT=$(get_port "hy2")
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
        
        GEO_TAG=$(get_geo_tag)
        touch /etc/hy2_tuic/saved_links.txt
        sed -i '/#Hy2_/d' /etc/hy2_tuic/saved_links.txt 2>/dev/null
        
        echo "hy2://$PASSWORD@$DOMAIN:$PORT?sni=$DOMAIN#Hy2_Domain_${GEO_TAG}" >> /etc/hy2_tuic/saved_links.txt
        # 仅新增：如果有 IPv6，多写一条带 Sni 的专属 IPv6 链接
        if [ -n "$IP6" ]; then
            echo "hy2://$PASSWORD@[${IP6}]:$PORT?sni=$DOMAIN#Hy2_IPv6_${GEO_TAG}" >> /etc/hy2_tuic/saved_links.txt
        fi

        deploy_shortcut
        clear
        /usr/local/bin/sd
        ;;

    2)
        PORT=$(get_port "tuic")
        init_env
        mkdir -p /etc/tuic
        sync_cert "/etc/tuic"
        
        echo "🚀 正在下载 TUIC v5 服务端核心..."
        TUIC_ARCH="x86_64-unknown-linux-gnu"
        [ "$(uname -m)" = "aarch64" ] && TUIC_ARCH="aarch64-unknown-linux-gnu"
        wget -qO /usr/local/bin/tuic-server "https://github.com/tuic-protocol/tuic/releases/download/tuic-server-1.0.0/tuic-server-1.0.0-${TUIC_ARCH}" || wget -qO /usr/local/bin/tuic-server "https://mirror.ghproxy.com/https://github.com/tuic-protocol/tuic/releases/download/tuic-server-1.0.0/tuic-server-1.0.0-${TUIC_ARCH}"
        chmod +x /usr/local/bin/tuic-server

        # 仅修改：0.0.0.0 改为 [::] 支持双栈
        cat << EOF_TUIC_JSON > /etc/tuic/config.json
{
  "server": "[::]:$PORT",
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
        
        GEO_TAG=$(get_geo_tag)
        touch /etc/hy2_tuic/saved_links.txt
        sed -i '/#TUIC_/d' /etc/hy2_tuic/saved_links.txt 2>/dev/null
        
        echo "tuic://$UUID:$PASSWORD@$DOMAIN:$PORT?congestion_control=bbr&alpn=h3&sni=$DOMAIN#TUIC_Domain_${GEO_TAG}" >> /etc/hy2_tuic/saved_links.txt
        # 仅新增：如果有 IPv6，多写一条带 Sni 的专属 IPv6 链接
        if [ -n "$IP6" ]; then
            echo "tuic://$UUID:$PASSWORD@[${IP6}]:$PORT?congestion_control=bbr&alpn=h3&sni=$DOMAIN#TUIC_IPv6_${GEO_TAG}" >> /etc/hy2_tuic/saved_links.txt
        fi

        deploy_shortcut
        clear
        /usr/local/bin/sd
        ;;

    3)
        if [ -f "/usr/local/bin/sd" ]; then
            /usr/local/bin/sd
        else
            echo "❌ 未找到已保存的节点信息！"
        fi
        ;;

    4)
        echo "🧹 正在强行剥离所有后台进程与残留环境..."
        systemctl stop hysteria-server tuic 2>/dev/null
        systemctl disable hysteria-server tuic 2>/dev/null
        rm -f /etc/systemd/system/hysteria-server.service /etc/systemd/system/tuic.service
        systemctl daemon-reload
        rm -f /usr/local/bin/hysteria /usr/local/bin/tuic-server /usr/local/bin/sd
        rm -rf /etc/hysteria /etc/tuic /etc/hy2_tuic
        echo "✅ VPS 环境与 sd 快捷指令已彻底清洗干净！"
        ;;
    *)
        exit 1
        ;;
esac
