#!/bin/bash

# 检查是否为 Root 用户
if [ "$EUID" -ne 0 ]; then
  echo "❌ 错误：请使用 root 用户运行此脚本！"
  exit 1
fi

mkdir -p /etc/hy2_auto

# 1. 获取随机配置
PORT=$(shuf -i 10000-60000 -n 1)
PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)

echo "[1/4] 正在获取本地及公网 IP 地址..."

# 网络接口尝试获取 IP
IP4=$(curl -sS4 --max-time 2 https://ifconfig.me || curl -sS4 --max-time 2 https://api.ipify.org)
IP6=$(curl -sS6 --max-time 2 https://api64.ipify.org || curl -sS6 --max-time 2 https://ident.me)

# 【严谨升级】保底逻辑：如果 curl 失败，直接从本地网卡提取
if [ -z "$IP4" ]; then
    IP4=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n 1)
fi
if [ -z "$IP6" ]; then
    IP6=$(ip -6 addr show | grep -oP '(?<=inet6\s)[a-f0-9:]+' | grep -v '^::1' | grep -v '^fe80' | head -n 1)
fi

# 2. 内核优化与防火墙清理
echo "[2/4] 正在优化系统内核网络参数并放行防火墙..."
cat << 'EOF_SYSCTL' > /etc/sysctl.d/99-hy2-tuning.conf
net.core.rmem_max=8388608
net.core.wmem_max=8388608
EOF_SYSCTL
sysctl --system >/dev/null 2>&1

if command -v ufw > /dev/null; then ufw disable >/dev/null 2>&1; fi
if command -v systemctl > /dev/null; then systemctl stop firewalld >/dev/null 2>&1 && systemctl disable firewalld >/dev/null 2>&1; fi
iptables -F && iptables -X && iptables -P INPUT ACCEPT
if command -v ip6tables > /dev/null; then ip6tables -F && ip6tables -X && ip6tables -P INPUT ACCEPT; fi

if command -v apt-get >/dev/null; then
  apt-get update -y >/dev/null 2>&1 && apt-get install -y curl openssl wget >/dev/null 2>&1
elif command -v yum >/dev/null; then
  yum makecache -y >/dev/null 2>&1 && yum install -y curl openssl wget >/dev/null 2>&1
fi

# 3. 安装官方核心
echo "[3/4] 正在下载并安装 Hysteria 2 官方核心（若卡住请检查VPS海外网络）..."
mkdir -p /etc/hysteria
# 放开静默，以便观察官方脚本是否报错
bash <(curl -fsSL https://get.hy2.sh)

# 4. 配置证书与服务
echo "[4/4] 正在配置自签名 TLS 证书与服务..."
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

# 5. 写入快捷查看脚本
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

# 6. 生成链接（移除 if 条件限制，强行写入，哪怕 IP 是空的也能暴露出格式问题）
rm -f /etc/hy2_auto/links.txt
echo "hy2://$PASSWORD@[$IP6]:$PORT?sni=Anonymity&insecure=1#Hy2_IPv6" >> /etc/hy2_auto/links.txt
echo "hy2://$PASSWORD@$IP4:$PORT?sni=Anonymity&insecure=1#Hy2_IPv4" >> /etc/hy2_auto/links.txt

# 7. 强行无条件终端打印
echo " "
echo "=========================================================="
echo -e "\033[32m🎉 脚本流运行完毕！最终终端打印测试：\033[0m"
echo "=========================================================="
echo "解析到的 IPv6 变量为: [$IP6]"
echo "解析到的 IPv4 变量为: [$IP4]"
echo "监听端口为: [$PORT]"
echo "----------------------------------------------------------"
echo "👉 最终拼接生成的节点链接如下："
cat /etc/hy2_auto/links.txt
echo "=========================================================="
echo -e "💡 \033[33m后续在 VPS 窗口随时输入快捷命令 [ sd ] 即可再次查看\033[0m"
echo " "
