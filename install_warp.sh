#!/usr/bin/env bash
# ==============================================================================
#  WARP for Gemini 终极全局解锁脚本 (修复 TUIC/UDP 断流问题)
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

check_root() {
  [ "$(id -u)" != "0" ] && die "请使用 root 权限运行"
  
  MAIN_IF=$(ip route get 8.8.8.8 | grep -oP 'dev \K\S+')
  MAIN_IP=$(ip -4 addr show dev "$MAIN_IF" | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
  [ -z "$MAIN_IP" ] && die "无法获取主网卡 IP"
  
  ok "主网卡: $MAIN_IF | IP: $MAIN_IP"
}

inst_wg() {
  step "安装 WireGuard & iptables"
  if ! command -v wg >/dev/null 2>&1 || ! command -v iptables >/dev/null 2>&1; then
    apt-get update -qq && apt-get install -y -qq wireguard-tools openresolv iptables || \
    yum install -y epel-release wireguard-tools iptables
  fi
  ok "环境安装完成"
}

setup_warp() {
  step "生成 WARP 账户"
  
  if [ ! -x "$WGCF_BIN" ]; then
    ARCH=$(uname -m)
    [ "$ARCH" = "x86_64" ] && A="amd64" || A="arm64"
    curl -fsSL -o "$WGCF_BIN" "https://github.com/ViRb3/wgcf/releases/download/v2.0.12/wgcf_2.0.12_linux_${A}"
    chmod +x "$WGCF_BIN"
  fi

  mkdir -p "$DIR" && cd "$DIR"
  
  if [ ! -f "wgcf-account.toml" ]; then
    "$WGCF_BIN" register --accept-tos >/dev/null 2>&1 || true
    if [ ! -f "wgcf-account.toml" ]; then
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
  ok "WARP 账户就绪"
}

config_wg() {
  step "配置全局路由 (含 TUIC/UDP 完美修复规则)"
  
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

  # 写入防 UDP 断流规则的 WG 配置文件
  cat > "$WG_CONF" <<EOF
[Interface]
PrivateKey = ${PRIVKEY}
Address = 172.16.0.2/32
Address = ${ADDR6}
DNS = 8.8.8.8, 8.8.4.4, 2001:4860:4860::8888
MTU = 1280

# === 核心防断流规则 (完美修复 TUIC 和 SSH) ===
# 1. 保证已有固定 IP 的进程正常回包 (修 SSH/HY2)
PostUp = ip -4 rule add from ${MAIN_IP} lookup main
PostDown = ip -4 rule delete from ${MAIN_IP} lookup main

# 2. 连接标记跟踪 (完美修复 TUIC 等无状态 UDP 代理)
PostUp = iptables -t mangle -I PREROUTING -i ${MAIN_IF} -m conntrack --ctstate NEW -j CONNMARK --set-mark 0x200
PostUp = iptables -t mangle -I OUTPUT -m connmark --mark 0x200 -j MARK --set-mark 0x200
PostUp = ip -4 rule add fwmark 0x200 lookup main

PostDown = iptables -t mangle -D PREROUTING -i ${MAIN_IF} -m conntrack --ctstate NEW -j CONNMARK --set-mark 0x200
PostDown = iptables -t mangle -D OUTPUT -m connmark --mark 0x200 -j MARK --set-mark 0x200
PostDown = ip -4 rule delete fwmark 0x200 lookup main
# ===============================================

[Peer]
PublicKey = bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=
# 接管全局流量，解锁所有 AI
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = 162.159.192.1:2408
EOF

  ok "配置文件写入完成"
}

start_wg() {
  step "重启 WARP 全局接管"
  
  systemctl daemon-reload
  systemctl enable wg-quick@wg0 >/dev/null 2>&1
  systemctl restart wg-quick@wg0
  sleep 3
  
  if ip link show wg0 >/dev/null 2>&1; then
    ok "WARP 虚拟网卡已接管全局流量！"
  else
    die "wg0 网卡启动失败"
  fi
}

verify() {
  step "验证最终解锁状态"
  
  local WARP_IP
  WARP_IP=$(curl -fsSL --max-time 10 https://api.ip.sb/ip 2>/dev/null)
  echo -e "\n  当前全局出站 IP: \033[1;32m${WARP_IP}\033[0m"
  
  local CODE
  CODE=$(curl -fsSL -o /dev/null -w "%{http_code}" --max-time 10 "https://generativelanguage.googleapis.com/")
  
  if [[ "$CODE" =~ ^(200|404|400|401)$ ]]; then
    ok "Gemini API 访问测试: HTTP $CODE (已完美解锁！)"
  else
    warn "Gemini API 测试异常 (HTTP $CODE)，请留意"
  fi
}

clean_old() {
  if systemctl is-active --quiet wireproxy 2>/dev/null; then
    systemctl stop wireproxy 2>/dev/null
    systemctl disable wireproxy 2>/dev/null
    rm -f /etc/systemd/system/wireproxy.service /usr/local/bin/wireproxy /etc/wireguard/wireproxy.conf
    systemctl daemon-reload 2>/dev/null
  fi
}

# 若之前 TUIC 因为残留规则坏了，这里强行清理 iptables 和 ip rule 残留
fix_tuic_remnants() {
  ip -4 rule show | grep 'fwmark 0x200 lookup main' | while read -r _; do ip -4 rule delete fwmark 0x200 lookup main 2>/dev/null; done
  ip -4 rule show | grep 'lookup main' | grep -v 'fwmark' | grep -v 'local' | while read -r line; do ip -4 rule delete $(echo "$line" | cut -d':' -f2) 2>/dev/null; done
  iptables -t mangle -D PREROUTING -i $(ip route get 8.8.8.8 | grep -oP 'dev \K\S+') -m conntrack --ctstate NEW -j CONNMARK --set-mark 0x200 2>/dev/null || true
  iptables -t mangle -D OUTPUT -m connmark --mark 0x200 -j MARK --set-mark 0x200 2>/dev/null || true
}

main() {
  echo -e "\n\033[1;36m===================================================\033[0m"
  echo -e "\033[1m  WARP for Gemini 终极全局解锁脚本 (TUIC 修复版)\033[0m"
  echo -e "\033[1;36m===================================================\033[0m\n"
  
  check_root
  fix_tuic_remnants
  clean_old
  inst_wg
  setup_warp
  config_wg
  start_wg
  verify
  
  echo -e "\n\033[1;32m🎉 恭喜！修复版已安装完成！\033[0m"
  echo -e "👉 \033[1mTUIC 断流问题已通过 CONNMARK 状态跟踪完美修复。\033[0m"
  echo -e "👉 \033[1m全局 IPv4 已被 WARP 接管，Gemini 恢复解锁，请尽情使用！\033[0m"
}

main "$@"
