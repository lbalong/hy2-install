#!/usr/bin/env bash
# ==============================================================
#  WARP for Gemini - 一键脚本 v3
#  解锁 Google Gemini API 访问限制（适用于 RackNerd 等受限 VPS）
#  原理: wgcf 注册账户 + wireproxy 暴露本地 SOCKS5
#
#  一键安装: bash <(curl -sL 你的脚本地址)
#  卸    载: bash <(curl -sL 你的脚本地址) -u
#  查看状态: bash <(curl -sL 你的脚本地址) -s
#  测试访问: bash <(curl -sL 你的脚本地址) -t
# ==============================================================

export DEBIAN_FRONTEND=noninteractive

# ===== 配置 =====
PORT="${WARP_PORT:-40000}"
DIR="/etc/wireguard"
WP_BIN="/usr/local/bin/wireproxy"
WGCF_BIN="/usr/local/bin/wgcf"
WP_CONF="${DIR}/wireproxy.conf"
WP_SVC="/etc/systemd/system/wireproxy.service"

# Cloudflare WARP 公开固定参数
CF_PUBKEY="bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo="
CF_ENDPOINT="162.159.192.1:2408"

# ===== 输出函数 =====
ok()   { echo -e "\033[32m[✓]\033[0m $*"; }
warn() { echo -e "\033[33m[!]\033[0m $*"; }
err()  { echo -e "\033[31m[✗]\033[0m $*"; }
step() { echo -e "\n\033[1;36m>>> $*\033[0m"; }
die()  { err "$*"; exit 1; }

banner() {
  echo -e "\033[1;36m"
  echo "  ╔══════════════════════════════════════════╗"
  echo "  ║     WARP for Gemini  -  一键脚本 v3      ║"
  echo "  ║  解锁 Google Gemini API | wgcf+wireproxy  ║"
  echo "  ╚══════════════════════════════════════════╝"
  echo -e "\033[0m"
  echo "  SOCKS5 端口: \033[1m${PORT}\033[0m"
  echo ""
}

# ===== 系统检测 =====
check_env() {
  [ "$(id -u)" != "0" ] && die "请用 root 运行: sudo bash $0"
  ok "Root 权限: OK"

  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64)        A_WGCF=amd64; A_WP=amd64 ;;
    aarch64|arm64) A_WGCF=arm64; A_WP=arm64 ;;
    armv7l)        A_WGCF=armv7; A_WP=arm   ;;
    *) die "不支持的架构: $ARCH" ;;
  esac

  OS=$(grep '^ID=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' | tr '[:upper:]' '[:lower:]')
  OSVER=$(grep '^VERSION_ID=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' | cut -d. -f1)
  OSNAME=$(grep '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')
  ok "系统: ${OSNAME:-$OS} | 架构: $ARCH"

  VIRT=$(systemd-detect-virt 2>/dev/null || echo unknown)
  ok "虚拟化: $VIRT"
  [ "$VIRT" = openvz ] || [ "$VIRT" = lxc ] && die "不支持 OpenVZ/LXC，请用 KVM VPS"
}

# ===== 安装 wireguard-tools =====
inst_wg() {
  command -v wg >/dev/null 2>&1 && { ok "wireguard-tools: 已存在"; return; }
  step "安装 wireguard-tools"
  case "$OS" in
    ubuntu|debian)
      apt-get update -qq 2>/dev/null
      apt-get install -y -qq wireguard-tools 2>/dev/null || die "wireguard-tools 安装失败"
      ;;
    centos|rhel|rocky|almalinux)
      [ "$OSVER" -ge 8 ] 2>/dev/null \
        && dnf install -y epel-release wireguard-tools >/dev/null 2>&1 \
        || yum install -y epel-release wireguard-tools >/dev/null 2>&1 \
        || die "wireguard-tools 安装失败"
      ;;
    fedora) dnf install -y wireguard-tools >/dev/null 2>&1 || die "安装失败" ;;
    *) die "不支持的系统 $OS，请手动安装 wireguard-tools" ;;
  esac
  ok "wireguard-tools 安装完成"
}

