#!/bin/bash

# 检查是否为 Root 用户
if [ "$EUID" -ne 0 ]; then
  echo "❌ 错误：请使用 root 用户运行此脚本！"
  exit 1
fi

# 创建完全独立的隔离工作目录
mkdir -p /etc/hy2_ipv6_secure
mkdir -p /etc/hysteria

# 将密码生成提到最顶部
PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)

echo "=========================================================="
echo "    Hysteria 2 纯 IPv6 专属【真空全隔离绝不冲突终极版】"
echo "=========================================================="

# 1. 定向到 /dev/tty，确保远程流式执行时也能强行拦截键盘输入
default_port=$(shuf -i 10000-60000 -n 1)
printf "👉 请输入节点监听端口 (直接回车随机使用 %s): " "$default_port"
read -r INPUT_PORT < /dev/tty
PORT="${INPUT_PORT:-$default_port}"

printf "👉 请输入解析好的域名 (若建纯IPv6 IP节点，请直接回车跳过): "
read -r DOMAIN < /dev/tty
echo "=========================================================="

# 2. 精准获取公网 IPv6 地址
echo "🔍 正在精准抓取公网 IPv6 地址..."
IP6=$(curl -sS6 --max-time 4 https://api64.ipify.org || curl -sS6 --max-time 4 https://ident.me)
if [ -z "$IP6" ]; then
    IP6=$(ip -6 addr show | grep -oP '(?<=inet6\s)[a-f0-9:]+' | grep -v '^::1' | grep -v '^fe80' | head -n 1)
fi

if [ -z "$IP6" ]; then
    echo "❌ 错误：未检测到本地或公网 IPv6 地址，请确认 VPS 是否开启了 IPv6 网络！"
    exit 1
fi

# 3. 系统底层内核与 UDP 缓冲区速度优化
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

# 调整物理网卡队列长度
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

# 4. 【降维打击：纯正静默直链】绕过所有动态代理层，直接拉取对纯 IPv6 最友好的高性能二进制直链
echo "[2/4] 正在隔离下载官方 Hysteria v2.6.0 核心组件..."
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    URL_ARCH="linux-amd64"
elif [ "$ARCH" = "aarch64" ]; then
    URL_ARCH="linux-arm64"
else
    URL_ARCH="linux-amd64"
fi

# 移除残余的空文件，确保重新开始
rm -f /etc/hy2_ipv6_secure/hy2-v6-core

# 采用纯 IPv6 路由极其优秀的公网静态直链通道（针对你的 VPS 环境量身定制）
wget -q --no-check-certificate --timeout=20 --tries=3 -O /etc/hy2_ipv6_secure/hy2-v6-core "https://gh.api.99988866.xyz/https://github.com/apernet/hysteria/releases/download/v2.6.0/hysteria-${URL_ARCH}"

# 保底终极手段：如果上面的分流镜像也断了，强制用通用网络代理再拉一次
FILE_SIZE=$(wc -c </etc/hy2_ipv6_secure/hy2-v6-core 2>/dev/null || echo 0)
if [ "$FILE_SIZE" -lt 1048576 ]; then
    wget -q --no-check-certificate --timeout=20 --tries=3 -O /etc/hy2_ipv6_secure/hy2-v6-core "https://download.fastgit.org/apernet/hysteria/releases/download/v2.6.0/hysteria-${URL_ARCH}"
fi

# 最终大小严格终审
FILE_SIZE=$(wc -c </etc/hy2_ipv6_secure/hy2-v6-core 2>/dev/null || echo 0)
if [ "$FILE_SIZE" -lt 1048576 ]; then
    echo "❌ 错误：核心文件在纯 IPv6 环境下下载失败！当前文件大小为: ${FILE_SIZE} 字节"
    echo "💡 提示：这说明您的纯 IPv6 VPS 彻底断绝了与海外 GitHub 及所有反代节点的网络通路，建议运行 [ apt install bind9-host ] 或检查机器的 DNS64 配置。"
    exit 1
fi

chmod +x /etc/hy2_ipv6_secure/hy2-v6-core

# 5. TLS 证书与加速服务配置
echo "[3/4] 正在配置 TLS 证书与暴风级加速参数..."

if [ -z "$DOMAIN" ]; then
    openssl req -x509 -nodes -newkey rsa:2048 -keyout /etc/hy2_ipv6_secure/server.key -out /etc/hy2_ipv6_secure/server.crt -days 3650 -subj "/CN=Anonymity" >/dev/null 2>&1
    SNI_PARAM="?sni=Anonymity&insecure=1"
else
    curl -sSL https://get.acme.sh | sh -s email=myhy2remote@gmail.com
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
    ~/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone
    ~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" --key-file "/etc/hy2_ipv6_secure/server.key" --fullchain-file "/etc/hy2_ipv6_secure/server.crt"
    SNI_PARAM="?sni=$DOMAIN"
fi

# listen 严格死锁 [::]:端口，实现纯 IPv6 的绝对独立监听
cat << EOF_HY2_YAML > /etc/hysteria/config.yaml
listen: "[::]:$PORT"
tls:
  cert: "/etc/hy2_ipv6_secure/server.crt"
  key: "/etc/hy2_ipv6_secure/server.key"
auth:
  type: "password"
  password: "$PASSWORD"
quic:
  initStreamReceiveWindow: 8388608
  maxStreamReceiveWindow: 8388608
  initConnectionReceiveWindow: 16777216
  maxConnectionReceiveWindow: 16777216
  maxIncomingStreams: 1024
EOF_HY2_YAML

chmod 644 /etc/hy2_ipv6_secure/server.crt; chmod 600 /etc/hy2_ipv6_secure/server.key

# 创建完全脱离官方控制的全新隔离 Systemd 服务
cat << 'EOF_SERVICE' > /etc/systemd/system/hy2-v6-custom.service
[Unit]
Description=Hysteria 2 Vacuum Isolated Pure IPv6 Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/hy2_ipv6_secure
ExecStart=/etc/hy2_ipv6_secure/hy2-v6-core server --config /etc/hysteria/config.yaml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF_SERVICE

systemctl daemon-reload
systemctl enable hy2-v6-custom && systemctl restart hy2-v6-custom >/dev/null 2>&1

# 6. 精准拼接纯 IPv6 节点链接
rm -f /etc/hy2_ipv6_secure/links.txt

if [ -n "$DOMAIN" ]; then
    echo "hy2://$PASSWORD@$DOMAIN:$PORT$SNI_PARAM#Hy2_v6_隔离专属版" >> /etc/hy2_ipv6_secure/links.txt
else
    echo "hy2://$PASSWORD@[$IP6]:$PORT$SNI_PARAM#Hy2_纯IPv6_隔离专属版" >> /etc/hy2_ipv6_secure/links.txt
fi

# 生成快捷查看命令 sd
cat << 'EOF_SHOW' > /usr/local/bin/sd
#!/bin/bash
if [ -f "/etc/hy2_ipv6_secure/links.txt" ]; then
    echo "=========================================================="
    echo "📋 当前纯 IPv6 高隔离高带宽节点链接："
    echo "=========================================================="
    cat /etc/hy2_ipv6_secure/links.txt
    echo "=========================================================="
else
    echo "❌ 未找到节点配置信息！"
fi
EOF_SHOW
chmod +x /usr/local/bin/sd

# 7. 最终终端纯净输出
echo " "
echo "=========================================================="
echo "🎉 Hysteria 2 纯 IPv6 隔离专属节点部署完成！请复制链接导入 V2rayN："
echo "=========================================================="
if [ -s "/etc/hy2_ipv6_secure/links.txt" ]; then
    cat /etc/hy2_ipv6_secure/links.txt
else
    echo "❌ 节点链接生成失败，请检查 VPS 的 IPv6 配置。"
fi
echo "=========================================================="
echo "💡 后续在 VPS 窗口随时输入快捷命令 [ sd ] 即可再次查看"
echo " "
exit 0
