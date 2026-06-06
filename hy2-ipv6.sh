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

# 读取已有状态
if [ -f "$STATE_FILE" ]; then
    source "$STATE_FILE" 2>/dev/null
fi

# 从现有 config.yaml 提取端口和密码（若存在）
EXISTING_PORT=""
EXISTING_PASSWORD=""
if [ -f "/etc/hysteria/config.yaml" ]; then
    # 提取端口号：匹配 listen: 字段，提取最后一个冒号后的数字，并清理空格和特殊字符
    EXISTING_PORT=$(grep -E '^\s*listen:' /etc/hysteria/config.yaml | awk -F ':' '{print $NF}')
    EXISTING_PORT=$(echo "$EXISTING_PORT" | tr -dc '0-9')
    
    # 提取密码：匹配 password: 字段，提取后面的内容并清理空格和引号
    EXISTING_PASSWORD=$(grep -E '^\s*password:' /etc/hysteria/config.yaml | awk '{print $NF}' | tr -d '[:space:]"')
fi

# 如果有旧密码则沿用，否则生成新密码
if [ -n "$EXISTING_PASSWORD" ]; then
    PASSWORD="$EXISTING_PASSWORD"
    echo "ℹ️ 检测到已存在节点密码，脚本将沿用旧密码以保持客户端配置有效。"
else
    PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
fi

echo "=========================================================="
echo "    Hysteria 2 高性能分流版（多节点共存与进程强杀版）"
echo "=========================================================="
echo " 1. 部署/增加【纯 IPv6】高性能节点"
echo " 2. 部署/增加【纯 IPv4】高性能节点"
echo " 3. 部署【IPv4 & IPv6 双栈】节点"
echo " 4. 彻底卸载 Hysteria 2"
echo "=========================================================="
read -p "请选择操作 [1-4]: " CHOICE

if [ "$CHOICE" -eq 4 ]; then
    echo "🧹 正在卸载服务并清理环境..."
    
    # 1. 尝试使用官方卸载程序卸载核心与系统服务
    if [ -f "/usr/local/bin/hysteria" ]; then
        echo "🔄 正在调用官方卸载脚本..."
        curl -fsSL https://get.hy2.sh -o /etc/hy2_auto/uninstall_hy2.sh 2>/dev/null
        if [ -f "/etc/hy2_auto/uninstall_hy2.sh" ]; then
            bash /etc/hy2_auto/uninstall_hy2.sh --remove </dev/null >/dev/null 2>&1
            rm -f /etc/hy2_auto/uninstall_hy2.sh
        fi
    fi

    # 2. 停止并禁用所有可能冲突的服务并强杀进程
    systemctl stop hysteria 2>/dev/null
    systemctl disable hysteria 2>/dev/null
    systemctl stop hysteria-server 2>/dev/null
    systemctl disable hysteria-server 2>/dev/null
    pkill -9 hysteria 2>/dev/null
    rm -f /etc/systemd/system/hysteria-server.service
    rm -f /etc/systemd/system/hysteria-server@.service
    systemctl daemon-reload

    # 3. 清理二进制文件和快捷命令
    rm -f /usr/local/bin/hysteria /usr/local/bin/sd

    # 4. 彻底清理已创建的系统用户和组
    if id "hysteria" &>/dev/null; then
        echo "👤 正在清理 hysteria 系统用户..."
        userdel -r hysteria 2>/dev/null
    fi

    # 5. 清理配置和状态文件夹
    rm -rf /etc/hysteria /etc/hy2_auto
    
    echo "✅ Hysteria 2 已彻底卸载并清理残留环境！"
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

# 2. 根据合并后的状态获取公网 IP 地址
IP4=""
IP6=""

