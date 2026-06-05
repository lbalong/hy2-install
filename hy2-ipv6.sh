#!/bin/bash

# 检查是否为 Root 用户
if [ "$EUID" -ne 0 ]; then
  echo "❌ 错误：请使用 root 用户运行此脚本！"
  exit 1
fi

mkdir -p /etc/hysteria
mkdir -p /etc/hy2_auto

# 将密码生成提到最顶部
PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)

echo "=========================================================="
echo "    Hysteria 2 纯 IPv6 专属【动态追加完美共存版】"
echo "=========================================================="

# 1. 交互询问：端口与域名
default_port=$(shuf -i 10000-60000 -n 1)
printf "👉 请输入节点监听端口 (直接回车随机使用 %s): " "$default_port"
read -r INPUT_PORT < /dev/tty
PORT="${INPUT_PORT:-$default_port}"

printf "👉 请输入解析好的域名 (若建纯IP节点，请直接回车跳过): "
read -r DOMAIN < /dev/tty
echo "=========================================================="

# 2. 精准获取公网 IPv6 地址
echo "🔍 正在获取公网 IPv6 地址..."
IP6=$(curl -sS6 --max-time 3 https://api64.ipify.org || curl -sS6 --max-time 3 https://ident.me)
if [ -z "$IP6" ]; then
    IP6=$(ip -6 addr show | grep -oP '(?<=inet6\s)[a-f0-9:]+' | grep -v '^::1' | grep -v '^fe80' | head -n 1)
fi

# 3. 系统内核与 UDP 缓冲区速度优化
echo "[1/4] 正在注入高性能 UDP 调优参数并开启 BBR..."
cat << 'EOF_SYSCTL' > /etc/sysctl.d/99-hy2-performance.conf
net.core.rmem_max=33554432
net.core.wmem_max=33554432
net.core.rmem_default=16777216
net.core.wmem_default=16777216
net.netfilter.nf_conntrack_max=1048576
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF_SYSCTL
sysctl --system >/dev/null 2>&1

# 4. 安全下载并安装 Hysteria 2 官方最新核心
echo "[2/4] 正在安全下载并安装 Hysteria 2 官方最新核心..."
curl -fsSL https://get.hy2.sh -o /etc/hy2_auto/install_hy2.sh
bash /etc/hy2_auto/install_hy2.sh </dev/null >/dev/null 2>&1
rm -f /etc/hy2_auto/install_hy2.sh

# 5. 【核心重构：无损动态配置机制】
echo "[3/4] 正在智能合并配置，确保 IPv4/IPv6 完美并存..."

# 如果原本没有配置文件，则初始化基础结构
if [ ! -f "/etc/hysteria/config.yaml" ] || [ ! -s "/etc/hysteria/config.yaml" ]; then
    openssl req -x509 -nodes -newkey rsa:2048 -keyout /etc/hysteria/server.key -out /etc/hysteria/server.crt -days 3650 -subj "/CN=Anonymity" >/dev/null 2>&1
    
    cat << EOF_INIT > /etc/hysteria/config.yaml
listen: :$PORT
tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key
auth:
  type: password
  password: $PASSWORD
EOF_INIT

else
    # 💥 如果系统里已经存在其它脚本建好的 IPv4 节点，我们采用官方的“多端口/多监听”高级语法进行动态追加！
    # 这样绝对不会覆盖、不会破坏原有的 IPv4 配置，两者完美共存。
    
    # 检查原本的证书是否存在，如果不存在则补充一个自签名证书备用
    if [ ! -f "/etc/hysteria/server.crt" ]; then
        openssl req -x509 -nodes -newkey rsa:2048 -keyout /etc/hysteria/server.key -out /etc/hysteria/server.crt -days 3650 -subj "/CN=Anonymity" >/dev/null 2>&1
    fi

    # 在原有配置文件的最末尾，安全地追加一个独立的 IPv6 监听流与专属密码
    cat << EOF_APPEND >> /etc/hysteria/config.yaml

# 👇 以下由纯 IPv6 专属脚本自动追加，实现双向完美共存
additionalListens:
  - listen: "[::]:$PORT"
    auth:
      type: password
      password: "$PASSWORD"
EOF_APPEND
fi

# 统一注入暴风级 QUIC 调优速度参数（如果文件中还没有的话）
if ! grep -q "quic:" /etc/hysteria/config.yaml; then
    cat << EOF_QUIC >> /etc/hysteria/config.yaml
quic:
  initStreamReceiveWindow: 8388608
  maxStreamReceiveWindow: 8388608
  initConnectionReceiveWindow: 16777216
  maxConnectionReceiveWindow: 16777216
  maxIncomingStreams: 1024
EOF_QUIC
fi

# 修复可能存在的旧隔离服务，统一归顺官方正统服务
systemctl stop hy2-v6-custom 2>/dev/null
systemctl disable hy2-v6-custom 2>/dev/null
rm -f /etc/systemd/system/hy2-v6-custom.service

chown -R hysteria:hysteria /etc/hysteria
systemctl daemon-reload
systemctl enable hysteria-server && systemctl restart hysteria-server >/dev/null 2>&1

# 6. 精准拼接有效格式链接
rm -f /etc/hy2_auto/links.txt
SNI_PARAM="?sni=Anonymity&insecure=1"
[ -n "$DOMAIN" ] && SNI_PARAM="?sni=$DOMAIN"

if [ -n "$DOMAIN" ]; then
    echo "hy2://$PASSWORD@$DOMAIN:$PORT$SNI_PARAM#Hy2_v6_域名共存版" >> /etc/hy2_auto/links.txt
else
    echo "hy2://$PASSWORD@[$IP6]:$PORT$SNI_PARAM#Hy2_纯IPv6_智能共存版" >> /etc/hy2_auto/links.txt
fi

# 生成快捷查看命令 sd
cat << 'EOF_SHOW' > /usr/local/bin/sd
#!/bin/bash
if [ -f "/etc/hy2_auto/links.txt" ]; then
    echo "=========================================================="
    echo "📋 当前智能共存版纯 IPv6 节点链接："
    echo "=========================================================="
    cat /etc/hy2_auto/links.txt
    echo "=========================================================="
else
    echo "❌ 未找到节点配置信息！"
fi
EOF_SHOW
chmod +x /usr/local/bin/sd

# 7. 最终终端纯净输出
echo " "
echo "=========================================================="
echo "🎉 Hysteria 2 纯 IPv6 智能共存节点部署完成！"
echo "=========================================================="
if [ -s "/etc/hy2_auto/links.txt" ]; then
    cat /etc/hy2_auto/links.txt
else
    echo "❌ 节点链接生成失败。"
fi
echo "=========================================================="
echo "💡 后续在 VPS 窗口随时输入快捷命令 [ sd ] 即可再次查看"
echo " "
exit 0
