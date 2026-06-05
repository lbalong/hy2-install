#!/bin/bash

# 检查是否为 Root 用户
if [ "$EUID" -ne 0 ]; then
  echo "❌ 错误：请使用 root 用户运行此脚本！"
  exit 1
fi

mkdir -p /etc/hy2_auto

# 将密码生成提到最顶部，确保任何菜单分支都能绝对获取到密码
PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)

echo "=========================================================="
echo "    Hysteria 2 高性能分流版（彻底根治流冲突版）"
echo "=========================================================="
echo " 1. 仅部署【纯 IPv6】高性能节点"
echo " 2. 仅部署【纯 IPv4】高性能节点"
echo " 3. 部署【IPv4 & IPv6 双栈】节点"
echo " 4. 彻底卸载 Hysteria 2"
echo "=========================================================="
read -p "请选择操作 [1-4]: " CHOICE

if [ "$CHOICE" -eq 4 ]; then
    echo "🧹 正在卸载服务并清理环境..."
    systemctl stop hysteria-server 2>/dev/null
    systemctl disable hysteria-server 2>/dev/null
    rm -f /etc/systemd/system/hysteria-server.service
    systemctl daemon-reload
    rm -f /usr/local/bin/hysteria /usr/local/bin/sd
    rm -rf /etc/hysteria /etc/hy2_auto
    echo "✅ Hysteria 2 已彻底卸载！"
    exit 0
elif [ "$CHOICE" -ne 1 ] && [ "$CHOICE" -ne 2 ] && [ "$CHOICE" -ne 3 ]; then
    echo "❌ 输入错误，脚本退出。"
    exit 1
fi

# 1. 交互询问：端口与域名
echo "----------------------------------------------------------"
default_port=$(shuf -i 10000-60000 -n 1)
read -p "👉 请输入节点监听端口 (直接回车随机使用 $default_port): " INPUT_PORT
PORT="${INPUT_PORT:-$default_port}"

read -p "👉 请输入解析好的域名 (若建纯IP节点，请直接回车跳过): " DOMAIN
echo "=========================================================="

# 2. 根据菜单选择精准获取 IP
IP4=""
IP6=""

if [ "$CHOICE" -eq 1 ] || [ "$CHOICE" -eq 3 ]; then
    echo "🔍 正在获取公网 IPv6 地址..."
    IP6=$(curl -sS6 --max-time 3 https://api64.ipify.org || curl -sS6 --max-time 3 https://ident.me)
    if [ -z "$IP6" ]; then
        IP6=$(ip -6 addr show | grep -oP '(?<=inet6\s)[a-f0-9:]+' | grep -v '^::1' | grep -v '^fe80' | head -n 1)
    fi
fi

if [ "$CHOICE" -eq 2 ] || [ "$CHOICE" -eq 3 ]; then
    echo "🔍 正在获取公网 IPv4 地址..."
    IP4=$(curl -sS4 --max-time 3 https://ifconfig.me || curl -sS4 --max-time 3 https://api.ipify.org)
    if [ -z "$IP4" ]; then
        IP4=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n 1)
    fi
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

# 调整网卡队列长度消除瓶颈
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

# 4. 【核心重构】下载官方脚本到本地离线运行，彻底断开标准输入流，防止截断
echo "[2/4] 正在安全下载并安装 Hysteria 2 官方最新核心..."
mkdir -p /etc/hysteria
curl -fsSL https://get.hy2.sh -o /etc/hy2_auto/install_hy2.sh
# 使用 </dev/null 强行关闭标准输入，彻底根治远程执行时的 EOF 冲突
bash /etc/hy2_auto/install_hy2.sh </dev/null >/dev/null 2>&1
rm -f /etc/hy2_auto/install_hy2.sh

# 5. TLS 证书与加速服务配置
echo "[3/4] 正在配置 TLS 证书与加速服务..."
if [ -z "$DOMAIN" ]; then
    openssl req -x509 -nodes -newkey rsa:2048 -keyout /etc/hysteria/server.key -out /etc/hysteria/server.crt -days 3650 -subj "/CN=Anonymity" >/dev/null 2>&1
    SNI_PARAM="?sni=Anonymity&insecure=1"
else
    curl -sSL https://get.acme.sh | sh -s email=myhy2remote@gmail.com
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
    ~/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone
    ~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" --key-file "/etc/hysteria/server.key" --fullchain-file "/etc/hysteria/server.crt"
    SNI_PARAM="?sni=$DOMAIN"
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

# 6. 精准拼接有效格式链接
rm -f /etc/hy2_auto/links.txt

if [ -n "$DOMAIN" ]; then
    echo "hy2://$PASSWORD@$DOMAIN:$PORT$SNI_PARAM#Hy2_域名加速版" >> /etc/hy2_auto/links.txt
else
    if [ "$CHOICE" -eq 1 ] && [ -n "$IP6" ]; then
        echo "hy2://$PASSWORD@[$IP6]:$PORT$SNI_PARAM#Hy2_纯IPv6_加速版" >> /etc/hy2_auto/links.txt
    elif [ "$CHOICE" -eq 2 ] && [ -n "$IP4" ]; then
        echo "hy2://$PASSWORD@$IP4:$PORT$SNI_PARAM#Hy2_纯IPv4_加速版" >> /etc/hy2_auto/links.txt
    elif [ "$CHOICE" -eq 3 ]; then
        [ -n "$IP6" ] && echo "hy2://$PASSWORD@[$IP6]:$PORT$SNI_PARAM#Hy2_双栈IPv6_加速版" >> /etc/hy2_auto/links.txt
        [ -n "$IP4" ] && echo "hy2://$PASSWORD@$IP4:$PORT$SNI_PARAM#Hy2_双栈IPv4_加速版" >> /etc/hy2_auto/links.txt
    fi
fi

# 生成快捷查看命令 sd
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

# 7. 最终终端纯净输出
echo " "
echo "=========================================================="
echo "🎉 Hysteria 2 节点加速部署完成！链接已修复，请复制导入："
echo "=========================================================="
if [ -s "/etc/hy2_auto/links.txt" ]; then
    cat /etc/hy2_auto/links.txt
else
    echo "❌ 节点链接生成失败，请确认您选择的 IP 类型是否在 VPS 上真实存在。"
fi
echo "=========================================================="
echo "💡 后续在 VPS 窗口随时输入快捷命令 [ sd ] 即可再次查看"
echo " "
exit 0