# ===== 下载二进制 =====
download() {
  local name=$1 repo=$2 pattern=$3 dest=$4 ver fallback_ver=$5

  [ -x "$dest" ] && { ok "${name}: 已存在 ($(${dest} -v 2>/dev/null | head -1 || true))"; return; }

  step "下载 ${name}"
  ver=$(curl -fsSL --max-time 10 "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null \
    | grep '"tag_name"' | head -1 | cut -d'"' -f4 | tr -d 'v')
  [ -z "$ver" ] && ver="$fallback_ver" && warn "自动获取版本失败，使用 v${ver}"

  local url="https://github.com/${repo}/releases/download/v${ver}/${pattern/VER/$ver}"
  ok "下载: $url"

  if echo "$url" | grep -q '.tar.gz'; then
    local tmp="/tmp/_${name}_$$.tar.gz"
    curl -fsSL --max-time 60 --retry 3 -o "$tmp" "$url" || die "${name} 下载失败"
    tar -xzf "$tmp" -C /tmp/ 2>/dev/null
    install -m 755 "/tmp/${name}" "$dest" || die "${name} 安装失败"
    rm -f "$tmp" "/tmp/${name}"
  else
    curl -fsSL --max-time 60 --retry 3 -o "$dest" "$url" || die "${name} 下载失败"
    chmod +x "$dest"
  fi
  ok "${name} 安装完成"
}

# ===== 注册 WARP 账户 & 生成私钥 =====
setup_warp() {
  mkdir -p "$DIR"

  # 已有账户则直接用
  if [ -f "${DIR}/wgcf-account.toml" ]; then
    ok "已有 WARP 账户，跳过注册"
  else
    step "注册 WARP 账户"
    cd "$DIR"
    if "$WGCF_BIN" register --accept-tos >/dev/null 2>&1; then
      ok "wgcf 在线注册成功"
    else
      warn "在线注册失败，使用内置备用账户"
      cat > "${DIR}/wgcf-account.toml" <<'TOML'
access_token = 'preset'
account_id   = 'b0fe9b24-3396-486e-a12d-c194dbbb7bfb'
license_key  = '36L7Pg9E-j6Jp2x04-I40UQ39C'
private_key  = 'hTk06uwwXhZx3RVqtug3MQ0RSodzdM/U5z/M5NIbh4c='
token        = '50d988c2-b5fb-c829-42dd-a33a960ea734'
TOML
    fi
  fi

  # 提取私钥
  PRIVKEY=$(grep 'private_key' "${DIR}/wgcf-account.toml" | head -1 | cut -d"'" -f2)
  [ -z "$PRIVKEY" ] && PRIVKEY=$(grep 'private_key' "${DIR}/wgcf-account.toml" | head -1 | cut -d'"' -f4)
  [ -z "$PRIVKEY" ] && die "无法提取私钥，请检查 ${DIR}/wgcf-account.toml"
  ok "私钥提取成功"

  # 尝试 wgcf generate 获取真实分配 IP（失败则用默认值，不影响功能）
  cd "$DIR"
  ADDR="172.16.0.2/32"
  if "$WGCF_BIN" generate --force >/dev/null 2>&1 && [ -f "${DIR}/wgcf-profile.conf" ]; then
    ok "获取到 WARP 分配 IP"
    ADDR=$(grep 'Address' "${DIR}/wgcf-profile.conf" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+' | head -1)
    ADDR="${ADDR:-172.16.0.2/32}"
  else
    warn "wgcf generate 被 Cloudflare 限制，使用默认地址 172.16.0.2/32（不影响代理功能）"
  fi
}

# ===== 写入 wireproxy 配置 =====
write_conf() {
  step "生成 wireproxy 配置"

  systemctl stop wireproxy 2>/dev/null || true

  cat > "$WP_CONF" <<CONF
[Interface]
PrivateKey = ${PRIVKEY}
Address    = ${ADDR}
DNS        = 1.1.1.1

[Peer]
PublicKey  = ${CF_PUBKEY}
AllowedIPs = 0.0.0.0/0
AllowedIPs = ::/0
Endpoint   = ${CF_ENDPOINT}
Reserved   = [0, 0, 0]

[Socks5]
BindAddress = 127.0.0.1:${PORT}
CONF

  ok "配置写入: $WP_CONF"
  echo ""
  grep -E 'PrivateKey|Address|PublicKey|Endpoint|BindAddress' "$WP_CONF" | sed 's/^/    /'
}

# ===== 安装并启动服务 =====
start_service() {
  step "启动 wireproxy 服务"

  cat > "$WP_SVC" <<SVC
[Unit]
Description=WireProxy WARP SOCKS5 Proxy
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${WP_BIN} -c ${WP_CONF}
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
SVC

  systemctl daemon-reload
  systemctl enable wireproxy >/dev/null 2>&1
  systemctl restart wireproxy
  sleep 4

  if systemctl is-active --quiet wireproxy; then
    ok "wireproxy 启动成功，已设置开机自启"
  else
    err "wireproxy 启动失败，日志如下:"
    journalctl -u wireproxy -n 30 --no-pager
    die "请根据日志排查问题"
  fi
}

# ===== 验证 =====
verify() {
  step "验证连接"
  sleep 2

  local orig warp org code
  orig=$(curl -fsSL --max-time 8  https://api.ip.sb/ip 2>/dev/null || echo "获取失败")
  warp=$(curl -fsSL --max-time 15 --proxy "socks5h://127.0.0.1:${PORT}" https://api.ip.sb/ip 2>/dev/null || echo "获取失败")
  org=$( curl -fsSL --max-time 15 --proxy "socks5h://127.0.0.1:${PORT}" https://ipinfo.io/org  2>/dev/null || echo "未知")

  echo ""
  echo -e "  原始 IP : \033[1m${orig}\033[0m"
  echo -e "  WARP IP : \033[32m\033[1m${warp}\033[0m"
  echo -e "  归    属 : ${org}"
  echo ""

  if [ "$warp" = "获取失败" ]; then
    warn "代理无法获取 IP，查看日志: journalctl -u wireproxy -n 50"
    return 1
  fi

  code=$(curl -fsSL -o /dev/null -w "%{http_code}" --max-time 15 \
    --proxy "socks5h://127.0.0.1:${PORT}" \
    "https://generativelanguage.googleapis.com/" 2>/dev/null || echo "000")

  case "$code" in
    200|400|401|404|405) ok "🎉 Gemini API 可达！HTTP ${code}" ;;
    403) warn "Gemini 返回 403（此 WARP IP 被限制）→ systemctl restart wireproxy 换 IP" ;;
    000) warn "Gemini 连接超时，代理在工作但 Google 可能拦截了此 IP" ;;
    *)   warn "Gemini HTTP ${code}，请手动验证" ;;
  esac
}

# ===== 使用说明 =====
usage_hint() {
  echo ""
  echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
  echo -e "\033[1m  使用说明\033[0m"
  echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
  echo ""
  echo "  代理地址: socks5h://127.0.0.1:${PORT}"
  echo ""
  echo "  curl 测试:"
  echo "    curl --proxy socks5h://127.0.0.1:${PORT} https://generativelanguage.googleapis.com/"
  echo ""
  echo "  全局代理（写入 /etc/profile.d/warp.sh）:"
  echo "    bash -c \"echo 'export https_proxy=socks5h://127.0.0.1:${PORT}' > /etc/profile.d/warp.sh\""
  echo "    bash -c \"echo 'export http_proxy=socks5h://127.0.0.1:${PORT}'  >> /etc/profile.d/warp.sh\""
  echo "    source /etc/profile.d/warp.sh"
  echo ""
  echo "  Python:"
  echo "    import os; os.environ['https_proxy']='socks5h://127.0.0.1:${PORT}'"
  echo ""
  echo "  管理:"
  echo "    systemctl restart wireproxy   # 重启换 IP"
  echo "    systemctl status  wireproxy   # 状态"
  echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
}

# ===== 子命令 =====
do_status() {
  echo ""
  systemctl status wireproxy --no-pager -l 2>/dev/null || echo "未安装"
  echo ""
  echo -n "  原始 IP : "; curl -fsSL --max-time 8 https://api.ip.sb/ip 2>/dev/null; echo
  echo -n "  WARP IP : "; curl -fsSL --max-time 15 --proxy "socks5h://127.0.0.1:${PORT}" https://api.ip.sb/ip 2>/dev/null || echo "获取失败"; echo
}

do_test() {
  echo ""
  echo "测试 Gemini API..."
  local code
  code=$(curl -fsSL -o /dev/null -w "%{http_code}" --max-time 15 \
    --proxy "socks5h://127.0.0.1:${PORT}" \
    "https://generativelanguage.googleapis.com/" 2>/dev/null || echo "000")
  case "$code" in
    200|400|401|404|405) ok "Gemini 可达 ✅  HTTP ${code}" ;;
    403) warn "返回 403，尝试换 IP: systemctl restart wireproxy" ;;
    000) err "连接失败，检查: systemctl status wireproxy" ;;
    *)   warn "HTTP ${code}" ;;
  esac
  echo ""
}

