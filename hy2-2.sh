#!/bin/bash

# 检查是否为 Root 用户
if [ "$EUID" -ne 0 ]; then
  echo "错误：请使用 root 用户运行此脚本！"
  exit 1
fi

echo "=========================================="
echo " 开始安装与优化 Hysteria 2 (纯域名正规证书版)"
echo "=========================================="

# 输入域名和邮箱
read -p "👉 请输入已解析到本机的完整域名: " DOMAIN
if [ -z "$DOMAIN" ]; then echo "域名不能为空！"; exit 1; fi

read -p "👉 请输入邮箱 (直接回车默认 admin@$DOMAIN): " EMAIL
if [ -z "$EMAIL" ]; then EMAIL="admin@$DOMAIN"; fi

# 端口选择：默认随机高位端口，也可以手动控死
DEFAULT_PORT=$(shuf -i 10000-65000 -n 1)
read -p "👉 请输入节点监听端口 (直接回车使用随机高位端口 $DEFAULT_PORT): " PORT
if [ -z "$PORT" ]; then
    PORT=$DEFAULT_PORT
fi

PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)

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

# 5. 写入 Hysteria 2 服务端配置文件 (ACME 自动证书模式)
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

# 6. 权限修复：修正目录及文件所有权，防止官方核心报 Permission Denied 错误
echo "正在优化文件权限..."
if id "hysteria" &>/dev/null; then
    chown -R hysteria:hysteria /etc/hysteria
fi

# 7. 配置并启动 Hysteria 2 服务
systemctl daemon-reload
systemctl enable hysteria-server
systemctl restart hysteria-server

sleep 5
# 8. 验证运行状态并输出结果
if systemctl is-active --quiet hysteria-server; then
    echo "=========================================="
    echo " 🎉 Hysteria 2 域名证书版安装与内核加速成功！"
    echo "=========================================="
    echo "⚠️  甲骨文云网页后台放行提示 ⚠️"
    echo "请务必进入该实例的「安全列表 (Security Lists)」手动放行："
    echo " 1. IP 协议: TCP, 目标端口: 80  (用于 ACME 自动申请/续签证书，必开)"
    echo " 2. IP 协议: UDP, 目标端口: $PORT (节点核心通信端口，必开)"
    echo "=========================================="
    echo "你的终极节点链接（已注入 ?sni=$DOMAIN 修复客户端留空 Bug）："
    echo ""
    echo "hy2://$PASSWORD@$DOMAIN:$PORT/?sni=$DOMAIN#Oracle_Hy2_Domain_$PORT"
    echo ""
    echo "=========================================="
else
    echo "❌ Hysteria 2 启动失败，请运行 'journalctl -u hysteria-server' 查看错误日志。"
fi
