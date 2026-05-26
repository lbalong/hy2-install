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
echo "    Sing-Box 官方原生规范：VLESS-Reality 满血版 (联动 sd)"
echo "=========================================================="
echo " 1. 安装/更新 VLESS-Reality 节点 (16MB内核超频 + TFO免握手版)"
echo " 2. 查看当前已建节点链接汇总 (快捷命令: sd)"
echo " 3. 彻底卸载 VLESS-Reality 服务"
echo "=========================================================="
read -p "请选择操作 [1-3]: " CHOICE

# 提取公共核心变量
IP=$(curl -sS4 https://ifconfig.me || curl -sS4 https://api.ipify.org)

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

# 🌟 优化一：100% 榨干 TCP 流速的 16MB 巨型网络管道
init_env() {
    echo "🚀 正在向内核物理注入 BBR + 16MB 满血网络超频补丁..."
    cat << 'EOF_SYSCTL' > /etc/sysctl.d/99-vless-bbr.conf
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

    echo "🔓 正在物理清理内部防火墙残留..."
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
    echo "📋 当前 VPS 已保存的节点链接汇总 (Hy2 vs TUIC vs Reality)"
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
    local default_p=443  # Reality 本命首选 443
    
    if [ -n "$cached_port" ]; then
        read -p "📋 检测到历史缓存端口 [$cached_port]，是否直接复用？[Y/n]: " CONFIRM
        if [ "$CONFIRM" != "n" ] && [ "$CONFIRM" != "N" ]; then
            echo "$cached_port"
            return 0
        fi
    fi
    
    read -p "👉 请输入监听端口 (强烈推荐直接回车用本命 443 端口伪装): " INPUT_PORT
    echo "${INPUT_PORT:-$default_p}"
}

case $CHOICE in
    1)
        init_env
        PORT=$(get_port)
        
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

        # 动态生成密钥对
        UUID=$(/usr/local/bin/sing-box generate uuid 2>/dev/null || cat /proc/sys/kernel/random/uuid)
        KEY_PAIR=$(/usr/local/bin/sing-box generate reality-keypair)
        PRIVATE_KEY=$(echo "$KEY_PAIR" | grep "PrivateKey" | awk '{print $2}' | tr -d '"')
        PUBLIC_KEY=$(echo "$KEY_PAIR" | grep "PublicKey" | awk '{print $2}' | tr -d '"')
        SHORT_ID=$(openssl rand -hex 8)
        DEST_SERVER="www.microsoft.com"

        # 🌟 优化二：入站配置强行挂载 tcp_fast_open 与 tcp_multi_path 极速起步外挂
        cat << EOF > /etc/sing-box/config.json
{
  "log": {
    "level": "info"
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-reality-in",
      "listen": "0.0.0.0",
      "listen_port": $PORT,
      "tcp_fast_open": true,
      "tcp_multi_path": true,
      "users": [
        {
          "uuid": "$UUID",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "$DEST_SERVER",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "$DEST_SERVER",
            "server_port": 443
          },
          "private_key": "$PRIVATE_KEY",
          "short_id": [
            "$SHORT_ID"
          ]
        }
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
Description=Sing-Box VLESS-Reality Service
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
        
        # 动态组装完全体链接
        GEO_TAG=$(get_geo_tag)
        REALITY_LINK="vless://$UUID@$IP:$PORT?security=reality&sni=$DEST_SERVER&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID&flow=xtls-rprx-vision&type=tcp&headerType=none#Reality_${GEO_TAG}"
        
        touch /etc/hy2_tuic/saved_links.txt
        sed -i '/#Reality_/d' /etc/hy2_tuic/saved_links.txt 2>/dev/null
        sed -i '/#AnyTLS_/d' /etc/hy2_tuic/saved_links.txt 2>/dev/null
        echo "$REALITY_LINK" >> /etc/hy2_tuic/saved_links.txt
        
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
        sed -i '/#Reality_/d' /etc/hy2_tuic/saved_links.txt 2>/dev/null
        echo "✅ VLESS-Reality (Sing-Box) 环境已彻底清洗干净！"
        ;;
    *)
        exit 1
        ;;
esac
