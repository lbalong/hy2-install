#!/bin/bash

# 检查是否为 Root 用户
if [ "$EUID" -ne 0 ]; then
  echo "错误：请使用 root 用户运行此脚本！"
  exit 1
fi

# 铁律第一步：开局直接物理创建核心目录，确保所有账本读写绝不踩空
mkdir -p /usr/local/etc/xray
mkdir -p /etc/cf_vless

echo "=========================================================="
echo "    Cloudflare 小云朵避风港：VLESS + WS + TLS 终极一键版"
echo "=========================================================="
echo " 1. 安装/更新 VLESS-WS-TLS 节点 (内核超频 + 端口完全自定版)"
echo " 2. 查看当前已建节点链接汇总 (快捷命令: sd)"
echo " 3. 彻底卸载节点服务"
echo "=========================================================="
read -p "请选择操作 [1-3]: " CHOICE

# 提取公共核心变量
CONFIG_FILE="/etc/cf_vless/last_cfg.conf"
if [ -f "$CONFIG_FILE" ]; then source "$CONFIG_FILE"; fi

IP=$(curl -sS4 https://ifconfig.me || curl -sS4 https://api.ipify.org)
UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "6a82e704-9ac8-4fb8-bef1-6c9d7d7e390a")

if [ -z "$IP" ] && [ "$CHOICE" -eq 1 ]; then
  echo "❌ 错误：无法获取服务器公网 IP，请检查网络连接。"
  exit 1
fi

# 核心环境清洗与 TCP/BBR 深度性能超频 (16MB 巨型缓冲区)
init_env() {
    echo "🚀 正在向内核物理注入 BBR + 16MB 满血网络超频补丁..."
    cat << 'EOF_SYSCTL' > /etc/sysctl.d/99-cf-vless-bbr.conf
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

    echo "📦 正在清洗基础网络并安装基础组件..."
    if command -v apt-get >/dev/null; then
      apt-get update -qq && apt-get install -y -qq curl jq uuid-runtime iptables socat net-tools
    elif command -v yum >/dev/null; then
      yum makecache && yum install -y curl jq uuid-runtime iptables socat net-tools
    fi

    echo "🔓 正在物理放行内部防火墙端口..."
    if command -v ufw > /dev/null; then ufw disable >/dev/null 2>&1; fi
    if command -v systemctl > /dev/null; then systemctl stop firewalld >/dev/null 2>&1 && systemctl disable firewalld >/dev/null 2>&1; fi
    iptables -F && iptables -X
    iptables -P INPUT ACCEPT && iptables -P FORWARD ACCEPT && iptables -P OUTPUT ACCEPT
}

# 部署专属快捷查询命令 sd (彻底解除 443 死锁，你填什么，这里就输出什么)
deploy_shortcut() {
    cat << 'EOF_SHOW' > /usr/local/bin/sd
#!/bin/bash
CF_CONF="/etc/cf_vless/last_cfg.conf"
if [ -f "$CF_CONF" ]; then
    source "$CF_CONF"
    clear
    echo "=========================================================="
    echo "📋 当前已套【小云朵】的 VLESS-WS-TLS 满血节点导入链接"
    echo "=========================================================="
    echo "🔗 链接一：常规自主端口导入单"
    echo "vless://$LAST_UUID@$LAST_CF_DOMAIN:$LAST_PORT?encryption=none&security=tls&sni=$LAST_CF_DOMAIN&type=ws&path=$LAST_WS_PATH#CF_自定端口_$LAST_PORT"
    echo ""
    echo "🔥 链接二：大厂专线全自动优选速飙单 (🔥 强烈推荐此链接导入)"
    echo "vless://$LAST_UUID@www.visa.com.sg:$LAST_PORT?encryption=none&security=tls&sni=$LAST_CF_DOMAIN&type=ws&path=$LAST_WS_PATH&host=$LAST_CF_DOMAIN#CF_满血优选_$LAST_PORT"
    echo "=========================================================="
    echo "💡 极速通车核对单："
    echo " 1. 请确保你在 Cloudflare 后台的【DNS 记录】里已经把【小云朵】点亮（开启代理）。"
    echo " 2. 请确保在 CF 后台的【SSL/TLS】菜单里，将加密模式改为了【Full (完全)】或【Strict (严格)】！"
    echo " 3. 老哥直接复制上面的【链接二】导入客户端，即可直接通车，免去任何手动调校。"
    echo "=========================================================="
fi
EOF_SHOW
    chmod +x /usr/local/bin/sd
}

