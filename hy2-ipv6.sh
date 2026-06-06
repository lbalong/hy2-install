#!/bin/bash

# 检查 Root 用户
[ "$EUID" -ne 0 ] && echo "❌ 错误：请使用 root 用户运行此脚本！" && exit 1

mkdir -p /etc/hy2_auto /etc/hysteria

# 状态文件路径
STATE_FILE="/etc/hy2_auto/state.conf"
DEPLOYED_IPV4="false"
DEPLOYED_IPV6="false"
DEPLOYED_DOMAIN=""
MASQUERADE_DOMAIN="www.bing.com"

# 读取已有状态
[ -f "$STATE_FILE" ] && source "$STATE_FILE" 2>/dev/null

# 提取现有端口和密码
EXISTING_PORT=""
EXISTING_PASSWORD=""
if [ -f "/etc/hysteria/config.yaml" ]; then
    EXISTING_PORT=$(grep -E '^\s*listen:' /etc/hysteria/config.yaml | awk -F ':' '{print $NF}' | tr -dc '0-9')
    EXISTING_PASSWORD=$(grep -E '^\s*password:' /etc/hysteria/config.yaml | awk '{print $NF}' | tr -d '[:space:]"')
fi

PASSWORD="${EXISTING_PASSWORD:-$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)}"

echo "=========================================================="
echo "    Hysteria 2 安全优化版（一键 IPv4/IPv6 部署）"
echo "=========================================================="
echo " 1. 部署/增加【纯 IPv6】节点"
echo " 2. 部署/增加【纯 IPv4】节点"
echo " 3. 部署【IPv4 & IPv6 双栈】节点"
echo " 4. 彻底卸载 Hysteria 2"
echo "=========================================================="
read -p "请选择操作 [1-4]: " CHOICE

if [ "$CHOICE" -eq 4 ]; then
    echo "🧹 正在卸载服务并清理环境..."
    systemctl stop hysteria hysteria-server 2>/dev/null
    systemctl disable hysteria hysteria-server 2>/dev/null
    pkill -9 hysteria 2>/dev/null
    rm -f /etc/systemd/system/hysteria-server.service /etc/systemd/system/hysteria-server@.service
    systemctl daemon-reload
    rm -f /usr/local/bin/hysteria /usr/local/bin/sd
    id "hysteria" &>/dev/null && userdel -r hysteria 2>/dev/null
    rm -rf /etc/hysteria /etc/hy2_auto
    echo "✅ Hysteria 2 已彻底卸载并清理残留！"
    exit 0
elif [ "$CHOICE" -ne 1 ] && [ "$CHOICE" -ne 2 ] && [ "$CHOICE" -ne 3 ]; then
    echo "❌ 输入错误，脚本退出。"
    exit 1
fi

echo "----------------------------------------------------------"
default_port="${EXISTING_PORT:-$(shuf -i 10000-60000 -n 1)}"
read -p "👉 请输入监听端口 (直接回车默认使用 $default_port): " INPUT_PORT
PORT="${INPUT_PORT:-$default_port}"

# 域名与伪装域名选择
if [ -n "$DEPLOYED_DOMAIN" ]; then
    read -p "👉 请输入解析好的域名 (直接回车沿用 $DEPLOYED_DOMAIN, 输入空格清除域名): " INPUT_DOMAIN
    [ "$INPUT_DOMAIN" = " " ] && DOMAIN="" || DOMAIN="${INPUT_DOMAIN:-$default_domain}"
else
    read -p "👉 请输入解析好的域名 (若使用纯IP节点，请直接回车跳过): " DOMAIN
fi

if [ -z "$DOMAIN" ]; then
    read -p "👉 请输入伪装/SNI域名 (直接回车默认使用 $MASQUERADE_DOMAIN): " INPUT_MASQ
    MASQUERADE_DOMAIN="${INPUT_MASQ:-$MASQUERADE_DOMAIN}"
