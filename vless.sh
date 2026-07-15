#!/bin/bash

# 兼容管道与直接执行：优先打开终端到 fd 3，否则回退到 stdin
if [ -c /dev/tty ]; then
    exec 3</dev/tty
else
    exec 3<&0
fi

# 清空终端输入缓冲区，防止用户复制粘贴脚本时带入的多余换行导致首个 read 被跳过
if [ -t 3 ]; then
    while read -t 0.01 -r <&3; do :; done
fi

# 检查是否为 Root 用户
if [ "$EUID" -ne 0 ]; then
  echo "错误：请使用 root 用户运行此脚本！"
  exit 1
fi

# ─────────────────────────────────────────────────────────────────
# 全局变量 & 历史配置加载
# ─────────────────────────────────────────────────────────────────
SB_DIR="/etc/s-box"
SB_BIN="$SB_DIR/sing-box"
SB_CONFIG="$SB_DIR/config.json"
CONFIG_FILE="/etc/sd_vless_last.conf"

mkdir -p "$SB_DIR"

# 预先读取历史配置
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# 检测系统架构
case $(uname -m) in
    x86_64)  CPU="amd64" ;;
    aarch64) CPU="arm64" ;;
    armv7l)  CPU="armv7" ;;
    *) echo "❌ 不支持的架构: $(uname -m)" && exit 1 ;;
esac

# 检测包管理器
if command -v apt-get >/dev/null 2>&1; then
    PKG_MGR="apt"
elif command -v yum >/dev/null 2>&1; then
    PKG_MGR="yum"
elif command -v dnf >/dev/null 2>&1; then
    PKG_MGR="dnf"
else
    PKG_MGR="unknown"
fi

# ─────────────────────────────────────────────────────────────────
# 公共函数
# ─────────────────────────────────────────────────────────────────
install_deps() {
    echo "📦 正在安装必要的基础组件..."
    case "$PKG_MGR" in
        apt) apt-get update -y && apt-get install -y curl wget jq openssl iptables >/dev/null 2>&1 ;;
        yum) yum makecache -y && yum install -y curl wget jq openssl iptables >/dev/null 2>&1 ;;
        dnf) dnf makecache -y && dnf install -y curl wget jq openssl iptables >/dev/null 2>&1 ;;
        *) echo "⚠️ 未知包管理器，请手动安装 curl wget jq openssl" ;;
    esac
}

