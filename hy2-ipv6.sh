#!/bin/bash

# 检查是否为 Root 用户
if [ "$EUID" -ne 0 ]; then
  echo "❌ 错误：请使用 root 用户运行此脚本！"
  exit 1
fi

mkdir -p /etc/hy2_auto

# 1. 交互询问：端口与域名
echo "=========================================================="
echo "    Hysteria 2 高性能速度优化版（支持远程/纯IPv6）"
echo "=========================================================="

default_port=$(shuf -i 10000-60000 -n 1)
read -p "👉 请输入节点监听端口 (直接回车随机使用 $default_port): " INPUT_PORT
PORT="${INPUT_PORT:-$default_port}"

read -p "👉 请输入解析到此VPS的域名 (若建纯IP节点，请直接回车跳过): " DOMAIN
echo "=========================================================="

# 2. 自动获取公网 IP（保底逻辑）
PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
IP4=$(curl -sS4 --max-time 2 https://ifconfig.me || curl -sS4 --max-time 2 https://api.ipify.org)
IP6=$(curl -sS6 --max-time 2 https://api64.ipify.org || curl -sS6 --max-time 2 https://ident.me)

if [ -z "$IP4" ]; then
    IP4=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n 1)
fi
if [ -z "$IP6" ]; then
    IP6=$(ip -6 addr show | grep -oP '(?<=inet6\s)[a-f0-9:]+' | grep -v '^::1' | grep -v '^fe80' | head -n 1)
fi

# 3. 核心速度优化：系统内核与网络队列调优
echo "[1/4] 正在注入高性能 UDP 调优参数并开启 BBR..."
cat << 'EOF_SYSCTL' > /etc/sysctl.d/99-hy2-performance.conf
# 极端放大 UDP 缓冲区，防止 QUIC/Hy2 大流量丢包
net.core.rmem_max=33554432
net.core.wmem_max=33554432
net.core.rmem_default=16777216
net.core.wmem_default=16777216
# 提高最大连接跟踪数
net.netfilter.nf_conntrack_max=1048576
# 开启 BBR 拥塞控制
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF_SYSCTL
sysctl --system >/dev/null 2>&1

# 调整所有可用网卡的队列长度，消除硬件层面的发送瓶颈
for dev in /sys/class/net/*; do
    if [ -d "$dev" ]; then
        ifconfig $(basename "$dev") txqueuelen 5000 >/dev/null 2>&1
    fi
done

# 清理防火墙
if command -v ufw > /dev/null; then ufw disable >/dev/null 2>&1; fi
if command -v systemctl > /dev/null; then systemctl stop firewalld >/dev/null 2>&1 && systemctl disable firewalld >/dev/null 2>&1; fi
iptables -F && iptables -X && iptables -P INPUT ACCEPT
if command -v ip6tables > /dev/null; then ip6tables -F && ip6tables -X && ip6tables -P INPUT ACCEPT; fi

if command -v apt-get >/dev/null; then
  apt-get update -y >/dev/null 2>&1 && apt-get install -y curl openssl wget >/dev/null 2>&1
elif command -v yum >/dev/null; then
  yum makecache -y >/dev/null 2>&1 && yum install -y curl openssl wget >/dev/null 2>&1
fi

# 4. 安装官方核心
echo "[2/4] 正在更新/安装 Hysteria 2 官方核心..."
mkdir -p /etc/hysteria
bash <(curl -fsSL https://get.hy2.sh)

# 5. 证书与服务配置
echo "[3/4] 正在配置 TLS 证书与加速服务..."
if [ -z "$DOMAIN" ]; then
    # 纯 IP 自签名证书逻辑
    openssl req -x509 -nodes -newkey rsa:2048 -keyout /etc/hysteria/server.key -out /etc/hysteria/server.crt -days 3650 -subj "/CN=Anonymity" >/dev/null 2>&1
    SNI_PARAM="&insecure=1"
    SERVER_NAME="Anonymity"
else
    # 域名申请证书逻辑
    curl -sSL https://get.acme.sh | sh -s email=myhy2remote@gmail.com
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
    ~/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone
    ~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" --key-file "/etc/hysteria/server.key" --fullchain-file "/etc/hysteria/server.crt"
    SNI_PARAM="&sni=$DOMAIN"
    SERVER_NAME="$DOMAIN"
fi

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

# 6. 生成保存快捷查看链接
rm -f /etc/hy2_auto/links.txt
if [ -n "$DOMAIN" ]; then
    echo "hy2://$PASSWORD@$DOMAIN:$PORT?sni=$DOMAIN#Hy2_域名加速版" >> /etc/hy2_auto/links.txt
else
    if [ -n "$IP6" ]; then
        echo "hy2://$PASSWORD@[$IP6]:$PORT?sni=$SERVER_NAME$SNI_PARAM#Hy2_IPv6_加速版" >> /etc/hy2_auto/links.txt
    fi
    if [ -n "$IP4" ]; then
        echo "hy2://$PASSWORD@$IP4:$PORT?sni=$SERVER_NAME$SNI_PARAM#Hy2_IPv4_Acc" >> /etc/hy2_auto/links.txt
    fi
fi

# 生成快捷命令 sd
cat << 'EOF_SHOW' > /usr/local/bin/sd
#!/bin/bash
if [ -f "/etc/hy2_auto/links.txt" ]; then
    echo "=========================================================="
    echo "📋 当前高带宽调优节点链接："
    echo "=========================================================="
    cat /etc/hy2_auto/links.txt
    echo "=========================================================="
else
    echo "❌ 未找到节点配置信息！"
fi
EOF_SHOW
chmod +x /usr/local/bin/sd

# 7. 最终终端输出
echo " "
echo "=========================================================="
echo -e "\033[32m🎉 Hysteria 2 节点加速部署完成！链接如下：\033[0m"
echo "=========================================================="
cat /etc/hy2_auto/links.txt
echo "=========================================================="
echo -e "💡 \033[33m后续在 VPS 窗口随时输入快捷命令 [ sd ] 即可再次查看\033[0m"
echo " "
