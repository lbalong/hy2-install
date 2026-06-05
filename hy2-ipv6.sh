#!/bin/bash

# 检查是否为 Root 用户
if [ "$EUID" -ne 0 ]; then
  echo "❌ 错误：请使用 root 用户运行此脚本！"
  exit 1
fi

mkdir -p /etc/hy2_v6

echo "=========================================================="
echo "      Hysteria 2 纯血 IPv6/IPv4 远程部署脚本"
echo "=========================================================="
echo " 1. 安装/更新 Hysteria 2"
echo " 2. 查看当前节点链接 (快捷命令: sd)"
echo " 3. 彻底卸载 Hysteria 2"
echo "=========================================================="
read -p "请选择操作 [1-3]: " CHOICE

# 获取公网 IP（容错处理）
IP4=$(curl -sS4 --max-time 3 https://ifconfig.me || curl -sS4 --max-time 3 https://api.ipify.org)
IP6=$(curl -sS6 --max-time 3 https://api64.ipify.org || curl -sS6 --max-time 3 https://ident.me)
PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)

if [ -z "$IP4" ] && [ -z "$IP6" ] && [ "$CHOICE" -eq 1 ]; then
  echo "❌ 错误：无法获取服务器公网 IP，请检查网络连接。"
  exit 1
fi

init_env() {
    echo "正在优化内核 UDP 缓冲区..."
    cat << 'EOF_SYSCTL' > /etc/sysctl.d/99-hy2-tuning.conf
net.core.rmem_max=8388608
net.core.wmem_max=8388608
EOF_SYSCTL
    sysctl --system >/dev/null 2>&1

    echo "正在清理防火墙限制..."
    if command -v ufw > /dev/null; then ufw disable >/dev/null 2>&1; fi
    if command -v systemctl > /dev/null; then systemctl stop firewalld >/dev/null 2>&1 && systemctl disable firewalld >/dev/null 2>&1; fi
    iptables -F && iptables -X && iptables -P INPUT ACCEPT
    if command -v ip6tables > /dev/null; then
        ip6tables -F && ip6tables -X && ip6tables -P INPUT ACCEPT
    fi

    if command -v apt-get >/dev/null; then
      apt-get update && apt-get install -y curl openssl wget
    elif command -v yum >/dev/null; then
      yum makecache && yum install -y curl openssl wget
    fi
}

deploy_shortcut() {
    cat << 'EOF_SHOW' > /usr/local/bin/sd
#!/bash
if [ -f "/etc/hy2_v6/saved_links.txt" ]; then
    clear
    echo "=========================================================="
    echo "📋 当前 Hysteria 2 节点链接汇总"
    echo "=========================================================="
    cat /etc/hy2_v6/saved_links.txt
    echo "=========================================================="
else
    echo "❌ 未找到节点信息！"
fi
EOF_SHOW
    chmod +x /usr/local/bin/sd
}

case $CHOICE in
    1)
        # 1. 端口选择
        default_port=$(shuf -i 10000-60000 -n 1)
        read -p "👉 请输入监听端口 (默认 $default_port): " INPUT_PORT
        PORT="${INPUT_PORT:-$default_port}"

        # 2. 域名选择（核心改动：允许为空建纯IP节点）
        read -p "👉 请输入解析到此VPS的域名 (若建纯IP节点，请直接回车跳过): " DOMAIN

        init_env
        mkdir -p /etc/hysteria
        
        # 安装官方最新核心
        bash <(curl -fsSL https://get.hy2.sh)

        # 3. 证书签发/生成逻辑
        if [ -z "$DOMAIN" ]; then
            echo "自我说明：未输入域名，正在生成自签名证书（客户端需开启允许不安全连接）..."
            openssl req -x509 -nodes -newkey rsa:2048 -keyout /etc/hysteria/server.key -out /etc/hysteria/server.crt -days 3650 -subj "/CN=Anonymity" >/dev/null 2>&1
            SNI_PARAM="&insecure=1"
            SERVER_NAME="Anonymity"
        else
            echo "🔄 正在使用 acme.sh 申请 Let's Encrypt 证书..."
            curl -sSL https://get.acme.sh | sh -s email=myhy2remote@gmail.com
            ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
            ~/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone
            ~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" --key-file "/etc/hysteria/server.key" --fullchain-file "/etc/hysteria/server.crt"
            SNI_PARAM="&sni=$DOMAIN"
            SERVER_NAME="$DOMAIN"
        fi

        # 4. 生成配置文件（同时监听 IPv4 和 IPv6）
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
        systemctl daemon-reload && systemctl enable hysteria-server && systemctl restart hysteria-server

        # 5. 拼接并保存纯净版链接
        rm -f /etc/hy2_v6/saved_links.txt
        
        if [ -n "$DOMAIN" ]; then
            echo "hy2://$PASSWORD@$DOMAIN:$PORT?sni=$DOMAIN#Hy2_域名双栈" >> /etc/hy2_v6/saved_links.txt
        else
            if [ -n "$IP6" ]; then
                echo "hy2://$PASSWORD@[$IP6]:$PORT?sni=$SERVER_NAME$SNI_PARAM#Hy2_纯IPv6" >> /etc/hy2_v6/saved_links.txt
            fi
            if [ -n "$IP4" ]; then
                echo "hy2://$PASSWORD@$IP4:$PORT?sni=$SERVER_NAME$SNI_PARAM#Hy2_纯IPv4" >> /etc/hy2_v6/saved_links.txt
            fi
        fi

        deploy_shortcut
        clear
        /usr/local/bin/sd
        ;;

    2)
        if [ -f "/usr/local/bin/sd" ]; then /usr/local/bin/sd; else echo "❌ 未找到已保存的节点信息！"; fi
        ;;

    3)
        echo "🧹 正在卸载服务并清理环境..."
        systemctl stop hysteria-server 2>/dev/null
        systemctl disable hysteria-server 2>/dev/null
        rm -f /etc/systemd/system/hysteria-server.service
        systemctl daemon-reload
        rm -f /usr/local/bin/hysteria /usr/local/bin/sd
        rm -rf /etc/hysteria /etc/hy2_v6
        echo "✅ Hysteria 2 已彻底卸载！"
        ;;
    *) exit 1 ;;
esac
