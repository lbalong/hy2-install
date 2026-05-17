#!/bin/bash

# 检查是否为 Root 用户
if [ "$EUID" -ne 0 ]; then
  echo "错误：请使用 root 用户运行此脚本！"
  exit 1
fi

echo "=========================================="
echo "    Hysteria 2 自动化双模一键脚本 (端口自定义版)"
echo "=========================================="
echo " 1. 安装 纯 IP 自签名版 (100% 成功 / 适合不折腾)"
echo " 2. 安装 域名正规证书版 (借鉴成功规则 / 完美闭环)"
echo "=========================================="
read -p "请选择安装模式 [1-2]: " CHOICE

# 提取公共核心：获取 IP 和 16 位强密码
IP=$(curl -sS4 https://ifconfig.me || curl -sS4 https://ipinfo.io/ip || curl -sS4 https://api.ipify.org)
PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)

# 端口控制逻辑：根据模式决定是否允许手动输入
if [ "$CHOICE" -eq 1 ]; then
    # IP版继续保持随机高位端口
    PORT=$(shuf -i 10000-65000 -n 1)
elif [ "$CHOICE" -eq 2 ]; then
    # 域名版允许老哥手动输入以前成功的固定端口
    echo "💡 提示：请输入你另一台成功 VPS 入站规则里开好门的那个端口。"
    read -p "👉 请输入节点监听端口 (例如 443 或 34433): " PORT
    if [ -z "$PORT" ]; then
        PORT=$(shuf -i 10000-65000 -n 1)
        echo "⚠️ 未输入端口，已自动生成随机端口: $PORT"
    fi
else
    echo "无效选项，退出脚本。"
    exit 1
fi

# 速度优化（调优 Linux 内核 UDP 缓冲区）
echo "正在注入内核加速参数（优化 UDP 缓冲区）..."
cat <<EOF > /etc/sysctl.d/99-hysteria2-tuning.conf
net.core.rmem_max=8388608
net.core.wmem_max=8388608
EOF
sysctl --system >/dev/null 2>&1

# 防火墙优化（彻底清空并放行本地防火墙，防止 Ubuntu 规则卡死）
echo "正在清空本地防火墙残留规则..."
if command -v ufw > /dev/null; then
    ufw disable >/dev/null 2>&1
fi
iptables -F
iptables -X
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

# 安装必要依赖
echo "正在安装基础依赖..."
if command -v apt-get >/dev/null; then
  apt-get update && apt-get install -y curl openssl wget iptables
elif command -v yum >/dev/null; then
  yum makecache && yum install -y curl openssl wget iptables
fi

# 调用官方脚本安装 Hysteria 2
echo "正在调用官方脚本安装 Hysteria 2 核心..."
bash <(curl -fsSL https://get.hy2.sh)

# 创建配置目录
mkdir -p /etc/hysteria

# 根据用户选择，切入不同的证书与配置流
if [ "$CHOICE" -eq 1 ]; then
    # 【模式 1：纯 IP 自签名流】
    echo "正在生成 10 年期自签名 TLS 证书..."
    openssl req -x509 -nodes -newkey rsa:2048 \
      -keyout /etc/hysteria/server.key \
      -out /etc/hysteria/server.crt \
      -days 3650 \
      -subj "/CN=www.bing.com"

    # 写入纯 IP 配置文件
    cat <<EOF > /etc/hysteria/config.yaml
listen: :$PORT
tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key
auth:
  type: password
  password: $PASSWORD
EOF

elif [ "$CHOICE" -eq 2 ]; then
    # 【模式 2：纯域名正规证书流】
    read -p "👉 请输入已解析到本机的完整域名 (例如 sg.099889.xyz): " DOMAIN
    if [ -z "$DOMAIN" ]; then echo "域名不能为空！"; exit 1; fi
    
    read -p "👉 请输入邮箱 (直接回车默认 admin@$DOMAIN): " EMAIL
    if [ -z "$EMAIL" ]; then EMAIL="admin@$DOMAIN"; fi

    # 写入纯正规域名配置文件 (不带任何反代干扰)
    cat <<EOF > /etc/hysteria/config.yaml
listen: :$PORT
acme:
  domains:
    - $DOMAIN
  email: $EMAIL
auth:
  type: password
  password: $PASSWORD
EOF
fi

# 权限修复
echo "正在优化文件权限..."
if id "hysteria" &>/dev/null; then
    chown -R hysteria:hysteria /etc/hysteria
fi

# 配置并启动 Hysteria 2 服务
systemctl daemon-reload
systemctl enable hysteria-server
systemctl restart hysteria-server

sleep 3

# 根据模式精准输出结果链接
if systemctl is-active --quiet hysteria-server; then
    echo "=========================================="
    echo " 🎉 Hysteria 2 服务部署与内核加速成功！"
    echo "=========================================="
    
    if [ "$CHOICE" -eq 1 ]; then
        echo "⚠️  甲骨文云网页后台放行提示 ⚠️"
        echo " - IP 协议: UDP, 目标端口: $PORT"
        echo "=========================================="
        echo "你的节点链接 (纯 IP 自签版):"
        echo ""
        echo "hy2://$PASSWORD@$IP:$PORT/?insecure=1&sni=www.bing.com#Oracle_Hy2_IP_$PORT"
    else
        echo "⚠️  甲骨文云网页后台放行提示 ⚠️"
        echo " 1. IP 协议: TCP, 目标端口: 80  (用于自动续签证书，务必保持开启)"
        echo " 2. IP 协议: UDP, 目标端口: $PORT (你借鉴并指定的固定通信端口)"
        echo "=========================================="
        echo "你的节点链接 (域名证书版 - 强注 SNI 参数):"
        echo ""
        echo "hy2://$PASSWORD@$DOMAIN:$PORT/?sni=$DOMAIN#Oracle_Hy2_Domain_$PORT"
    fi
    echo "=========================================="
else
    echo "❌ Hysteria 2 启动失败，请运行 'journalctl -u hysteria-server' 查看错误日志。"
fi
