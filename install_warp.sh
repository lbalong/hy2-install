#!/usr/bin/env bash
#
# ============================================================================
#  Cloudflare WARP 一键安装脚本 - 解锁 Gemini API
#  适用于 RackNerd 等被 Google 限制的 VPS
# ============================================================================
#
#  功能：
#    - 自动检测系统类型 (Debian/Ubuntu/CentOS/RHEL)
#    - 安装 Cloudflare WARP 客户端
#    - 配置为 proxy 模式（安全，不影响 SSH）
#    - 验证 WARP 连接和 Gemini API 可达性
#    - 配置 systemd 开机自启
#    - 可选：配置全局环境变量代理
#
#  用法：
#    chmod +x install_warp.sh
#    sudo bash install_warp.sh
#
#  卸载：
#    sudo bash install_warp.sh --uninstall
#
# ============================================================================
set -euo pipefail
# ========================== 配置参数 ==========================
WARP_PROXY_PORT="${WARP_PROXY_PORT:-40000}"
GEMINI_API_HOST="generativelanguage.googleapis.com"
PROXY_ADDR="socks5h://127.0.0.1:${WARP_PROXY_PORT}"
MAX_RETRY=30          # WARP 连接等待最大重试次数
RETRY_INTERVAL=2      # 重试间隔（秒）
ENV_FILE="/etc/profile.d/warp-proxy.sh"
# ========================== 颜色输出 ==========================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color
info()    { echo -e "${BLUE}[INFO]${NC}    $*"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}    $*"; }
error()   { echo -e "${RED}[ERROR]${NC}   $*"; }
banner() {
    echo -e "${CYAN}${BOLD}"
    cat << 'EOF'
  ╔══════════════════════════════════════════════════════════╗
  ║   Cloudflare WARP Installer for Gemini API Unblocking   ║
  ║                                                          ║
  ║   解锁 Google Gemini API 访问限制                        ║
  ║   适用于 RackNerd 等受限 VPS                             ║
  ╚══════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}
