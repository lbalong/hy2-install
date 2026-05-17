#!/bin/bash

# 检查是否为 Root 用户
if [ "$EUID" -ne 0 ]; then
  echo "错误：请使用 root 用户运行此脚本！"
  exit 1
fi

# 获取系统的公网 IP
IP=$(curl -sS4 https://ifconfig.me || curl -sS4 https://ipinfo.io/ip || curl -sS4 https://api.ipify.org)
if [ -z "$IP" ]; then
  echo "错误：无法获取服务器公网 IP，请检查 network 连接。"
  exit 1
fi

# 随机生成 10000-65000 之间的 UDP 端口
PORT=$(shuf -i 10000-65000 -n 1)
# 随机生成 16 位强密码
PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)

echo "=========================================="
echo " 开始安装与优化 Hysteria 2 (纯 IP 高速稳定版)"
echo "=========================================="

# 1. 速度优化：调优 Linux 内核 UDP 缓冲区
echo "正在注入内核加速参数（优化 UDP 缓冲区）..."
cat <<EOF > /etc/sysctl.d/99-hysteria2-tuning.conf
net.core.rmem_max=8388608
net.core.wmem_max=8388608
EOF
sysctl --system >/dev/null 2>&1

# 2. 防火墙优化：彻底清空并放行本地防火墙（防止 Ubuntu 默认规则卡死）
echo "正在清空本地防火墙残留规则..."
if command -v ufw > /dev/null; then
    ufw disable >/dev/null 2>&1
fi
iptables -F
iptables -X
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

# 3. 安装必要依赖
echo "正在安装基础依赖..."
if command -v apt-get >/dev/null; then
  apt-get update && apt-get install -y curl openssl wget iptables
elif command -v yum >/dev/null; then
  yum makecache && yum install -y curl openssl wget iptables
fi

# 4. 调用官方脚本安装 Hysteria 2
echo "正在调用官方脚本安装 Hysteria 2 核心..."
bash <(curl -fsSL https://get.hy2.sh)

# 5. 创建配置目录并生成自签名证书（有效期 10 年，伪装 SNI 为 www.bing.com）
mkdir -p /etc/hysteria
echo "正在生成 10 年期自签名 TLS 证书..."
openssl req -x509 -nodes -newkey rsa:2048 \
  -keyout /etc/hysteria/server.key \
  -out /etc/hysteria/server.crt \
  -days 3650 \
  -subj "/CN=www.bing.com"

# 6. 写入 Hysteria 2 服务端配置文件
cat <<EOF > /etc/hysteria/config.yaml
listen: :$PORT
tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key
auth:
  type: password
  password: $PASSWORD
EOF

# 7. 权限修复：修正目录及文件所有权，防止官方核心报 Permission Denied 错误
echo "正在优化文件权限..."
if id "hysteria" &>/dev/null; then
    chown -R hysteria:hysteria /etc/hysteria
fi

# 8. 配置并启动 Hysteria 2 服务
systemctl daemon-reload
systemctl enable hysteria-server
systemctl restart hysteria-server

# 9. 验证运行状态并输出结果
if systemctl is-active --quiet hysteria-server; then
    echo "=========================================="
    echo " 🎉 Hysteria 2 安装、内核加速与权限修复成功！"
    echo "=========================================="
    echo "⚠️  甲骨文云关键提示 ⚠️"
    echo "请务必登录「甲骨文云控制台」，进入该实例的「安全列表 (Security Lists)」"
    echo "手动添加一条入站规则："
    echo " - IP 协议: UDP"
    echo " - 源 CIDR: 0.0.0.0/0"
    echo " - 目标端口范围: $PORT"
    echo "=========================================="
    echo "你的节点链接 (直接复制到 v2rayN、Nekobox 等客户端):"
    echo ""
    echo "hy2://$PASSWORD@$IP:$PORT/?insecure=1&sni=www.bing.com#Oracle_Hy2_$PORT"
    echo ""
    echo "=========================================="
else
    echo "❌ Hysteria 2 启动失败，请运行 'journalctl -u hysteria-server' 查看错误日志。"
fi
