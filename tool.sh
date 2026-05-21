#!/bin/sh

# 1. 环境基础合规性检查
if [ ! -f /etc/openwrt_release ]; then
    echo "❌ 错误：未检测到标准的 OpenWrt/ImmortalWrt 系统文件，脚本退出。"
    exit 1
fi

. /etc/openwrt_release
SYS_TITLE="${DISTRIB_DESCRIPTION:-$DISTRIB_ID $DISTRIB_RELEASE}"

# 🎯 2. 前置自动补齐 curl 命令及 HTTPS 证书链
if ! command -v curl >/dev/null 2>&1; then
    echo "🌐 检测到原厂系统未打包 curl 命令，正在全自动为您铺设底层网络水管..."
    rm -rf /var/cache/apk/* /tmp/apk* 2>/dev/null
    apk update >/dev/null 2>&1
    apk add curl ca-bundle libustream-openssl >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "❌ 严重错误：底层 curl 组件补齐失败，请检查软路由国内网络是否通畅！"
        exit 1
    fi
    echo "✅ curl 核心及安全证书链已满血就位。"
fi

update_source() {
    echo "🔄 正在执行前置洗地，清空旧缓存暗病..."
    rm -rf /var/cache/apk/* /tmp/luci-*cache /tmp/apk* 2>/dev/null
    echo "🔄 正在同步本地官方 APK 软件包索引 (apk update)..."
    apk update
}

refresh_system() {
    echo "🧹 正在强制清理网页菜单缓存并重载界面..."
    rm -rf /tmp/luci-indexcache /tmp/luci-modulecache 2>/dev/null
    echo "🔄 正在重新唤醒防火墙、网页与代理服务核心..."
    /etc/init.d/uhttpd restart 2>/dev/null
    /etc/init.d/nginx restart 2>/dev/null
    /etc/init.d/firewall restart 2>/dev/null
    [ -f /etc/init.d/passwall ] && /etc/init.d/passwall restart 2>/dev/null
}

# ==================== 核心模块 1：PassWall ====================
install_passwall() {
    echo "-------------------------------------------------"
    rm -f /etc/apk/repositories 2>/dev/null
    rm -f /etc/apk/repositories.d/custom.list 2>/dev/null
    rm -f /etc/apk/repositories.d/customfeeds.list 2>/dev/null
    
    update_source
    echo "-------------------------------------------------"
    echo "🔍 正在读取 PassWall 组件版本信息..."

    if apk info -e luci-app-passwall >/dev/null 2>&1; then
        CURRENT_VER=$(apk list -I luci-app-passwall 2>/dev/null | head -n 1 | awk '{print $1}' | sed 's/luci-app-passwall-//')
    else
        CURRENT_VER="未安装"
    fi

    LATEST_VER=$(apk list luci-app-passwall 2>/dev/null | head -n 1 | awk '{print $1}' | sed 's/luci-app-passwall-//')
    
    if [ -z "$LATEST_VER" ]; then
        echo "❌ 警告：当前系统官方软件源内未发现 luci-app-passwall。"
        echo "-------------------------------------------------"
        echo "💡 我们可以尝试为您自动下发安全公网密钥，并接入完美适配 APK v3 的正统 PassWall 扩展源。"
        printf "❓ 是否允许脚本尝试为您配置第三方 PassWall 软件源？[y/N]: "
        read add_repo
        
        if [ "$add_repo" = "y" ] || [ "$add_repo" = "Y" ]; then
            ARCH=$(cat /etc/apk/arch 2>/dev/null || echo "aarch64_cortex-a53")
            CUSTOM_REPO_FILE="/etc/apk/repositories.d/customfeeds.list"
            
            mkdir -p /etc/apk/repositories.d
            mkdir -p /etc/apk/keys
            
            echo "🔑 正在同步下发专属第三方安全信任密钥..."
            curl -sLk "https://master.dl.sourceforge.net/project/openwrt-passwall-build/apk.pub" -o /etc/apk/keys/passwall.pub
            
            echo "📥 正在配置全套兼容的经典 Passwall 核心及前端组件专线..."
            echo "https://master.dl.sourceforge.net/project/openwrt-passwall-build/releases/packages-25.12/$ARCH/passwall_luci/packages.adb" > "$CUSTOM_REPO_FILE"
            echo "https://master.dl.sourceforge.net/project/openwrt-passwall-build/releases/packages-25.12/$ARCH/passwall_packages/packages.adb" >> "$CUSTOM_REPO_FILE"
            echo "✅ 扩展源及公钥配置完毕。"
            
            update_source
            LATEST_VER=$(apk list luci-app-passwall 2>/dev/null | head -n 1 | awk '{print $1}' | sed 's/luci-app-passwall-//')
        fi
        
        if [ -z "$LATEST_VER" ]; then
            echo "❌ 错误：依旧未发现 luci-app-passwall，请手动检查网络或更换有效的自定义镜像源。"
            return 1
        fi
    fi

    echo "📊 PassWall 版本看板："
    echo "   • 当前本地已安装: ${CURRENT_VER}"
    echo "   • 软件源最新可用: ${LATEST_VER}"
    echo "-------------------------------------------------"

    printf "❓ 是否确认执行满血安装/升级流程？[y/N]: "
    read confirm
    switch_confirm=$(echo "$confirm" | tr '[:upper:]' '[:lower:]')
    
    if [ "$switch_confirm" = "y" ] || [ "$switch_confirm" = "yes" ]; then
        echo "🚀 正在全自动部署前端、汉化包、多协议核心及防火墙内核抓包外挂..."
        apk add --allow-untrusted \
                luci-app-passwall \
                luci-i18n-passwall-zh-cn \
                luci-i18n-base-zh-cn \
                xray-core \
                sing-box \
                hysteria \
                geoview \
                chinadns-ng \
                ca-bundle \
                libustream-openssl \
                curl \
                kmod-nft-tproxy \
                ip-full \
                iptables-nft
                
        if [ $? -eq 0 ]; then
            refresh_system
            echo "================================================="
            echo "✅ 🎉 恭喜老哥！PassWall（含 Hysteria 与 Geoview）已完美闭环通关！"
            echo "================================================="
        else
            echo "❌ 安装失败，请查看上方 apk 报错。"
        fi
    else
        echo "🛑 操作已取消。"
    fi
}

uninstall_passwall() {
    echo "-------------------------------------------------"
    echo "🗑️ 正在启动 PassWall 安全卸载程序..."
    
    if [ -f /etc/init.d/passwall ]; then
        echo "🛑 正在强制停止 PassWall 后台所有运行线程..."
        /etc/init.d/passwall stop 2>/dev/null
    fi
    
    apk del luci-app-passwall luci-i18n-passwall-zh-cn
    rm -rf /etc/config/passwall /usr/share/passwall /var/etc/passwall /var/run/passwall* 2>/dev