# ========================== 前置检查 ==========================
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "此脚本需要 root 权限运行"
        echo -e "  请使用: ${BOLD}sudo bash $0${NC}"
        exit 1
    fi
}
check_virt() {
    # 检查虚拟化类型，OpenVZ 不支持 WireGuard/WARP
    if command -v systemd-detect-virt &>/dev/null; then
        local virt
        virt=$(systemd-detect-virt 2>/dev/null || echo "unknown")
        if [[ "$virt" == "openvz" || "$virt" == "lxc" ]]; then
            error "检测到虚拟化类型: ${virt}"
            error "OpenVZ/LXC 容器不支持 Cloudflare WARP，建议使用 KVM VPS"
            exit 1
        fi
        info "虚拟化类型: ${virt}"
    fi
}
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS_ID="${ID,,}"
        OS_VERSION_ID="${VERSION_ID:-}"
        OS_CODENAME="${VERSION_CODENAME:-}"
        OS_NAME="${PRETTY_NAME:-$ID}"
    elif [[ -f /etc/redhat-release ]]; then
        OS_ID="centos"
        OS_VERSION_ID=$(grep -oP '[0-9]+' /etc/redhat-release | head -1)
        OS_NAME=$(cat /etc/redhat-release)
    else
        error "无法识别操作系统类型"
        exit 1
    fi
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)  PKG_ARCH="amd64" ;;
        aarch64) PKG_ARCH="arm64" ;;
        armv7l)  PKG_ARCH="armhf" ;;
        *)
            error "不支持的架构: $ARCH"
            exit 1
            ;;
    esac
    info "系统信息: ${OS_NAME} (${ARCH})"
}
check_existing_warp() {
    if command -v warp-cli &>/dev/null; then
        local status
        status=$(warp-cli status 2>/dev/null || echo "Disconnected")
        if echo "$status" | grep -qi "Connected"; then
            warn "WARP 已安装并处于连接状态"
            echo ""
            echo -e "  当前状态: ${GREEN}已连接${NC}"
            echo -e "  代理端口: ${BOLD}${WARP_PROXY_PORT}${NC}"
            echo ""
            read -rp "是否重新配置？(y/N): " choice
            if [[ "${choice,,}" != "y" ]]; then
                info "跳过安装，退出"
                exit 0
            fi
            # 断开现有连接
            warp-cli disconnect 2>/dev/null || true
        else
            warn "WARP 已安装但未连接，将重新配置"
        fi
    fi
}
# ========================== 安装 WARP ==========================
install_dependencies() {
    info "安装依赖..."
    case "$OS_ID" in
        ubuntu|debian)
            apt-get update -qq
            apt-get install -y -qq curl gnupg lsb-release >/dev/null 2>&1
            ;;
        centos|rhel|rocky|almalinux|fedora)
            yum install -y -q curl >/dev/null 2>&1 || dnf install -y -q curl >/dev/null 2>&1
            ;;
    esac
    success "依赖安装完成"
}
add_warp_repo() {
    info "添加 Cloudflare WARP 仓库..."
    case "$OS_ID" in
        ubuntu|debian)
            # 添加 GPG key
            curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg \
                | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
            # 确定正确的版本代号
            local codename="$OS_CODENAME"
            if [[ -z "$codename" ]]; then
                # Fallback: 尝试 lsb_release
                codename=$(lsb_release -cs 2>/dev/null || echo "")
            fi
            # 如果还是获取不到，根据版本号推断
            if [[ -z "$codename" ]]; then
                case "$OS_ID" in
                    ubuntu)
                        case "${OS_VERSION_ID%%.*}" in
                            20) codename="focal" ;;
                            22) codename="jammy" ;;
                            24) codename="noble" ;;
                            *)  codename="jammy" ;;  # 默认
                        esac
                        ;;
                    debian)
                        case "${OS_VERSION_ID%%.*}" in
                            10) codename="buster" ;;
                            11) codename="bullseye" ;;
                            12) codename="bookworm" ;;
                            *)  codename="bookworm" ;;  # 默认
                        esac
                        ;;
                esac
            fi
            echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ ${codename} main" \
                | tee /etc/apt/sources.list.d/cloudflare-client.list >/dev/null
            info "使用版本代号: ${codename}"
            ;;
        centos|rhel|rocky|almalinux)
            curl -fsSL https://pkg.cloudflareclient.com/cloudflare-warp-ascii.repo \
                | tee /etc/yum.repos.d/cloudflare-warp.repo >/dev/null
            ;;
        fedora)
            curl -fsSL https://pkg.cloudflareclient.com/cloudflare-warp-ascii.repo \
                | tee /etc/yum.repos.d/cloudflare-warp.repo >/dev/null
            ;;
        *)
            error "不支持的操作系统: ${OS_ID}"
            error "支持的系统: Ubuntu, Debian, CentOS, RHEL, Rocky, AlmaLinux, Fedora"
            exit 1
            ;;
    esac
    success "仓库添加完成"
}
install_warp_client() {
    info "安装 Cloudflare WARP 客户端..."
    case "$OS_ID" in
        ubuntu|debian)
            apt-get update -qq
            if ! apt-get install -y -qq cloudflare-warp 2>/dev/null; then
                error "WARP 客户端安装失败"
                error "可能原因: 系统版本不受支持，请检查 https://pkg.cloudflareclient.com/"
                exit 1
            fi
            ;;
        centos|rhel|rocky|almalinux|fedora)
            if ! yum install -y cloudflare-warp 2>/dev/null && ! dnf install -y cloudflare-warp 2>/dev/null; then
                error "WARP 客户端安装失败"
                exit 1
            fi
            ;;
    esac
    # 验证安装
    if ! command -v warp-cli &>/dev/null; then
        error "warp-cli 命令未找到，安装可能失败"
        exit 1
    fi
    local version
    version=$(warp-cli --version 2>/dev/null || echo "unknown")
    success "WARP 客户端安装成功: ${version}"
}
# ========================== 配置 WARP ==========================
configure_warp() {
    info "配置 WARP..."
    # 确保 warp-svc 服务启动
    if systemctl is-active --quiet warp-svc 2>/dev/null; then
        info "warp-svc 服务已运行"
    else
        info "启动 warp-svc 服务..."
        systemctl enable --now warp-svc 2>/dev/null || true
        sleep 3
    fi
    # 检查注册状态，未注册则注册
    local reg_status
    reg_status=$(warp-cli registration show 2>&1 || echo "Missing")
    if echo "$reg_status" | grep -qi "Missing\|No registration"; then
        info "注册 WARP..."
        if ! warp-cli registration new 2>/dev/null; then
            # 某些版本使用旧命令
            warp-cli register 2>/dev/null || true
        fi
        sleep 2
        success "WARP 注册完成"
    else
        info "WARP 已注册，跳过注册步骤"
    fi
    # 设置为 proxy 模式（安全模式，不影响 SSH）
    info "设置为 proxy 模式（端口: ${WARP_PROXY_PORT}）..."
    warp-cli mode proxy 2>/dev/null || warp-cli set-mode proxy 2>/dev/null || true
    warp-cli proxy port "${WARP_PROXY_PORT}" 2>/dev/null || warp-cli set-proxy-port "${WARP_PROXY_PORT}" 2>/dev/null || true
    # 接受 TOS（某些版本需要）
    warp-cli --accept-tos 2>/dev/null || true
    success "WARP 配置完成"
}
connect_warp() {
    info "连接 WARP..."
    warp-cli connect 2>/dev/null || true
    # 等待连接成功
    local retry=0
    while [[ $retry -lt $MAX_RETRY ]]; do
        local status
        status=$(warp-cli status 2>/dev/null || echo "")
        if echo "$status" | grep -qi "Connected"; then
            success "WARP 连接成功！"
            return 0
        fi
        retry=$((retry + 1))
        echo -ne "\r  等待连接... (${retry}/${MAX_RETRY})"
        sleep "$RETRY_INTERVAL"
    done
    echo ""
    error "WARP 连接超时"
    warn "可以尝试手动连接: warp-cli connect"
    return 1
}
# ========================== 验证 ==========================
verify_warp() {
    echo ""
    info "========== 验证 WARP 连接 =========="
    echo ""
    # 检查原始 IP
    local original_ip
    original_ip=$(curl -s --max-time 10 https://ipinfo.io/ip 2>/dev/null || echo "获取失败")
    info "原始出口 IP: ${BOLD}${original_ip}${NC}"
    # 检查 WARP 代理 IP
    local warp_ip
    warp_ip=$(curl -s --max-time 10 --proxy "${PROXY_ADDR}" https://ipinfo.io/ip 2>/dev/null || echo "获取失败")
    if [[ "$warp_ip" == "获取失败" ]]; then
        error "无法通过 WARP 代理获取 IP"
        return 1
    fi
    info "WARP 代理 IP: ${BOLD}${GREEN}${warp_ip}${NC}"
    # 检查 IP 归属
    local warp_org
    warp_org=$(curl -s --max-time 10 --proxy "${PROXY_ADDR}" https://ipinfo.io/org 2>/dev/null || echo "未知")
    info "WARP IP 归属: ${warp_org}"
    # 验证 IP 是否变化
    if [[ "$original_ip" == "$warp_ip" ]]; then
        warn "IP 未发生变化，WARP 代理可能未生效"
    else
        success "IP 已变更，WARP 代理工作正常"
    fi
    echo ""
    # 测试 Gemini API 可达性
    info "测试 Gemini API 可达性..."
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 15 \
        --proxy "${PROXY_ADDR}" \
        "https://${GEMINI_API_HOST}/" 2>/dev/null || echo "000")
    if [[ "$http_code" == "000" ]]; then
        error "Gemini API 连接失败（超时或网络错误）"
        return 1
    elif [[ "$http_code" == "403" ]]; then
        warn "Gemini API 返回 403 - WARP IP 可能仍被限制"
        warn "可以尝试重新连接获取新 IP: warp-cli disconnect && warp-cli connect"
        return 1
    elif [[ "$http_code" =~ ^(200|404|400|401|405)$ ]]; then
        success "Gemini API 可达！(HTTP ${http_code})"
        success "🎉 Google Gemini API 访问限制已成功绕过！"
    else
        info "Gemini API 返回 HTTP ${http_code}（可能正常）"
    fi
    return 0
}
# ========================== 环境变量配置 ==========================
setup_env_proxy() {
    echo ""
    read -rp "是否将 WARP 代理设置为全局环境变量？(y/N): " setup_env
    if [[ "${setup_env,,}" != "y" ]]; then
        info "跳过全局环境变量配置"
        return
    fi
    cat > "${ENV_FILE}" << ENVEOF
# Cloudflare WARP Proxy - Auto-generated
# 用于通过 WARP 代理访问被限制的服务（如 Google Gemini）
export http_proxy="socks5h://127.0.0.1:${WARP_PROXY_PORT}"
export https_proxy="socks5h://127.0.0.1:${WARP_PROXY_PORT}"
export HTTP_PROXY="socks5h://127.0.0.1:${WARP_PROXY_PORT}"
export HTTPS_PROXY="socks5h://127.0.0.1:${WARP_PROXY_PORT}"
# 排除本地地址
export no_proxy="localhost,127.0.0.1,::1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
export NO_PROXY="localhost,127.0.0.1,::1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
ENVEOF
    chmod 644 "${ENV_FILE}"
    success "全局代理环境变量已写入 ${ENV_FILE}"
    warn "需要重新登录或执行 'source ${ENV_FILE}' 使其生效"
}
# ========================== 开机自启 ==========================
setup_autostart() {
    info "配置开机自启..."
    # 创建自启脚本 - 确保 WARP 在重启后自动连接
    local service_file="/etc/systemd/system/warp-auto-connect.service"
    cat > "${service_file}" << 'SVCEOF'
[Unit]
Description=Cloudflare WARP Auto Connect
After=warp-svc.service network-online.target
Wants=network-online.target
Requires=warp-svc.service
[Service]
Type=oneshot
ExecStartPre=/bin/sleep 5
ExecStart=/usr/bin/warp-cli connect
RemainAfterExit=yes
ExecStop=/usr/bin/warp-cli disconnect
[Install]
WantedBy=multi-user.target
SVCEOF
    systemctl daemon-reload
    systemctl enable warp-auto-connect.service 2>/dev/null
    success "开机自启配置完成"
}
# ========================== 输出使用说明 ==========================
print_usage() {
    echo ""
    echo -e "${CYAN}${BOLD}============================================================${NC}"
    echo -e "${CYAN}${BOLD}  安装完成！以下是使用说明${NC}"
    echo -e "${CYAN}${BOLD}============================================================${NC}"
    echo ""
    echo -e "  ${BOLD}WARP SOCKS5 代理地址:${NC}"
    echo -e "    ${GREEN}socks5h://127.0.0.1:${WARP_PROXY_PORT}${NC}"
    echo ""
    echo -e "  ${BOLD}使用方法:${NC}"
    echo ""
    echo -e "  ${YELLOW}1. curl 命令:${NC}"
    echo -e "     curl --proxy socks5h://127.0.0.1:${WARP_PROXY_PORT} https://generativelanguage.googleapis.com/"
    echo ""
    echo -e "  ${YELLOW}2. 环境变量（当前终端生效）:${NC}"
    echo -e "     export https_proxy=socks5h://127.0.0.1:${WARP_PROXY_PORT}"
    echo -e "     export http_proxy=socks5h://127.0.0.1:${WARP_PROXY_PORT}"
    echo ""
    echo -e "  ${YELLOW}3. Python 中使用:${NC}"
    echo -e "     import google.generativeai as genai"
    echo -e "     import os"
    echo -e "     os.environ['https_proxy'] = 'socks5h://127.0.0.1:${WARP_PROXY_PORT}'"
    echo ""
    echo -e "  ${YELLOW}4. Node.js 中使用:${NC}"
    echo -e "     process.env.https_proxy = 'socks5h://127.0.0.1:${WARP_PROXY_PORT}'"
    echo ""
    echo -e "  ${BOLD}常用管理命令:${NC}"
    echo -e "     warp-cli status          # 查看连接状态"
    echo -e "     warp-cli connect         # 连接"
    echo -e "     warp-cli disconnect      # 断开"
    echo -e "     warp-cli registration show  # 查看注册信息"
    echo ""
    echo -e "  ${BOLD}如果 Gemini 仍然不可用:${NC}"
    echo -e "     尝试重新连接以获取新的出口 IP:"
    echo -e "     ${GREEN}warp-cli disconnect && sleep 2 && warp-cli connect${NC}"
    echo ""
    echo -e "${CYAN}${BOLD}============================================================${NC}"
}
# ========================== 卸载 ==========================
uninstall_warp() {
    banner
    warn "即将卸载 Cloudflare WARP..."
    echo ""
    read -rp "确定要卸载吗？(y/N): " confirm
    if [[ "${confirm,,}" != "y" ]]; then
        info "取消卸载"
        exit 0
    fi
    info "断开 WARP 连接..."
    warp-cli disconnect 2>/dev/null || true
    info "删除注册信息..."
    warp-cli registration delete 2>/dev/null || true
    info "停止并删除自启服务..."
    systemctl stop warp-auto-connect.service 2>/dev/null || true
    systemctl disable warp-auto-connect.service 2>/dev/null || true
    rm -f /etc/systemd/system/warp-auto-connect.service
    systemctl daemon-reload 2>/dev/null || true
    info "卸载 WARP 客户端..."
    case "$OS_ID" in
        ubuntu|debian)
            apt-get remove -y --purge cloudflare-warp 2>/dev/null || true
            rm -f /etc/apt/sources.list.d/cloudflare-client.list
            rm -f /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
            ;;
        centos|rhel|rocky|almalinux|fedora)
            yum remove -y cloudflare-warp 2>/dev/null || dnf remove -y cloudflare-warp 2>/dev/null || true
            rm -f /etc/yum.repos.d/cloudflare-warp.repo
            ;;
    esac
    info "清理环境变量..."
    rm -f "${ENV_FILE}"
    success "Cloudflare WARP 已完全卸载"
}
# ========================== 主流程 ==========================
main() {
    banner
    # 处理卸载参数
    if [[ "${1:-}" == "--uninstall" || "${1:-}" == "-u" ]]; then
        check_root
        detect_os
        uninstall_warp
        exit 0
    fi
    # 处理帮助参数
    if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
        echo "用法: sudo bash $0 [选项]"
        echo ""
        echo "选项:"
        echo "  --help, -h        显示帮助信息"
        echo "  --uninstall, -u   卸载 Cloudflare WARP"
        echo ""
        echo "环境变量:"
        echo "  WARP_PROXY_PORT   设置代理端口 (默认: 40000)"
        echo ""
        echo "示例:"
        echo "  sudo bash $0                            # 安装（默认端口 40000）"
        echo "  sudo WARP_PROXY_PORT=1080 bash $0       # 安装（使用端口 1080）"
        echo "  sudo bash $0 --uninstall                # 卸载"
        exit 0
    fi
    # 前置检查
    check_root
    detect_os
    check_virt
    check_existing_warp
    echo ""
    info "========== 开始安装 Cloudflare WARP =========="
    echo ""
    # 安装步骤
    install_dependencies
    add_warp_repo
    install_warp_client
    echo ""
    info "========== 配置 WARP =========="
    echo ""
    configure_warp
    connect_warp
    verify_warp
    # 后续配置
    setup_autostart
    setup_env_proxy
    # 输出使用说明
    print_usage
}
main "$@"
