#!/bin/bash
set -e

# 1. 系统架构检测与必要依赖清洗
ARCH=$(uname -m)
SB_ARCH="amd64"
[ "$ARCH" = "aarch64" ] && SB_ARCH="arm64"

echo "正在物理安装网络与解压基础工具..."
if command -v apt-get >/dev/null; then
    apt-get update -qq && apt-get install -y -qq curl wget tar openssl
elif command -v yum >/dev/null; then
    yum install -y -q curl wget tar openssl
fi

# 2. 动态捕获官方最新正规军 Sing-Box 核心
echo "正在从 GitHub 获取 Sing-Box 官方最新发行版..."
LATEST_VER=$(curl -s https://api.github.com/repos/sagernet/sing-box/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
VERSION=${LATEST_VER#v}
echo "成功锁定官方核心版本: v$VERSION"

echo "正在下载官方二进制压缩包..."
wget -qO /tmp/sing-box.tar.gz "https://github.com/sagernet/sing-box/releases/download/v${VERSION}/sing-box-${VERSION}-linux-${SB_ARCH}.tar.gz"

# 解压并物理安置核心程序
cd /tmp
tar -zxf sing-box.tar.gz
mv sing-box-${VERSION}-linux-${SB_ARCH}/sing-box /usr/local/bin/sing-box
chmod +x /usr/local/bin/sing-box
rm -rf sing-box*

# 3. 交互锁定端口与自动化生成对账参数
echo "=========================================================="
read -p "👉 请输入 AnyTLS 监听端口 (直接回车使用 38443): " INPUT_PORT
PORT="${INPUT_PORT:-38443}"

PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
IP=$(curl -sS4 https://ifconfig.me || curl -sS4 https://api.ipify.org)

# 核心黑科技：用官方内核现场捏出 REALITY 密钥对
echo "正在生成正规 REALITY 密钥对与 Short ID..."
KEYPAIR=$(/usr/local/bin/sing-box generate reality-keypair)
PRIVATE_KEY=$(echo "$KEYPAIR" | grep "Private key:" | awk '{print $3}')
PUBLIC_KEY=$(echo "$KEYPAIR" | grep "Public key:" | awk '{print $3}')
SHORT_ID=$(openssl rand -hex 8)

# 4. 物理写入符合官方绝对规范的 config.json
mkdir -p /etc/sing-box
cat << EOF > /etc/sing-box/config.json
{
  "log": {
    "level": "info"
  },
  "inbounds": [
    {
      "type": "anytls",
      "tag": "anytls-in",
      "listen": "::",
      "listen_port": $PORT,
      "users": [
        {
          "name": "qiutonglin",
          "password": "$PASSWORD"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "addons.mozilla.org",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "addons.mozilla.org",
            "port": 443
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

# 5. 注入标准的 Systemd 后台守护生命周期
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

# 刷新并物理点火启动
systemctl daemon-reload
systemctl enable sing-box >/dev/null 2>&1
systemctl restart sing-box

# 6. 瞬间对账清屏，交出核心资产
clear
echo "=========================================================="
echo "✅ AnyTLS + REALITY (Sing-Box 官方原生规范) 极简节点已通车！"
echo "=========================================================="
echo "服务器公网 IP : $IP"
echo "节点监听端口   : $PORT"
echo "AnyTLS 密码    : $PASSWORD"
echo "REALITY 公钥   : $PUBLIC_KEY"
echo "REALITY 短 ID  : $SHORT_ID"
echo "目标伪装域名   : addons.mozilla.org"
echo "=========================================================="
echo ""
echo "📋 客户端通用配置链接 (支持 Mihomo / Stash / Karing 直接导入)："
echo "anytls://$PASSWORD@$IP:$PORT?sni=addons.mozilla.org&pbk=$PUBLIC_KEY&sid=$SHORT_ID#AnyTLS_Reality_Node"
echo ""
echo "📋 如果你的客户端（如 v2rayN 纯文本模式）需要完整 JSON 格式："
cat << EOF
{
  "type": "anytls",
  "tag": "AnyTLS-Reality-Node",
  "server": "$IP",
  "server_port": $PORT,
  "password": "$PASSWORD",
  "tls": {
    "enabled": true,
    "server_name": "addons.mozilla.org",
    "utls": {
      "enabled": true,
      "fingerprint": "chrome"
    },
    "reality": {
      "enabled": true,
      "public_key": "$PUBLIC_KEY",
      "short_id": "$SHORT_ID"
    }
  }
}
EOF
echo "=========================================================="
