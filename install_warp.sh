#!/usr/bin/env bash
# ==============================================================================
#  WARP for Gemini - 一键脚本 v2
#  解锁 RackNerd VPS 对 Google Gemini API 的访问限制
#  原理: wgcf 注册 WARP + wireproxy 本地 SOCKS5 代理
#
#  用法：
#    bash install_warp.sh           # 安装
#    bash install_warp.sh -u        # 卸载
#    bash install_warp.sh -s        # 查看状态
#    bash install_warp.sh -t        # 测试 Gemini
# ==============================================================================
# 不使用 set -euo pipefail，改为逐步显式判断，避免 bash <(curl) 场景下的隐式退出
export DEBIAN_FRONTEND=noninteractive
# ==================== 可修改配置 ====================
SOCKS5_PORT="${WARP_PORT:-40000}"
WARP_CONF_DIR="/etc/wireguard"
WIREPROXY_BIN="/usr/local/bin/wireproxy"
WGCF_BIN="/usr/local/bin/wgcf"
WIREPROXY_CONF="${WARP_CONF_DIR}/wireproxy.conf"
WIREPROXY_SERVICE="/etc/systemd/system/wireproxy.service"
GEMINI_HOST="generativelanguage.googleapis.com"
# ====================================================
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[✗]${NC} $*"; }
step()  { echo -e "\n${CYAN}${BOLD}>>> $*${NC}"; }
die()   { error "$*"; exit 1; }
banner() {
  echo -e "${CYAN}${BOLD}"
  echo " ██╗    ██╗ █████╗ ██████╗ ██████╗"
  echo " ██║    ██║██╔══██╗██╔══██╗██╔══██╗"
  echo " ██║ █╗ ██║███████║██████╔╝██████╔╝"
  echo " ██║███╗██║██╔══██║██╔══██╗██╔═══╝"
  echo " ╚███╔███╔╝██║  ██║██║  ██║██║"
  echo "  ╚══╝╚══╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝   for Gemini"
  echo -e "${NC}"
  echo "  解锁 Google Gemini API | 基于 wgcf + wireproxy"
  echo "  SOCKS5 端口: ${BOLD}${SOCKS5_PORT}${NC}"
  echo ""
}
# ==================== 前置检查 ====================
check_root() {
  if [ "$(id -u)" != "0" ]; then
    die "请以 root 权限运行: sudo bash $0"
  fi
  info "Root 权限: OK"
}
detect_env() {
  # 操作系统
  if [ -f /etc/os-release ]; then
    OS_ID=$(grep '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"' | tr '[:upper:]' '[:lower:]')
    OS_VER=$(grep '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '"' | cut -d. -f1)
    OS_CODENAME=$(grep '^VERSION_CODENAME=' /etc/os-release | cut -d= -f2 | tr -d '"')
    OS_NAME=$(grep '^PRETTY_NAME=' /etc/os-release | cut -d= -f2 | tr -d '"')
  else
    die "无法识别操作系统"
  fi
  info "操作系统: ${OS_NAME}"
  # 架构
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64)        ARCH_WGCF="amd64";  ARCH_WP="amd64" ;;
    aarch64|arm64) ARCH_WGCF="arm64";  ARCH_WP="arm64" ;;
    armv7l)        ARCH_WGCF="armv7";  ARCH_WP="arm"   ;;
    *) die "不支持的架构: $ARCH（仅支持 x86_64 / aarch64 / armv7l）" ;;
  esac
  info "系统架构: $ARCH"
  # 虚拟化
  VIRT="unknown"
  if command -v systemd-detect-virt >/dev/null 2>&1; then
    VIRT=$(systemd-detect-virt 2>/dev/null || echo "unknown")
  fi
  info "虚拟化类型: $VIRT"
  if [ "$VIRT" = "openvz" ] || [ "$VIRT" = "lxc" ]; then
    die "不支持 OpenVZ/LXC，请使用 KVM VPS"
  fi
}
# ==================== 安装依赖 ====================
install_wireguard_tools() {
  if command -v wg >/dev/null 2>&1; then
    info "wireguard-tools: 已存在"
    return 0
  fi
  info "安装 wireguard-tools..."
  case "$OS_ID" in
    ubuntu|debian)
      apt-get update -qq 2>/dev/null
      apt-get install -y -qq wireguard-tools 2>/dev/null || die "wireguard-tools 安装失败"
      ;;
    centos|rhel|rocky|almalinux)
      if [ "$OS_VER" -ge 8 ] 2>/dev/null; then
        dnf install -y epel-release >/dev/null 2>&1 || true
        dnf install -y wireguard-tools >/dev/null 2>&1 || die "wireguard-tools 安装失败"
      else
        yum install -y epel-release >/dev/null 2>&1 || true
        yum install -y wireguard-tools >/dev/null 2>&1 || die "wireguard-tools 安装失败"
      fi
      ;;
    fedora)
      dnf install -y wireguard-tools >/dev/null 2>&1 || die "wireguard-tools 安装失败"
      ;;
    *) die "不支持的系统 $OS_ID，请手动安装 wireguard-tools" ;;
  esac
  info "wireguard-tools 安装完成"
}
# ==================== 下载 wgcf ====================
install_wgcf() {
  if [ -x "$WGCF_BIN" ]; then
    info "wgcf: 已存在 ($($WGCF_BIN version 2>/dev/null | head -1))"
    return 0
  fi
  info "下载 wgcf..."
  # 尝试从 GitHub 获取最新版本
  local ver url
  ver=$(curl -fsSL --max-time 10 "https://api.github.com/repos/ViRb3/wgcf/releases/latest" 2>/dev/null \
    | grep '"tag_name"' | head -1 | cut -d'"' -f4 | tr -d 'v')
  if [ -z "$ver" ]; then
    ver="2.0.12"
    warn "自动获取 wgcf 版本失败，使用稳定版 v${ver}"
  else
    info "wgcf 最新版本: v${ver}"
  fi
  url="https://github.com/ViRb3/wgcf/releases/download/v${ver}/wgcf_${ver}_linux_${ARCH_WGCF}"
  info "下载: $url"
  curl -fsSL --max-time 60 --retry 3 -o "$WGCF_BIN" "$url" 2>/dev/null \
    || die "wgcf 下载失败，请检查网络"
  chmod +x "$WGCF_BIN"
  info "wgcf 安装完成: $($WGCF_BIN version 2>/dev/null | head -1)"
}
# ==================== 下载 wireproxy ====================
install_wireproxy() {
  if [ -x "$WIREPROXY_BIN" ]; then
    info "wireproxy: 已存在 ($($WIREPROXY_BIN -v 2>/dev/null | head -1))"
    return 0
  fi
  info "下载 wireproxy..."
  local ver url tmpfile
  ver=$(curl -fsSL --max-time 10 "https://api.github.com/repos/pufferffish/wireproxy/releases/latest" 2>/dev/null \
    | grep '"tag_name"' | head -1 | cut -d'"' -f4 | tr -d 'v')
  if [ -z "$ver" ]; then
    ver="1.0.9"
    warn "自动获取 wireproxy 版本失败，使用稳定版 v${ver}"
  else
    info "wireproxy 最新版本: v${ver}"
  fi
  url="https://github.com/pufferffish/wireproxy/releases/download/v${ver}/wireproxy_linux_${ARCH_WP}.tar.gz"
  info "下载: $url"
  tmpfile="/tmp/wireproxy_$$.tar.gz"
  curl -fsSL --max-time 60 --retry 3 -o "$tmpfile" "$url" 2>/dev/null \
    || die "wireproxy 下载失败，请检查网络"
  tar -xzf "$tmpfile" -C /tmp/ 2>/dev/null \
    || die "wireproxy 解压失败"
  install -m 755 /tmp/wireproxy "$WIREPROXY_BIN" \
    || die "wireproxy 安装失败"
  rm -f "$tmpfile" /tmp/wireproxy
  info "wireproxy 安装完成: $($WIREPROXY_BIN -v 2>/dev/null | head -1)"
}
# ==================== 注册 WARP 账户 ====================
register_warp() {
  mkdir -p "$WARP_CONF_DIR"
  # 若已有配置文件，跳过注册
  if [ -f "${WARP_CONF_DIR}/wgcf-profile.conf" ]; then
    info "已有 WARP 配置，跳过注册"
    return 0
  fi
  info "注册 WARP 账户..."
  cd "$WARP_CONF_DIR" || die "无法进入 $WARP_CONF_DIR"
  # 先尝试直接通过 wgcf 注册
  if "$WGCF_BIN" register --accept-tos 2>/dev/null; then
    info "wgcf 注册成功"
  else
    warn "wgcf 直连注册失败，使用内置预设账户..."
    # 内置备用账户（来源：fscarmen warp 脚本公共账户）
    cat > wgcf-account.toml <<'TOML'
access_token = 'preset'
account_id = 'preset'
license_key = '36L7Pg9E-j6Jp2x04-I40UQ39C'
private_key = 'hTk06uwwXhZx3RVqtug3MQ0RSodzdM/U5z/M5NIbh4c='
token = 'preset'
TOML
  fi
  # 生成 WireGuard 配置
  if ! "$WGCF_BIN" generate --force 2>/dev/null; then
    die "生成 wgcf-profile.conf 失败"
  fi
  [ -f "${WARP_CONF_DIR}/wgcf-profile.conf" ] || die "wgcf-profile.conf 未生成"
  info "WARP WireGuard 配置生成完成"
}
# ==================== 生成 wireproxy 配置 ====================
generate_wireproxy_conf() {
  info "生成 wireproxy 配置..."
  local src="${WARP_CONF_DIR}/wgcf-profile.conf"
  [ -f "$src" ] || die "找不到 wgcf-profile.conf"
  local privkey addr4 addr6 dns pubkey endpoint reserved
  privkey=$(grep 'PrivateKey' "$src" | head -1 | awk '{print $NF}')
  addr4=$(grep 'Address' "$src" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+' | head -1)
  addr6=$(grep 'Address' "$src" | grep -oE '([0-9a-fA-F:]+:+[0-9a-fA-F:]+)/[0-9]+' | head -1)
  dns=$(grep 'DNS' "$src" | awk -F'= ' '{print $2}' | head -1 | awk '{print $1}')
  pubkey=$(grep 'PublicKey' "$src" | head -1 | awk '{print $NF}')
  endpoint=$(grep 'Endpoint' "$src" | head -1 | awk '{print $NF}')
  reserved=$(grep 'Reserved' "$src" | head -1 | awk -F'= ' '{print $2}')
  dns="${dns:-1.1.1.1}"
  endpoint="${endpoint:-engage.cloudflareclient.com:2408}"
  reserved="${reserved:-[0, 0, 0]}"
  cat > "$WIREPROXY_CONF" <<CONF
[Interface]
PrivateKey = ${privkey}
Address = ${addr4:-172.16.0.2/32}
DNS = ${dns}
[Peer]
PublicKey = ${pubkey}
AllowedIPs = 0.0.0.0/0
AllowedIPs = ::/0
Endpoint = ${endpoint}
Reserved = ${reserved}
[Socks5]
BindAddress = 127.0.0.1:${SOCKS5_PORT}
CONF
  # 若有 IPv6 地址也加入
  if [ -n "$addr6" ]; then
    sed -i "/^Address = ${addr4}/a Address = ${addr6}" "$WIREPROXY_CONF" 2>/dev/null || true
  fi
  info "wireproxy 配置写入: $WIREPROXY_CONF"
}
# ==================== 安装 systemd 服务 ====================
install_service() {
  info "配置 systemd 服务..."
  # 停止旧实例
  systemctl stop wireproxy 2>/dev/null || true
  cat > "$WIREPROXY_SERVICE" <<SERVICE
[Unit]
Description=WireProxy - WARP SOCKS5 Proxy (Gemini)
After=network-online.target
Wants=network-online.target
[Service]
Type=simple
ExecStart=${WIREPROXY_BIN} -c ${WIREPROXY_CONF}
Restart=on-failure
RestartSec=5
LimitNOFILE=65536
[Install]
WantedBy=multi-user.target
SERVICE
  systemctl daemon-reload
  systemctl enable wireproxy >/dev/null 2>&1
  systemctl start wireproxy
  sleep 3
  if systemctl is-active --quiet wireproxy; then
    info "wireproxy 服务启动成功，开机自启已配置"
  else
    error "wireproxy 服务启动失败，查看日志:"
    journalctl -u wireproxy -n 20 --no-pager
    die "安装失败"
  fi
}
# ==================== 验证 ====================
verify() {
  step "验证 WARP 连接..."
  sleep 2
  local orig_ip warp_ip warp_org http_code
  orig_ip=$(curl -fsSL --max-time 10 https://ipinfo.io/ip 2>/dev/null || echo "获取失败")
  warp_ip=$(curl -fsSL --max-time 15 --proxy "socks5h://127.0.0.1:${SOCKS5_PORT}" \
    https://ipinfo.io/ip 2>/dev/null || echo "获取失败")
  warp_org=$(curl -fsSL --max-time 15 --proxy "socks5h://127.0.0.1:${SOCKS5_PORT}" \
    https://ipinfo.io/org 2>/dev/null || echo "未知")
  echo ""
  echo -e "  原始 IP : ${BOLD}${orig_ip}${NC}"
  echo -e "  WARP IP : ${GREEN}${BOLD}${warp_ip}${NC}"
  echo -e "  IP 归属 : ${warp_org}"
  echo ""
  if [ "$warp_ip" = "获取失败" ]; then
    warn "代理连接失败，查看日志: journalctl -u wireproxy -n 50"
    return 1
  fi
  http_code=$(curl -fsSL -o /dev/null -w "%{http_code}" --max-time 15 \
    --proxy "socks5h://127.0.0.1:${SOCKS5_PORT}" \
    "https://${GEMINI_HOST}/" 2>/dev/null || echo "000")
  case "$http_code" in
    200|400|401|404|405)
      info "🎉 Gemini API 可达！(HTTP ${http_code})"
      ;;
    403)
      warn "Gemini 返回 403，此 WARP IP 被限制"
      warn "尝试重启换 IP: systemctl restart wireproxy"
      ;;
    *)
      warn "Gemini HTTP ${http_code}，请手动验证"
      ;;
  esac
}
# ==================== 使用说明 ====================
print_usage() {
  echo ""
  echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${CYAN}${BOLD}  安装完成！使用说明${NC}"
  echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  echo -e "  ${BOLD}SOCKS5 代理: socks5h://127.0.0.1:${SOCKS5_PORT}${NC}"
  echo ""
  echo "  测试:"
  echo "    curl --proxy socks5h://127.0.0.1:${SOCKS5_PORT} https://ipinfo.io"
  echo ""
  echo "  全局环境变量（永久生效）:"
  echo "    echo 'export https_proxy=socks5h://127.0.0.1:${SOCKS5_PORT}' >> /etc/profile.d/warp.sh"
  echo "    echo 'export http_proxy=socks5h://127.0.0.1:${SOCKS5_PORT}'  >> /etc/profile.d/warp.sh"
  echo "    source /etc/profile.d/warp.sh"
  echo ""
  echo "  Python Gemini SDK:"
  echo "    import os"
  echo "    os.environ['https_proxy'] = 'socks5h://127.0.0.1:${SOCKS5_PORT}'"
  echo ""
  echo "  管理:"
  echo "    systemctl status  wireproxy   # 状态"
  echo "    systemctl restart wireproxy   # 重启（换 IP）"
  echo "    bash \$0 -t                    # 测试 Gemini"
  echo "    bash \$0 -u                    # 卸载"
  echo ""
  echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}
# ==================== 状态 / 测试 / 卸载 ====================
show_status() {
  echo ""
  echo -e "${BOLD}=== wireproxy 状态 ===${NC}"
  systemctl status wireproxy --no-pager -l 2>/dev/null || echo "未安装"
  echo ""
  echo -n "  原始 IP : "
  curl -fsSL --max-time 8 https://ipinfo.io/ip 2>/dev/null || echo "获取失败"
  echo ""
  echo -n "  WARP IP : "
  curl -fsSL --max-time 12 --proxy "socks5h://127.0.0.1:${SOCKS5_PORT}" \
    https://ipinfo.io/ip 2>/dev/null || echo "获取失败"
  echo ""
}
test_gemini() {
  echo ""
  echo -e "${BOLD}=== 测试 Gemini API ===${NC}"
  local code
  code=$(curl -fsSL -o /dev/null -w "%{http_code}" --max-time 15 \
    --proxy "socks5h://127.0.0.1:${SOCKS5_PORT}" \
    "https://${GEMINI_HOST}/" 2>/dev/null || echo "000")
  case "$code" in
    200|400|401|404|405) info "Gemini API 可达 ✅ (HTTP ${code})" ;;
    403) warn "返回 403 - 尝试: systemctl restart wireproxy" ;;
    000) error "连接失败 - 检查: systemctl status wireproxy" ;;
    *)   warn "HTTP ${code} - 请手动验证" ;;
  esac
  echo ""
}
do_uninstall() {
  echo ""
  warn "即将卸载 WARP for Gemini..."
  printf "确认卸载? (y/N): "
  read -r confirm
  [ "${confirm}" = "y" ] || [ "${confirm}" = "Y" ] || { info "已取消"; exit 0; }
  systemctl stop wireproxy 2>/dev/null || true
  systemctl disable wireproxy 2>/dev/null || true
  rm -f "$WIREPROXY_SERVICE" "$WIREPROXY_BIN" "$WGCF_BIN"
  rm -f "$WIREPROXY_CONF"
  rm -f "${WARP_CONF_DIR}/wgcf-account.toml"
  rm -f "${WARP_CONF_DIR}/wgcf-profile.conf"
  rm -f /etc/profile.d/warp.sh
  systemctl daemon-reload 2>/dev/null || true
  info "卸载完成"
}
# ==================== 主流程 ====================
main() {
  banner
  ARG="${1:-}"
  case "$ARG" in
    -u|--uninstall)
      check_root
      OS_ID=$(grep '^ID=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')
      do_uninstall
      exit 0
      ;;
    -s|--status)
      show_status
      exit 0
      ;;
    -t|--test)
      test_gemini
      exit 0
      ;;
    -h|--help)
      echo "用法: bash $0 [-u|-s|-t|-h]"
      echo "  (无参数)   安装"
      echo "  -u         卸载"
      echo "  -s         查看状态"
      echo "  -t         测试 Gemini"
      echo ""
      echo "环境变量: WARP_PORT=<端口>  自定义代理端口（默认 40000）"
      exit 0
      ;;
  esac
  # ---- 安装流程 ----
  check_root
  detect_env
  step "Step 1/5: 安装 wireguard-tools"
  install_wireguard_tools
  step "Step 2/5: 安装 wgcf"
  install_wgcf
  step "Step 3/5: 安装 wireproxy"
  install_wireproxy
  step "Step 4/5: 注册 WARP 账户 & 生成配置"
  register_warp
  generate_wireproxy_conf
  step "Step 5/5: 启动服务"
  install_service
  verify
  print_usage
}
main "$@"