do_uninstall() {
  echo ""
  warn "将卸载 WARP for Gemini..."
  printf "确认卸载? (y/N): "; read -r c
  [ "$c" = y ] || [ "$c" = Y ] || { ok "已取消"; exit 0; }
  systemctl stop    wireproxy 2>/dev/null || true
  systemctl disable wireproxy 2>/dev/null || true
  rm -f "$WP_SVC" "$WP_BIN" "$WGCF_BIN" "$WP_CONF"
  rm -f "${DIR}/wgcf-account.toml" "${DIR}/wgcf-profile.conf"
  rm -f /etc/profile.d/warp.sh
  systemctl daemon-reload 2>/dev/null || true
  ok "卸载完成"
}

# ===== 主流程 =====
main() {
  banner
  local cmd="${1:-}"
  case "$cmd" in
    -s|--status)    do_status;    exit 0 ;;
    -t|--test)      do_test;      exit 0 ;;
    -u|--uninstall) do_uninstall; exit 0 ;;
    -h|--help)
      echo "用法: bash $0 [-s|-t|-u|-h]"
      echo "  (无参数)  安装"
      echo "  -s        查看状态"
      echo "  -t        测试 Gemini"
      echo "  -u        卸载"
      echo "环境变量: WARP_PORT=端口（默认 40000）"
      exit 0 ;;
  esac

  check_env

  step "Step 1/4: 安装 wireguard-tools"
  inst_wg

  step "Step 2/4: 安装 wgcf"
  download wgcf ViRb3/wgcf "wgcf_VER_linux_${A_WGCF}" "$WGCF_BIN" 2.0.12

  step "Step 3/4: 安装 wireproxy"
  download wireproxy pufferffish/wireproxy "wireproxy_linux_${A_WP}.tar.gz" "$WP_BIN" 1.0.9

  step "Step 4/4: 配置 & 启动"
  setup_warp
  write_conf
  start_service

  verify
  usage_hint
}

main "$@"
