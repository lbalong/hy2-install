#!/bin/bash

# 检查是否为 Root 用户
if [ "$EUID" -ne 0 ]; then
  echo "错误：请使用 root 用户运行此脚本！"
  exit 1
fi

# 铁律第一步：开局直接物理创建核心目录，确保所有账本读写绝不踩空
mkdir -p /etc/sing-box
mkdir -p /etc/hy2_tuic

echo "=========================================================="
echo "    Sing-Box 官方原生规范：AnyTLS 满血超频脚本 (联动 sd)"
echo "=========================================================="
echo " 1. 安装/更新 AnyTLS 节点 (16MB内核超频 + 智能证书复用)"
echo " 2. 查看当前已建节点链接汇总 (快捷命令: sd)"
echo " 3. 彻底卸载 AnyTLS 服务"
echo "=========================================================="
read -p "请选择操作 [1-3]: " CHOICE

# 提取公共核心变量
IP=$(curl -sS4 https://ifconfig.me || curl -sS4 https://api.ipify.org)
PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)

if [ -z "$IP" ] && [ "$CHOICE" -eq 1 ]; then
  echo "❌ 错误：无法获取服务器公网 IP，请检查网络连接。"
  exit 1
fi

# 智能获取服务商与地理位置标签
get_geo_tag() {
    local geo_info=$(curl -s --max-time 3 http://ip-api.com/json/)
    if [ -n "$geo_info" ] && echo "$geo_info" | grep -q '"status":"success"'; then
        local isp=$(echo "$geo_info" | grep -oE '"isp":"[^"]+"' | cut -d'"' -f4 | awk '{print $1}')
        local country=$(echo "$geo_info" | grep -oE '"country":"[^"]+"' | cut -d'"' -f4 | tr -d ' ')
        isp=$(echo "$isp" | tr -cd 'A-Za-z0-9_')
        country=$(echo "$country" | tr -cd 'A-Za-z0-9_')
        echo "${isp}_${country}"
    else
        echo "VPS_Node"
    fi
}

# 核心环境清洗与 TCP/BBR 深度性能榨干 (16MB 满血超频版)
init_env() {
    echo "🚀 正在向内核物理注入 BBR + 16MB 满血网络超频补丁..."
    cat << 'EOF_SYSCTL' > /etc/sysctl.d/99-anytls-bbr.conf
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max = 16772160
net.core.wmem_max = 16772160
net.ipv4.tcp_rmem = 4096 87380 16772160
net.ipv4.tcp_wmem = 4096 65536 16772160
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_fastopen = 3
EOF_SYSCTL
    sysctl --system >/dev/null 2>&1

    echo "📦 正在清洗基础网络与解压依赖组件..."
    if command -v apt-get >/dev/null; then
      apt-get update -qq && apt-get install -y -qq curl wget tar openssl net-tools iptables
    elif command -v yum >/dev/null; then
      yum install -y -q curl wget tar openssl net-tools iptables
    fi

    echo "🔓 正在物理清理内部防火墙残留（全开接单状态）..."
    if command -v ufw > /dev/null; then ufw disable >/dev/null 2>&1; fi
    if command -v systemctl > /dev/null; then systemctl stop firewalld >/dev/null 2>&1 && systemctl disable firewalld >/dev/null 2>&1; fi
    iptables -F && iptables -X
    iptables -P INPUT ACCEPT && iptables -P FORWARD ACCEPT && iptables -P OUTPUT ACCEPT
}

# 部署/更新联动专属快捷查询命令 sd
deploy_shortcut() {
    cat << 'EOF_SHOW' > /usr/local/bin/sd
#!/bin/bash
if [ -f "/etc/hy2_tuic/saved_links.txt" ]; then
    clear
    echo "=========================================================="
    echo "📋 当前 VPS 已保存的节点链接汇总 (Hy2 vs TUIC vs AnyTLS)"
    echo "=========================================================="
    cat /etc/hy2_tuic/saved_links.txt
    echo "=========================================================="
else
    echo "❌ 未找到已保存的节点信息，请先使用脚本创建节点！"
fi
EOF_SHOW
    chmod +x /usr/local/bin/sd
}

# 端口锁定机制
get_port() {
    local cached_port=""
    if [ -f "/etc/sing-box/config.json" ]; then
        cached_port=$(grep -oE '"listen_port": [0-9]+' /etc/sing-box/config.json | head -n 1 | awk '{print $2}')
    fi
    local default_p=38443
    
    if [ -n "$cached_port" ]; then
        read -p "📋 检测到历史缓存 AnyTLS 端口 [$cached_port]，是否直接复用？[Y/n]: " CONFIRM
        if [ "$CONFIRM" != "n" ] && [ "$CONFIRM" != "N" ]; then
            echo "$cached_port"
            return 0
        fi
    fi
    
    read -p "👉 请输入 AnyTLS 监听端口 (直接回车使用默认 $default_p): " INPUT_PORT
    echo "${INPUT_PORT:-$default_p}"
}

# 智能证书同步与保底签发机制
sync_cert() {
    local target_dir="/etc/sing-box"
    DOMAIN="anytls.vps.node"
    if [ -f "/etc/hy2_tuic/vps_domain.txt" ]; then
        DOMAIN=$(cat /etc/hy2_tuic/vps_domain.txt)
    fi

    if [ -f "/etc/hysteria/server.crt" ]; then
        echo "📥 检测到 Hysteria 2 已持有正规证书，正在执行无缝复制复用..."
        cp /etc/hysteria/server.crt "$target_dir/server.crt"
        cp /etc/hysteria/server.key "$target_dir/server.key"
        IS_SELF_SIGNED=false
    elif [ -f "/etc/tuic/server.crt" ]; then
        echo "📥 检测到 TUIC 已持有正规证书，正在执行无缝复制复用..."
        cp /etc/tuic/server.crt "$target_dir/server.crt"
        cp /etc/tuic/server.key "$target_dir/server.key"
        IS_SELF_SIGNED=false
    else
        echo "📋 未检测到本地正规域名证书，正在现场秒发 10 年期官方合规自签名证书保底..."
        openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
          -keyout "$target_dir/server.key" \
          -out "$target_dir/server.crt" \
          -subj "/CN=$DOMAIN" >/dev/null 2>&1
        IS_SELF_SIGNED=true
    fi
}

case $CHOICE in
    1)
        init_env
        PORT=$(get_port)
        sync_cert
        
        echo "🚀 正在下载 Sing-Box 官方原生二进制核心..."
        ARCH=$(uname -m)
        SB_ARCH="amd64"
        [ "$ARCH" = "aarch64" ] && SB_ARCH="arm64"
        
        LATEST_VER=$(curl -s https://api.github.com/repos/sagernet/sing-box/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        VERSION=${LATEST_VER#v}
        
        wget -qO /tmp/sing-box.tar.gz "https://github.com/sagernet/sing-box/releases/download/v${VERSION}/sing-box-${VERSION}-linux-${SB_ARCH}.tar.gz"
        cd /tmp && tar -zxf sing-box.tar.gz
        mv sing-box-${VERSION}-linux-${SB_ARCH}/sing-box /usr/local/bin/sing-box
        chmod +x /usr/local/bin/sing-box
        rm -rf sing-box*

        # 🌟 核心修正：100% 对齐官方 inbound 标准格式，顺手塞入流速解封外挂
        cat << EOF > /etc/sing-box/config.json
{
  "log": {
    "level": "info"
  },
  "inbounds": [
    {
      "type": "anytls",
      "tag": "anytls-in",
      "listen": "0.0.0.0",
      "listen_port": $PORT,
      "tcp_fast_open": true,
      "tcp_multi_path": true,
      "users": [
        {
          "name": "qiutonglin",
          "password": "$PASSWORD"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "$DOMAIN",
        "certificate_path": "/etc/sing-box/server.crt",
        "key_path": "/etc/sing-box/server.key"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
EOF

        echo "🔄 正在进行官方内核合规性核验..."
        /usr/local/bin/sing-box check -c /etc/sing-box/config.json

        # 注入标准 Systemd 后台守护
        cat << EOF > /etc/systemd/system/sing-box.service
[Unit]
Description=Sing-Box AnyTLS Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/sing-box
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

        systemctl daemon-reload
        systemctl enable sing-box >/dev/null 2>&1
        systemctl restart sing-box
        
        # 动态组装完全体链接并合流进总账本
        # 对齐最新 AnyTLS 客户端规范识别规则
        GEO_TAG=$(get_geo_tag)
        if [ "$IS_SELF_SIGNED" = true ]; then
            ANYTLS_LINK="anytls://$PASSWORD@$IP:$PORT?sni=$DOMAIN&allowInsecure=1#AnyTLS_${GEO_TAG}"
        else
            ANYTLS_LINK="anytls://$PASSWORD@$IP:$PORT?sni=$DOMAIN#AnyTLS_${GEO_TAG}"
        fi
        
        touch /etc/hy2_tuic/saved_links.txt
        sed -i '/#AnyTLS_/d' /etc/hy2_tuic/saved_links.txt 2>/dev/null
        echo "$ANYTLS_LINK" >> /etc/hy2_tuic/saved_links.txt
        
        deploy_shortcut
        clear
        /usr/local/bin/sd
        ;;

    2)
        if [ -f "/usr/local/bin/sd" ]; then
            /usr/local/bin/sd
        else
            echo "❌ 未找到已保存的节点信息！"
        fi
        ;;

    3)
        echo "🧹 正在彻底剥离 Sing-Box 服务端与残留环境..."
        systemctl stop sing-box 2>/dev/null
        systemctl disable sing-box 2>/dev/null
        rm -f /etc/systemd/system/sing-box.service
        systemctl daemon-reload
        rm -f /usr/local/bin/sing-box
        rm -rf /etc/sing-box
        sed -i '/#AnyTLS_/d' /etc/hy2_tuic/saved_links.txt 2>/dev/null
        echo "✅ AnyTLS (Sing-Box) 环境已彻底清洗干净！"
        ;;
    *)
        exit 1
        ;;
esac
