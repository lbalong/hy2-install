#!/bin/bash

# 检查是否为 Root 用户
if [ "$EUID" -ne 0 ]; then
  echo "错误：请使用 root 用户运行此脚本！"
  exit 1
fi

# 获取系统的公网 IP
IP=$(curl -sS4 https://ifconfig.me || curl -sS4 https://ipinfo.io/ip || curl -sS4 https://api.ipify.org)
if [ -z "$IP" ]; then
  echo "错误：无法获取服务器公网 IP，请检查网络连接。"
  exit 1
fi

# 随机生成 10000-65000 之间的 UDP 端口
PORT=$(shuf -i 10000-65000 -n 1)
# 随机生成 16 位密码
PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)

echo "=========================================="
echo " 开始安装并优化 Hysteria 2..."
echo "=========================================="

# 1. 速度优化：调优 Linux 内核 UDP 缓冲区
echo "正在注入内核加速参数（优化 UDP 缓冲区）..."
cat <<EOF > /etc/sysctl.d/99-hysteria2-tuning.conf
net.core.rmem_max=8388608
net.core.wmem_max=8388608
EOF
sysctl --system >/dev/null 2>&1

# 2. 安装必要依赖
echo "正在安装基础依赖..."
if command -v apt-get >/dev/null; then
  apt-get update && apt-get install -y curl openssl wget
elif command -v yum >/dev/null; then
  yum makecache && yum install -y curl openssl wget
fi

# 3. 调用官方脚本安装 Hysteria 2
bash <(curl -fsSL https://get.hy2.sh)

# 4. 创建配置目录并生成自签名证书
mkdir -p /etc/hysteria
echo "正在生成自签名 TLS 证书..."
openssl req -x509 -nodes -newkey rsa:2048 \
  -keyout /etc/hysteria/server.key \
  -out /etc/hysteria/server.crt \
  -days 3650 \
  -subj "/CN=www.bing.com"

# 5. 写入 Hysteria 2 服务端配置文件
cat <<EOF > /etc/hysteria/config.yaml
listen: :$PORT
tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key
auth:
  type: password
  password: $PASSWORD
EOF

# 6. 【核心修复】修正目录及文件所有权，防止 Permission Denied
echo "正在优化文件权限..."
if id "hysteria" &>/dev/null; then
    chown -R hysteria:hysteria /etc/hysteria
fi

# 7. 放行本地防火墙（针对 Oracle Linux / Ubuntu 默认规则调整）
echo "正在配置本地防火墙放行 UDP 端口: $PORT..."
if command -v ufw > /dev/null; then
    ufw allow $PORT/udp
fi
if command -v iptables > /dev/null; then
    iptables -I INPUT -p udp --dport $PORT -j ACCEPT
    if command -v iptables-save > /dev/null; then
        iptables-save > /etc/iptables.rules 2>/dev/null
    fi
fi

# 8. 配置并启动 Hysteria 2 服务
systemctl daemon-reload
systemctl enable hysteria-server
systemctl restart hysteria-server

# 9. 验证运行状态并输出
if systemctl is-active --quiet hysteria-server; then
    echo "=========================================="
    echo " 🎉 Hysteria 2 安装、权限修复且加速成功！"
    echo "=========================================="
    echo "⚠️  甲骨文云关键提示 ⚠️"
    echo "请务必登录「甲骨文云控制台」，进入你实例的「安全列表 (Security Lists)」"
    echo "添加添加入站规则："
    echo " - IP 协议: UDP"
    echo " - 源 CIDR: 0.0.0.0/0"
    echo " - 目标端口范围: $PORT"
    echo "=========================================="
    echo "你的节点链接 (已集成跳过证书验证):"
    echo ""
    echo "hy2://$PASSWORD@$IP:$PORT/?insecure=1&sni=www.bing.com#Oracle_Hy2_Speed_$PORT"
    echo ""
    echo "=========================================="
else
    echo "❌ Hysteria 2 启动失败，请运行 'journalctl -u hysteria-server' 查看错误日志。"
fi
