#!/bin/bash

# 检查是否为 Root 用户
if [ "$EUID" -ne 0 ]; then
  echo "❌ 错误：请使用 root 用户运行此脚本！"
  exit 1
fi

# 【严谨前置】创建完全属于此脚本节点的绝对隔离目录
mkdir -p /etc/hy2_v6_isolated
mkdir -p /etc/hy2_auto

# 将密码生成提到最顶部，确保任何菜单分支都能绝对获取到密码
PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)

echo "=========================================================="
echo "    Hysteria 2 路径隔离纯净版（仅部署纯 IPv6 节点）"
echo "=========================================================="
echo " 1. 仅部署【纯 IPv6】高性能节点"
echo " 2. 仅部署【纯 IPv4】高性能节点 (不建议运行，会与其它脚本冲突)"
echo " 3. 部署【IPv4 & IPv6 双栈】节点 (不建议运行)"
echo " 4. 彻底卸载此专属 Hysteria 2 节点"
echo "=========================================================="
# 强行拦截终端输入，防止远程执行时 read 闪退
printf "请选择操作 [1-4]: "
read -r CHOICE < /dev/tty

if [ "$CHOICE" -eq 4 ]; then
    echo "🧹 正在卸载专属服务并清理环境..."
    systemctl stop hy2-v6-custom 2>/dev/null
    systemctl disable hy2-v6-custom 2>/dev/null
    rm -f /etc/systemd/system/hy2-v6-custom.service
    systemctl daemon-reload
    rm -rf /etc/hy2_v6_isolated /etc/hy2_auto
    rm -f /usr/local/bin/sd
    echo "✅ 专属隔离 Hysteria 2 节点已彻底卸载！"
    exit 0
elif [ "$CHOICE" -ne 1 ] && [ "$CHOICE" -ne 2 ] && [ "$CHOICE" -ne 3 ]; then
    echo "❌ 输入错误，脚本退出。"
    exit 1
fi

# 1. 交互询问：端口与域名
echo "----------------------------------------------------------"
default_port=$(shuf -i 10000-60000 -n 1)
printf "👉 请输入节点监听端口 (直接回车随机使用 %s): " "$default_port"
read -r INPUT_PORT < /dev/tty
PORT="${INPUT_PORT:-$default_port}"

printf "👉 请输入解析好的域名 (若建纯IP节点，请直接回车跳过): "
read -r DOMAIN < /dev/tty
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

# 4. 下载官方最新核心（保持原版安装机制）
echo "[2/4] 正在安全下载并安装 Hysteria 2 官方最新核心..."
curl -fsSL https://get.hy2.sh -o /etc/hy2_auto/install_hy2.sh
bash /etc/hy2_auto/install_hy2.sh </dev/null >/dev/null 2>&1
rm -f /etc/hy2_auto/install_hy2.sh

# 5. 【严谨关联性修复】恢复全 root 权限生态，确保特权端口（443）绑定与证书读取链完美闭环
echo "[3/4] 正在配置 TLS 证书与加速服务..."
if [ -z "$DOMAIN" ]; then
    # 路径修改点 1：自签名证书安全生成到隔离区
    openssl req -x509 -nodes -newkey rsa:2048 -keyout /etc/hy2_v6_isolated/server.key -out /etc/hy2_v6_isolated/server.crt -days 3650 -subj "/CN=Anonymity" >/dev/null 2>&1
    SNI_PARAM="?sni=Anonymity&insecure=1"
else
    curl -sSL https://get.acme.sh | sh -s email=myhy2remote@gmail.com
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
    ~/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone
    # 路径修改点 2：正规证书无缝关联安装到隔离区
    ~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" --key-file "/etc/hy2_v6_isolated/server.key" --fullchain-file "/etc/hy2_v6_isolated/server.crt"
    SNI_PARAM="?sni=$DOMAIN"
fi

# 路径修改点 3：配置文件写入隔离区，内部证书引用关系完全对应
cat << EOF_HY2_YAML > /etc/hy2_v6_isolated/config.yaml
listen: :$PORT
tls:
  cert: /etc/hy2_v6_isolated/server.crt
  key: /etc/hy2_v6_isolated/server.key
auth:
  type: password
  password: $PASSWORD
quic:
  initStreamReceiveWindow: 8388608
  maxStreamReceiveWindow: 8388608
  initConnectionReceiveWindow: 16777216
  maxConnectionReceiveWindow: 16777216
  maxIncomingStreams: 1024
EOF_HY2_YAML

# 保持最高规格的 Root 安全权限，允许特权端口调用
chmod 700 /etc/hy2_v6_isolated
chmod 644 /etc/hy2_v6_isolated/server.crt
chmod 600 /etc/hy2_v6_isolated/server.key

# 路径修改点 4：定制使用 Root 权限独立启动的全新 Systemd 服务，确保 443 端口绝对不闪退
cat << 'EOF_SERVICE' > /etc/systemd/system/hy2-v6-custom.service
[Unit]
Description=Hysteria 2 Pure IPv6 Custom Isolated Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/hy2_v6_isolated
ExecStart=/usr/local/bin/hysteria server --config /etc/hy2_v6_isolated/config.yaml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF_SERVICE

systemctl daemon-reload
systemctl enable hy2-v6-custom && systemctl restart hy2-v6-custom >/dev/null 2>&1

# 6. 精准拼接有效格式链接
rm -f /etc/hy2_auto/links.txt

if [ -n "$DOMAIN" ]; then
    echo "hy2://$PASSWORD@$DOMAIN:$PORT$SNI_PARAM#Hy2_域名加速版" >> /etc/hy2_auto/links.txt
else
    if [ "$CHOICE" -eq 1 ] && [ -n "$IP6" ]; then
        echo "hy2://$PASSWORD@[$IP6]:$PORT$SNI_PARAM#Hy2_纯IPv6_路径隔离版" >> /etc/hy2_auto/links.txt
    elif [ "$CHOICE" -eq 2 ] && [ -n "$IP4" ]; then
        echo "hy2://$PASSWORD@$IP4:$PORT$SNI_PARAM#Hy2_纯IPv4_防冲突版" >> /etc/hy2_auto/links.txt
    elif [ "$CHOICE" -eq 3 ]; then
        [ -n "$IP6" ] && echo "hy2://$PASSWORD@[$IP6]:$PORT$SNI_PARAM#Hy2_双栈IPv6_防冲突版" >> /etc/hy2_auto/links.txt
        [ -n "$IP4" ] && echo "hy2://$PASSWORD@$IP4:$PORT$SNI_PARAM#Hy2_双栈IPv4_防冲突版" >> /etc/hy2_auto/links.txt
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
