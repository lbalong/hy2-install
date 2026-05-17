#!/bin/bash

# 检查是否为 Root 用户
if [ "$EUID" -ne 0 ]; then
  echo "错误：请使用 root 用户运行此脚本！"
  exit 1
fi

echo "=========================================="
echo " 准备安装 Hysteria 2 (域名正规证书版)"
echo "=========================================="

# 交互式获取域名和邮箱
read -p "👉 请输入你在 Cloudflare 解析到本机的完整域名 (如 hy2.yourdomain.com): " DOMAIN
if [ -z "$DOMAIN" ]; then
    echo "错误：域名不能为空！"
    exit 1
fi

read -p "👉 请输入一个邮箱地址 (用于申请 Let's Encrypt 证书，随便填个真实的格式即可，直接回车默认用 admin@$DOMAIN): " EMAIL
if [ -z "$EMAIL" ]; then
    EMAIL="admin@$DOMAIN"
fi

# 随机生成 16 位密码
PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)

# 1. 速度优化：调优 Linux 内核 UDP 缓冲区
echo "正在注入内核加速参数..."
cat <<EOF > /etc/sysctl.d/99-hysteria2-tuning.conf
net.core.rmem_max=8388608
net.core.wmem_max=8388608
EOF
sysctl --system >/dev/null 2>&1

# 2. 安装必要依赖
echo "正在安装基础依赖..."
if command -v apt-get >/dev/null; then
  apt-get update && apt-get install -y curl openssl wget iptables
elif command -v yum >/dev/null; then
  yum makecache && yum install -y curl openssl wget iptables
fi

# 3. 调用官方脚本安装 Hysteria 2
bash <(curl -fsSL https://get.hy2.sh)

# 4. 创建配置目录并设置权限
mkdir -p /etc/hysteria
if id "hysteria" &>/dev/null; then
    chown -R hysteria:hysteria /etc/hysteria
fi

# 5. 写入 Hysteria 2 域名版服务端配置文件
# 使用 443 端口，内置 acme 自动申请证书
cat <<EOF > /etc/hysteria/config.yaml
listen: :443
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

# 6. 放行本地防火墙（必须放行 TCP 80, TCP 443 申请证书，以及 UDP 443 用于连接）
echo "正在配置本地防火墙放行 80 和 443 端口..."
if command -v ufw > /dev/null; then
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw allow 443/udp
fi
if command -v iptables > /dev/null; then
    iptables -I INPUT -p tcp --dport 80 -j ACCEPT
    iptables -I INPUT -p tcp --dport 443 -j ACCEPT
    iptables -I INPUT -p udp --dport 443 -j ACCEPT
    if command -v iptables-save > /dev/null; then
        iptables-save > /etc/iptables.rules 2>/dev/null
    fi
fi

# 7. 配置并启动 Hysteria 2 服务
systemctl daemon-reload
systemctl enable hysteria-server
systemctl restart hysteria-server

# 8. 验证运行状态
sleep 3
if systemctl is-active --quiet hysteria-server; then
    echo "=========================================="
    echo " 🎉 Hysteria 2 域名白盒版安装成功！"
    echo "=========================================="
    echo "⚠️  甲骨文云终极放行提示 ⚠️"
    echo "请登录「甲骨文云控制台 -> 实例 -> 子网 -> 安全列表」"
    echo "添加以下入站规则 (源 CIDR 均为 0.0.0.0/0)："
    echo " 1. IP 协议: TCP, 目标端口: 80 (用于申请证书)"
    echo " 2. IP 协议: TCP, 目标端口: 443 (用于网页伪装)"
    echo " 3. IP 协议: UDP, 目标端口: 443 (节点核心端口)"
    echo "=========================================="
    echo "你的终极安全节点链接 (已自动绑定域名，无需 insecure):"
    echo ""
    echo "hy2://$PASSWORD@$DOMAIN:443#Oracle_Hy2_Pro"
    echo ""
    echo "=========================================="
else
    echo "❌ Hysteria 2 启动失败，请运行 'journalctl -u hysteria-server' 查看错误日志。"
    echo "请确保你在 Cloudflare 的域名解析已经生效，并且是'仅 DNS (灰云)'状态！"
fi
