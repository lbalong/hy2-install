#!/bin/bash

# 检查是否为 Root 用户
if [ "$EUID" -ne 0 ]; then
  echo "错误：请使用 root 用户运行此脚本！"
  exit 1
fi

# 铁律第一步：开局无脑直接创建核心目录，确保所有账本读写绝不踩空
mkdir -p /etc/hy2_tuic

echo "=========================================================="
echo "    Hysteria 2 & TUIC v5 官方原生内核完全体 V9.0 (内置跳跃版)"
echo "=========================================================="
echo " 1. 安装 Hysteria 2 (官方原生内置端口跳跃方案 - 彻底告别 iptables)"
echo " 2. 安装 TUIC v5    (全盘扫描端口 + 证书智能复用)"
echo " 3. 查看当前已建节点链接汇总 (快捷命令: sd)"
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
        isp=$(echo "$isp" | tr -cd 'A-Za-z0-9_')
        country=$(echo "$country" | tr -cd 'A-Za-z0-9_')
        echo "${isp}_${country}"
    else
        echo "VPS_Node"
    fi
}

# 核心环境一键物理洗地
init_env() {
    echo "正在优化内核 UDP 缓冲区..."
    cat << 'EOF_SYSCTL' > /etc/sysctl.d/99-connectivity-tuning.conf
net.core.rmem_max=8388608
net.core.wmem_max=8388608
EOF_SYSCTL
    sysctl --system >/dev/null 2>&1

    echo "正在开放系统基础网络组件..."
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

# 智能提取与分配原生端口配置
get_port() {
    local proto=$1
    local cache_file="/etc/hy2_tuic/vps_port_${proto}.txt"
    local cached_port=""
    
    if [ -f "$cache_file" ]; then
        cached_port=$(cat "$cache_file")
    fi
    
    if [ -n "$cached_port" ]; then
        read -p "📋 检测到历史缓存 ${proto} 端口配置 [$cached_port]，是否直接复用？[Y/n]: " CONFIRM
        if [ "$CONFIRM" != "n" ] && [ "$CONFIRM" != "N" ]; then
            echo "$cached_port"
            return 0
        fi
    fi
    
    if [ "$proto" = "hy2" ]; then
        local rand_start=$(shuf -i 20000-35000 -n 1)
        local rand_end=$((rand_start + 10000))
        echo "----------------------------------------------------------"
        echo "💡 提示：单端口请输入数字(如 443)，开启跳跃请输入范围(如 20000-30000)"
        read -p "👉 请输入监听配置 (直接回车默认开启原生跳跃大通道 ${rand_start}-${rand_end}): " INPUT_PORT
        local final_port="${INPUT_PORT:-${rand_start}-${rand_end}}"
    else
        local default_p=$(shuf -i 10000-60000 -n 1)
        read -p "👉 请输入 TUIC 监听端口 (直接回车使用随机端口 $default_p): " INPUT_PORT
        local final_port="${INPUT_PORT:-$default_p}"
    fi
    
    echo "$final_port" > "$cache_file"
    echo "$final_port"
}

# 智能证书管理
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
        PORT_CONFIG=$(get_port "hy2")
        init_env
        mkdir -p /etc/hysteria
        bash <(curl -fsSL https://get.hy2.sh)
        sync_cert "/etc/hysteria"
        
        # 🌟 核心分流对账：判断是单端口还是内置原生范围监听
        if [[ "$PORT_CONFIG" == *'-'* ]]; then
            # 原生跳跃模式：把主端口定为范围的第一个数字
            MAIN_PORT=$(echo "$PORT_CONFIG" | cut -d'-' -f1)
            END_PORT=$(echo "$PORT_CONFIG" | cut -d'-' -f2)
            HOP_START=$((MAIN_PORT + 1))
            # 客户端链接里所需的跳跃参数（mport 格式）
            PORT_PARAM="&mport=${HOP_START}-${END_PORT}"
            DISPLAY_PORT=$MAIN_PORT
        else
            # 普通单端口模式
            PORT_PARAM=""
            DISPLAY_PORT=$PORT_CONFIG
        fi

        # 🌟 满血核心改动：直接把端口配置写入 listen 字段，交给官方原生核心内部接管，不留一丝安全隐患
        cat << EOF_HY2_YAML > /etc/hysteria/config.yaml
listen: :$PORT_CONFIG
tls:
