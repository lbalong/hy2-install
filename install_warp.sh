#!/usr/bin/env bash
# ==============================================================================
#  WARP for Gemini - 一键脚本
#  解锁 RackNerd VPS 对 Google Gemini API 的访问限制
#
#  原理：使用 wgcf 注册 WARP 账户，结合 wireproxy 在本地暴露 SOCKS5 代理
#        wireproxy 方案无需修改系统路由，SSH 绝对安全，兼容性最强
#
#  用法：
#    bash warp_gemini.sh          # 安装
#    bash warp_gemini.sh -u       # 卸载
#    bash warp_gemini.sh -s       # 查看状态
#    bash warp_gemini.sh -t       # 测试 Gemini 是否可达
# ==============================================================================
set -euo pipefail
# ==================== 可修改配置 ====================
SOCKS5_PORT="${WARP_PORT:-40000}"          # 本地 SOCKS5 代理端口
WARP_CONF_DIR="/etc/wireguard"
WIREPROXY_BIN="/usr/local/bin/wireproxy"
WGCF_BIN="/usr/local/bin/wgcf"
WARP_CONF="${WARP_CONF_DIR}/warp.conf"
WIREPROXY_CONF="${WARP_CONF_DIR}/wireproxy.conf"
WIREPROXY_SERVICE="/etc/systemd/system/wireproxy.service"
GEMINI_HOST="generativelanguage.googleapis.com"
# 多个 wgcf 注册 API 反代，自动择优（借鉴 fscarmen 思路）
WGCF_API_MIRRORS=(
  "https://warp.cloudflare.nyc.mn/?run=register"
  "https://api.zeroteam.top/warp?run=register"
)
# ====================================================
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${GREEN}[✓]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
error()   { echo -e "${RED}[✗]${NC} $*" >&2; }
step()    { echo -e "\n${CYAN}${BOLD}==> $*${NC}"; }
die()     { error "$*"; exit 1; }
banner() {
  echo -e "${CYAN}${BOLD}"
  cat <<'BANNER'
 ██╗    ██╗ █████╗ ██████╗ ██████╗
 ██║    ██║██╔══██╗██╔══██╗██╔══██╗
 ██║ █╗ ██║███████║██████╔╝██████╔╝
 ██║███╗██║██╔══██║██╔══██╗██╔═══╝
 ╚███╔███╔╝██║  ██║██║  ██║██║
  ╚══╝╚══╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝   for Gemini
BANNER
  echo -e "${NC}  解锁 Google Gemini API | 基于 wgcf + wireproxy"
  echo -e "  SOCKS5 端口: ${BOLD}${SOCKS5_PORT}${NC}"
  echo ""
}
# ==================== 前置检查 ====================
check_root() {
  [[ $EUID -ne 0 ]] && die "请以 root 权限运行: sudo bash $0"
}
check_virt() {
  local virt=""
  command -v systemd-detect-virt &>/dev/null && virt=$(systemd-detect-virt 2>/dev/null || true)
  if [[ "$virt" == "openvz" || "$virt" == "lxc" ]]; then
    die "不支持 OpenVZ/LXC 虚拟化，请使用 KVM VPS"
  fi
  info "虚拟化类型: ${virt:-未知}"
}
detect_arch() {
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64)  ARCH_WGCF="amd64"; ARCH_WP="amd64" ;;
    aarch64) ARCH_WGCF="arm64"; ARCH_WP="arm64" ;;
    armv7l)  ARCH_WGCF="armv7"; ARCH_WP="arm" ;;
    *)        die "不支持的架构: $ARCH" ;;
  esac
  info "系统架构: $ARCH"
}
detect_os() {
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS_ID="${ID,,}"
    OS_VER="${VERSION_ID%%.*}"
    OS_CODENAME="${VERSION_CODENAME:-}"
  else
    die "无法识别操作系统"
  fi
  info "操作系统: ${PRETTY_NAME:-$OS_ID}"
}
# ==================== 工具下载 ====================
# 获取 GitHub 最新 Release 的下载 URL
get_github_latest_url() {
  local repo="$1"
  local pattern="$2"
  curl -fsSL --max-time 15 "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null \
    | grep '"browser_download_url"' \
    | grep -i "$pattern" \
    | head -1 \
    | cut -d'"' -f4
}
install_wgcf() {
  if [[ -x "$WGCF_BIN" ]]; then
    info "wgcf 已存在: $($WGCF_BIN version 2>/dev/null | head -1)"
    return
  fi
  step "下载 wgcf..."
  local url
  url=$(get_github_latest_url "ViRb3/wgcf" "linux.*${ARCH_WGCF}") || true
  if [[ -z "$url" ]]; then
    # 回退到已知稳定版本
    local ver="2.0.12"
    url="https://github.com/ViRb3/wgcf/releases/download/v${ver}/wgcf_${ver}_linux_${ARCH_WGCF}"
    warn "自动获取版本失败，使用稳定版 v${ver}"
  fi
  info "下载地址: $url"
  curl -fsSL --max-time 60 -o "$WGCF_BIN" "$url" || die "wgcf 下载失败，请检查网络"
  chmod +x "$WGCF_BIN"
  info "wgcf 安装完成: $($WGCF_BIN version 2>/dev/null | head -1)"
}
install_wireproxy() {
  if [[ -x "$WIREPROXY_BIN" ]]; then
    info "wireproxy 已存在: $($WIREPROXY_BIN -v 2>/dev/null | head -1)"
    return
  fi
  step "下载 wireproxy..."
  local url
  url=$(get_github_latest_url "pufferffish/wireproxy" "linux.*${ARCH_WP}.*tar.gz") || true
  if [[ -z "$url" ]]; then
    local ver="1.0.9"
    url="https://github.com/pufferffish/wireproxy/releases/download/v${ver}/wireproxy_linux_${ARCH_WP}.tar.gz"
    warn "自动获取版本失败，使用稳定版 v${ver}"
  fi
  info "下载地址: $url"
  local tmpdir
  tmpdir=$(mktemp -d)
  trap "rm -rf $tmpdir" EXIT
  curl -fsSL --max-time 60 -o "${tmpdir}/wireproxy.tar.gz" "$url" || die "wireproxy 下载失败"
  tar -xzf "${tmpdir}/wireproxy.tar.gz" -C "$tmpdir"
  install -m 755 "${tmpdir}/wireproxy" "$WIREPROXY_BIN"
  info "wireproxy 安装完成: $($WIREPROXY_BIN -v 2>/dev/null | head -1)"
}
install_wireguard_tools() {
  if command -v wg &>/dev/null; then
    info "wireguard-tools 已存在"
    return
  fi
  step "安装 wireguard-tools..."
  case "$OS_ID" in
    ubuntu|debian)
      apt-get update -qq
      apt-get install -y -qq wireguard-tools >/dev/null
      ;;
    centos|rhel|rocky|almalinux)
      if [[ "$OS_VER" -ge 8 ]]; then
        dnf install -y epel-release >/dev/null 2>&1 || true
        dnf install -y wireguard-tools >/dev/null
      else
        yum install -y epel-release >/dev/null 2>&1 || true
        yum install -y wireguard-tools >/dev/null
      fi
      ;;
    fedora)
      dnf install -y wireguard-tools >/dev/null
      ;;
    *)
      die "不支持的系统: $OS_ID，请手动安装 wireguard-tools"
      ;;
  esac
  info "wireguard-tools 安装完成"
}
# ==================== WARP 账户注册 ====================
register_warp() {
  mkdir -p "$WARP_CONF_DIR"
  # 如已有有效配置则跳过
  if [[ -f "${WARP_CONF_DIR}/wgcf-account.toml" ]]; then
    info "已有 WARP 账户配置，跳过注册"
    return
  fi
  step "注册 WARP 免费账户..."
  # 尝试用镜像 API 注册，获取预设账户（借鉴 fscarmen 的预设账户兜底策略）
  local account=""
  for api in "${WGCF_API_MIRRORS[@]}"; do
    account=$(curl -fsSL --max-time 10 "$api" 2>/dev/null || true)
    if echo "$account" | grep -q '"private_key"'; then
      info "通过镜像 API 获取账户成功"
      break
    fi
    account=""
  done
  cd "$WARP_CONF_DIR"
  if [[ -n "$account" ]]; then
    # 将 API 返回的账户转换为 wgcf toml 格式
    local privkey pubkey license
    privkey=$(echo "$account" | grep -o '"private_key":"[^"]*"' | cut -d'"' -f4)
    pubkey=$(echo "$account"  | grep -o '"public_key":"[^"]*"'  | cut -d'"' -f4 | head -1 || true)
    license=$(echo "$account" | grep -o '"license":"[^"]*"'     | cut -d'"' -f4 || true)
    # 若能直接通过 wgcf 注册则优先，API 账户作备用
    if "$WGCF_BIN" register --accept-tos 2>/dev/null; then
      info "wgcf 直接注册成功"
    else
      warn "wgcf 直连注册失败，使用预设账户"
      # 写一个最小化的 toml 让 wgcf generate 能用
      cat > wgcf-account.toml <<TOML
access_token = 'preset'
account_id = 'preset'
license_key = '${license}'
private_key = '${privkey}'
token = 'preset'
TOML
    fi
  else
    # 纯离线预设：直接使用 fscarmen 脚本中内置的公共账户信息
    warn "所有在线注册渠道失败，使用内置备用账户"
    cat > wgcf-account.toml <<'TOML'
access_token = 'preset'
account_id = 'preset'
license_key = '36L7Pg9E-j6Jp2x04-I40UQ39C'
private_key = 'hTk06uwwXhZx3RVqtug3MQ0RSodzdM/U5z/M5NIbh4c='
token = 'preset'
TOML
  fi
  # 生成 WireGuard 配置
  "$WGCF_BIN" generate --force 2>/dev/null || die "生成 wgcf-profile.conf 失败"
  info "WARP WireGuard 配置生成完成"
  # 将生成的配置移到标准位置
  [[ -f wgcf-profile.conf ]] && cp wgcf-profile.conf "$WARP_CONF"
}
# ==================== 生成 wireproxy 配置 ====================
generate_wireproxy_conf() {
  step "生成 wireproxy 配置..."
  # 从 wgcf-profile.conf 提取所需字段
  local conf_src="${WARP_CONF_DIR}/wgcf-profile.conf"
  [[ ! -f "$conf_src" ]] && conf_src="$WARP_CONF"
  [[ ! -f "$conf_src" ]] && die "找不到 WireGuard 配置文件"
  local privkey endpoint pubkey dns addr4 addr6 reserved=""
  privkey=$(  awk '/^\[Interface\]/,/^\[Peer\]/' "$conf_src" | grep '^PrivateKey' | cut -d= -f2- | tr -d ' ')
  addr4=$(    awk '/^\[Interface\]/,/^\[Peer\]/' "$conf_src" | grep '^Address'    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+' | head -1)
  addr6=$(    awk '/^\[Interface\]/,/^\[Peer\]/' "$conf_src" | grep '^Address'    | grep -oE '[0-9a-f:]+/[0-9]+' | head -1)
  dns=$(      awk '/^\[Interface\]/,/^\[Peer\]/' "$conf_src" | grep '^DNS'        | cut -d= -f2- | tr -d ' ' | head -1)
  pubkey=$(   awk '/^\[Peer\]/,0'                "$conf_src" | grep '^PublicKey'  | cut -d= -f2- | tr -d ' ')
  endpoint=$( awk '/^\[Peer\]/,0'                "$conf_src" | grep '^Endpoint'   | cut -d= -f2- | tr -d ' ')
  reserved=$( awk '/^\[Peer\]/,0'                "$conf_src" | grep '^Reserved'   | cut -d= -f2- | tr -d ' ')
  # 若 wgcf 没有写 Reserved，尝试从 API 账户 JSON 中取（兜底）
  [[ -z "$reserved" ]] && reserved="[0,0,0]"
  # 默认 DNS（Cloudflare）
  dns="${dns:-1.1.1.1}"
  cat > "$WIREPROXY_CONF" <<CONF
[Interface]
PrivateKey = ${privkey}
Address = ${addr4:-172.16.0.2/32}
${addr6:+Address = ${addr6}}
DNS = ${dns}
[Peer]
PublicKey = ${pubkey}
AllowedIPs = 0.0.0.0/0
AllowedIPs = ::/0
Endpoint = ${endpoint:-engage.cloudflareclient.com:2408}
Reserved = ${reserved}
[Socks5]
BindAddress = 127.0.0.1:${SOCKS5_PORT}
CONF
  info "wireproxy 配置写入: $WIREPROXY_CONF"
}
# ==================== 安装 systemd 服务 ====================
install_service() {
  step "配置 systemd 服务..."
  cat > "$WIREPROXY_SERVICE" <<SERVICE
[Unit]
Description=WireProxy - WARP SOCKS5 Proxy for Gemini
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
  systemctl enable --now wireproxy
  info "wireproxy 服务已启动并设置开机自启"
}
# ==================== 验证 ====================
verify() {
  step "验证连接..."
  sleep 3
  if ! systemctl is-active --quiet wireproxy; then
    error "wireproxy 服务未运行，查看日志:"
    journalctl -u wireproxy -n 30 --no-pager
    return 1
  fi
  local orig_ip warp_ip warp_org
  orig_ip=$(curl -fsSL --max-time 10 https://ipinfo.io/ip 2>/dev/null || echo "获取失败")
  warp_ip=$(curl -fsSL --max-time 15 --proxy "socks5h://127.0.0.1:${SOCKS5_PORT}" https://ipinfo.io/ip 2>/dev/null || echo "获取失败")
  warp_org=$(curl -fsSL --max-time 15 --proxy "socks5h://127.0.0.1:${SOCKS5_PORT}" https://ipinfo.io/org 2>/dev/null || echo "未知")
  echo ""
  echo -e "  原始 IP  : ${BOLD}${orig_ip}${NC}"
  echo -e "  WARP IP  : ${GREEN}${BOLD}${warp_ip}${NC}"
  echo -e "  IP 归属  : ${warp_org}"
  echo ""
  if [[ "$warp_ip" == "获取失败" ]]; then
    warn "无法通过 WARP 代理获取 IP，可能连接失败"
    warn "查看日志: journalctl -u wireproxy -n 50 --no-pager"
    return 1
  fi
  # 测试 Gemini 可达性
  local http_code
  http_code=$(curl -fsSL -o /dev/null -w "%{http_code}" --max-time 15 \
    --proxy "socks5h://127.0.0.1:${SOCKS5_PORT}" \
    "https://${GEMINI_HOST}/" 2>/dev/null || echo "000")
  if [[ "$http_code" =~ ^(200|400|401|404|405)$ ]]; then
    info "🎉 Gemini API 可达！(HTTP ${http_code})"
    echo ""
    echo -e "${GREEN}${BOLD}  ✅ 安装成功！${NC}"
  elif [[ "$http_code" == "403" ]]; then
    warn "Gemini 返回 403，当前 WARP IP 可能仍被限制"
    warn "尝试重启服务更换 IP: systemctl restart wireproxy"
  else
    warn "Gemini 返回 HTTP ${http_code}，请手动验证"
  fi
}
# ==================== 使用说明 ====================
print_usage() {
  echo ""
  echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${CYAN}${BOLD}  使用说明${NC}"
  echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  echo -e "  ${BOLD}SOCKS5 代理地址:${NC}"
  echo -e "    ${GREEN}socks5h://127.0.0.1:${SOCKS5_PORT}${NC}"
  echo ""
  echo -e "  ${BOLD}curl 使用:${NC}"
  echo -e "    curl --proxy socks5h://127.0.0.1:${SOCKS5_PORT} https://${GEMINI_HOST}/"
  echo ""
  echo -e "  ${BOLD}环境变量（当前终端）:${NC}"
  echo -e "    export https_proxy=socks5h://127.0.0.1:${SOCKS5_PORT}"
  echo -e "    export http_proxy=socks5h://127.0.0.1:${SOCKS5_PORT}"
  echo ""
  echo -e "  ${BOLD}全局环境变量（永久）:${NC}"
  cat <<ENVTIP
    echo 'export https_proxy=socks5h://127.0.0.1:${SOCKS5_PORT}' >> /etc/profile.d/warp.sh
    echo 'export http_proxy=socks5h://127.0.0.1:${SOCKS5_PORT}'  >> /etc/profile.d/warp.sh
    source /etc/profile.d/warp.sh
ENVTIP
  echo ""
  echo -e "  ${BOLD}Python Gemini SDK:${NC}"
  echo -e "    import os"
  echo -e "    os.environ['https_proxy'] = 'socks5h://127.0.0.1:${SOCKS5_PORT}'"
  echo -e "    import google.generativeai as genai"
  echo ""
  echo -e "  ${BOLD}管理命令:${NC}"
  echo -e "    systemctl status wireproxy      # 查看状态"
  echo -e "    systemctl restart wireproxy     # 重启（更换 IP）"
  echo -e "    bash $0 -s                      # 查看状态"
  echo -e "    bash $0 -t                      # 测试 Gemini"
  echo -e "    bash $0 -u                      # 卸载"
  echo ""
  echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}
# ==================== 状态查看 ====================
show_status() {
  echo ""
  echo -e "${BOLD}=== wireproxy 服务状态 ===${NC}"
  systemctl status wireproxy --no-pager -l || true
  echo ""
  echo -e "${BOLD}=== 当前出口 IP ===${NC}"
  echo -n "  原始 IP : "
  curl -fsSL --max-time 8 https://ipinfo.io/ip 2>/dev/null || echo "获取失败"
  echo ""
  echo -n "  WARP IP : "
  curl -fsSL --max-time 10 --proxy "socks5h://127.0.0.1:${SOCKS5_PORT}" https://ipinfo.io/ip 2>/dev/null || echo "获取失败（服务未运行？）"
  echo ""
}
# ==================== 测试 Gemini ====================
test_gemini() {
  echo ""
  echo -e "${BOLD}=== 测试 Gemini API 可达性 ===${NC}"
  local code
  code=$(curl -fsSL -o /dev/null -w "%{http_code}" --max-time 15 \
    --proxy "socks5h://127.0.0.1:${SOCKS5_PORT}" \
    "https://${GEMINI_HOST}/" 2>/dev/null || echo "000")
  if [[ "$code" =~ ^(200|400|401|404|405)$ ]]; then
    info "Gemini API 可达 (HTTP ${code}) ✅"
  elif [[ "$code" == "403" ]]; then
    warn "Gemini 返回 403 - 当前 WARP IP 被限制，尝试: systemctl restart wireproxy"
  else
    error "连接失败 (HTTP ${code})，检查 wireproxy 是否运行: systemctl status wireproxy"
  fi
  echo ""
}
# ==================== 卸载 ====================
uninstall() {
  echo ""
  warn "即将卸载 WARP for Gemini..."
  read -rp "确认卸载? (y/N): " confirm
  [[ "${confirm,,}" != "y" ]] && { info "取消"; exit 0; }
  systemctl stop wireproxy 2>/dev/null || true
  systemctl disable wireproxy 2>/dev/null || true
  rm -f "$WIREPROXY_SERVICE" "$WIREPROXY_BIN" "$WGCF_BIN"
  rm -f "$WIREPROXY_CONF" "$WARP_CONF"
  rm -f "${WARP_CONF_DIR}/wgcf-account.toml" "${WARP_CONF_DIR}/wgcf-profile.conf"
  rm -f /etc/profile.d/warp.sh
  systemctl daemon-reload 2>/dev/null || true
  info "卸载完成"
}
# ==================== 主流程 ====================
main() {
  banner
  case "${1:-}" in
    -u|--uninstall) check_root; detect_os; uninstall; exit 0 ;;
    -s|--status)    show_status; exit 0 ;;
    -t|--test)      test_gemini; exit 0 ;;
    -h|--help)
      echo "用法: bash $0 [选项]"
      echo "  (无参数)       安装"
      echo "  -u, --uninstall  卸载"
      echo "  -s, --status     查看状态"
      echo "  -t, --test       测试 Gemini API"
      echo ""
      echo "环境变量:"
      echo "  WARP_PORT=<端口>   自定义 SOCKS5 端口（默认 40000）"
      exit 0
      ;;
  esac
  check_root
  detect_os
  detect_arch
  check_virt
  step "Step 1/5: 安装系统依赖"
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