fi
echo "=========================================================="

# 更新节点状态
[ "$CHOICE" -eq 1 ] && DEPLOYED_IPV6="true"
[ "$CHOICE" -eq 2 ] && DEPLOYED_IPV4="true"
if [ "$CHOICE" -eq 3 ]; then
    DEPLOYED_IPV4="true"
    DEPLOYED_IPV6="true"
fi

# 获取 IP
IP4=""
IP6=""
if [ "$DEPLOYED_IPV6" = "true" ]; then
    IP6=$(curl -sS6 --max-time 3 https://api64.ipify.org || curl -sS6 --max-time 3 https://ident.me || ip -6 addr show | grep -oP '(?<=inet6\s)[a-f0-9:]+' | grep -v '^::1' | grep -v '^fe80' | head -n 1)
fi
if [ "$DEPLOYED_IPV4" = "true" ]; then
    IP4=$(curl -sS4 --max-time 3 https://ifconfig.me || curl -sS4 --max-time 3 https://api.ipify.org || ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n 1)
fi

# 内核与防火墙调优
echo "[1/4] 正在配置系统内核调优并开启 BBR..."
cat << 'EOF_SYSCTL' > /etc/sysctl.d/99-hy2-performance.conf
net.core.rmem_max=67108864
net.core.wmem_max=67108864
net.core.rmem_default=33554432
net.core.wmem_default=33554432
net.core.netdev_max_backlog=100000
net.netfilter.nf_conntrack_max=1048576
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
net.ipv4.udp_rmem_min=16384
net.ipv4.udp_wmem_min=16384
net.ipv4.ipfrag_high_thresh=26214400
net.ipv4.ipfrag_low_thresh=19660800
net.ipv6.ip6frag_high_thresh=26214400
net.ipv6.ip6frag_low_thresh=19660800
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF_SYSCTL
sysctl --system >/dev/null 2>&1

# 调优网卡
for dev in /sys/class/net/*; do
    [ -d "$dev" ] && ip link set dev "$(basename "$dev")" txqueuelen 5000 >/dev/null 2>&1
done

# 清理防火墙并安装依赖
command -v ufw >/dev/null && ufw disable >/dev/null 2>&1
command -v systemctl >/dev/null && systemctl stop firewalld >/dev/null 2>&1 && systemctl disable firewalld >/dev/null 2>&1
iptables -F && iptables -X && iptables -P INPUT ACCEPT
command -v ip6tables >/dev/null && ip6tables -F && ip6tables -X && ip6tables -P INPUT ACCEPT
if command -v apt-get >/dev/null; then
  apt-get update -y >/dev/null 2>&1 && apt-get install -y curl openssl wget psmisc >/dev/null 2>&1
elif command -v yum >/dev/null; then
  yum makecache -y >/dev/null 2>&1 && yum install -y curl openssl wget psmisc >/dev/null 2>&1
fi

# 下载官方安装程序并运行
echo "[2/4] 正在下载并安装 Hysteria 2 官方核心..."
curl -fsSL https://get.hy2.sh -o /etc/hy2_auto/install_hy2.sh
if [ -f "/etc/hy2_auto/install_hy2.sh" ]; then
    bash /etc/hy2_auto/install_hy2.sh </dev/null >/etc/hy2_auto/install.log 2>&1
    rm -f /etc/hy2_auto/install_hy2.sh
else
    echo "❌ 错误：官方安装脚本下载失败，请检查网络！" && exit 1
fi

# 证书配置
echo "[3/4] 正在配置安全证书与 TLS..."
if [ -z "$DOMAIN" ]; then
    # 无域名自签名证书，CN设置为伪装域名
    openssl req -x509 -nodes -newkey rsa:2048 -keyout /etc/hysteria/server.key -out /etc/hysteria/server.crt -days 3650 -subj "/CN=$MASQUERADE_DOMAIN" >/dev/null 2>&1
    SNI_PARAM="?sni=$MASQUERADE_DOMAIN&insecure=1"
    MASQ_URL="https://$MASQUERADE_DOMAIN"
else
    # 有域名，申请真实 Let's Encrypt 证书
    if [ "$DOMAIN" != "$DEPLOYED_DOMAIN" ] || [ ! -f /etc/hysteria/server.key ]; then
        [ ! -d ~/.acme.sh ] && curl -sSL https://get.acme.sh | sh -s email=myhy2remote@gmail.com
        ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
        ~/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone
        ~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" --key-file "/etc/hysteria/server.key" --fullchain-file "/etc/hysteria/server.crt"
    fi
    SNI_PARAM="?sni=$DOMAIN"
    MASQ_URL="https://www.bing.com" # 域名版默认伪装至微软
fi

[ ! -f /etc/hysteria/server.key ] && echo "❌ 错误：证书配置生成失败！" && exit 1

# 生成配置文件 (带有高级伪装 masquerade 功能，防主动探测)
cat << EOF_HY2_YAML > /etc/hysteria/config.yaml
listen: :$PORT
tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key
auth:
  type: password
  password: $PASSWORD
masquerade:
  type: proxy
  proxy:
    url: $MASQ_URL
    rewriteHost: true
EOF_HY2_YAML

chown -R hysteria:hysteria /etc/hysteria
chmod 755 /etc/hysteria && chmod 644 /etc/hysteria/server.crt && chmod 600 /etc/hysteria/server.key

# 清理占用端口的进程并启动服务
echo "🛑 正在停止并清理残留端口占用..."
systemctl stop hysteria hysteria-server 2>/dev/null
pkill -9 hysteria 2>/dev/null

echo "🔄 正在启动 Hysteria 2 服务..."
systemctl daemon-reload
systemctl enable hysteria-server >/dev/null 2>&1

if ! systemctl restart hysteria-server; then
    echo "❌ 错误：服务启动命令执行失败！"
    journalctl -u hysteria-server --no-pager -n 15 && exit 1
fi

sleep 2
if ! systemctl is-active --quiet hysteria-server; then
    echo "❌ 错误：Hysteria 2 服务未能维持运行！"
    systemctl status hysteria-server --no-pager && exit 1
fi
echo "✅ Hysteria 2 服务启动成功，目前正在后台正常运行。"

# 生成链接
rm -f /etc/hy2_auto/links.txt
if [ -n "$DOMAIN" ]; then
    echo "hy2://$PASSWORD@$DOMAIN:$PORT$SNI_PARAM#Hy2_域名安全版" >> /etc/hy2_auto/links.txt
else
    [ "$DEPLOYED_IPV6" = "true" ] && [ -n "$IP6" ] && echo "hy2://$PASSWORD@[$IP6]:$PORT$SNI_PARAM#Hy2_纯IPv6_安全伪装版" >> /etc/hy2_auto/links.txt
    [ "$DEPLOYED_IPV4" = "true" ] && [ -n "$IP4" ] && echo "hy2://$PASSWORD@$IP4:$PORT$SNI_PARAM#Hy2_纯IPv4_安全伪装版" >> /etc/hy2_auto/links.txt
fi

# 保存状态
cat << EOF_STATE > "$STATE_FILE"
DEPLOYED_IPV4="$DEPLOYED_IPV4"
DEPLOYED_IPV6="$DEPLOYED_IPV6"
DEPLOYED_DOMAIN="$DOMAIN"
MASQUERADE_DOMAIN="$MASQUERADE_DOMAIN"
EOF_STATE

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

# 输出结果
echo " "
echo "=========================================================="
echo "🎉 Hysteria 2 节点安全优化版部署完成！"
echo "=========================================================="
cat /etc/hy2_auto/links.txt
echo "=========================================================="
echo "💡 后续在 VPS 窗口随时输入快捷命令 [ sd ] 即可再次查看"
echo " "
exit 0
