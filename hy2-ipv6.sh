#!/bin/bash

# 检查是否为 Root 用户
if [ "$EUID" -ne 0 ]; then
  echo "❌ 错误：请使用 root 用户运行此脚本！"
  exit 1
fi

mkdir -p /etc/hy2_auto

# 1. 自动生成随机配置
PORT=$(shuf -i 10000-60000 -n 1)
PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
IP4=$(curl -sS4 --max-time 3 https://ifconfig.me || curl -sS4 --max-time 3 https://api.ipify.org)
IP6=$(curl -sS6 --max-time 3 https://api64.ipify.org || curl -sS6 --max-time 3 https://ident.me)

if [ -z "$IP4" ] && [ "$IP6" ]; then
    echo "系统检测：当前为纯 IPv6 环境"
elif [ -z "$IP6" ] && [ "$IP4" ]; then
    echo "系统检测：当前为纯 IPv4 环境"
fi

# 2. 静默初始化环境与内核优化
echo "🔄 正在优化系统环境并安装 Hysteria 2..."
cat << 'EOF_SYSCTL' > /etc/sysctl.d/99-hy2-tuning.conf
net.core.rmem_max=8388608
net.core.wmem_max=8388608
EOF_SYSCTL
sysctl --system >/dev/null 2>&1

if command -v ufw > /dev/null; then ufw disable >/dev/null 2>&1; fi
if command -v systemctl > /dev/null; then systemctl stop firewalld >/dev/null 2>&1 && systemctl disable firewalld >/dev/null 2>&1; fi
iptables -F && iptables -X && iptables -P INPUT ACCEPT
if command -v ip6tables > /dev/null; then ip6tables -F && ip6tables -X && ip6tables -P INPUT ACCEPT; fi

if command -v apt-get >/dev/null; then
  apt-get update -y >/dev/null 2>&1 && apt-get install -y curl openssl wget >/dev/null 2>&1
elif command -v yum >/dev/null; then
  yum makecache -y >/dev/null 2>&1 && yum install -y curl openssl wget >/dev/null 2>&1
fi

# 3. 安装官方核心与配置证书
mkdir -p /etc/hysteria
bash <(curl -fsSL https://get.hy2.sh) >/dev/null 2>&1

openssl req -x509 -nodes -newkey rsa:2048 -keyout /etc/hysteria/server.key -out /etc/hysteria/server.crt -days 3650 -subj "/CN=Anonymity" >/dev/null 2>&1

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
chmod 755 /etc/hysteria; chmod 644 /etc/hysteria/server.crt; chmod 600 /etc/hysteria/server.key
systemctl daemon-reload && systemctl enable hysteria-server && systemctl restart hysteria-server >/dev/null 2>&1

# 4. 生成快捷查看脚本
cat << 'EOF_SHOW' > /usr/local/bin/sd
#!/bin/bash
if [ -f "/etc/hy2_auto/links.txt" ]; then
    echo "=========================================================="
    echo "📋 当前 VPS Hysteria 2 节点链接："
    echo "=========================================================="
    cat /etc/hy2_auto/links.txt
    echo "=========================================================="
else
    echo "❌ 未找到节点信息！"
fi
EOF_SHOW
chmod +x /usr/local/bin/sd

# 5. 直接拼接并保存纯净版链接
rm -f /etc/hy2_auto/links.txt
if [ -n "$IP6" ]; then
    echo "hy2://$PASSWORD@[$IP6]:$PORT?sni=Anonymity&insecure=1#Hy2_IPv6_Auto" >> /etc/hy2_auto/links.txt
fi
if [ -n "$IP4" ]; then
    echo "hy2://$PASSWORD@$IP4:$PORT?sni=Anonymity&insecure=1#Hy2_IPv4_Auto" >> /etc/hy2_auto/links.txt
fi

# 6. 最终直接在控制台吐出节点链接
clear
/usr/local/bin/sd
