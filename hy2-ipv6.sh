#!/bin/bash

# 检查是否为 Root 用户
if [ "$EUID" -ne 0 ]; then
  echo "❌ 错误：请使用 root 用户运行此脚本！"
  exit 1
fi

mkdir -p /etc/hy2_auto
mkdir -p /etc/hysteria

# 定义状态文件路径
STATE_FILE="/etc/hy2_auto/state.conf"
DEPLOYED_IPV4="false"
DEPLOYED_IPV6="false"
DEPLOYED_DOMAIN=""
MASQUERADE_DOMAIN="www.bing.com"

# 读取已有状态
if [ -f "$STATE_FILE" ]; then
    source "$STATE_FILE" 2>/dev/null
fi

# 从现有 config.yaml 提取端口 and 密码（若存在）
EXISTING_PORT=""
EXISTING_PASSWORD=""
if [ -f "/etc/hysteria/config.yaml" ]; then
    EXISTING_PORT=$(grep -E '^\s*listen:' /etc/hysteria/config.yaml | head -n 1 | awk -F ':' '{print $NF}')
    EXISTING_PORT=$(echo "$EXISTING_PORT" | tr -dc '0-9')
    # 限制 head -n 1，防止提取到 obfs 模块里的第二个 password 导致密码成倍叠加
    EXISTING_PASSWORD=$(grep -E '^\s*password:' /etc/hysteria/config.yaml | head -n 1 | awk '{print $NF}' | tr -d '[:space:]"')
fi

# 如果有旧密码则沿用，否则生成新密码
if [ -n "$EXISTING_PASSWORD" ]; then
    PASSWORD="$EXISTING_PASSWORD"
    echo "ℹ️ 检测到已存在节点密码，脚本将沿用旧密码以保持客户端配置有效。"
else
    PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
fi

echo "=========================================================="
echo "    Hysteria 2 高性能分流版（流量混淆加速版）"
echo "=========================================================="
echo " 1. 部署/增加【纯 IPv6】高性能节点"
echo " 2. 部署/增加【纯 IPv4】高性能节点"
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
    if id "hysteria" &>/dev/null; then
        userdel -r hysteria 2>/dev/null
    fi
    rm -rf /etc/hysteria /etc/hy2_auto
    echo "✅ Hysteria 2 已彻底卸载！"
    exit 0
elif [ "$CHOICE" -ne 1 ] && [ "$CHOICE" -ne 2 ] && [ "$CHOICE" -ne 3 ]; then
    echo "❌ 输入错误，脚本退出。"
    exit 1
fi

# 1. 交互询问：端口与域名
echo "----------------------------------------------------------"
if [ -n "$EXISTING_PORT" ]; then
    default_port="$EXISTING_PORT"
    echo "ℹ️ 检测到已有 Hysteria 2 服务运行在端口 $default_port"
else
    default_port=$(shuf -i 10000-60000 -n 1)
fi
read -p "👉 请输入节点监听端口 (直接回车默认使用 $default_port): " INPUT_PORT
PORT="${INPUT_PORT:-$default_port}"

# 询问域名，并支持沿用或清除
if [ -n "$DEPLOYED_DOMAIN" ]; then
    default_domain="$DEPLOYED_DOMAIN"
    read -p "👉 请输入解析好的域名 (直接回车将沿用旧域名 $default_domain, 输入空格清除域名): " INPUT_DOMAIN
    if [ "$INPUT_DOMAIN" = " " ]; then
        DOMAIN=""
    else
        DOMAIN="${INPUT_DOMAIN:-$default_domain}"
    fi
else
    read -p "👉 请输入解析好的域名 (若建纯IP节点，请直接回车跳过): " DOMAIN
fi

if [ -z "$DOMAIN" ]; then
    read -p "👉 请输入伪装/SNI域名 (直接回车默认使用 $MASQUERADE_DOMAIN): " INPUT_MASQ
    MASQUERADE_DOMAIN="${INPUT_MASQ:-$MASQUERADE_DOMAIN}"
fi
echo "=========================================================="

# 更新并合并节点部署状态
if [ "$CHOICE" -eq 1 ]; then
    DEPLOYED_IPV6="true"
    if [ "$DEPLOYED_IPV4" = "true" ]; then
        echo "ℹ️ 检测到您已部署过 IPv4 节点，本次操作将同时保留/更新 IPv4 和 IPv6 节点。"
    fi