if [ "$DEPLOYED_IPV6" = "true" ]; then
    echo "🔍 正在获取公网 IPv6 地址..."
    IP6=$(curl -sS6 --max-time 3 https://api64.ipify.org || curl -sS6 --max-time 3 https://ident.me)
    if [ -z "$IP6" ]; then
        IP6=$(ip -6 addr show | grep -oP '(?<=inet6\s)[a-f0-9:]+' | grep -v '^::1' | grep -v '^fe80' | head -n 1)
    fi
fi

if [ "$DEPLOYED_IPV4" = "true" ]; then
    echo "🔍 正在获取公网 IPv4 地址..."
    IP4=$(curl -sS4 --max-time 3 https://ifconfig.me || curl -sS4 --max-time 3 https://api.ipify.org)
    if [ -z "$IP4" ]; then
        IP4=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n 1)
    fi
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
# 极大增加最大 and 默认缓冲区大小，支持高带宽延迟积 (BDP)
net.core.rmem_max=67108864
net.core.wmem_max=67108864
net.core.rmem_default=33554432
net.core.wmem_default=33554432

# 增加网卡接收队列的最大数据包数，防止 UDP 高速传输时丢包
net.core.netdev_max_backlog=100000

# 优化连接跟踪最大值，防止高并发连接时丢包
net.netfilter.nf_conntrack_max=1048576

# TCP/UDP 内存调优
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
net.ipv4.udp_rmem_min=16384
net.ipv4.udp_wmem_min=16384

# IP分片内存限制，避免高速 UDP 分片丢失导致重传
net.ipv4.ipfrag_high_thresh=26214400
net.ipv4.ipfrag_low_thresh=19660800
net.ipv6.ip6frag_high_thresh=26214400
net.ipv6.ip6frag_low_thresh=19660800

# 开启 BBR 拥塞控制算法
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF_SYSCTL
sysctl --system >/dev/null 2>&1

# 调整网卡队列长度消除瓶颈
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

# 4. 下载官方脚本到本地运行，增加运行诊断
echo "[2/4] 正在安全下载并安装 Hysteria 2 官方最新核心..."
curl -fsSL https://get.hy2.sh -o /etc/hy2_auto/install_hy2.sh
if [ ! -f "/etc/hy2_auto/install_hy2.sh" ]; then
    echo "❌ 错误：未能从官方源下载安装脚本，请检查 VPS 的网络连接！"
    exit 1
fi

# 运行并记录日志，方便在安装出错时查看原因
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
    # 无域名时，若证书已存在则无需重新生成
    if [ ! -f /etc/hysteria/server.key ] || [ ! -f /etc/hysteria/server.crt ] || [ -n "$DEPLOYED_DOMAIN" ]; then
        openssl req -x509 -nodes -newkey rsa:2048 -keyout /etc/hysteria/server.key -out /etc/hysteria/server.crt -days 3650 -subj "/CN=Anonymity" >/dev/null 2>&1
    fi
    SNI_PARAM="?sni=Anonymity&insecure=1"
else
    # 有域名时，若域名发生变化或证书文件缺失，才重新申请证书以避免 Let's Encrypt 频率限制
    if [ "$DOMAIN" != "$DEPLOYED_DOMAIN" ] || [ ! -f /etc/hysteria/server.key ] || [ ! -f /etc/hysteria/server.crt ]; then
        echo "🌐 正在使用 acme.sh 申请/更新域名证书..."
        if [ ! -d ~/.acme.sh ]; then
            curl -sSL https://get.acme.sh | sh -s email=myhy2remote@gmail.com
        fi
        ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
        ~/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone
        ~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" --key-file "/etc/hysteria/server.key" --fullchain-file "/etc/hysteria/server.crt"
    else
        echo "ℹ️ 检测到域名未发生变化且证书已存在，跳过证书申请。"
    fi
    SNI_PARAM="?sni=$DOMAIN"
fi

# 确保证书文件生成成功
if [ ! -f /etc/hysteria/server.key ] || [ ! -f /etc/hysteria/server.crt ]; then
    echo "❌ 错误：TLS 证书文件不存在，配置生成失败！"
    exit 1
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

# 预先清理可能残留占用该端口的旧 hysteria 进程
echo "🛑 正在停止并清理可能残留的 Hysteria 进程，释放端口..."
systemctl stop hysteria 2>/dev/null
systemctl stop hysteria-server 2>/dev/null
pkill -9 hysteria 2>/dev/null

# 检测端口占用
port_occupied=false
if command -v ss &>/dev/null; then
    if ss -ulnp | grep -q ":$PORT "; then
        port_occupied=true
    fi
elif command -v netstat &>/dev/null; then
    if netstat -ulnp | grep -q ":$PORT "; then
        port_occupied=true
    fi
fi

if [ "$port_occupied" = "true" ]; then
    echo "⚠️ 警告：检测到端口 $PORT UDP 已被其他非 Hysteria 服务占用！"
    echo "📋 占用端口的进程信息如下："
    if command -v ss &>/dev/null; then
        ss -ulnp | grep ":$PORT "
    else
        netstat -ulnp | grep ":$PORT "
    fi
    echo "💡 提示：如果该端口被 Nginx/Caddy (HTTP/3) 或其他代理服务占用，Hysteria 将启动失败。请换用其他端口重新运行脚本。"
fi

# 启动并进行状态检测
echo "🔄 正在启动 Hysteria 2 服务..."
systemctl daemon-reload
systemctl enable hysteria-server >/dev/null 2>&1

if ! systemctl restart hysteria-server; then
    echo "❌ 错误：Hysteria 2 服务启动命令执行失败！"
    echo "📋 诊断日志："
    journalctl -u hysteria-server --no-pager -n 30
    exit 1
fi

# 稍等 2 秒等待服务初始化绑定端口
sleep 2
if ! systemctl is-active --quiet hysteria-server; then
    echo "❌ 错误：Hysteria 2 服务未能成功保持运行！"
    echo "📋 服务当前状态："
    systemctl status hysteria-server --no-pager
    echo "📋 详细系统日志："
    journalctl -u hysteria-server --no-pager -n 30
    exit 1
fi
echo "✅ Hysteria 2 服务启动成功，目前正在后台正常运行。"

# 6. 精准拼接有效格式链接
rm -f /etc/hy2_auto/links.txt

if [ -n "$DOMAIN" ]; then
    echo "hy2://$PASSWORD@$DOMAIN:$PORT$SNI_PARAM#Hy2_域名加速版" >> /etc/hy2_auto/links.txt
else
    # 结合已部署的协议类型生成相应链接
    if [ "$DEPLOYED_IPV4" = "true" ] && [ "$DEPLOYED_IPV6" = "true" ]; then
        [ -n "$IP6" ] && echo "hy2://$PASSWORD@[$IP6]:$PORT$SNI_PARAM#Hy2_双栈IPv6_加速版" >> /etc/hy2_auto/links.txt
        [ -n "$IP4" ] && echo "hy2://$PASSWORD@$IP4:$PORT$SNI_PARAM#Hy2_双栈IPv4_加速版" >> /etc/hy2_auto/links.txt
    elif [ "$DEPLOYED_IPV6" = "true" ] && [ -n "$IP6" ]; then
        echo "hy2://$PASSWORD@[$IP6]:$PORT$SNI_PARAM#Hy2_纯IPv6_加速版" >> /etc/hy2_auto/links.txt
    elif [ "$DEPLOYED_IPV4" = "true" ] && [ -n "$IP4" ]; then
        echo "hy2://$PASSWORD@$IP4:$PORT$SNI_PARAM#Hy2_纯IPv4_加速版" >> /etc/hy2_auto/links.txt
    fi
fi

# 保存本次部署的状态
cat << EOF_STATE > "$STATE_FILE"
DEPLOYED_IPV4="$DEPLOYED_IPV4"
DEPLOYED_IPV6="$DEPLOYED_IPV6"
DEPLOYED_DOMAIN="$DOMAIN"
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
