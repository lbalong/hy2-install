cat << 'EOF' > /tmp/hy2_old.sh
#!/bin/bash

# 检查是否为 Root 用户
if [ "$EUID" -ne 0 ]; then
  echo "错误：请使用 root 用户运行此脚本！"
  exit 1
fi

echo "=========================================="
echo "    Hysteria 2 自动化双模一键脚本 V3.1 (隔离修正版)"
echo "=========================================="
echo " 1. 安装 纯 IP 自签名版 (100% 成功 / 适合不折腾)"
echo " 2. 安装 域名正规证书版 (智能校验 / 网页伪装 / 自动续签)"
echo "=========================================="
read -p "请选择安装模式 [1-2]: " CHOICE

# 1. 获取 VPS 本机公网 IP 和生成 16 位强密码
IP=$(curl -sS4 https://ifconfig.me || curl -sS4 https://ipinfo.io/ip || curl -sS4 https://api.ipify.org)
PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)

if [ -z "$IP" ]; then
  echo "❌ 错误：无法获取服务器公网 IP，请检查网络连接。"
  exit 1
fi

# 2. 允许用户完全自定义端口
DEFAULT_PORT=$(shuf -i 10000-65000 -n 1)
echo "------------------------------------------"
read -p "👉 请输入节点监听端口 (直接回车使用随机端口 $DEFAULT_PORT): " PORT
if [ -z "$PORT" ]; then
    PORT=$DEFAULT_PORT
    echo "🎲 检测到输入为空，已为您无缝启用自动随机端口: $PORT"
fi
echo "------------------------------------------"

# 3. 速度优化（调优 Linux 内核 UDP 缓冲区）
echo "正在注入内核加速参数（优化 UDP 缓冲区）..."
cat << EOF_TUNING > /etc/sysctl.d/99-hysteria2-tuning.conf
net.core.rmem_max=8388608
net.core.wmem_max=8388608
EOF_TUNING
sysctl --system >/dev/null 2>&1

# 4. 防火墙优化
echo "正在清空本地防火墙残留规则并建立通信通道..."
if command -v ufw > /dev/null; then
    ufw allow $PORT/udp >/dev/null 2>&1
    [ "$CHOICE" -eq 2 ] && ufw allow 80/tcp >/dev/null 2>&1
    ufw reload >/dev/null 2>&1
    ufw disable >/dev/null 2>&1
fi

if command -v firewall-cmd > /dev/null; then
    firewall-cmd --zone=public --add-port=$PORT/udp --permanent >/dev/null 2>&1
    [ "$CHOICE" -eq 2 ] && firewall-cmd --zone=public --add-port=80/tcp --permanent >/dev/null 2>&1
    firewall-cmd --reload >/dev/null 2>&1
fi

iptables -F
iptables -X
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT
iptables -I INPUT -p udp --dport $PORT -j ACCEPT
[ "$CHOICE" -eq 2 ] && iptables -I INPUT -p tcp --dport 80 -j ACCEPT

# 5. 安装必要依赖
echo "正在安装基础依赖..."
if command -v apt-get >/dev/null; then
  apt-get update && apt-get install -y curl openssl wget iptables socat cron
elif command -v yum >/dev/null; then
  yum makecache && yum install -y curl openssl wget iptables socat crontabs
fi

# 6. 调用官方脚本安装 Hysteria 2
echo "正在调用官方脚本安装 Hysteria 2 核心..."
mkdir -p /etc/hysteria
bash <(curl -fsSL https://get.hy2.sh)

# 7. 根据用户选择，切入不同的证书与配置流
if [ "$CHOICE" -eq 1 ]; then
    echo "正在生成 10 年期自签名 TLS 证书..."
    openssl req -x509 -nodes -newkey rsa:2048 \
      -keyout /etc/hysteria/server.key \
      -out /etc/hysteria/server.crt \
      -days 3650 \
      -subj "/CN=www.bing.com"

    cat << EOF_CONF1 > /etc/hysteria/config.yaml
listen: :$PORT
tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key
auth:
  type: password
  password: $PASSWORD
EOF_CONF1

elif [ "$CHOICE" -eq 2 ]; then
    while true; do
        read -p "👉 请输入已解析到本机的完整域名 (例如 sg.099889.xyz): " DOMAIN
        if [ -z "$DOMAIN" ]; then
            echo "❌ 域名不能为空，请重新输入！"
            continue
        fi
        
        echo "🔄 正在请求多路公网 DNS 校验域名解析..."
        DOMAIN_IP=$(curl -s4 "https://1.1.1.1/dns-query?name=$DOMAIN" -H "accept: application/dns-json" | grep -oE '"data":"[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}"' | head -n 1 | awk -F'"' '{print $4}')
        [ -z "$DOMAIN_IP" ] && DOMAIN_IP=$(getent ahosts "$DOMAIN" | awk '{print $1}' | head -n 1)

        if [ "$DOMAIN_IP" = "$IP" ]; then
            echo "✅ 校验通过！域名 [$DOMAIN] 已精准解析到本机公网 IP ($IP)"
            break
        else
            echo "❌ 校验失败：当前域名解析出的 IP 为 [$DOMAIN_IP]，与本机 IP [$IP] 不符，请检查解析！"
            echo "=========================================="
        fi
    done

    echo "🔄 正在申请 Let's Encrypt 正规证书..."
    curl -sSL https://get.acme.sh | sh -s email=myhy2@gmail.com
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
    ~/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone
    
    if [ $? -eq 0 ]; then
        ~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" --key-file /etc/hysteria/server.key --fullchain-file /etc/hysteria/server.crt
        echo "✅ 正规证书下发成功！"
    else
        echo "❌ 证书签发失败！自动降级为 10 年期自签名证书保底..."
        openssl req -x509 -nodes -newkey rsa:2048 -keyout /etc/hysteria/server.key -out /etc/hysteria/server.crt -days 3650 -subj "/CN=$DOMAIN"
    fi

    cat << EOF_CONF2 > /etc/hysteria/config.yaml
listen: :$PORT
tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key
auth:
  type: password
  password: $PASSWORD
EOF_CONF2
fi

# 🌟 修复新版官方核心带来的低权限用户读不到证书死火的暗坑
chown -R hysteria:hysteria /etc/hysteria 2>/dev/null
chmod 644 /etc/hysteria/server.crt 2>/dev/null
chmod 600 /etc/hysteria/server.key 2>/dev/null

# 8. 启动服务
systemctl daemon-reload
systemctl enable hysteria-server
systemctl restart hysteria-server

# 9. 输出看板
clear
echo "=========================================="
echo "🎉 恭喜老哥！原版 Hysteria 2 满血完全体点火成功！"
echo "=========================================="
if [ "$CHOICE" -eq 1 ]; then
    echo "👉 分享链接: hy2://$PASSWORD@$IP:$PORT?insecure=1&sni=www.bing.com#Hy2_IP_自签"
else
    echo "👉 分享链接: hy2://$PASSWORD@$DOMAIN:$PORT?sni=$DOMAIN#Hy2_Domain_正规"
fi
echo "=========================================="
EOF
chmod +x /tmp/hy2_old.sh
/tmp/hy2_old.sh
