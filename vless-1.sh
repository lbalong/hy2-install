#!/bin/bash
set -e
clear

# 铁律第一步：物理创建核心账本目录，确保所有账本读写绝不踩空
mkdir -p /etc/cf_vless
mkdir -p /root/cert
mkdir -p /etc/sing-box

# 激活并提取历史持久化缓存
CONFIG_FILE="/etc/cf_vless/last_cfg.conf"
if [ -f "$CONFIG_FILE" ]; then source "$CONFIG_FILE"; fi

IP=$(curl -sS4 https://ifconfig.me || curl -sS4 https://api.ipify.org)
UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "6a82e704-9ac8-4fb8-bef1-6c9d7d7e390a")

# 用户专属的优选 IP 库
USER_CF_IPS=(108.162.198.5 172.64.229.8 172.64.229.150 172.64.229.221 108.162.198.1 172.64.229.44 172.64.229.100 172.64.53.96 172.64.53.8 108.162.198.8 108.162.198.100 172.64.148.221 173.245.58.50 173.245.58.172)
RANDOM_CF_IP=${USER_CF_IPS[$RANDOM % ${#USER_CF_IPS[@]}]}

CURRENT_PREF_IP="${LAST_PREF_IP:-$RANDOM_CF_IP}"
CURRENT_PROXY="${LAST_OUTBOUND_PROXY:-VPS直连}"
CURRENT_GEO="${LAST_GEO:-未设置}"

echo "=========================================================="
echo "    Cloudflare 避风港：Sing-Box VLESS-WS-TLS 满血完全体"
echo "=========================================================="
echo " 1. 安装/更新 VLESS-WS-TLS 节点 (内核超频调校 + 证书复用)"
echo " 2. 更换出口国家 / 切换直连  (当前出口: [$CURRENT_GEO] $CURRENT_PROXY)"
echo " 3. 查看当前已建节点链接汇总 (快捷命令: sd)"
echo " 4. 彻底卸载节点服务"
echo " 5. 强制刷新/更换 WARP 落地 IP"
echo " 6. 修改节点入站端口 (支持秒切 CF 官方安全端口)"
echo "=========================================================="
read -p "请选择操作 [1-6]: " CHOICE

# ──────────────────────────────────────────────────────────────
# 国家菜单：同时决定 CF 入口标签 和 出口 SOCKS5 代理拉取地区
# ──────────────────────────────────────────────────────────────
COUNTRY_MENU() {
    echo "=========================================================="
    echo " 🌍 选择出口目标网络（流量将从该网络出去）"
    echo "=========================================================="
    echo -e " \033[1;32m[88] ⚡ 启用 Cloudflare WARP 出口 (推荐！秒开/解锁流媒体)\033[0m"
    echo -e " \033[1;31m[99] 🚫 不使用代理，直接用 VPS 出口（直连）\033[0m"
    echo "----------------------------------------------------------"
    echo " 以下为免费 SOCKS5 代理池（穷举测速，速度慢但可换国家）:"
    echo " [1]  🇺🇸 美国   (US)    [2]  🇯🇵 日本   (JP)"
    echo " [3]  🇸🇬 新加坡 (SG)    [4]  🇭🇰 香港   (HK)"
    echo " [5]  🇰🇷 韩国   (KR)    [6]  🇩🇪 德国   (DE)"
    echo " [7]  🇬🇧 英国   (GB)    [8]  🇫🇷 法国   (FR)"
    echo " [9]  🇳🇱 荷兰   (NL)    [10] 🇨🇦 加拿大 (CA)"
    echo " [11] 🇦🇺 澳大利亚(AU)   [12] 🇮🇳 印度   (IN)"
    echo " [13] 🇧🇷 巴西   (BR)    [14] 🇷🇺 俄罗斯 (RU)"
    echo " [15] 🇹🇼 台湾   (TW)    [16] 🇹🇷 土耳其 (TR)"
    echo " [17] 🇦🇷 阿根廷 (AR)    [18] 🇳🇬 尼日利亚(NG)"
    echo "----------------------------------------------------------"
    echo " [0]  ✏️  手动输入 SOCKS5 代理地址（格式: IP:端口）"
    echo "=========================================================="
}

# 根据编号设置 GEO_TAG / PREF_IP_PRESET / COUNTRY_CODE
GET_COUNTRY_CONFIG() {
    local sel="$1"
    case "$sel" in
        1)  GEO_TAG="US"; COUNTRY_CODE="US"; PREF_IP_PRESET="104.16.0.1" ;;
        2)  GEO_TAG="JP"; COUNTRY_CODE="JP"; PREF_IP_PRESET="104.18.16.1" ;;
        3)  GEO_TAG="SG"; COUNTRY_CODE="SG"; PREF_IP_PRESET="104.19.48.1" ;;
        4)  GEO_TAG="HK"; COUNTRY_CODE="HK"; PREF_IP_PRESET="104.21.64.1" ;;
        5)  GEO_TAG="KR"; COUNTRY_CODE="KR"; PREF_IP_PRESET="104.22.0.1" ;;
        6)  GEO_TAG="DE"; COUNTRY_CODE="DE"; PREF_IP_PRESET="104.20.0.1" ;;
        7)  GEO_TAG="GB"; COUNTRY_CODE="GB"; PREF_IP_PRESET="104.17.192.1" ;;
        8)  GEO_TAG="FR"; COUNTRY_CODE="FR"; PREF_IP_PRESET="104.17.64.1" ;;
        9)  GEO_TAG="NL"; COUNTRY_CODE="NL"; PREF_IP_PRESET="104.17.128.1" ;;
        10) GEO_TAG="CA"; COUNTRY_CODE="CA"; PREF_IP_PRESET="104.16.128.1" ;;
        11) GEO_TAG="AU"; COUNTRY_CODE="AU"; PREF_IP_PRESET="104.21.0.1" ;;
        12) GEO_TAG="IN"; COUNTRY_CODE="IN"; PREF_IP_PRESET="104.21.32.1" ;;
        13) GEO_TAG="BR"; COUNTRY_CODE="BR"; PREF_IP_PRESET="104.22.32.1" ;;
        14) GEO_TAG="RU"; COUNTRY_CODE="RU"; PREF_IP_PRESET="104.20.192.1" ;;
        15) GEO_TAG="TW"; COUNTRY_CODE="TW"; PREF_IP_PRESET="104.22.64.1" ;;
        16) GEO_TAG="TR"; COUNTRY_CODE="TR"; PREF_IP_PRESET="104.21.80.1" ;;
        17) GEO_TAG="AR"; COUNTRY_CODE="AR"; PREF_IP_PRESET="104.22.80.1" ;;
        18) GEO_TAG="NG"; COUNTRY_CODE="NG"; PREF_IP_PRESET="104.22.96.1" ;;
        0)
            read -p " 请输入 SOCKS5 代理地址 (格式 IP:端口，例如 1.2.3.4:1080): " MANUAL_PROXY
            read -p " 请输入地区标签 (如 US/JP/SG): " GEO_TAG
            GEO_TAG="${GEO_TAG:-Custom}"
            COUNTRY_CODE="$GEO_TAG"
            PREF_IP_PRESET="${CURRENT_PREF_IP}"
            OUTBOUND_PROXY="$MANUAL_PROXY"
            return 0
            ;;
        88)
            VPS_CC=$(curl -s -m 3 ipinfo.io/country 2>/dev/null | tr -d '\n')
            [ -z "$VPS_CC" ] && VPS_CC="WARP"
            GEO_TAG="$VPS_CC"
            COUNTRY_CODE=""
            PREF_IP_PRESET="${CURRENT_PREF_IP}"
            if GENERATE_WARP_PROFILE; then
                OUTBOUND_PROXY="WARP"
            else
                echo " ⚠️ WARP 启用失败，将回退到直连模式。"
                VPS_CC=$(curl -s -m 3 ipinfo.io/country 2>/dev/null | tr -d '\n')
                [ -z "$VPS_CC" ] && VPS_CC="Direct"
                GEO_TAG="$VPS_CC"
                OUTBOUND_PROXY=""
            fi
            return 0
            ;;
        99|*)
            VPS_CC=$(curl -s -m 3 ipinfo.io/country 2>/dev/null | tr -d '\n')
            [ -z "$VPS_CC" ] && VPS_CC="Direct"
            GEO_TAG="$VPS_CC"
            COUNTRY_CODE=""
            PREF_IP_PRESET="${CURRENT_PREF_IP}"
            OUTBOUND_PROXY=""
            echo " ✅ 已选择直连出口（不使用代理）"
            return 0
            ;;
    esac
    
    # 强制覆盖所有国家的优选IP为用户的私人 IP 库中的随机一个
    PREF_IP_PRESET="$RANDOM_CF_IP"
}

