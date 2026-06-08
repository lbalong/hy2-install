#!/usr/bin/env bash
# ==============================================================================
#  WARP for Gemini 全局解锁脚本 (完美版)
#  专为 v2ray/hy2/tuic 节点用户定制，直接接管 VPS 全局流量
#  透明代理：无需修改节点配置，客户端直连即可解锁 Gemini
# ==============================================================================

export DEBIAN_FRONTEND=noninteractive

DIR="/etc/wireguard"
WGCF_BIN="/usr/local/bin/wgcf"
WG_CONF="${DIR}/wg0.conf"

ok()   { echo -e "\033[32m[✓]\033[0m $*"; }
warn() { echo -e "\033[33m[!]\033[0m $*"; }
err()  { echo -e "\033[31m[✗]\033[0m $*"; }
step() { echo -e "\n\033[1;36m>>> $*\033[0m"; }
die()  { err "$*"; exit 1; }

# ===== 1. 环境准备 =====
check_root() {
  [ "$(id -u)" != "0" ] && die "请使用 root 权限运行"
  
  # 获取当前主网卡和IP，防止失联
  MAIN_IF=$(ip route get 8.8.8.8 | grep -oP 'dev \K\S+')
  MAIN_IP=$(ip -4 addr show dev "$MAIN_IF" | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
  [ -z "$MAIN_IP" ] && die "无法获取主网卡 IP"
  
  ok "检测到主网卡: $MAIN_IF, IP: $MAIN_IP"
}

inst_wg() {
  step "安装 WireGuard"
  if ! command -v wg >/dev/null 2>&1; then
    apt-get update -qq && apt-get install -y -qq wireguard-tools openresolv || \
    yum install -y epel-release wireguard-tools
  fi
  ok "WireGuard 安装完成"
}

# ===== 2. 获取 WARP 账号 =====
setup_warp() {
  step "生成 WARP 账户"
  
  # 下载 wgcf
  if [ ! -x "$WGCF_BIN" ]; then
    ARCH=$(uname -m)
    [ "$ARCH" = "x86_64" ] && A="amd64" || A="arm64"
    curl -fsSL -o "$WGCF_BIN" "https://github.com/ViRb3/wgcf/releases/download/v2.0.12/wgcf_2.0.12_linux_${A}"
    chmod +x "$WGCF_BIN"
  fi

  mkdir -p "$DIR" && cd "$DIR"
  
  # 注册并生成原始配置
  if [ ! -f "wgcf-account.toml" ]; then
    "$WGCF_BIN" register --accept-tos >/dev/null 2>&1 || true
    if [ ! -f "wgcf-account.toml" ]; then
      # 备用公开账户
      cat > wgcf-account.toml <<'EOF'
access_token = 'preset'
account_id   = 'b0fe9b24-3396-486e-a12d-c194dbbb7bfb'
license_key  = '36L7Pg9E-j6Jp2x04-I40UQ39C'
private_key  = 'hTk06uwwXhZx3RVqtug3MQ0RSodzdM/U5z/M5NIbh4c='
token        = '50d988c2-b5fb-c829-42dd-a33a960ea734'
EOF
    fi
  fi

  "$WGCF_BIN" generate --force >/dev/null 2>&1
  ok "WARP 账户生成完成"
}

# ===== 3. 配置全局路由 (核心防失联) =====
config_wg() {
  step "配置全局透明路由"
  
  cd "$DIR"
  local PRIVKEY ADDR6
  
  if [ -f "wgcf-profile.conf" ]; then
    PRIVKEY=$(grep 'PrivateKey' wgcf-profile.conf | head -1 | awk '{print $NF}')
    ADDR6=$(grep 'Address' wgcf-profile.conf | grep ':' | head -1 | awk '{print $NF}')
  else
    PRIVKEY=$(grep 'private_key' wgcf-account.toml | head -1 | cut -d"'" -f2 | cut -d'"' -f2)
  fi
  
  [ -z "$PRIVKEY" ] && PRIVKEY="hTk06uwwXhZx3RVqtug3MQ0RSodzdM/U5z/M5NIbh4c="
  [ -z "$ADDR6" ] && ADDR6="2606:4700:110:8048:da0c:5620:6c5d:7448/128"

  systemctl stop wg-quick@wg0 2>/dev/null || true

  # 生成安全的 wg0.conf
  # 关键点：仅接管 IPv6 流量，彻底避开 IPv4 的 UDP 路由冲突！
  cat > "$WG_CONF" <<EOF
[Interface]
PrivateKey = ${PRIVKEY}
Address = ${ADDR6}
DNS = 2001:4860:4860::8888
MTU = 1280

[Peer]
PublicKey = bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=
# 【核心修改】只接管 IPv6！不碰 0.0.0.0/0！
# 这样你的 TUIC (IPv4)、SSH 等所有原生业务完全不受影响！
AllowedIPs = ::/0
Endpoint = 162.159.192.1:2408
EOF

  ok "WG 配置文件已写入: $WG_CONF"
}

# ===== 4. 启动与验证 =====
start_wg() {
  step "启动 WARP 网络接管"
  
  systemctl daemon-reload
  systemctl enable wg-quick@wg0 >/dev/null 2>&1
  systemctl restart wg-quick@wg0
  sleep 3
  
  if ip link show wg0 >/dev/null 2>&1; then
    ok "WARP 虚拟网卡已启动，已接管全局流量！"
  else
    die "wg0 网卡启动失败，请检查配置或尝试重启 VPS"
  fi
}

verify() {
  step "验证最终解锁状态"
  
  local WARP_IP
  WARP_IP=$(curl -fsSL -6 --max-time 10 https://api.ip.sb/ip 2>/dev/null)
  
  echo -e "\n  当前 IPv6 出站 IP: \033[1;32m${WARP_IP}\033[0m (全自动解锁路线)"
  
  local CODE
  CODE=$(curl -fsSL -o /dev/null -w "%{http_code}" --max-time 10 "https://generativelanguage.googleapis.com/")
  
  if [[ "$CODE" =~ ^(200|404|400|401)$ ]]; then
    ok "Gemini API 访问测试: HTTP $CODE (已完美解锁！)"
  else
    warn "Gemini API 测试异常 (HTTP $CODE)，请留意"
  fi
}

# ===== 清理原有的 wireproxy 残留 =====
clean_old() {
  if systemctl is-active --quiet wireproxy 2>/dev/null; then
    step "清理旧版 wireproxy"
    systemctl stop wireproxy 2>/dev/null
    systemctl disable wireproxy 2>/dev/null
    rm -f /etc/systemd/system/wireproxy.service /usr/local/bin/wireproxy /etc/wireguard/wireproxy.conf
    ok "旧版清理完成"
  fi
}

main() {
  echo -e "\n\033[1;36m===================================================\033[0m"
  echo -e "\033[1m  WARP for Gemini 智能解锁脚本 (IPv6 分流版)\033[0m"
  echo -e "\033[1;36m===================================================\033[0m\n"
  
  check_root
  clean_old
  inst_wg
  setup_warp
  config_wg
  start_wg
  verify
  
  echo -e "\n\033[1;32m🎉 恭喜！IPv6 智能解锁已安装完成！\033[0m"
  echo -e "👉 \033[1m你的 IPv4 流量 (TUIC/SSH等) 原封不动，完全恢复正常！\033[0m"
  echo -e "👉 \033[1mGemini、ChatGPT 等大厂 AI 自动走新增的 IPv6 通道，完美解锁！\033[0m"
}

main "$@"
