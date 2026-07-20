#!/bin/bash

# 检查是否为 Root 用户
if [ "$EUID" -ne 0 ]; then
  echo "❌ 错误：请使用 root 用户运行此脚本！"
  exit 1
fi

CONFIG="/usr/local/etc/xray/config.json"
BACKUP="/usr/local/etc/xray/config.json.bak"

if [ ! -f "$CONFIG" ]; then
    echo "❌ 找不到 Xray 配置文件！请确认节点已安装。"
    exit 1
fi

# ================= 卸载/恢复直连 =================
remove_warp() {
    echo "=========================================="
    echo "  正在恢复默认直连路由..."
    echo "=========================================="
    cp "$CONFIG" "$BACKUP"
    
    # 使用 jq 剔除 routing，恢复基础 outbound
    jq '.outbounds = [{"protocol": "freedom", "tag": "direct"}] | del(.routing)' "$CONFIG" > /tmp/pure.json
    mv /tmp/pure.json "$CONFIG"
    
    systemctl restart xray
    echo "✅ 已清除 WARP 分流，所有流量现已恢复 VPS 原生 IP 直连！"
    exit 0
}

# ================= 安装 WARP 出站 =================
install_warp() {
    echo "=========================================="
    echo "  正在配置 WARP 流媒体/AI 专属出口"
    echo "=========================================="
    
    # 1. 安装必备工具
    echo "⚙️ 安装 jq 和 wget..."
    if command -v apt-get >/dev/null; then
        apt-get update -y && apt-get install -y jq wget curl
    elif command -v yum >/dev/null; then
        yum install -y jq wget curl
    fi

    # 2. 获取 WARP 密钥 (使用 wgcf)
    echo "🔑 正在向 Cloudflare 申请 WARP 账户..."
    ARCH=$(uname -m)
    if [ "$ARCH" = "x86_64" ]; then
        WGCF_ARCH="amd64"
    elif [ "$ARCH" = "aarch64" ]; then
        WGCF_ARCH="arm64"
    else
        echo "❌ 不支持的 CPU 架构"
        exit 1
    fi

    mkdir -p /etc/warp && cd /etc/warp
    wget -qO wgcf "https://github.com/ViRb3/wgcf/releases/download/v2.2.22/wgcf_2.2.22_linux_${WGCF_ARCH}"
    chmod +x wgcf

    if [ ! -f "wgcf-account.toml" ]; then
        yes | ./wgcf register --accept-tos >/dev/null 2>&1
    fi
    ./wgcf generate >/dev/null 2>&1

    if [ ! -f "wgcf-profile.conf" ]; then
        echo "❌ WARP 账户申请失败，可能是 Cloudflare 当前限制了该 IP 段的注册。"
        exit 1
    fi

    # 提取私钥和 IP
    PRIVATE_KEY=$(grep 'PrivateKey' wgcf-profile.conf | awk '{print $3}')
    IPV4=$(grep 'Address' wgcf-profile.conf | head -1 | awk '{print $3}')
    IPV6=$(grep 'Address' wgcf-profile.conf | tail -1 | awk '{print $3}')

    if [ -z "$PRIVATE_KEY" ]; then
        echo "❌ 提取 WARP 密钥失败！"
        exit 1
    fi

    echo "✅ WARP 账户申请成功！正在进行微创注入..."
    cp "$CONFIG" "$BACKUP"

    # 3. 使用 jq 注入路由和出站 (绝对不碰 inbounds)
    jq --arg pkey "$PRIVATE_KEY" --arg v4 "$IPV4" --arg v6 "$IPV6" '
      .outbounds = [
        {"protocol": "freedom", "tag": "direct"},
        {"protocol": "blackhole", "tag": "block"},
        {
          "tag": "warp",
          "protocol": "wireguard",
          "settings": {
            "secretKey": $pkey,
            "address": [$v4, $v6],
            "peers": [
              {
                "publicKey": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
                "endpoint": "engage.cloudflareclient.com:2408"
              }
            ],
            "mtu": 1280
          }
        }
      ] |
      .routing = {
        "domainStrategy": "IPIfNonMatch",
        "rules": [
          {
            "type": "field",
            "outboundTag": "warp",
            "domain": [
              "geosite:netflix",
              "geosite:openai",
              "geosite:disney",
              "geosite:primevideo",
              "geosite:hbo",
              "geosite:google"
            ]
          },
          {
            "type": "field",
            "outboundTag": "direct",
            "network": "tcp,udp"
          }
        ]
      }
    ' "$CONFIG" > /tmp/warp_injected.json

    mv /tmp/warp_injected.json "$CONFIG"
    
    systemctl restart xray
    sleep 2
    
    if ! systemctl is-active --quiet xray; then
        echo "❌ Xray 启动失败，可能是配置合并出错！正在恢复备份..."
        mv "$BACKUP" "$CONFIG"
        systemctl restart xray
        exit 1
    fi

    echo "=========================================="
    echo " 🎉 注入成功！"
    echo " 当前状态：所有入站节点未受任何影响。"
    echo " 路由策略：ChatGPT、Netflix 等流媒体流量将自动走 WARP，其他流量走 VPS 宽带直连。"
    echo "=========================================="
}

# ================= 主菜单 =================
echo "=========================================="
echo "    Xray 独立辅助插件: WARP 路由分流"
echo "=========================================="
echo "  1. 开启 WARP 流媒体/AI 专属解锁"
echo "  2. 卸载 WARP (恢复纯 VPS 直连)"
echo "  0. 退出"
echo "=========================================="
read -p "👉 请输入选项 [0-2]: " CHOICE

case $CHOICE in
  1) install_warp ;;
  2) remove_warp ;;
  0) exit 0 ;;
  *) echo "❌ 无效输入" ;;
esac
