#!/bin/bash

# 检查是否为 Root 用户
if [ "$EUID" -ne 0 ]; then
  echo "错误：请使用 root 用户运行此脚本！"
  exit 1
fi

# 铁律第一步：开局无脑直接创建核心目录，确保所有账本读写绝不踩空
mkdir -p /etc/hy2_tuic
mkdir -p /etc/anytls

echo "=========================================================="
echo "    AnyTLS 节点纯血逻辑完全体完美版 (联动 sd 命令)"
echo "=========================================================="
echo " 1. 安装/更新 AnyTLS  (全盘扫描端口 + 证书智能复用)"
echo " 2. 查看当前已建节点链接汇总 (快捷命令: sd)"
echo " 3. 彻底卸载 AnyTLS 服务"
echo "=========================================================="
read -p "请选择操作 [1-3]: " CHOICE

# 提取公共核心变量
IP=$(curl -sS4 https://ifconfig.me || curl -sS4 https://ipinfo.io/ip || curl -sS4 https://api.ipify.org)
PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)

if [ -z "$IP" ] && [ "$CHOICE" -eq 1 ]; then
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
    echo "正在优化内核网络缓冲区..."
    cat << 'EOF_SYSCTL' > /etc/sysctl.d/99-anytls-tuning.conf
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
}

# 部署/更新联动专属快捷查询命令 sd
deploy_shortcut() {
    cat << 'EOF_SHOW' > /usr/local/bin/sd
#!/bin/bash
if [ -f "/etc/hy2_tuic/saved_links.txt" ]; then
    clear
    echo "=========================================================="
    echo "📋 当前 VPS 已保存的节点链接汇总 (Hy2 vs TUIC vs AnyTLS)"
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
        read -p "👉 请输入您当前解析好的完整域名 (例如 jp.099889.xyz): " DOMAIN
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

# 铁逻辑：全盘扫描本地配置，100% 榨出 AnyTLS 历史端口
get_port() {
    local cache_file="/etc/hy2_tuic/vps_port_anytls.txt"
    local cached_port=""
    
    if [ -f "$cache_file" ]; then
        cached_port=$(cat "$cache_file")
    elif [ -f "/etc/anytls/config.json" ]; then
        cached_port=$(grep -oE '"listen":\s*"[^"]+"' /etc/anytls/config.json | grep -oE '[0-9]+' | head -n 1)
    fi
    
    local default_p=$(shuf -i 10000-60000 -n 1)
    
    if [ -n "$cached_port" ]; then
        read -p "📋 检测到历史缓存 AnyTLS 端口 [$cached_port]，是否直接复用？[Y/n]: " CONFIRM
        if [ "$CONFIRM" != "n" ] && [ "$CONFIRM" != "N" ]; then
            echo "$cached_port" > "$cache_file"
            echo "$cached_port"
            return 0
        fi
    fi
    
    read -p "👉 请输入 AnyTLS 监听端口 (直接回车使用随机端口 $default_p): " INPUT_PORT
    local final_port="${INPUT_PORT:-$default_p}"
    echo "$final_port" > "$cache_file"
    echo "$final_port"
}

# 铁逻辑：智能防御型证书管理，跨协议无缝同步复用
sync_cert() {
    local target_dir=$1
    get_domain
    
    if [ -f "/etc/hysteria/server.crt" ]; then
        echo "📥 检测到 Hysteria 2 已持有正规证书，正在执行无缝复制复用..."
        cp /etc/hysteria/server.crt "$target_dir/server.crt"
        cp /etc/hysteria/server.key "$target_dir/server.key"
        return 0
    elif [ -f "/etc/tuic/server.crt" ]; then
        echo "📥 检测到 TUIC 已持有正规证书，正在执行无缝复制复用..."
        cp /etc/tuic/server.crt "$target_dir/server.crt"
        cp /etc/tuic/server.key "$target_dir/server.key"
        return 0
    fi

    echo "🔄 正在向 Let's Encrypt 申请正式合规证书..."
    systemctl stop nginx apache2 2>/dev/null
    curl -sSL https://get.acme.sh | sh -s email=myanytls@gmail.com
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
        PORT=$(get_port)
        init_env
        sync_cert "/etc/anytls"
        
        echo "🚀 正在下载 AnyTLS 服务端核心..."
        ARCH="amd64"
        [ "$(uname -m)" = "aarch64" ] && ARCH="arm64"
        
        # 自动获取 GitHub 最新 Release 版本并下载标准二进制文件
        ANYTLS_VER=$(curl -s "https://api.github.com/repos/anytls/anytls/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        [ -z "$ANYTLS_VER" ] && ANYTLS_VER="v1.0.0" # 兜底版本
        
        wget -qO /usr/local/bin/anytls-server "https://github.com/anytls/anytls/releases/download/${ANYTLS_VER}/anytls-server-linux-${ARCH}" || \
        wget -qO /usr/local/bin/anytls-server "https://mirror.ghproxy.com/https://github.com/anytls/anytls/releases/download/${ANYTLS_VER}/anytls-server-linux-${ARCH}"
        
        chmod +x /usr/local/bin/anytls-server

        # 写入正规的标准账本 config.json
        cat << EOF_ANYTLS_JSON > /etc/anytls/config.json
{
  "listen": "0.0.0.0:$PORT",
  "auth_password": "$PASSWORD",
  "cert_file": "/etc/anytls/server.crt",
  "key_file": "/etc/anytls/server.key",
  "bbr": true
}
EOF_ANYTLS_JSON

        # 注入 systemd 后台守护进程
        cat << EOF_ANYTLS_SERVICE > /etc/systemd/system/anytls.service
[Unit]
Description=AnyTLS Server Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/anytls
ExecStart=/usr/local/bin/anytls-server -c /etc/anytls/config.json
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF_ANYTLS_SERVICE

        systemctl daemon-reload && systemctl enable anytls && systemctl restart anytls
        
        # 动态计算地理位置标签并记账
        GEO_TAG=$(get_geo_tag)
        ANYTLS_LINK="anytls://$PASSWORD@$DOMAIN:$PORT?sni=$DOMAIN#AnyTLS_${GEO_TAG}"
        
        touch /etc/hy2_tuic/saved_links.txt
        sed -i '/#AnyTLS_/d' /etc/hy2_tuic/saved_links.txt 2>/dev/null
        echo "$ANYTLS_LINK" >> /etc/hy2_tuic/saved_links.txt
        deploy_shortcut

        clear
        /usr/local/bin/sd
        ;;

    2)
        if [ -f "/usr/local/bin/sd" ]; then
            /usr/local/bin/sd
        else
            echo "❌ 未找到已保存的节点信息！"
        fi
        ;;

    3)
        echo "🧹 正在强行剥离 AnyTLS 后台进程与残留环境..."
        systemctl stop anytls 2>/dev/null
        systemctl disable anytls 2>/dev/null
        rm -f /etc/systemd/system/anytls.service
        systemctl daemon-reload
        rm -f /usr/local/bin/anytls-server
        rm -rf /etc/anytls
        sed -i '/#AnyTLS_/d' /etc/hy2_tuic/saved_links.txt 2>/dev/null
        echo "✅ AnyTLS 环境已彻底洗净！"
        ;;
    *)
        exit 1
        ;;
esac
