#!/bin/bash

# 检查是否为 Root 用户
if [ "$EUID" -ne 0 ]; then
  echo "❌ 错误：请使用 root 用户运行此脚本！"
  exit 1
fi

mkdir -p /etc/hy2_auto

# 1. 自动生成随机配置
PORT=$(shuf -i 10000-60000 -n 1)
PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
IP4=$(curl -sS4 --max-time 3 https://ifconfig.me || curl -sS4 --max-time 3 https://api.ipify.org)
IP6=$(curl -sS6 --max-time 3 https://api64.ipify.org || curl -sS6 --max-time 3 https://ident.me)

# 2. 静默初始化环境与内核优化
echo "[1/4] 正在优化系统内核网络参数..."
cat << 'EOF_SYSCTL' > /etc/sysctl.d/99-hy2-tuning.conf
net.core.rmem_max=8388608
net.core.wmem_max=8388608
EOF_SYSCTL
sysctl --system >/dev/null 2>&1

# 强力清理防火墙
if command -v ufw > /dev/null; then ufw disable >/dev/null 2>&1; fi
if command -v systemctl > /dev/null; then systemctl stop firewalld >/dev/null 2>&1 && systemctl disable firewalld >/dev/null 2>&1; fi
iptables -F && iptables -X && iptables -P INPUT ACCEPT
if command -v ip6tables > /dev/null; then ip6tables -F && ip6tables -X && ip6tables -P INPUT ACCEPT; fi

if command -v apt-get >/dev/null; then
  apt-get update -y >/dev/null 2>&1 && apt-get install -y curl openssl wget >/dev/null 2>&1
elif command -v yum >/dev/null; then
  yum makecache -y >/dev/null 2>&1 && yum install -y curl openssl wget >/dev/null 2>&1
fi

# 3. 安装官方核心与配置自签名证书
echo "[2/4] 正在下载并安装 Hysteria 2 官方核心..."
mkdir -p /etc/hysteria
bash <(curl -fsSL https://get.hy2.sh) >/dev/null 2>&1

echo "[3/4] 正在配置自签名 TLS 证书与服务..."
openssl req -x509 -nodes -newkey rsa:2048 -keyout /etc/hysteria/server.key -out /etc/hysteria/server.crt -days 3650 -subj "/CN=Anonymity" >/dev/null 2>&1

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
systemctl daemon-reload && systemctl enable hysteria-server && systemctl restart hysteria-server >/dev/null 2>&1

# 4. 生成快捷查看命令 sd
cat << 'EOF_SHOW' > /usr/local/bin/sd
#!/bin/bash
if [ -f "/etc/hy2_auto/links.txt" ]; then
    echo "=========================================================="
    echo "📋 Hysteria 2 节点链接列表："
    echo "=========================================================="
    cat /etc/hy2_auto/links.txt
    echo "=========================================================="
else
    echo "❌ 未找到节点配置信息！"
fi
EOF_SHOW
chmod +x /usr/local/bin/sd

# 5. 拼接节点链接并存盘
rm -f /etc/hy2_auto/links.txt
if [ -n "$IP6" ]; then
    echo "hy2://$PASSWORD@[$IP6]:$PORT?sni=Anonymity&insecure=1#Hy2_IPv6_Auto" >> /etc/hy2_auto/links.txt
fi
if [ -n "$IP4" ]; then
    echo "hy2://$PASSWORD@$IP4:$PORT?sni=Anonymity&insecure=1#Hy2_IPv4_Auto" >> /etc/hy2_auto/links.txt
fi

# 6. 【严谨核心】直接在当前终端强行打印输出，绝不刷新屏幕
echo " "
echo "=========================================================="
echo -e "\033[32m🎉 Hysteria 2 远程节点部署成功！链接如下：\033[0m"
echo "=========================================================="
if [ -f "/etc/hy2_auto/links.txt" ]; then
    cat /etc/hy2_auto/links.txt
else
    echo "❌ 链接文件生成失败，请检查 IP 获取是否正常。"
fi
echo "=========================================================="
echo -e "💡 \033[33m后续在 VPS 窗口随时输入快捷命令 [ sd ] 即可再次查看\033[0m"
echo " "
