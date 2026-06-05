#!/bin/bash

# 检查是否为 Root 用户
if [ "$EUID" -ne 0 ]; then
  echo "❌ 错误：请使用 root 用户运行此脚本！"
  exit 1
fi

mkdir -p /etc/hy2_auto

# 1. 【严谨闭环】全自动生成核心变量，彻底断绝因交互引起的 YAML 留空崩溃
PORT=$(shuf -i 10000-60000 -n 1)
PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)

echo "=========================================================="
echo "    Hysteria 2 纯 IPv6 专属高性能极速部署脚本 (全自动防崩版)"
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

# 调整网卡队列长度消除高带宽丢包瓶颈
for dev in /sys/class/net/*; do
    if [ -d "$dev" ]; then
        ifconfig $(basename "$dev") txqueuelen 5000 >/dev/null 2>&1
    fi
done

# 清理防火墙（确保原生放行 IPv6）
if command -v ufw > /dev/null; then ufw disable >/dev/null 2>&1; fi
if command -v systemctl > /dev/null; then systemctl stop firewalld >/dev/null 2>&1 && systemctl disable firewalld >/dev/null 2>&1; fi
iptables -F && iptables -X && iptables -P INPUT ACCEPT
if command -v ip6tables > /dev/null; then ip6tables -F && ip6tables -X && ip6tables -P INPUT ACCEPT; fi

if command -v apt-get >/dev/null; then
  apt-get update -y >/dev/null 2>&1 && apt-get install -y curl openssl wget >/dev/null 2>&1
elif command -v yum >/dev/null; then
  yum makecache -y >/dev/null 2>&1 && yum install -y curl openssl wget >/dev/null 2>&1
fi

# 4. 安全下载并安装 Hysteria 2 官方最新核心（规避流冲突）
echo "[2/4] 正在安全下载并安装 Hysteria 2 官方最新核心..."
mkdir -p /etc/hysteria
curl -fsSL https://get.hy2.sh -o /etc/hy2_auto/install_hy2.sh
bash /etc/hy2_auto/install_hy2.sh </dev/null >/dev/null 2>&1
rm -f /etc/hy2_auto/install_hy2.sh

# 5. TLS 证书与加速服务配置
echo "[3/4] 正在配置自签名 TLS 证书与加速服务..."
openssl req -x509 -nodes -newkey rsa:2048 -keyout /etc/hysteria/server.key -out /etc/hysteria/server.crt -days 3650 -subj "/CN=Anonymity" >/dev/null 2>&1

# 【严格校对】使用带双引号包裹的明确字符串，彻底根治 YAML 解析器敏感度故障
cat << EOF_HY2_YAML > /etc/hysteria/config.yaml
listen: ":$PORT"
tls:
  cert: "/etc/hysteria/server.crt"
  key: "/etc/hysteria/server.key"
auth:
  type: "password"
  password: "$PASSWORD"
EOF_HY2_YAML

chown -R hysteria:hysteria /etc/hysteria
chmod 755 /etc/hysteria; chmod 644 /etc/hysteria/server.crt; chmod 600 /etc/hysteria/server.key
systemctl daemon-reload && systemctl enable hysteria-server && systemctl restart hysteria-server >/dev/null 2>&1

# 6. 精准拼接纯 IPv6 节点链接
rm -f /etc/hy2_auto/links.txt
echo "hy2://$PASSWORD@[$IP6]:$PORT?sni=Anonymity&insecure=1#Hy2_纯IPv6_加速版" >> /etc/hy2_auto/links.txt

# 生成快捷查看命令 sd
cat << 'EOF_SHOW' > /usr/local/bin/sd
#!/bin/bash
if [ -f "/etc/hy2_auto/links.txt" ]; then
    echo "=========================================================="
    echo "📋 当前纯 IPv6 高带宽调优节点链接："
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
echo "🎉 Hysteria 2 纯 IPv6 节点部署完成！请复制链接导入 V2rayN："
echo "=========================================================="
if [ -s "/etc/hy2_auto/links.txt" ]; then
    cat /etc/hy2_auto/links.txt
else
    echo "❌ 节点链接生成失败，请检查 VPS 的 IPv6 配置。"
fi
echo "=========================================================="
echo "💡 后续在 VPS 窗口随时输入快捷命令 [ sd ] 即可再次查看"
echo " "
exit 0
