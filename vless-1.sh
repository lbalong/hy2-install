#!/bin/bash

set -e

echo "======================================"
echo " Cloudflare VPS 防直扫安全加固"
echo "======================================"

read -p "请输入你的业务端口(如8443): " PORT
PORT=${PORT:-8443}

echo ""
echo "安装依赖..."
apt update -y
apt install -y iptables-persistent curl

echo ""
echo "获取 Cloudflare IP 段..."
CF_V4=$(curl -s https://www.cloudflare.com/ips-v4)
CF_V6=$(curl -s https://www.cloudflare.com/ips-v6)

echo ""
echo "清空旧防火墙规则..."
iptables -F
iptables -X
ip6tables -F
ip6tables -X

echo ""
echo "设置默认策略：全部拒绝入站..."
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

ip6tables -P INPUT DROP
ip6tables -P FORWARD DROP
ip6tables -P OUTPUT ACCEPT

echo ""
echo "允许本地回环..."
iptables -A INPUT -i lo -j ACCEPT
ip6tables -A INPUT -i lo -j ACCEPT

echo ""
echo "允许已建立连接..."
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
ip6tables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

echo ""
echo "放行 SSH（防止锁机）"
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
ip6tables -A INPUT -p tcp --dport 22 -j ACCEPT

echo ""
echo "只放行业务端口：$PORT（仅Cloudflare）"

for ip in $CF_V4; do
    iptables -A INPUT -p tcp -s $ip --dport $PORT -j ACCEPT
done

for ip in $CF_V6; do
    ip6tables -A INPUT -p tcp -s $ip --dport $PORT -j ACCEPT
done

echo ""
echo "保存规则..."
netfilter-persistent save

echo ""
echo "======================================"
echo " 完成"
echo "======================================"
echo ""
echo "当前效果："
echo "- VPS 端口 $PORT 不再对公网直接开放"
echo "- 只允许 Cloudflare 回源访问"
echo "- 扫描器无法直接命中服务"
echo ""
echo "注意："
echo "- SSH(22) 已保留"
echo "- 如果你改端口，需要重新运行脚本"
echo ""