get_public_ip() {
    local ip=""
    ip=$(curl -s4m5 https://ifconfig.me 2>/dev/null) ||
    ip=$(curl -s4m5 https://ipinfo.io/ip 2>/dev/null) ||
    ip=$(curl -s4m5 https://api.ipify.org 2>/dev/null)
    echo "$ip"
}

install_singbox() {
    echo ""
    echo "════════════════════════════════════════════"
    echo " 📥 安装/更新 sing-box 内核"
    echo "════════════════════════════════════════════"

    # 获取最新版本号
    local sb_version
    sb_version=$(curl -Ls https://api.github.com/repos/SagerNet/sing-box/releases/latest | jq -r '.tag_name' 2>/dev/null | sed 's/^v//')
    if [ -z "$sb_version" ] || [ "$sb_version" = "null" ]; then
        # 备用方式
        sb_version=$(curl -Ls https://github.com/SagerNet/sing-box/releases/latest | grep -oP 'tag/v\K[0-9.]+' | head -n 1)
    fi
    if [ -z "$sb_version" ]; then
        echo "❌ 无法获取 sing-box 最新版本号，请检查网络"
        exit 1
    fi

    local sb_name="sing-box-${sb_version}-linux-${CPU}"
    local download_url="https://github.com/SagerNet/sing-box/releases/download/v${sb_version}/${sb_name}.tar.gz"

    echo "  ⏬ 正在下载 sing-box v${sb_version} (${CPU})..."
    curl -L -o "$SB_DIR/sing-box.tar.gz" -# --retry 2 "$download_url"

    if [ ! -f "$SB_DIR/sing-box.tar.gz" ]; then
        echo "❌ 下载失败，请检查网络连接或 GitHub 访问"
        exit 1
    fi

    tar xzf "$SB_DIR/sing-box.tar.gz" -C "$SB_DIR"
    mv "$SB_DIR/$sb_name/sing-box" "$SB_BIN"
    rm -rf "$SB_DIR/sing-box.tar.gz" "$SB_DIR/$sb_name"

    if [ ! -f "$SB_BIN" ]; then
        echo "❌ sing-box 二进制文件解压失败"
        exit 1
    fi

    chown root:root "$SB_BIN"
    chmod +x "$SB_BIN"

    local installed_ver
    installed_ver=$("$SB_BIN" version 2>/dev/null | awk '/version/{print $NF}')
    echo "  ✅ sing-box 内核安装成功，版本: ${installed_ver}"
}

create_service() {
    cat > /etc/systemd/system/sing-box.service <<SVCEOF
[Unit]
Description=sing-box service
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target

[Service]
User=root
WorkingDirectory=/root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
ExecStart=$SB_BIN run -c $SB_CONFIG
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=10
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
SVCEOF

    systemctl daemon-reload
    systemctl enable sing-box >/dev/null 2>&1
}

# ─────────────────────────────────────────────────────────────────
# 主菜单
# ─────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════════"
echo "   VLESS + Reality 极速版 (sing-box 内核 · 全面兼容 OpenWrt)"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "  1. 安装 / 重装 VLESS-Reality 节点"
echo "  2. 查看当前节点配置 (快捷命令: sd)"
echo "  3. 彻底卸载节点"
echo ""
echo "════════════════════════════════════════════════════════════"
read -p "请选择 [1-3]: " MENU_CHOICE <&3

# ─────────────────────────────────────────────────────────────────
# 选项 2：查看节点
# ─────────────────────────────────────────────────────────────────
if [ "$MENU_CHOICE" = "2" ]; then
    if [ -f /usr/local/bin/sd ]; then
        /usr/local/bin/sd
    else
        echo "❌ 未找到已安装的节点，请先选择 [1] 安装。"
    fi
    exit 0
fi

# ─────────────────────────────────────────────────────────────────
# 选项 3：卸载
# ─────────────────────────────────────────────────────────────────
if [ "$MENU_CHOICE" = "3" ]; then
    echo ""
    read -p "⚠️ 确认彻底卸载 VLESS-Reality 节点？[y/N]: " CONFIRM_UNINSTALL <&3
    if [[ ! "$CONFIRM_UNINSTALL" =~ ^[Yy]$ ]]; then
        echo "已取消。"
        exit 0
    fi
    systemctl stop sing-box 2>/dev/null || true
    systemctl disable sing-box 2>/dev/null || true
    rm -f /etc/systemd/system/sing-box.service
    systemctl daemon-reload
    rm -rf "$SB_DIR"
    rm -f "$CONFIG_FILE"
    rm -f /usr/local/bin/sd
    # 兼容清理旧 xray
    systemctl stop xray 2>/dev/null || true
    systemctl disable xray 2>/dev/null || true
    echo "✅ 卸载完成！所有配置和程序已清除。"
    exit 0
fi

# ─────────────────────────────────────────────────────────────────
# 选项 1：安装节点
# ─────────────────────────────────────────────────────────────────
if [ "$MENU_CHOICE" != "1" ]; then
    echo "❌ 无效选择"; exit 1
fi

echo ""
echo "════════════════════════════════════════════════════════════"
echo " 🚀 开始安装 VLESS-Reality (sing-box 内核)"
echo "════════════════════════════════════════════════════════════"

# 获取公网 IP
IP=$(get_public_ip)
if [ -z "$IP" ]; then
    echo "❌ 错误：无法获取服务器公网 IP，请检查网络连接。"
    exit 1
fi
echo "  🌐 服务器公网 IP: $IP"

# ─────── 域名选择 ─────────────────────────────────────────────────
if [ -n "$LAST_NEED_DOMAIN" ] && [[ ! "$LAST_NEED_DOMAIN" =~ ^[YyNn]$ ]]; then
    LAST_NEED_DOMAIN=""
fi

if [ -n "$LAST_DOMAIN" ]; then
    read -p "👉 检测到上次使用域名 $LAST_DOMAIN，是否继续使用？[Y/n] (回车默认 Y): " USE_LAST_DOMAIN <&3
    [ -z "$USE_LAST_DOMAIN" ] && USE_LAST_DOMAIN="y"
    
    if [[ "$USE_LAST_DOMAIN" =~ ^[Yy]$ ]]; then
        NEED_DOMAIN="y"
        DOMAIN="$LAST_DOMAIN"
    else
        read -p "👉 是否需要使用新域名连接？[Y/n] (输入 n 则使用纯 IP 模式，回车默认 Y): " NEED_DOMAIN <&3
        [ -z "$NEED_DOMAIN" ] && NEED_DOMAIN="y"
        if [[ "$NEED_DOMAIN" =~ ^[Yy]$ ]]; then
            read -p "👉 请输入已解析的完整域名 (例如 sg.099889.xyz): " DOMAIN <&3
            if [ -z "$DOMAIN" ]; then echo "❌ 错误：域名不能为空！"; exit 1; fi
        fi
    fi
else
    read -p "👉 是否需要使用域名连接？[Y/n] (回车默认 Y): " NEED_DOMAIN <&3
    [ -z "$NEED_DOMAIN" ] && NEED_DOMAIN="y"
    if [[ "$NEED_DOMAIN" =~ ^[Yy]$ ]]; then
        read -p "👉 请输入已解析的完整域名 (例如 sg.099889.xyz): " DOMAIN <&3
        if [ -z "$DOMAIN" ]; then echo "❌ 错误：域名不能为空！"; exit 1; fi
    fi
fi

if [[ "$NEED_DOMAIN" =~ ^[Yy]$ ]]; then
    TYPE="DOMAIN"
    echo "🔍 正在校验域名 DNS 解析..."
    DOMAIN_IP=$(getent ahosts "$DOMAIN" 2>/dev/null | head -n 1 | awk '{print $1}')
    if [ -n "$DOMAIN_IP" ] && [ "$DOMAIN_IP" != "$IP" ]; then
        echo "⚠️ 域名解析 IP ($DOMAIN_IP) 与 VPS IP ($IP) 不匹配"
        read -p "👉 确认继续？[Y/n] (回车默认 Y): " FORCE_INSTALL <&3
        [ -z "$FORCE_INSTALL" ] && FORCE_INSTALL="y"
        if [[ ! "$FORCE_INSTALL" =~ ^[Yy]$ ]]; then
            echo "❌ 已终止。"; exit 1
        fi
    else
        echo "✅ 域名解析验证通过"
    fi
else
    TYPE="IP"
fi

# ─────── 端口 ─────────────────────────────────────────────────────
if [ -n "$LAST_PORT" ]; then
    read -p "👉 节点端口 (回车沿用: $LAST_PORT): " PORT <&3
    [ -z "$PORT" ] && PORT=$LAST_PORT
else
    DEFAULT_PORT=$(shuf -i 10000-65000 -n 1)
    read -p "👉 节点端口 (回车随机: $DEFAULT_PORT): " PORT <&3
    [ -z "$PORT" ] && PORT=$DEFAULT_PORT
fi

# 检测端口占用
if ss -tlnp 2>/dev/null | grep -qw ":$PORT "; then
    echo "⚠️ 端口 $PORT 已被占用："
    ss -tlnp 2>/dev/null | grep -w ":$PORT "
    read -p "👉 是否强制继续？[Y/n] (回车默认 Y): " FORCE_PORT <&3
    [ -z "$FORCE_PORT" ] && FORCE_PORT="y"
    if [[ ! "$FORCE_PORT" =~ ^[Yy]$ ]]; then
        echo "❌ 已终止。"; exit 1
    fi
fi

# ─────── Reality SNI 目标选择 ────────────────────────────────────
echo ""
echo "════════════════════════════════════════════"
echo " 🎯 选择 Reality 伪装目标 (SNI)"
echo "════════════════════════════════════════════"
echo "  1. apple.com"
echo "  2. gateway.icloud.com      (Apple iCloud 网关)"
echo "  3. itunes.apple.com        (Apple iTunes)"
echo "  4. swdist.apple.com        (Apple 软件分发)"
echo "  5. www.microsoft.com       (Microsoft 官网)"
echo "  6. www.samsung.com         (Samsung 官网)"
echo "  7. dl.google.com           (Google 下载)"
echo "  8. 自定义输入"
echo "════════════════════════════════════════════"

DEST_OPTIONS=("apple.com" "gateway.icloud.com" "itunes.apple.com" "swdist.apple.com" "www.microsoft.com" "www.samsung.com" "dl.google.com")

if [ -n "$LAST_DEST" ]; then
    read -p "👉 请选择 [1-8] (回车沿用: $LAST_DEST): " DEST_CHOICE <&3
    if [ -z "$DEST_CHOICE" ]; then
        DEST_SERVER="$LAST_DEST"
    else
        if [ "$DEST_CHOICE" -ge 1 ] 2>/dev/null && [ "$DEST_CHOICE" -le 7 ]; then
            DEST_SERVER="${DEST_OPTIONS[$((DEST_CHOICE-1))]}"
        elif [ "$DEST_CHOICE" == "8" ]; then
            read -p "👉 请输入自定义 SNI 域名: " CUSTOM_DEST <&3
            [ -z "$CUSTOM_DEST" ] && echo "❌ 域名不能为空！" && exit 1
            DEST_SERVER="$CUSTOM_DEST"
        else
            echo "❌ 无效选项！"; exit 1
        fi
    fi
else
    read -p "👉 请选择 [1-8] (回车默认 1): " DEST_CHOICE <&3
    [ -z "$DEST_CHOICE" ] && DEST_CHOICE="1"
    if [ "$DEST_CHOICE" -ge 1 ] 2>/dev/null && [ "$DEST_CHOICE" -le 7 ]; then
        DEST_SERVER="${DEST_OPTIONS[$((DEST_CHOICE-1))]}"
    elif [ "$DEST_CHOICE" == "8" ]; then
        read -p "👉 请输入自定义 SNI 域名: " CUSTOM_DEST <&3
        [ -z "$CUSTOM_DEST" ] && echo "❌ 域名不能为空！" && exit 1
        DEST_SERVER="$CUSTOM_DEST"
    else
        echo "❌ 无效选项！"; exit 1
    fi
fi

echo "✅ Reality SNI: $DEST_SERVER"

# ─────────────────────────────────────────────────────────────────
# 开启系统 BBR 加速 (精简兼容版)
# ─────────────────────────────────────────────────────────────────
echo ""
echo "⚡ 正在开启 BBR 加速..."
cat <<SYSEOF > /etc/sysctl.d/99-vless-reality.conf
# 仅开启 BBR，移除激进的网络参数以保证最大兼容性
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
SYSEOF
sysctl --system >/dev/null 2>&1

# ─────────────────────────────────────────────────────────────────
# 安装基础依赖 & sing-box 内核
# ─────────────────────────────────────────────────────────────────
install_deps

# 停止旧服务（兼容 xray 迁移）
systemctl stop sing-box 2>/dev/null || true
systemctl stop xray 2>/dev/null || true

install_singbox

# ─────────────────────────────────────────────────────────────────
# 生成核心参数
# ─────────────────────────────────────────────────────────────────
echo ""
echo "🔐 正在生成密钥与参数..."

# UUID：复用已有或新生成
if [ -n "$LAST_UUID" ]; then
    UUID="$LAST_UUID"
    echo "  🔑 复用已有 UUID: ${UUID:0:8}..."
else
    UUID=$("$SB_BIN" generate uuid 2>/dev/null || cat /proc/sys/kernel/random/uuid)
    echo "  🔑 新 UUID: ${UUID:0:8}..."
fi

# Reality 密钥对
KEY_OUTPUT=$("$SB_BIN" generate reality-keypair 2>/dev/null)
if [ -z "$KEY_OUTPUT" ]; then
    echo "❌ 密钥对生成失败，请检查 sing-box 安装"
    exit 1
fi
PRIVATE_KEY=$(echo "$KEY_OUTPUT" | grep -i "PrivateKey" | awk '{print $NF}')
PUBLIC_KEY=$(echo "$KEY_OUTPUT" | grep -i "PublicKey" | awk '{print $NF}')

if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
    echo "❌ 密钥解析失败！密钥输出："
    echo "$KEY_OUTPUT"
    exit 1
fi
echo "  ✅ Reality 密钥对生成成功 (PubKey: ${PUBLIC_KEY:0:16}...)"

# Short ID
SHORT_ID=$(openssl rand -hex 8)
echo "  ✅ Short ID: ${SHORT_ID}"

# ─────────────────────────────────────────────────────────────────
# 写入 sing-box 配置（自动适配版本）
# 策略：先写最新格式 → sing-box check 校验 → 失败则降级
# ─────────────────────────────────────────────────────────────────
SB_VER_FULL=$("$SB_BIN" version 2>/dev/null | head -1 | awk '{print $NF}')
echo ""
echo "📝 正在生成 sing-box 配置... (内核版本: ${SB_VER_FULL:-未知})"

# ── 方案A: 1.12+ 格式 ───────────────────────────────────────────
write_config_v112() {
    cat > "$SB_CONFIG" <<SBEOF
{
  "log": {
    "disabled": false,
    "level": "warn",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "::",
      "listen_port": ${PORT},
      "users": [
        {
          "uuid": "${UUID}",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${DEST_SERVER}",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "${DEST_SERVER}",
            "server_port": 443
          },
          "private_key": "${PRIVATE_KEY}",
          "short_id": ["${SHORT_ID}"]
        }
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "route": {
    "rules": [
      {
        "protocol": ["quic"],
        "action": "reject"
      }
    ],
    "final": "direct"
  }
}
SBEOF
}

# ── 方案B: 1.10.x 兼容格式 ──────────────────────────────────────
write_config_v110() {
    cat > "$SB_CONFIG" <<SBEOF
{
  "log": {
    "disabled": false,
    "level": "warn",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "sniff": true,
      "sniff_override_destination": true,
      "tag": "vless-in",
      "listen": "::",
      "listen_port": ${PORT},
      "users": [
        {
          "uuid": "${UUID}",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${DEST_SERVER}",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "${DEST_SERVER}",
            "server_port": 443
          },
          "private_key": "${PRIVATE_KEY}",
          "short_id": ["${SHORT_ID}"]
        }
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct",
      "domain_strategy": "prefer_ipv4"
    }
  ],
  "route": {
    "rules": [
      {
        "protocol": ["quic"],
        "outbound": "block"
      }
    ],
    "final": "direct"
  }
}
SBEOF
}

# ── 方案C: 极简保底格式（任何版本都能跑）──────────────────────────
write_config_minimal() {
    cat > "$SB_CONFIG" <<SBEOF
{
  "log": {
    "level": "warn"
  },
  "inbounds": [
    {
      "type": "vless",
      "sniff": true,
      "sniff_override_destination": true,
      "tag": "vless-in",
      "listen": "::",
      "listen_port": ${PORT},
      "users": [
        {
          "uuid": "${UUID}",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${DEST_SERVER}",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "${DEST_SERVER}",
            "server_port": 443
          },
          "private_key": "${PRIVATE_KEY}",
          "short_id": ["${SHORT_ID}"]
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
SBEOF
}

# ── 自动选择：先试 A → 再试 B → 最后保底 C ──────────────────────
CONFIG_OK=0

echo "  → 尝试方案A (1.12+ 新格式)..."
write_config_v112
if "$SB_BIN" check -c "$SB_CONFIG" >/dev/null 2>&1; then
    echo "  ✅ 方案A 校验通过"
    CONFIG_OK=1
else
    echo "  ✗ 方案A 未通过，尝试方案B..."
    write_config_v110
    if "$SB_BIN" check -c "$SB_CONFIG" >/dev/null 2>&1; then
        echo "  ✅ 方案B 校验通过"
        CONFIG_OK=1
    else
        echo "  ✗ 方案B 未通过，使用极简保底方案C..."
        write_config_minimal
        if "$SB_BIN" check -c "$SB_CONFIG" >/dev/null 2>&1; then
            echo "  ✅ 方案C 校验通过"
            CONFIG_OK=1
        else
            echo "  ❌ 所有配置方案均校验失败！sing-box check 输出："
            "$SB_BIN" check -c "$SB_CONFIG" 2>&1 || true
            exit 1
        fi
    fi
fi

# ─────────────────────────────────────────────────────────────────
# 防火墙放行
# ─────────────────────────────────────────────────────────────────
echo ""
echo "🔓 正在放行端口 $PORT ..."
if command -v ufw > /dev/null 2>&1; then
    ufw allow "$PORT/tcp" >/dev/null 2>&1
    ufw reload >/dev/null 2>&1
fi
if command -v firewall-cmd > /dev/null 2>&1; then
    firewall-cmd --zone=public --add-port="$PORT/tcp" --permanent >/dev/null 2>&1
    firewall-cmd --reload >/dev/null 2>&1
fi
if command -v iptables > /dev/null 2>&1; then
    if ! iptables -C INPUT -p tcp --dport "$PORT" -j ACCEPT 2>/dev/null; then
        iptables -I INPUT -p tcp --dport "$PORT" -j ACCEPT
    fi
fi

# ─────────────────────────────────────────────────────────────────
# 创建 systemd 服务 & 启动
# ─────────────────────────────────────────────────────────────────
create_service
systemctl restart sing-box
sleep 2

# 验证服务状态
if systemctl is-active --quiet sing-box; then
    echo "  ✅ sing-box 服务启动成功"
else
    echo "  ❌ sing-box 服务启动失败！错误日志："
    journalctl -u sing-box --no-pager -n 20
    exit 1
fi

# ─────────────────────────────────────────────────────────────────
# 持久化配置
# ─────────────────────────────────────────────────────────────────
[ -z "$DOMAIN" ] && DOMAIN="$LAST_DOMAIN"
cat > "$CONFIG_FILE" <<CFEOF
LAST_NEED_DOMAIN="$NEED_DOMAIN"
LAST_DOMAIN="$DOMAIN"
LAST_PORT="$PORT"
TYPE="$TYPE"
LAST_DEST="$DEST_SERVER"
LAST_UUID="$UUID"
LAST_PUBLIC_KEY="$PUBLIC_KEY"
CFEOF

# ─────────────────────────────────────────────────────────────────
# 部署快捷查询命令 sd
# ─────────────────────────────────────────────────────────────────
cat << 'SDEOF' > /usr/local/bin/sd
#!/bin/bash
CONFIG_FILE="/etc/sd_vless_last.conf"
SB_CONFIG="/etc/s-box/config.json"

if [ ! -f "$SB_CONFIG" ] || [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ 未检测到节点配置，请先运行安装脚本！"
    exit 1
fi

source "$CONFIG_FILE"
IP=$(curl -s4m5 https://ifconfig.me 2>/dev/null || curl -s4m5 https://api.ipify.org 2>/dev/null)
PORT=$(jq -r '.inbounds[0].listen_port' "$SB_CONFIG")
UUID=$(jq -r '.inbounds[0].users[0].uuid' "$SB_CONFIG")
SHORT_ID=$(jq -r '.inbounds[0].tls.reality.short_id[0]' "$SB_CONFIG")
DEST_SERVER=$(jq -r '.inbounds[0].tls.server_name' "$SB_CONFIG")
PUBLIC_KEY="$LAST_PUBLIC_KEY"

if [ -z "$PUBLIC_KEY" ]; then
    echo "❌ 未找到 Public Key，请重新安装！"
    exit 1
fi

SB_VER=$(/etc/s-box/sing-box version 2>/dev/null | awk '/version/{print $NF}')
SB_STATUS=$(systemctl is-active sing-box 2>/dev/null || echo "unknown")

echo ""
echo "════════════════════════════════════════════════════════════"
echo " 📋 VLESS-Reality 节点信息 (sing-box v${SB_VER})"
echo "════════════════════════════════════════════════════════════"
echo " 服务状态: $SB_STATUS"
echo " 运行模式: $TYPE"
echo " 服务器 IP: $IP"
echo " 端口: $PORT"
echo " 伪装 SNI: $DEST_SERVER"
echo " PubKey: ${PUBLIC_KEY:0:20}..."
echo "════════════════════════════════════════════════════════════"

if [ "$TYPE" == "DOMAIN" ] && [ -n "$LAST_DOMAIN" ]; then
    CONNECT_ADDR="$LAST_DOMAIN"
    LINK_TAG="Reality-Domain-${PORT}"
else
    CONNECT_ADDR="$IP"
    LINK_TAG="Reality-IP-${PORT}"
fi

LINK="vless://${UUID}@${CONNECT_ADDR}:${PORT}?security=reality&sni=${DEST_SERVER}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&headerType=none&flow=xtls-rprx-vision&encryption=none#${LINK_TAG}"

echo ""
echo "👇 一键导入链接（复制整行）："
echo ""
echo "$LINK"
echo ""
echo "════════════════════════════════════════════════════════════"
SDEOF
chmod +x /usr/local/bin/sd

# ─────────────────────────────────────────────────────────────────
# 输出结果
# ─────────────────────────────────────────────────────────────────
echo ""
echo "🎉 安装完成！"
echo ""
/usr/local/bin/sd
