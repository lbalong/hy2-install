#!/bin/bash

# 检查是否为 Root 用户
if [ "$EUID" -ne 0 ]; then
  echo "错误：请使用 root 用户运行此脚本！"
  exit 1
fi

# 基础内核优化：调优 Linux 内核 UDP 缓冲区
sysctl_optimize() {
    echo "正在注入内核加速参数（优化 UDP 缓冲区）..."
    cat <<EOF > /etc/sysctl.d/99-hysteria2-tuning.conf
net.core.rmem_max=8388608
net.core.wmem_max=8388608
EOF
    sysctl --system >/dev/null 2>&1
}

# 彻底清空并放行本地防火墙（防止 Ubuntu 默认规则卡死）
clear_local_firewall() {
    echo "正在清空并优化本地防火墙规则..."
    if command -v ufw > /dev/null; then
        ufw disable >/dev/null 2>&1
    fi
    iptables -F
    iptables -X
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
}

# 基础依赖安装
install_dependencies() {
    echo "正在安装基础依赖..."
    if command -v apt-get >/dev/null; then
      apt-get update && apt-get install -y curl openssl wget iptables
    elif command -v yum >/dev/null; then
      yum makecache && yum install -y curl openssl wget iptables
    fi
}

# 核心权限修复
fix_permissions() {
    echo "正在优化文件权限..."
    if id "hysteria" &>/dev/null; then
        chown -R hysteria:hysteria /etc/hysteria
    fi
}

# 获取公网 IP
get_ip() {
    curl -sS4 https://ifconfig.me || curl -sS4 https://ipinfo.io/ip || curl -sS4 https://api.ipify.org
}

# 模式 1：安装纯 IP 自签名版
install_ip_version() {
    echo "=========================================="
    echo " 开始安装：Hysteria 2 (纯 IP 自签名版)"
    echo "=========================================="
    
    IP=$(get_ip)
    PORT=$(shuf -i 10000-65000 -n 1)
    PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
    
    sysctl_optimize
    clear_local_firewall
    install_dependencies
    
    bash <(curl -fsSL https://get.hy2.sh)
    
    mkdir -p /etc/hysteria
    openssl req -x509 -nodes -newkey rsa:2048 \
      -keyout /etc/hysteria/server.key \
      -out /etc/hysteria/server.crt \
      -days 3650 \
      -subj "/CN=www.bing.com"
      
    cat <<EOF > /etc/hysteria/config.yaml
listen: :$PORT
tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key
auth:
  type: password
  password: $PASSWORD
EOF

    fix_permissions
    
    systemctl daemon-reload
    systemctl enable hysteria-server
    systemctl restart hysteria-server
    
    if systemctl is-active --quiet hysteria-server; then
        echo "=========================================="
        echo " 🎉 Hysteria 2 IP 自签版安装成功！"
        echo "=========================================="
        echo "⚠️  甲骨文云提示：请去网页后台放行 UDP 端口: $PORT"
        echo "=========================================="
        echo "你的节点链接："
        echo "hy2://$PASSWORD@$IP:$PORT/?insecure=1&sni=www.bing.com#Oracle_Hy2_IP_$PORT"
        echo "=========================================="
    else
        echo "❌ 启动失败，请检查日志。"
    fi
}

# 模式 2：安装域名正规证书版（已微调：采用高位端口绕过高墙阻断）
install_domain_version() {
    echo "=========================================="
    echo " 开始安装：Hysteria 2 (域名正规证书 + 高位端口版)"
    echo "=========================================="
    
    read -p "👉 请输入已解析到本机的完整域名: " DOMAIN
    if [ -z "$DOMAIN" ]; then echo "域名不能为空！"; exit 1; fi
    
    read -p "👉 请输入邮箱 (直接回车默认 admin@$DOMAIN): " EMAIL
    if [ -z "$EMAIL" ]; then EMAIL="admin@$DOMAIN"; fi
    
    # 核心微调：域名版同样采用随机高位端口，彻底解决运营商 UDP 443 阻断问题
    PORT=$(shuf -i 10000-65000 -n 1)
    PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
    
    sysctl_optimize
    clear_local_firewall
    install_dependencies
    
    bash <(curl -fsSL https://get.hy2.sh)
    
    mkdir -p /etc/hysteria
    cat <<EOF > /etc/hysteria/config.yaml
listen: :$PORT
acme:
  domains:
    - $DOMAIN
  email: $EMAIL
auth:
  type: password
  password: $PASSWORD
masquerade:
  type: proxy
  proxy:
    url: https://www.bing.com/
    rewriteHost: true
EOF

    fix_permissions
    
    systemctl daemon-reload
    systemctl enable hysteria-server
    systemctl restart hysteria-server
    
    sleep 5
    if systemctl is-active --quiet hysteria-server; then
        echo "=========================================="
        echo " 🎉 Hysteria 2 域名白盒版（高位端口抗阻断）安装成功！"
        echo "=========================================="
        echo "⚠️  甲骨文云后台放行提示："
        echo " 请务必去网页后台增加入站规则："
        echo " 1. IP 协议: TCP, 目标端口: 80  (用于自动续签证书，不可缺少)"
        echo " 2. IP 协议: UDP, 目标端口: $PORT (节点核心通信端口)"
        echo "=========================================="
        echo "你的终极节点链接（无需跳过证书验证）："
        echo "hy2://$PASSWORD@$DOMAIN:$PORT#Oracle_Hy2_Domain_$PORT"
        echo "=========================================="
    else
        echo "❌ 启动失败，请确保 CF 解析已生效（仅DNS模式）并运行 'journalctl -u hysteria-server' 查看日志。"
    fi
}

# 主菜单
echo "=========================================="
echo "      Hysteria 2 自动化双模安装脚本"
echo "=========================================="
echo " 1. 安装 纯 IP 自签名版（随机高位端口）"
echo " 2. 安装 域名正规证书版（随机高位端口 + 网页伪装 + 绕过阻断）"
echo "=========================================="
read -p "请选择安装模式 [1-2]: " CHOICE

case $CHOICE in
    1) install_ip_version ;;
    2) install_domain_version ;;
    *) echo "无效选项，退出脚本。" ;;
esac
