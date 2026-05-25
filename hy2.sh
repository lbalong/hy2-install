#!/bin/bash

# 检查是否为 Root 用户
if [ "$EUID" -ne 0 ]; then
  echo "错误：请使用 root 用户运行此脚本！"
  exit 1
fi

# 铁律第一步：开局无脑直接创建核心目录，确保所有账本读写绝不踩空
mkdir -p /etc/hy2_tuic

echo "=========================================================="
echo "    Hysteria 2 & TUIC v5 纯血逻辑完全体 V8.9 (GitHub 纯净版)"
echo "=========================================================="
echo " 1. 安装 Hysteria 2 (智能端口跳跃 + 官方原生满血调校)"
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
  echo "❌ 错误：无法获取服务器公网 IP，请检查 network 连接。"
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

    echo "正在物理清洗内部防火墙与 NAT 残留规则..."
    if command -v ufw > /dev/null; then ufw disable >/dev/null 2>&1; fi
    if command -v systemctl > /dev/null; then systemctl stop firewalld >/dev/null 2>&1 && systemctl disable firewalld >/dev/null 2>&1; fi
    
    # 🌟 核心修复：不仅洗 filter 表，连带把 nat 表的老脏规则一网打尽
    iptables -F && iptables -X
    iptables -t nat -F && iptables -t nat -X
    if command -v ip6tables >/dev/null 2>&1; then
        ip6tables -F && ip6tables -X
        ip6tables -t nat -F && ip6tables -t nat -X
    fi
    iptables -P INPUT ACCEPT && iptables -P FORWARD ACCEPT && iptables -P OUTPUT ACCEPT

    if command -v apt-get >/dev/null; then
      apt-get update && apt-get install -y curl openssl wget iptables socat cron net-tools iptables-persistent
    elif command -v yum >/dev/null; then
      yum makecache && yum install -y curl openssl wget iptables socat crontabs net-tools iptables-services
      systemctl enable iptables >/dev/null 2>&1
      systemctl start iptables >/dev/null 2>&1
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

# 全盘扫描本地官方配置，100% 榨出历史端口
get_port() {
    local proto=$1
    local cache_file="/etc/hy2_tuic/vps_port_${proto}.txt"
    local cached_port=""
    
    if [ -f "$cache_file" ]; then
        cached_port=$(cat "$cache_file")
    elif [ "$proto" = "hy2" ] && [ -f "/etc/hysteria/server.yaml" ]; then
        cached_port=$(grep -oE 'listen:\s*:[0-9]+' /etc/hysteria/server.yaml | grep -oE '[0-9]+' | head -