elif [ "$CHOICE" -eq 2 ]; then
    DEPLOYED_IPV4="true"
    if [ "$DEPLOYED_IPV6" = "true" ]; then
        echo "ℹ️ 检测到您已部署过 IPv6 节点，本次操作将同时保留/更新 IPv4 和 IPv6 节点。"
    fi
elif [ "$CHOICE" -eq 3 ]; then
    DEPLOYED_IPV4="true"
    DEPLOYED_IPV6="true"
fi

# 2. 根据合并后的状态获取公网 IP 地址 (基于 awk + cut 提取)
IP4=""
IP6=""

if [ "$DEPLOYED_IPV6" = "true" ]; then
    echo "🔍 正在获取公网 IPv6 地址..."
    IP6=$(curl -sS6 --max-time 3 https://api64.ipify.org || curl -sS6 --max-time 3 https://ident.me)
    if [ -z "$IP6" ]; then
        IP6=$(ip -6 addr show | grep 'inet6' | awk '{print $2}' | cut -d'/' -f1 | grep -v '^::1' | grep -v '^fe80' | head -n 1)
    fi
    echo "🌐 检测到 IPv6 地址: ${IP6:-[未检测到]}"
fi

if [ "$DEPLOYED_IPV4" = "true" ]; then
    echo "🔍 正在获取公网 IPv4 地址..."
    IP4=$(curl -sS4 --max-time 3 https://ifconfig.me || curl -sS4 --max-time 3 https://api.ipify.org)
    if [ -z "$IP4" ]; then
        IP4=$(ip -4 addr show | grep 'inet' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d'/' -f1 | head -n 1)
    fi
    echo "🌐 检测到 IPv4 地址: ${IP4:-[未检测到]}"
fi

# 检查 IP 是否成功获取
if [ -z "$DOMAIN" ]; then
    if [ "$DEPLOYED_IPV6" = "true" ] && [ -z "$IP6" ]; then
        echo "⚠️ 警告：未检测到公网 IPv6 地址，IPv6 节点可能无法正常工作！"
    fi
    if [ "$DEPLOYED_IPV4" = "true" ] && [ -z "$IP4" ]; then
        echo "⚠️ 警告：未检测到公网 IPv4 地址，IPv4 节点可能无法正常工作！"
    fi
    if [ -z "$IP4" ] && [ -z "$IP6" ]; then
        echo "❌ 错误：未能检测到任何公网 IP 地址，部署终止。"
        exit 1
    fi
fi

# 3. 系统内核与 UDP 缓冲区速度优化
echo "[1/4] 正在注入高性能 UDP 调优参数并开启 BBR..."
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
# 强制即时载入优化参数
sysctl -p /etc/sysctl.d/99-hy2-performance.conf >/dev/null 2>&1
sysctl --system >/dev/null 2>&1

# 调整网卡队列长度
for dev in /sys/class/net/*; do
    if [ -d "$dev" ]; then
        dev_name=$(basename "$dev")
        ip link set dev "$dev_name" txqueuelen 5000 >/dev/null 2>&1 || ifconfig "$dev_name" txqueuelen 5000 >/dev/null 2>&1
    fi
done

# 清理防火墙
if command -v ufw > /dev/null; then ufw disable >/dev/null 2>&1; fi
if command -v systemctl > /dev/null; then systemctl stop firewalld >/dev/null 2>&1 && systemctl disable firewalld >/dev/null 2>&1; fi
iptables -F && iptables -X && iptables -P INPUT ACCEPT
if command -v ip6tables > /dev/null; then ip6tables -F && ip6tables -X && ip6tables -P INPUT ACCEPT; fi

if command -v apt-get >/dev/null; then
  apt-get update -y >/dev/null 2>&1 && apt-get install -y curl openssl wget psmisc >/dev/null 2>&1
elif command -v yum >/dev/null; then
  yum makecache -y >/dev/null 2>&1 && yum install -y curl openssl wget psmisc >/dev/null 2>&1
fi

# 4. 下载官方脚本到本地运行
echo "[2/4] 正在安全下载并安装 Hysteria 2 官方最新核心..."
curl -fsSL https://get.hy2.sh -o /etc/hy2_auto/install_hy2.sh
if [ ! -f "/etc/hy2_auto/install_hy2.sh" ]; then
    echo "❌ 错误：未能从官方源下载安装脚本，请检查 VPS 的网络连接！"
    exit 1
fi
if ! bash /etc/hy2_auto/install_hy2.sh </dev/null >/etc/hy2_auto/install.log 2>&1; then
    echo "❌ 错误：Hysteria 2 核心安装失败！"
    echo "📋 官方安装日志如下："
    cat /etc/hy2_auto/install.log
    exit 1
fi
rm -f /etc/hy2_auto/install_hy2.sh

# 5. TLS 证书与加速服务配置
echo "[3/4] 正在配置 TLS 证书与加速服务..."
if [ -z "$DOMAIN" ]; then
    # 无域名自签名证书，CN设置为伪装域名
    openssl req -x509 -nodes -newkey rsa:2048 -keyout /etc/hysteria/server.key -out /etc/hysteria/server.crt -days 3650 -subj "/CN=$MASQUERADE_DOMAIN" >/dev/null 2>&1
    SNI_PARAM="?sni=$MASQUERADE_DOMAIN&insecure=1"
else
    # 有域名，申请真实 Let's Encrypt 证书
    if [ "$DOMAIN" != "$DEPLOYED_DOMAIN" ] || [ ! -f /etc/hysteria/server.key ] || [ ! -f /etc/hysteria/server.crt ]; then
        echo "🌐 正在使用 acme.sh 申请/更新域名证书..."
        if [ ! -d ~/.acme.sh ]; then
            curl -sSL https://get.acme.sh | sh -s email=myhy2remote@gmail.com
        fi
        ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
        ~/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone
        ~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" --key-file "/etc/hysteria/server.key" --fullchain-file "/etc/hysteria/server.crt"
    fi
    SNI_PARAM="?sni=$DOMAIN"
fi

# 确保证书文件生成成功
if [ ! -f /etc/hysteria/server.key ] || [ ! -f /etc/hysteria/server.crt ]; then
    echo "❌ 错误：TLS 证书文件不存在，配置生成失败！"
    exit 1
fi

# 写入 Hysteria 2 配置文件，默认开启 salamander 流量混淆
cat << EOF_HY2_YAML > /etc/hysteria/config.yaml
listen: :$PORT
tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key
auth:
  type: password
  password: $PASSWORD
obfs:
  type: salamander
  salamander:
    password: $PASSWORD
EOF_HY2_YAML

chown -R hysteria:hysteria /etc/hysteria
chmod 755 /etc/hysteria; chmod 644 /etc/hysteria/server.crt; chmod 600 /etc/hysteria/server.key

# 清理可能残留的 Hysteria 进程并启动
echo "🛑 正在清理残留端口占用..."
systemctl stop hysteria 2>/dev/null
systemctl stop hysteria-server 2>/dev/null
pkill -9 hysteria 2>/dev/null

echo "🔄 正在启动 Hysteria 2 服务..."
systemctl daemon-reload
systemctl enable hysteria-server >/dev/null 2>&1

if ! systemctl restart hysteria-server; then
    echo "❌ 错误：Hysteria 2 服务启动命令执行失败！"
    echo "📋 诊断日志："
    journalctl -u hysteria-server --no-pager -n 15
    exit 1
fi

sleep 2
if ! systemctl is-active --quiet hysteria-server; then
    echo "❌ 错误：Hysteria 2 服务未能成功保持运行！"
    echo "📋 服务当前状态："
    systemctl status hysteria-server --no-pager
    exit 1
fi
echo "✅ Hysteria 2 服务启动成功，目前正在后台正常运行。"

# 6. 精准拼接有效格式链接 (附加混淆参数)
rm -f /etc/hy2_auto/links.txt
CURRENT_LINKS=""

# 辅助写入链接的函数，同时记录到 links.txt 和本次输出中
add_link() {
    local link="$1"
    local is_for_current="$2"
    echo "$link" >> /etc/hy2_auto/links.txt
    if [ "$is_for_current" = "true" ]; then
        if [ -z "$CURRENT_LINKS" ]; then
            CURRENT_LINKS="$link"
        else
            CURRENT_LINKS="${CURRENT_LINKS}
${link}"
        fi
    fi
}

# 如果配置了域名，输出真正的域名直连节点，并提供 IP 直连但通过域名 TLS 验证的辅助节点
if [ -n "$DOMAIN" ]; then
    # 1. 输出域名直连节点（主机名为域名，由客户端自动解析双栈或单栈）
    if [ "$DEPLOYED_IPV4" = "true" ] && [ "$DEPLOYED_IPV6" = "true" ]; then
        # 既然现在是双栈，如果本次操作是 1 (纯IPv6) 或 2 (纯IPv4) 或 3 (双栈)，这个双栈域名节点对本次操作都是有效的
        add_link "hy2://$PASSWORD@$DOMAIN:$PORT?sni=$DOMAIN&obfs=salamander&obfs-password=$PASSWORD#Hy2_域名双栈_自动选择" "true"
    elif [ "$DEPLOYED_IPV6" = "true" ]; then
        local is_curr="false"
        if [ "$CHOICE" -eq 1 ] || [ "$CHOICE" -eq 3 ]; then is_curr="true"; fi
        add_link "hy2://$PASSWORD@$DOMAIN:$PORT?sni=$DOMAIN&obfs=salamander&obfs-password=$PASSWORD#Hy2_域名_纯IPv6" "$is_curr"
    elif [ "$DEPLOYED_IPV4" = "true" ]; then
        local is_curr="false"
        if [ "$CHOICE" -eq 2 ] || [ "$CHOICE" -eq 3 ]; then is_curr="true"; fi
        add_link "hy2://$PASSWORD@$DOMAIN:$PORT?sni=$DOMAIN&obfs=salamander&obfs-password=$PASSWORD#Hy2_域名_纯IPv4" "$is_curr"
    fi

    # 2. 输出 IP 直连域名验证节点（主机名为 IP，TLS 握手使用域名 SNI，安全无报警，方便强制指定线路）
    if [ "$DEPLOYED_IPV4" = "true" ] && [ -n "$IP4" ]; then
        local is_curr="false"
        if [ "$CHOICE" -eq 2 ] || [ "$CHOICE" -eq 3 ]; then is_curr="true"; fi
        add_link "hy2://$PASSWORD@$IP4:$PORT?sni=$DOMAIN&obfs=salamander&obfs-password=$PASSWORD#Hy2_IPv4_域名验证版" "$is_curr"
    fi
    if [ "$DEPLOYED_IPV6" = "true" ] && [ -n "$IP6" ]; then
        local is_curr="false"
        if [ "$CHOICE" -eq 1 ] || [ "$CHOICE" -eq 3 ]; then is_curr="true"; fi
        add_link "hy2://$PASSWORD@[$IP6]:$PORT?sni=$DOMAIN&obfs=salamander&obfs-password=$PASSWORD#Hy2_IPv6_域名验证版" "$is_curr"
    fi
else
    # 无域名时，输出以 IP 为主机的“纯IP自签混淆版”链接
    if [ "$DEPLOYED_IPV4" = "true" ] && [ -n "$IP4" ]; then
        local is_curr="false"
        if [ "$CHOICE" -eq 2 ] || [ "$CHOICE" -eq 3 ]; then is_curr="true"; fi
        add_link "hy2://$PASSWORD@$IP4:$PORT?sni=$MASQUERADE_DOMAIN&insecure=1&obfs=salamander&obfs-password=$PASSWORD#Hy2_纯IPv4_自签混淆版" "$is_curr"
    fi
    if [ "$DEPLOYED_IPV6" = "true" ] && [ -n "$IP6" ]; then
        local is_curr="false"
        if [ "$CHOICE" -eq 1 ] || [ "$CHOICE" -eq 3 ]; then is_curr="true"; fi
        add_link "hy2://$PASSWORD@[$IP6]:$PORT?sni=$MASQUERADE_DOMAIN&insecure=1&obfs=salamander&obfs-password=$PASSWORD#Hy2_纯IPv6_自签混淆版" "$is_curr"
    fi
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

# 7. 最终终端纯净输出
echo " "
echo "=========================================================="
echo "🎉 Hysteria 2 节点加速部署完成！请复制导入本次新增/更新节点："
echo "=========================================================="
if [ -n "$CURRENT_LINKS" ]; then
    echo "$CURRENT_LINKS"
else
    echo "❌ 节点链接生成失败，请确认您选择的 IP 类型是否在 VPS 上真实存在。"
fi
echo "=========================================================="
echo "💡 后续在 VPS 窗口随时输入快捷命令 [ sd ] 即可查看所有有效节点"
echo " "
exit 0
