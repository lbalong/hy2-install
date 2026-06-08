#!/bin/bash
# Cloudflare WARP Gemini 解锁一键脚本
# 方案：wgcf 注册账号 + wireproxy 用户态 SOCKS5 代理
# SOCKS5 监听地址：127.0.0.1:40000
set -e
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
NC='\033[0m'
info()    { echo -e "${BLUE}[信息]${NC} $1"; }
success() { echo -e "${GREEN}[成功]${NC} $1"; }
warn()    { echo -e "${YELLOW}[警告]${NC} $1"; }
error()   { echo -e "${RED}[错误]${NC} $1"; exit 1; }
[ "$EUID" -ne 0 ] && error "请使用 root 权限运行本脚本。"
ARCH=$(uname -m)
[ "$ARCH" = "x86_64" ]  && ARCH_TAG="amd64" || \
[ "$ARCH" = "aarch64" ] && ARCH_TAG="arm64" || \
  error "不支持的架构：$ARCH"
# ── 1. 停止旧的官方 warp-svc（如存在）────────────────────────────
info "停止官方 cloudflare-warp 服务（如存在）..."
systemctl stop warp-svc    2>/dev/null || true
systemctl disable warp-svc 2>/dev/null || true
pkill wireproxy            2>/dev/null || true
# ── 2. 安装依赖 ───────────────────────────────────────────────────
info "安装依赖包..."
if command -v apt-get &>/dev/null; then
  apt-get update -y -qq
  apt-get install -y -qq curl tar ca-certificates jq
elif command -v yum &>/dev/null; then
  yum install -y -q curl tar ca-certificates jq
else
  error "无法识别的包管理器，请手动安装 curl tar jq。"
fi
# ── 3. 下载 wgcf（自动获取最新版本号）───────────────────────────
info "获取 wgcf 最新版本号..."
WGCF_VER=$(curl -fsSL "https://api.github.com/repos/ViRb3/wgcf/releases/latest" \
           | jq -r '.tag_name' | tr -d 'v')
[ -z "$WGCF_VER" ] && error "无法获取 wgcf 版本号，请检查网络。"
info "下载 wgcf v${WGCF_VER}..."
curl -fsSL -o /usr/local/bin/wgcf \
  "https://github.com/ViRb3/wgcf/releases/download/v${WGCF_VER}/wgcf_${WGCF_VER}_linux_${ARCH_TAG}"
chmod +x /usr/local/bin/wgcf
# ── 4. 注册 WARP 账号并生成配置 ──────────────────────────────────
info "注册 Cloudflare WARP 账号..."
TMPDIR=$(mktemp -d)
cd "$TMPDIR"
/usr/local/bin/wgcf register --accept-tos || error "wgcf 注册失败，请检查网络连通性。"
/usr/local/bin/wgcf generate            || error "wgcf 配置生成失败。"
PRIVATE_KEY=$(awk -F' = ' '/PrivateKey/{print $2}' wgcf-profile.conf)
PUBLIC_KEY=$(awk -F' = ' '/PublicKey/{print $2}'  wgcf-profile.conf)
ADDR_V4=$(awk -F'[ ,/]' '/^Address/{print $4}'   wgcf-profile.conf)
cd /
rm -rf "$TMPDIR"
[ -z "$PRIVATE_KEY" ] && error "无法解析 PrivateKey。"
[ -z "$PUBLIC_KEY"  ] && error "无法解析 PublicKey。"
[ -z "$ADDR_V4"     ] && ADDR_V4="172.16.0.2"
info "账号注册成功，私钥已提取。"
# ── 5. 下载 wireproxy ─────────────────────────────────────────────
info "下载 wireproxy..."
curl -fsSL "https://github.com/windtf/wireproxy/releases/latest/download/wireproxy_linux_${ARCH_TAG}.tar.gz" \
  | tar -xz -C /usr/local/bin/
chmod +x /usr/local/bin/wireproxy
# ── 6. 逐一探测可用 Endpoint ─────────────────────────────────────
ENDPOINTS=(
  "162.159.193.10:500"
  "162.159.193.10:4500"
  "162.159.192.1:500"
  "162.159.192.1:4500"
  "188.114.96.1:500"
  "188.114.96.1:4500"
  "engage.cloudflareclient.com:2408"
)
write_conf() {
  cat > /etc/wireproxy.conf <<EOF
[WireGuard]
PrivateKey = ${PRIVATE_KEY}
Address = ${ADDR_V4}/32
DNS = 1.1.1.1
[Peer]
PublicKey = ${PUBLIC_KEY}
Endpoint = $1
AllowedIPs = 0.0.0.0/0
[Socks5]
BindAddress = 127.0.0.1:40000
EOF
}
CONNECTED=false
for EP in "${ENDPOINTS[@]}"; do
  info "尝试端点 $EP ..."
  write_conf "$EP"
  /usr/local/bin/wireproxy -c /etc/wireproxy.conf >/dev/null 2>&1 &
  WP_PID=$!
  for i in {1..6}; do
    sleep 1
    RESULT=$(curl -s --max-time 3 --socks5-hostname 127.0.0.1:40000 \
              https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null || true)
    if echo "$RESULT" | grep -q "warp=on\|warp=plus"; then
      CONNECTED=true
      break
    fi
  done
  if [ "$CONNECTED" = true ]; then
    success "端点 $EP 连接成功！"
    break
  fi
  kill $WP_PID 2>/dev/null || true
  wait $WP_PID 2>/dev/null || true
done
[ "$CONNECTED" = false ] && error "所有端点均连接失败，请检查 VPS 防火墙是否放行 UDP 出站流量。"
# 停掉探测进程，改由 systemd 管理
kill $WP_PID 2>/dev/null || true
wait $WP_PID 2>/dev/null || true
# ── 7. 写入 systemd 服务 ──────────────────────────────────────────
info "配置 systemd 服务..."
cat > /etc/systemd/system/wireproxy.service <<'EOF'
[Unit]
Description=Cloudflare WARP Wireproxy SOCKS5
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/wireproxy -c /etc/wireproxy.conf
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now wireproxy
sleep 3
# ── 8. 最终验证 ───────────────────────────────────────────────────
WARP_TRACE=$(curl -s --max-time 5 --socks5-hostname 127.0.0.1:40000 \
             https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null || true)
GEMINI_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 8 \
              --socks5-hostname 127.0.0.1:40000 \
              https://generativelanguage.googleapis.com/ 2>/dev/null || echo "000")
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if echo "$WARP_TRACE" | grep -q "warp=on\|warp=plus"; then
  success "WARP SOCKS5 代理运行正常！"
else
  warn "WARP 代理状态未确认，请手动检查：systemctl status wireproxy"
fi
if [ "$GEMINI_CODE" -eq 200 ] || [ "$GEMINI_CODE" -eq 403 ] || [ "$GEMINI_CODE" -eq 404 ]; then
  success "Gemini API 可访问（HTTP $GEMINI_CODE）！"
else
  warn "Gemini API 响应码：$GEMINI_CODE（可能需要在代理工具中配置分流规则）"
fi
echo ""
echo "  本地 SOCKS5 代理地址：127.0.0.1:40000"
echo "  在 Xray/Sing-box 中将 Gemini 流量指向此地址即可。"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
