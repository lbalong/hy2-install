#!/bin/bash

# 检查是否为 Root 用户
if [ "$EUID" -ne 0 ]; then
  echo "错误：请使用 root 用户运行此脚本！"
  exit 1
fi

# 铁律第一步：开局无脑直接创建核心目录
mkdir -p /etc/hy2_tuic

echo "=========================================================="
echo "   Hysteria 2 & TUIC v5 纯血逻辑 IPv6双栈版 (GitHub 纯净版)"
echo "=========================================================="
echo " 1. 安装 Hysteria 2 (IPv4/IPv6 双栈监听)"
echo " 2. 安装 TUIC v5    (IPv4/IPv6 双栈监听)"
echo " 3. 查看当前已建节点链接汇总 (快捷命令: sd)"
echo " 4. 彻底卸载服务并清空 VPS 环境"
echo "=========================================================="
read -p "请选择操作 [1-4]: " CHOICE

# 提取公共核心变量
IP=$(curl -s4 https://ifconfig.me || curl -s4 https://api.ipify.org)
PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "8e21e704-9ac8-4fb8-bef1-6c9d7d7e390b")

# 核心环境与系统防火墙一键物理洗地 (新增 IPv6 规则清理)
init_env() {
    echo "正在优化内核 UDP 缓冲区..."
    cat << 'EOF_SYSCTL' > /etc/sysctl.d/99-connectivity-tuning.conf
net.core.rmem_max=8388608
net.core.wmem_max=8388608
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.default.disable_ipv6 = 0
EOF_SYSCTL
    sysctl --system >/dev/null 2>&1

    echo "正在物理清洗内部防火墙残留（全开 IPv4/IPv6 接单状态）..."
    if command -v ufw > /dev/null; then ufw disable >/dev/null 2>&1; fi
    iptables -F && iptables -X
    ip6tables -F && ip6tables -X 2>/dev/null
    iptables -P INPUT ACCEPT && iptables -P FORWARD ACCEPT && iptables -P OUTPUT ACCEPT
    ip6tables -P INPUT ACCEPT && ip6tables -P FORWARD ACCEPT && ip6tables -P OUTPUT ACCEPT

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
    echo "📋 当前 VPS 已保存的节点链接汇总 (支持 IPv4/IPv6)"
    echo "=========================================================="
    cat /etc/hy2_tuic/saved_links.txt
    echo "=========================================================="
else
    echo "❌ 未找到已保存的节点信息，请先使用脚本创建节点！"
fi
EOF_SHOW
    chmod +x /usr/local/bin/sd
}

# 保持原有的 get_domain, get_port, sync_cert 逻辑不变...
# (此处省略中间辅助函数，实际运行时请确保它们与你原脚本一致)
# ...

case $CHOICE in
    1)
        PORT=$(get_port "hy2")
        init_env
        mkdir -p /etc/hysteria
        bash <(curl -fsSL https://get.hy2.sh)
        sync_cert "/etc/hysteria"
        
        # 核心改动：监听 [::] 支持双栈
        cat << EOF_HY2_YAML > /etc/hysteria/config.yaml
listen: [::]:$PORT
tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key
auth:
  type: password
  password: $PASSWORD
EOF_HY2_YAML

        systemctl daemon-reload && systemctl enable hysteria-server && systemctl restart hysteria-server
        
        HY2_LINK="hy2://$PASSWORD@$DOMAIN:$PORT?sni=$DOMAIN#Hy2_IPv6_Ready"
        echo "$HY2_LINK" >> /etc/hy2_tuic/saved_links.txt
        deploy_shortcut
        /usr/local/bin/sd
        ;;

    2)
        PORT=$(get_port "tuic")
        init_env
        mkdir -p /etc/tuic
        sync_cert "/etc/tuic"
        
        # 核心改动：监听 [::] 支持双栈
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

        # (Systemd 配置逻辑保持你原有的不变)
        systemctl restart tuic
        TUIC_LINK="tuic://$UUID:$PASSWORD@$DOMAIN:$PORT?congestion_control=bbr&alpn=h3&sni=$DOMAIN#TUIC_IPv6_Ready"
        echo "$TUIC_LINK" >> /etc/hy2_tuic/saved_links.txt
        deploy_shortcut
        /usr/local/bin/sd
        ;;
    # 3, 4 保持不变
esac