case $CHOICE in
    1)
        init_env
        
        # 智能收集域名
        while true; do
            read -p "👉 请输入你在 Cloudflare 解析好的完整域名 (例如 cf.099889.xyz): " CF_DOMAIN
            if [ -n "$CF_DOMAIN" ]; then break; fi
        done

        # 🌟 核心修复一：强制要求老哥纯手动输入端口，不搞任何擅自做主的越权指派
        while true; do
            echo "----------------------------------------------------------"
            echo "⚠️  注意：套小云朵且链接内保留自定端口，必须使用 CF 官方支持的 HTTPS 规范端口："
            echo "   👉 [ 443, 2053, 2083, 2087, 2096, 8443 ]"
            echo "----------------------------------------------------------"
            read -p "✍️ 请纯手动输入上面列表中的一个端口号: " PORT
            if [[ " 443 2053 2083 2087 2096 8443 " =~ " ${PORT} " ]] && [ -n "$PORT" ]; then
                break
            else
                echo "❌ 错误：输入的端口不在 Cloudflare 官方支持的 HTTPS 允许列表中，请重新输入！"
            fi
        done

        WS_PATH="/vless-cf-tls-ws"
        
        # 保存本地临时账本
        echo "LAST_CF_DOMAIN=\"$CF_DOMAIN\"" > "$CONFIG_FILE"
        echo "LAST_UUID=\"$UUID\"" >> "$CONFIG_FILE"
        echo "LAST_PORT=\"$PORT\"" >> "$CONFIG_FILE"
        echo "LAST_WS_PATH=\"$WS_PATH\"" >> "$CONFIG_FILE"

        # 🌟 核心修复二：现场通过 Let's Encrypt 摇号为你的域名下发正规军全套 TLS 证书
        echo "🔄 正在请求 Let's Encrypt 官方签发合规域名证书..."
        curl -sSL https://get.acme.sh | sh -s email=mycfvless@gmail.com
        ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
        ~/.acme.sh/acme.sh --issue -d "$CF_DOMAIN" --standalone
        
        if [ $? -ne 0 ] && [ ! -d "/root/.acme.sh/${CF_DOMAIN}_ecc" ] && [ ! -d "/root/.acme.sh/${CF_DOMAIN}" ]; then
            echo "❌ 证书申请彻底失败，请务必检查域名是否已解析成功，且 80 端口没有被占用！"
            exit 1
        fi
        
        # 稳妥锚定证书安装路径
        ~/.acme.sh/acme.sh --install-cert -d "$CF_DOMAIN" --key-file "/etc/cf_vless/server.key" --fullchain-file "/etc/cf_vless/server.crt"

        echo "🚀 正在拉取正规军 Xray 官方二进制核心..."
        bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)"

        # 🌟 核心修复三：写入 100% 对齐官方满血 HTTPS 规范的 VLESS + WS + TLS 纯净账本
        cat << EOF > /usr/local/etc/xray/config.json
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": $PORT,
      "listen": "0.0.0.0",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "level": 0
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "/etc/cf_vless/server.crt",
              "keyFile": "/etc/cf_vless/server.key"
            }
          ]
        },
        "wsSettings": {
          "path": "$WS_PATH"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOF

        # 强破权限并配置后台守护
        chmod 644 /usr/local/etc/xray/config.json
        chown -R nobody:nogroup /usr/local/etc/xray 2>/dev/null || chown -R nobody:nobody /usr/local/etc/xray 2>/dev/null
        
        systemctl daemon-reload
        systemctl enable xray >/dev/null 2>&1
        systemctl restart xray

        deploy_shortcut
        clear
        /usr/local/bin/sd
        ;;

    2)
        if [ -f "/usr/local/bin/sd" ]; then /usr/local/bin/sd; else echo "❌ 未找到节点配置！"; fi
        ;;

    3)
        echo "🧹 正在彻底物理剥离服务与清洗环境..."
        systemctl stop xray 2>/dev/null
        systemctl disable xray 2>/dev/null
        rm -rf /usr/local/bin/xray /usr/local/etc/xray /etc/cf_vless /usr/local/bin/sd
        echo "✅ 卸载清洗完成！"
        ;;
    *)
        exit 1
        ;;
esac
