#!/bin/bash

# 检查是否为 Root 用户
if [ "$EUID" -ne 0 ]; then
  echo "错误：请使用 root 用户运行此脚本！"
  exit 1
fi

# 铁律第一步：开局直接物理创建核心目录
mkdir -p /usr/local/etc/xray
mkdir -p /etc/cf_vless

echo "=========================================================="
echo "    Sing-Box 调优思路：VLESS + WS + Cloudflare 安全满血版"
echo "=========================================================="
echo " 1. 安装/更新 VLESS-WS 盾牌节点 (16MB 内核超频 + 智能记忆版)"
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

# 部署专属快捷查询命令 sd
deploy_shortcut() {
    cat << 'EOF_SHOW' > /usr/local/bin/sd
#!/bin/bash
CF_CONF="/etc/cf_vless/last_cfg.conf"
if [ -f "$CF_CONF" ]; then
    source "$CF_CONF"
    clear
    echo "=========================================================="
    echo "📋 您当前激活的 VLESS + Cloudflare 节点链接"
    echo "=========================================================="
    echo "👇 您的通用一键导入链接（已套小云朵安全防护版）："
    echo "vless://$LAST_UUID@$LAST_CF_DOMAIN:443?encryption=none&security=tls&sni=$LAST_CF_DOMAIN&type=ws&path=$LAST_WS_PATH#CF_Shield_$LAST_PORT"
    echo "=========================================================="
    echo "💡 极速超频通车指南："
    echo "1. 必须登录 Cloudflare 后台，把【小云朵】点亮（开启 Proxy）。"
    echo "2. 在 Cloudflare 的【SSL/TLS】菜单里，将加密模式改为【Flexible (灵活)】！"
    echo "3. 针对你的 1000M 电信宽带，建议在手机/电脑客户端的【伪装地址/Address】"
    echo "   栏里，填入优选的 CF 节点 IP（如 www.visa.com.sg 或 优选IP），速度能瞬间飙满！"
    echo "=========================================================="
else
    echo "❌ 未找到历史节点信息，请先选择 1 进行安装！"
fi
EOF_SHOW
    chmod +x /usr/local/bin/sd
}

case $CHOICE in
    1)
        init_env
        
        # 智能收集配置（带历史记忆）
        if [ -n "$LAST_CF_DOMAIN" ]; then
            read -p "👉 请输入你在 CF 托付的域名 (回车自动复用: $LAST_CF_DOMAIN): " CF_DOMAIN
            CF_DOMAIN=${CF_DOMAIN:-$LAST_CF_DOMAIN}
        else
            while true; do
                read -p "👉 请输入你在 Cloudflare 解析好的完整域名 (例如 cf.099889.xyz): " CF_DOMAIN
                if [ -n "$CF_DOMAIN" ]; then break; fi
            done
        fi

        # 端口锁定（必须在 Cloudflare 官方支持的标准 HTTP 端口集里挑：80, 8080, 8880, 2052, 2082, 2086, 2095）
        PORT=8080
        WS_PATH="/vless-cf-ws"
        
        # 保存本地账本
        echo "LAST_CF_DOMAIN=\"$CF_DOMAIN\"" > "$CONFIG_FILE"
        echo "LAST_UUID=\"$UUID\"" >> "$CONFIG_FILE"
        echo "LAST_PORT=\"$PORT\"" >> "$CONFIG_FILE"
        echo "LAST_WS_PATH=\"$WS_PATH\"" >> "$CONFIG_FILE"

        echo "🚀 正在拉取正规军 Xray 官方二进制核心..."
        bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)"

        # 写入 100% 对齐官方规范的 VLESS-WS 纯净入站配置
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