# ──────────────────────────────────────────────────────────────
# 核心函数：从免费代理池拉取指定国家的 SOCKS5 代理并测试
# 成功则设置全局变量 OUTBOUND_PROXY="IP:PORT"
# ──────────────────────────────────────────────────────────────
FETCH_AND_TEST_PROXY() {
    local country="$1"
    local MIN_SPEED_KB="${2:-100}"   # 最低速度门槛，默认 100 KB/s
    OUTBOUND_PROXY=""

    echo " 🌐 正在从各代理源拉取 [$country] 地区的 SOCKS5 代理列表..."
    echo " ⚡ 速度门槛：≥ ${MIN_SPEED_KB} KB/s（低于此门槛将尝试选用最快者）"

    local combined=""

    # ── 数据源1: proxyscrape（按国家直接过滤）──────────────────
    local src1
    src1=$(curl -s --max-time 15 \
        "https://api.proxyscrape.com/v3/free-proxy-list/get?request=displayproxies&country=${country}&protocol=socks5&proxy_format=ipport&format=text&timeout=5000" \
        2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$' | head -1000)
    local cnt1=$(echo "$src1" | grep -c . 2>/dev/null || echo 0)
    echo " 📦 proxyscrape:   $cnt1 条"
    combined=$(printf '%s\n%s' "$combined" "$src1")

    # ── 数据源2: geonode 扩容拉取 ──────
    local p1 p2 src2
    p1=$(curl -s --max-time 15 \
        "https://proxylist.geonode.com/api/proxy-list?protocols=socks5&country=${country}&limit=500&page=1&sort_by=lastChecked&sort_type=desc" \
        2>/dev/null | jq -r '.data[]? | "\(.ip):\(.port)"' 2>/dev/null)
    p2=$(curl -s --max-time 15 \
        "https://proxylist.geonode.com/api/proxy-list?protocols=socks5&country=${country}&limit=500&page=2&sort_by=lastChecked&sort_type=desc" \
        2>/dev/null | jq -r '.data[]? | "\(.ip):\(.port)"' 2>/dev/null)
    src2=$(printf '%s\n%s' "$p1" "$p2" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$' | head -1000)
    local cnt2=$(echo "$src2" | grep -c . 2>/dev/null || echo 0)
    echo " 📦 geonode:       $cnt2 条"
    combined=$(printf '%s\n%s' "$combined" "$src2")

    # ── 数据源3: TheSpeedX 全球大列表 + 批量地理过滤 ──────────
    echo " 📦 TheSpeedX 全球库：正在拉取并按地区过滤（稍等）..."
    local global_raw src3=""
    global_raw=$(curl -s --max-time 20 \
        "https://raw.githubusercontent.com/TheSpeedX/PROXY-List/master/socks5.txt" \
        2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$' | shuf | head -400)
    
    if [ -n "$global_raw" ]; then
        local ips_batch1 ips_batch2 ips_batch3 ips_batch4
        ips_batch1=$(echo "$global_raw" | head -100 | awk -F: '{print "\"" $1 "\""}' | tr '\n' ',' | sed 's/,$//')
        ips_batch2=$(echo "$global_raw" | tail -n +101 | head -100 | awk -F: '{print "\"" $1 "\""}' | tr '\n' ',' | sed 's/,$//')
        ips_batch3=$(echo "$global_raw" | tail -n +201 | head -100 | awk -F: '{print "\"" $1 "\""}' | tr '\n' ',' | sed 's/,$//')
        ips_batch4=$(echo "$global_raw" | tail -n +301 | head -100 | awk -F: '{print "\"" $1 "\""}' | tr '\n' ',' | sed 's/,$//')
        
        local geo1="" geo2="" geo3="" geo4=""
        [ -n "$ips_batch1" ] && geo1=$(curl -s --max-time 12 -X POST "http://ip-api.com/batch?fields=countryCode,query" -H "Content-Type: application/json" --data "[${ips_batch1}]" 2>/dev/null)
        [ -n "$ips_batch2" ] && geo2=$(curl -s --max-time 12 -X POST "http://ip-api.com/batch?fields=countryCode,query" -H "Content-Type: application/json" --data "[${ips_batch2}]" 2>/dev/null)
        [ -n "$ips_batch3" ] && geo3=$(curl -s --max-time 12 -X POST "http://ip-api.com/batch?fields=countryCode,query" -H "Content-Type: application/json" --data "[${ips_batch3}]" 2>/dev/null)
        [ -n "$ips_batch4" ] && geo4=$(curl -s --max-time 12 -X POST "http://ip-api.com/batch?fields=countryCode,query" -H "Content-Type: application/json" --data "[${ips_batch4}]" 2>/dev/null)
        
        local matched_ips
        matched_ips=$(printf '%s\n%s\n%s\n%s' "$geo1" "$geo2" "$geo3" "$geo4" \
            | jq -r ".[]? | select(.countryCode==\"${country}\") | .query" 2>/dev/null)
        if [ -n "$matched_ips" ]; then
            while IFS= read -r mip; do
                local mport
                mport=$(echo "$global_raw" | grep "^${mip}:" | head -1 | awk -F: '{print $2}')
                [ -n "$mport" ] && src3=$(printf '%s\n%s:%s' "$src3" "$mip" "$mport")
            done <<< "$matched_ips"
            src3=$(echo "$src3" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$')
        fi
    fi
    local cnt3=$(echo "$src3" | grep -c . 2>/dev/null || echo 0)
    echo " 📦 TheSpeedX:     $cnt3 条（经地理过滤）"
    combined=$(printf '%s\n%s' "$combined" "$src3")

    # ── 去重 ───────────────────────────────────────────────────
    combined=$(echo "$combined" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$' | sort -u)
    local total
    total=$(echo "$combined" | grep -c . 2>/dev/null || echo 0)
    if [ "$total" -eq 0 ]; then
        echo " ❌ 所有数据源均未找到 [$country] 地区的代理，将使用 VPS 直连出口"
        return 1
    fi

    echo " ----------------------------------------------------------"
    echo " 📋 合并去重后共 $total 个候选代理，开始两关测试（门槛 ${MIN_SPEED_KB} KB/s）..."
    echo " ----------------------------------------------------------"

    local tested=0
    local best_speed=0
    local best_proxy=""
    local best_ip=""

    while IFS= read -r proxy; do
        [ -z "$proxy" ] && continue
        [ "$tested" -ge 1000 ] && break
        tested=$((tested + 1))
        local phost="${proxy%%:*}"
        local pport="${proxy##*:}"

        # 第一关：连通性 + 出口IP
        local exit_ip
        exit_ip=$(curl -s --max-time 5 \
            --socks5-hostname "${phost}:${pport}" \
            "https://api.ipify.org" 2>/dev/null)
        if ! echo "$exit_ip" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
            echo " ✗ [$tested/$total] $proxy → 无响应"
            continue
        fi

        # 第二关：速度测试（下载 100KB，超时 8s）
        local speed_bytes speed_kb=0
        speed_bytes=$(curl -s --max-time 8 \
            --socks5-hostname "${phost}:${pport}" \
            -o /dev/null -w "%{speed_download}" \
            "https://speed.cloudflare.com/__down?bytes=102400" 2>/dev/null)
        if [ -n "$speed_bytes" ] && echo "$speed_bytes" | grep -qE '^[0-9]+(\.[0-9]+)?$'; then
            speed_kb=$(awk "BEGIN {printf \"%d\", ${speed_bytes}/1024}")
        fi

        # 记录最快的代理
        if [ "$speed_kb" -gt "$best_speed" ]; then
            best_speed="$speed_kb"
            best_proxy="$proxy"
            best_ip="$exit_ip"
        fi

        echo " ⚡ [$tested/$total] $proxy → $exit_ip，速度: ${speed_kb} KB/s"

        if [ "$speed_kb" -ge 300 ]; then
            echo " 🚀 发现极速节点(≥300KB/s)，无需继续，提前结束测速！"
            break
        fi
    done <<< "$combined"

    if [ -n "$best_proxy" ]; then
        echo " 🏆 穷举测速完成！挑选出测试池中最快节点："
        echo " ✅ [最终选用] $best_proxy → 出口IP: $best_ip，速度: ${best_speed} KB/s"
        OUTBOUND_PROXY="$best_proxy"
        return 0
    fi

    echo " ❌ 已测试 $tested 个（共 $total 个），完全没有一点速度或连通性。"
    echo " 💡 提示：选 [99] 切换为 VPS 直连"
    return 1
}

# ──────────────────────────────────────────────────────────────
# 生成 WARP WireGuard 配置
# ──────────────────────────────────────────────────────────────
GENERATE_WARP_PROFILE() {
    mkdir -p /etc/cf_vless
    if [ -f "/etc/cf_vless/wgcf-profile.conf" ]; then
        echo " ⚡ 发现已有的 WARP 配置文件，跳过重新注册。"
        return 0
    fi

    echo " 🌐 正在向 Cloudflare 申请 WARP 账户，这可能需要一点时间..."
    local arch=""
    case $(uname -m) in
        x86_64) arch="amd64" ;;
        aarch64) arch="arm64" ;;
        *) echo "不支持的架构: $(uname -m)"; return 1 ;;
    esac

    local wgcf_url="https://github.com/ViRb3/wgcf/releases/download/v2.2.22/wgcf_2.2.22_linux_${arch}"
    curl -sL --max-time 15 "$wgcf_url" -o /tmp/wgcf
    if [ ! -f "/tmp/wgcf" ]; then
        echo " ❌ 下载 wgcf 失败！"
        return 1
    fi
    chmod +x /tmp/wgcf

    cd /etc/cf_vless
    rm -f wgcf-account.toml wgcf-profile.conf
    
    /tmp/wgcf register --accept-tos >/dev/null 2>&1
    if [ ! -f "wgcf-account.toml" ]; then
        echo " ❌ WARP 注册失败，可能是当前 VPS IP 被 Cloudflare 限制注册。"
        rm -f /tmp/wgcf
        return 1
    fi

    /tmp/wgcf generate >/dev/null 2>&1
    if [ ! -f "wgcf-profile.conf" ]; then
        echo " ❌ WARP 配置文件生成失败。"
        rm -f /tmp/wgcf
        return 1
    fi

    rm -f /tmp/wgcf
    echo " ✅ WARP 账户申请并生成成功！"
    return 0
}

# ──────────────────────────────────────────────────────────────
# 写入 sing-box 配置（支持直连和 SOCKS5 出口两种模式）
# ──────────────────────────────────────────────────────────────
WRITE_SINGBOX_CONFIG() {
    local sb_port="$1"
    local sb_domain="$2"
    local sb_uuid="$3"
    local sb_wspath="$4"
    local sb_proxy="$5"   # 可为空（直连）或 "IP:PORT"

    local SB_CONFIG="/etc/sing-box/config.json"

    if [ "$sb_proxy" = "WARP" ]; then
        echo " 🔀 sing-box 出口模式：Cloudflare WARP 骨干网"
        local private_key=$(grep -m1 '^PrivateKey' /etc/cf_vless/wgcf-profile.conf | awk '{print $3}')
        local public_key=$(grep -m1 '^PublicKey' /etc/cf_vless/wgcf-profile.conf | awk '{print $3}')
        local addresses=$(grep '^Address' /etc/cf_vless/wgcf-profile.conf | awk '{print "\"" $3 "\""}' | tr '\n' ',' | sed 's/,$//')
        
        cat > "$SB_CONFIG" <<SBEOF
{
  "log": { "level": "info" },
  "endpoints": [
    {
      "type": "wireguard",
      "tag": "warp-out",
      "address": [${addresses}],
      "private_key": "${private_key}",
      "mtu": 1280,
      "peers": [
        {
          "address": "engage.cloudflareclient.com",
          "port": 2408,
          "public_key": "${public_key}",
          "allowed_ips": ["0.0.0.0/0", "::/0"],
          "reserved": [0,0,0]
        }
      ]
    }
  ],
  "inbounds": [
    {
      "type": "vless",
      "listen": "::",
      "listen_port": ${sb_port},
      "users": [ { "uuid": "${sb_uuid}" } ],
      "transport": { "type": "ws", "path": "${sb_wspath}" },
      "tls": {
        "enabled": true,
        "server_name": "${sb_domain}",
        "certificate_path": "/root/cert/fullchain.cer",
        "key_path": "/root/cert/private.key"
      },
      "tcp_fast_open": true
    }
  ],
  "outbounds": [
    { "type": "direct", "tag": "direct" }
  ],
  "route": { "final": "warp-out" }
}
SBEOF
    elif [ -n "$sb_proxy" ]; then
        local phost="${sb_proxy%%:*}"
        local pport="${sb_proxy##*:}"
        echo " 🔀 sing-box 出口模式：SOCKS5 代理 → $sb_proxy"
        cat > "$SB_CONFIG" <<SBEOF
{
  "log": { "level": "info" },
  "inbounds": [
    {
      "type": "vless",
      "listen": "::",
      "listen_port": ${sb_port},
      "users": [ { "uuid": "${sb_uuid}" } ],
      "transport": {
        "type": "ws",
        "path": "${sb_wspath}"
      },
      "tls": {
        "enabled": true,
        "server_name": "${sb_domain}",
        "certificate_path": "/root/cert/fullchain.cer",
        "key_path": "/root/cert/private.key"
      },
      "tcp_fast_open": true
    }
  ],
  "outbounds": [
    {
      "type": "socks",
      "tag": "proxy-out",
      "server": "${phost}",
      "server_port": ${pport},
      "version": "5"
    },
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "route": {
    "final": "proxy-out"
  }
}
SBEOF
    else
        echo " 🔀 sing-box 出口模式：VPS 直连"
        cat > "$SB_CONFIG" <<SBEOF
{
  "log": { "level": "info" },
  "inbounds": [
    {
      "type": "vless",
      "listen": "::",
      "listen_port": ${sb_port},
      "users": [ { "uuid": "${sb_uuid}" } ],
      "transport": {
        "type": "ws",
        "path": "${sb_wspath}"
      },
      "tls": {
        "enabled": true,
        "server_name": "${sb_domain}",
        "certificate_path": "/root/cert/fullchain.cer",
        "key_path": "/root/cert/private.key"
      },
      "tcp_fast_open": true
    }
  ],
  "outbounds": [ { "type": "direct" } ]
}
SBEOF
    fi
}

# ──────────────────────────────────────────────────────────────
# 部署代理看门狗（每小时自动检测代理存活，失效则换新）
# 这里只做简单的看门狗：如果挂了就切换回直连或重新拉取同国家代理，但为了稳定，先实现重拉取
# ──────────────────────────────────────────────────────────────
DEPLOY_PROXY_WATCHDOG() {
    cat > /usr/local/bin/cf-proxy-watchdog << 'WATCHDOG'
#!/bin/bash
CONFIG_FILE="/etc/cf_vless/last_cfg.conf"
LOG="/var/log/cf-proxy-watchdog.log"
[ -f "$CONFIG_FILE" ] || exit 0
source "$CONFIG_FILE"

# 如果没有设置出口代理或是WARP/直连，不处理
[ -z "$LAST_OUTBOUND_PROXY" ] && exit 0
[ "$LAST_OUTBOUND_PROXY" = "WARP" ] && exit 0
[ -z "$LAST_GEO" ] || [ "$LAST_GEO" = "Direct" ] && exit 0

PHOST="${LAST_OUTBOUND_PROXY%%:*}"
PPORT="${LAST_OUTBOUND_PROXY##*:}"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] 检测代理存活: $LAST_OUTBOUND_PROXY" >> "$LOG"

# 测试当前代理
EXIT_IP=$(curl -s --max-time 8 --socks5-hostname "${PHOST}:${PPORT}" \
    "https://api.ipify.org" 2>/dev/null)

if echo "$EXIT_IP" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ 代理正常，出口IP: $EXIT_IP" >> "$LOG"
    exit 0
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  代理失效，将暂时降级为 VPS 直连" >> "$LOG"

# 为避免看门狗在后台长时间卡死，我们这里仅简单回退直连
PHOST_NEW=""
PPORT_NEW=""
sed -i "s|LAST_OUTBOUND_PROXY=.*|LAST_OUTBOUND_PROXY=\"\"|" "$CONFIG_FILE"

# 重写 sing-box 配置并重启
SB_CONFIG="/etc/sing-box/config.json"
cat > "$SB_CONFIG" <<SBEOF
{
  "log": { "level": "info" },
  "inbounds": [
    {
      "type": "vless",
      "listen": "::",
      "listen_port": ${LAST_PORT},
      "users": [ { "uuid": "${LAST_UUID}" } ],
      "transport": { "type": "ws", "path": "${LAST_WSPATH}" },
      "tls": {
        "enabled": true,
        "server_name": "${LAST_DOMAIN}",
        "certificate_path": "/root/cert/fullchain.cer",
        "key_path": "/root/cert/private.key"
      },
      "tcp_fast_open": true
    }
  ],
  "outbounds": [ { "type": "direct" } ]
}
SBEOF

systemctl restart sing-box 2>/dev/null || true
echo "[$(date '+%Y-%m-%d %H:%M:%S')] sing-box 已重启，回退直连完成" >> "$LOG"
WATCHDOG

    chmod +x /usr/local/bin/cf-proxy-watchdog

    # 注册每小时 cron 任务
    ( crontab -l 2>/dev/null | grep -v 'cf-proxy-watchdog'
      echo "0 * * * * /usr/local/bin/cf-proxy-watchdog" ) | crontab -
    echo " ✅ 代理看门狗已部署（每小时自动检测，失效回退直连以免断网，日志: /var/log/cf-proxy-watchdog.log）"
}

# ──────────────────────────────────────────────────────────────
# 部署快捷命令 sd
# ──────────────────────────────────────────────────────────────
deploy_shortcut() {
    cat > /usr/local/bin/sd << 'SDEOF'
#!/bin/bash
CF_CONF="/etc/cf_vless/last_cfg.conf"
if [ -f "$CF_CONF" ]; then
    source "$CF_CONF"
    PREF_IP="${LAST_PREF_IP:-104.16.0.1}"
    PROXY_STATUS="${LAST_OUTBOUND_PROXY:-VPS直连}"
    [ -z "$LAST_OUTBOUND_PROXY" ] && PROXY_STATUS="VPS直连"
    clear
    echo "=========================================================="
    echo " 📋 双引流节点汇总（可直接两行全选，一次性批量复制导入）"
    echo "=========================================================="
    echo "vless://$LAST_UUID@$LAST_DOMAIN:$LAST_PORT?encryption=none&security=tls&sni=$LAST_DOMAIN&type=ws&host=$LAST_DOMAIN&path=$LAST_ENCODED_PATH#CF-[${LAST_GEO:-Node}]-Domain-$LAST_PORT"
    echo "vless://$LAST_UUID@$PREF_IP:$LAST_PORT?encryption=none&security=tls&sni=$LAST_DOMAIN&type=ws&host=$LAST_DOMAIN&path=$LAST_ENCODED_PATH#CF-[${LAST_GEO:-Node}]-Optimized-$LAST_PORT"
    echo "=========================================================="
    echo " 🌍 出口国家: [${LAST_GEO:-未设置}]  出口代理: $PROXY_STATUS"
    echo "=========================================================="
fi
SDEOF
    chmod +x /usr/local/bin/sd
}

# ══════════════════════════════════════════════════════════════
#  选项 1：安装/更新节点
# ══════════════════════════════════════════════════════════════
if [ "$CHOICE" -eq 1 ]; then
    echo "正在超频优化系统网络层，激活 BBRv2 级别缓冲区与 TCP Fast Open..."
    echo "net.core.default_qdisc = fq" > /etc/sysctl.d/99-cf-vless-bbr.conf
    echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.d/99-cf-vless-bbr.conf
    echo "net.ipv4.tcp_fastopen = 3" >> /etc/sysctl.d/99-cf-vless-bbr.conf
    echo "net.core.rmem_max = 16772160" >> /etc/sysctl.d/99-cf-vless-bbr.conf
    echo "net.core.wmem_max = 16772160" >> /etc/sysctl.d/99-cf-vless-bbr.conf
    echo "net.ipv4.tcp_rmem = 4096 87380 16772160" >> /etc/sysctl.d/99-cf-vless-bbr.conf
    echo "net.ipv4.tcp_wmem = 4096 65536 16772160" >> /etc/sysctl.d/99-cf-vless-bbr.conf
    sysctl --system >/dev/null 2>&1

    echo "正在拉取系统组件..."
    apt update -y && apt install -y curl wget socat cron unzip tar openssl ufw jq

    # ── 国家选择 ────────────────────────────────────────────
    COUNTRY_MENU
    read -p " 请选择出口国家编号: " COUNTRY_SEL
    GET_COUNTRY_CONFIG "${COUNTRY_SEL:-99}"
    CURRENT_PREF_IP="$PREF_IP_PRESET"

    # ── 拉取出口代理（非直连模式/非WARP）──────────────────────────
    OUTBOUND_PROXY=""
    if [ "$COUNTRY_SEL" = "88" ]; then
        OUTBOUND_PROXY="WARP"
    elif [ -n "$COUNTRY_CODE" ] && [ "$COUNTRY_SEL" != "99" ] && [ "$COUNTRY_SEL" != "0" ]; then
        set +e
        FETCH_AND_TEST_PROXY "$COUNTRY_CODE" "100"
        set -e
    fi

    systemctl stop sing-box 2>/dev/null || true
    systemctl stop xray 2>/dev/null || true

    if [ -n "$LAST_DOMAIN" ]; then
        read -p " 请输入域名 (直接回车复用历史域名 [$LAST_DOMAIN]): " DOMAIN_INPUT
        DOMAIN=${DOMAIN_INPUT:-$LAST_DOMAIN}
    else
        while true; do
            read -p " 请输入你在 Cloudflare 解析好的完整域名 (例如 us9.099889.xyz): " DOMAIN
            if [ -n "$DOMAIN" ]; then break; fi
        done
    fi

    echo "正在请求公网 DNS 校验域名解析账目..."
    DOMAIN_IP=$(curl -s4 "https://1.1.1.1/dns-query?name=$DOMAIN" -H "accept: application/dns-json" | grep -oE '"data":"[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}"' | head -n 1 | awk -F'"' '{print $4}')

    if [ -n "$DOMAIN_IP" ] && [ "$DOMAIN_IP" != "$IP" ]; then
        echo "----------------------------------------------------------"
        echo " 提示：检测到当前域名解析 IP 为 [$DOMAIN_IP]，本机 IP 为 [$IP]"
        echo " 如果您在 Cloudflare 后台已经开启了【橙色小云朵】Proxy 保护，属于完全正常现象。"
        echo "----------------------------------------------------------"
        read -p " 是否确认域名绑定无误并强行继续？[Y/n]: " IP_CONFIRM
        if [ "$IP_CONFIRM" = "n" ] || [ "$IP_CONFIRM" = "N" ]; then exit 1; fi
    fi

    if [ -n "$LAST_WSPATH" ]; then
        read -p " 请输入WS路径 (直接回车复用历史路径 [$LAST_WSPATH]): " WSPATH_INPUT
        WSPATH=${WSPATH_INPUT:-$LAST_WSPATH}
    else
        read -p " 请输入WS路径(默认 /ray): " WSPATH_INPUT
        WSPATH=${WSPATH_INPUT:-/ray}
    fi

    while true; do
        if [ -n "$LAST_PORT" ]; then
            read -p " 请输入端口号 (直接回车复用历史端口 [$LAST_PORT]): " PORT_INPUT
            PORT=${PORT_INPUT:-$LAST_PORT}
        else
            read -p " 请输入端口号(默认 8443): " PORT_INPUT
            PORT=${PORT_INPUT:-8443}
        fi
        if [ "$PORT" = "443" ] || [ "$PORT" = "2053" ] || [ "$PORT" = "2083" ] || [ "$PORT" = "2087" ] || [ "$PORT" = "2096" ] || [ "$PORT" = "8443" ]; then break; fi
        echo " 错误：输入的端口不在允许列表中，请重新输入！"
    done

    ENCODED_PATH=$(printf '%s' "$WSPATH" | sed 's/\//%2F/g')

    # 持久化记忆
    {
        echo "LAST_DOMAIN=\"$DOMAIN\""
        echo "LAST_WSPATH=\"$WSPATH\""
        echo "LAST_PORT=\"$PORT\""
        echo "LAST_UUID=\"$UUID\""
        echo "LAST_ENCODED_PATH=\"$ENCODED_PATH\""
        echo "LAST_GEO=\"$GEO_TAG\""
        echo "LAST_PREF_IP=\"$CURRENT_PREF_IP\""
        echo "LAST_OUTBOUND_PROXY=\"$OUTBOUND_PROXY\""
    } > "$CONFIG_FILE"

    bash <(curl -fsSL https://sing-box.app/deb-install.sh)

    if [ ! -f "/root/.acme.sh/acme.sh" ]; then curl https://get.acme.sh | sh || true; fi

    set +e
    CERT_OK=0
    if [ -f "/root/cert/fullchain.cer" ] && [ -f "/root/cert/private.key" ] && [ "$DOMAIN" = "$LAST_DOMAIN" ]; then
        echo " ✅ 检测到本地已有该域名的有效证书快照，自动开启智能复用，跳过申请流！"
        CERT_OK=1
    elif [ -f "/root/.acme.sh/${DOMAIN}_ecc/fullchain.cer" ] && [ -f "/root/.acme.sh/${DOMAIN}_ecc/${DOMAIN}.key" ]; then
        echo " ✅ 检测到 acme.sh 内部物理文件夹仍存有证书，强行提取复用防风控！"
        mkdir -p /root/cert
        cp "/root/.acme.sh/${DOMAIN}_ecc/fullchain.cer" /root/cert/fullchain.cer
        cp "/root/.acme.sh/${DOMAIN}_ecc/${DOMAIN}.key" /root/cert/private.key
        CERT_OK=1
    else
        echo " 正在首选 Let's Encrypt 签发正规证书..."
        ~/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone --keylength ec-256 --force
        if [ $? -eq 0 ]; then
            CERT_OK=1
        else
            echo "=========================================================="
            echo " ⚠️ Let's Encrypt 触发官方频次锁死限制！"
            echo " 🔄 脚本正在全自动切入 ZeroSSL 备用绿色通道..."
            echo "=========================================================="
            ~/.acme.sh/acme.sh --register-account -m admin@$DOMAIN --server zerossl || true
            ~/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone --keylength ec-256 --force --server zerossl
            if [ $? -eq 0 ]; then CERT_OK=1; fi
        fi
    fi
    set -e

    if [ "$CERT_OK" -ne 1 ]; then
        echo " ❌ 错误：所有证书信道（含备用信道）签发均告失败！"
        exit 1
    fi

    ~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" --ecc \
        --fullchain-file /root/cert/fullchain.cer \
        --key-file /root/cert/private.key || true

    WRITE_SINGBOX_CONFIG "$PORT" "$DOMAIN" "$UUID" "$WSPATH" "$OUTBOUND_PROXY"

    ufw allow $PORT/tcp 2>/dev/null || true
    systemctl daemon-reload && systemctl enable sing-box && systemctl restart sing-box

    # 部署看门狗（有代理才有意义）
    if [ -n "$OUTBOUND_PROXY" ]; then
        DEPLOY_PROXY_WATCHDOG
    fi

    deploy_shortcut
    clear
    /usr/local/bin/sd

# ══════════════════════════════════════════════════════════════
#  选项 2：更换出口国家 / 切换直连（不重装节点）
# ══════════════════════════════════════════════════════════════
elif [ "$CHOICE" -eq 2 ]; then
    if [ ! -f "$CONFIG_FILE" ] || [ -z "$LAST_DOMAIN" ]; then
        echo " ❌ 错误：请先选择 [1] 安装节点！"
        exit 1
    fi

    apt install -y jq curl 2>/dev/null || true

    echo "=========================================================="
    echo " 🔄 出口管理（实时更换，无需重装节点）"
    echo " 当前出口: [${LAST_GEO:-未设置}] → ${LAST_OUTBOUND_PROXY:-VPS直连}"
    echo "=========================================================="
    COUNTRY_MENU
    read -p " 请选择新的出口编号: " COUNTRY_SEL
    GET_COUNTRY_CONFIG "${COUNTRY_SEL:-99}"

    OUTBOUND_PROXY=""
    if [ "$COUNTRY_SEL" = "88" ]; then
        OUTBOUND_PROXY="WARP"
    elif [ -n "$COUNTRY_CODE" ] && [ "$COUNTRY_SEL" != "99" ] && [ "$COUNTRY_SEL" != "0" ]; then
        set +e
        FETCH_AND_TEST_PROXY "$COUNTRY_CODE" "100"
        set -e
    fi

    # 更新 sing-box 配置
    WRITE_SINGBOX_CONFIG "$LAST_PORT" "$LAST_DOMAIN" "$LAST_UUID" "$LAST_WSPATH" "$OUTBOUND_PROXY"
    systemctl restart sing-box 2>/dev/null || true

    # 更新持久化配置
    sed -i "s|LAST_GEO=.*|LAST_GEO=\"${GEO_TAG}\"|" "$CONFIG_FILE"
    if grep -q 'LAST_OUTBOUND_PROXY' "$CONFIG_FILE"; then
        sed -i "s|LAST_OUTBOUND_PROXY=.*|LAST_OUTBOUND_PROXY=\"${OUTBOUND_PROXY}\"|" "$CONFIG_FILE"
    else
        echo "LAST_OUTBOUND_PROXY=\"$OUTBOUND_PROXY\"" >> "$CONFIG_FILE"
    fi

    # 部署/更新看门狗
    if [ -n "$OUTBOUND_PROXY" ]; then
        DEPLOY_PROXY_WATCHDOG
    fi

    deploy_shortcut
    clear
    /usr/local/bin/sd
    echo ""
    echo " 🎉 出口已切换！连接节点后访问 https://ip.sb 验证出口 IP 地区。"

# ══════════════════════════════════════════════════════════════
#  选项 3：查看节点
# ══════════════════════════════════════════════════════════════
elif [ "$CHOICE" -eq 3 ]; then
    if [ -f "/usr/local/bin/sd" ]; then /usr/local/bin/sd; else echo " 未找到节点配置！"; fi

# ══════════════════════════════════════════════════════════════
#  选项 4：卸载
# ══════════════════════════════════════════════════════════════
elif [ "$CHOICE" -eq 4 ]; then
    systemctl stop sing-box 2>/dev/null || true
    ( crontab -l 2>/dev/null | grep -v 'cf-proxy-watchdog' ) | crontab - 2>/dev/null || true
    rm -rf /etc/cf_vless /etc/sing-box /usr/local/bin/sd /usr/local/bin/cf-proxy-watchdog /root/cert
    echo " 卸载清洗完成！"

# ══════════════════════════════════════════════════════════════
#  选项 5：刷新/更换 WARP 落地 IP
# ══════════════════════════════════════════════════════════════
elif [ "$CHOICE" -eq 5 ]; then
    if [ ! -f "$CONFIG_FILE" ] || [ -z "$LAST_DOMAIN" ]; then
        echo " ❌ 错误：请先选择 [1] 安装节点！"
        exit 1
    fi
    echo "=========================================================="
    echo " 🔄 正在销毁当前 WARP 账户，向 Cloudflare 重新申请全新 IP..."
    echo "=========================================================="
    # 删掉旧账号配置，强迫重新生成
    rm -f /etc/cf_vless/wgcf-account.toml /etc/cf_vless/wgcf-profile.conf
    
    source "$CONFIG_FILE"
    CURRENT_PREF_IP="${LAST_PREF_IP:-$RANDOM_CF_IP}"
    
    if GENERATE_WARP_PROFILE; then
        WRITE_SINGBOX_CONFIG "$LAST_PORT" "$LAST_DOMAIN" "$LAST_UUID" "$LAST_WSPATH" "WARP"
        systemctl restart sing-box 2>/dev/null || true
        
        # 更新持久化记录
        VPS_CC=$(curl -s -m 3 ipinfo.io/country 2>/dev/null | tr -d '\n')
        [ -z "$VPS_CC" ] && VPS_CC="WARP"
        sed -i "s|LAST_GEO=.*|LAST_GEO=\"$VPS_CC\"|" "$CONFIG_FILE"
        if grep -q 'LAST_OUTBOUND_PROXY' "$CONFIG_FILE"; then
            sed -i "s|LAST_OUTBOUND_PROXY=.*|LAST_OUTBOUND_PROXY=\"WARP\"|" "$CONFIG_FILE"
        else
            echo "LAST_OUTBOUND_PROXY=\"WARP\"" >> "$CONFIG_FILE"
        fi
        
        echo " 🎉 WARP 落地 IP 刷新成功！sing-box 已重启生效。"
        echo " 🌐 请在本地连上节点后，浏览器访问 https://ip.sb 查看你的全新原生 IP！"
    else
        echo " ❌ WARP 刷新失败，可能是当前服务器 IP 被 CF 暂时限制注册，请过几个小时再试。"
    fi

# ══════════════════════════════════════════════════════════════
#  选项 6：修改节点端口（秒切热更）
# ══════════════════════════════════════════════════════════════
elif [ "$CHOICE" -eq 6 ]; then
    if [ ! -f "$CONFIG_FILE" ] || [ -z "$LAST_DOMAIN" ]; then
        echo " ❌ 错误：请先选择 [1] 安装节点！"
        exit 1
    fi
    source "$CONFIG_FILE"
    echo "=========================================================="
    echo " 🔄 节点端口热切换"
    echo " 当前端口: $LAST_PORT"
    echo " 允许的 Cloudflare HTTPS 端口: 443, 2053, 2083, 2087, 2096, 8443"
    echo "=========================================================="
    while true; do
        read -p " 请输入新的端口号: " PORT_INPUT
        if [ "$PORT_INPUT" = "443" ] || [ "$PORT_INPUT" = "2053" ] || [ "$PORT_INPUT" = "2083" ] || [ "$PORT_INPUT" = "2087" ] || [ "$PORT_INPUT" = "2096" ] || [ "$PORT_INPUT" = "8443" ]; then 
            NEW_PORT="$PORT_INPUT"
            break
        fi
        echo " ❌ 错误：输入的端口不在允许列表中，请重新输入！"
    done

    if [ "$NEW_PORT" = "$LAST_PORT" ]; then
        echo " ⚠️ 新端口与当前端口相同，无需修改。"
        exit 0
    fi

    # 重写配置文件
    WRITE_SINGBOX_CONFIG "$NEW_PORT" "$LAST_DOMAIN" "$LAST_UUID" "$LAST_WSPATH" "$LAST_OUTBOUND_PROXY"
    ufw allow $NEW_PORT/tcp 2>/dev/null || true
    systemctl restart sing-box 2>/dev/null || true

    # 更新持久化记录
    sed -i "s|LAST_PORT=.*|LAST_PORT=\"$NEW_PORT\"|" "$CONFIG_FILE"

    # 更新快捷命令
    deploy_shortcut
    clear
    echo " 🎉 端口已成功秒切为 $NEW_PORT ！请重新复制下方节点导入："
    /usr/local/bin/sd

else
    exit 1
fi
