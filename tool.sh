#!/bin/sh

# 1. 环境基础合规性检查
if [ ! -f /etc/openwrt_release ]; then
    echo "❌ 错误：未检测到标准的 OpenWrt/ImmortalWrt 系统文件，脚本退出。"
    exit 1
fi

. /etc/openwrt_release
SYS_TITLE="${DISTRIB_DESCRIPTION:-$DISTRIB_ID $DISTRIB_RELEASE}"

# 📊 状态账本：记录本轮脚本运行中，是否已经执行过全局索引同步
GLOBAL_UPDATED=0

update_source() {
    echo "🔄 正在同步本地 APK 软件包索引 (apk update)..."
    rm -rf /var/cache/apk/* /tmp/luci-*cache /tmp/apk* 2>/dev/null
    apk update
    GLOBAL_UPDATED=1
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

# 🎯 3. 核心调校：NTP 时间服务器智能对账去重函数
optimize_ntp() {
    echo "-------------------------------------------------"
    echo "⚙️ 正在智能调优 NTP 时间服务器名单..."
    local modified=0
    
    for server in "ntp.aliyun.com" "ntp.tencent.com" "ntp.ntsc.ac.cn" "time.apple.com"; do
        if ! uci get system.ntp.server 2>/dev/null | grep -q "$server"; then
            uci add_list system.ntp.server="$server"
            echo "➕ 成功追加国内优质时间源: $server"
            modified=1
        else
            echo "ℹ️ 检测到系统已存在时间源: $server，自动跳过防止重复。"
        fi
    done
    
    if [ "$modified" -eq 1 ]; then
        uci commit system
        /etc/init.d/system restart 2>/dev/null
        echo "✅ 系统时间服务数据库已成功合闸生效！"
    fi
}

# ==================== 核心模块 1：PassWall ====================
install_passwall() {
    echo "-------------------------------------------------"
    CUSTOM_REPO_FILE="/etc/apk/repositories.d/customfeeds.list"

    # 💡 智能判断：如果发现已经配置过扩展源文件，直接跳过配源动作
    if [ ! -f "$CUSTOM_REPO_FILE" ]; then
        echo "📥 正在为您配置适配 APK v3 的正统 PassWall 扩展源..."
        ARCH=$(cat /etc/apk/arch 2>/dev/null || echo "aarch64_cortex-a53")
        mkdir -p /etc/apk/repositories.d /etc/apk/keys
        
        # 下发密钥与仓库地址
        curl -sLk "https://master.dl.sourceforge.net/project/openwrt-passwall-build/apk.pub" -o /etc/apk/keys/passwall.pub
        echo "https://master.dl.sourceforge.net/project/openwrt-passwall-build/releases/packages-25.12/$ARCH/passwall_luci/packages.adb" > "$CUSTOM_REPO_FILE"
        echo "https://master.dl.sourceforge.net/project/openwrt-passwall-build/releases/packages-25.12/$ARCH/passwall_packages/packages.adb" >> "$CUSTOM_REPO_FILE"
        echo "✅ 扩展源及公钥配置完毕。"
        update_source
    fi

    if [ "$GLOBAL_UPDATED" -ne 1 ]; then
        update_source
    fi

    echo "-------------------------------------------------"
    echo "🚀 正在精准补齐缺失的 PassWall 前端、汉化及独占特产组件..."
    # 🌟 绝杀去重：只抓取固件无法集成的偏门特产，绝不触碰系统自带的 sing-box 和 xray-core！
    apk add --allow-untrusted \
            luci-app-passwall \
            luci-i18n-passwall-zh-cn \
            geoview \
            chinadns-ng \
            hysteria
            
    if [ $? -eq 0 ]; then
        optimize_ntp
        refresh_system
        echo "================================================="
        echo "✅ 🎉 恭喜老哥！PassWall 极速闪电安装已无损完成！"
        echo "💡 提示：请进入 [DNS] 选项卡，将模式改为「使用 Sing-Box 本地内核高级分流」！"
        echo "================================================="
    else
        echo "❌ 安装失败，请查看上方 apk 报错。"
    fi
}

uninstall_passwall() {
    echo "-------------------------------------------------"
    echo "🗑️ 正在安全拔除 PassWall 组件..."
    
    if [ -f /etc/init.d/passwall ]; then
        /etc/init.d/passwall stop 2>/dev/null
    fi
    
    # 🌟 绝杀保护：卸载时只切除外挂组件，绝对不会误删你预装进固件的官方核心！
    apk del luci-app-passwall luci-i18n-passwall-zh-cn geoview chinadns-ng hysteria 2>/dev/null
    rm -rf /etc/config/passwall /usr/share/passwall /var/etc/passwall /var/run/passwall* 2>/dev/null
    rm -f /etc/apk/repositories.d/customfeeds.list /etc/apk/keys/passwall.pub 2>/dev/null
    
    refresh_system
    echo "✅ 彻底洗地完毕！系统已恢复纯净固件状态。"
}

# ==================== 核心模块 2：Argon 主题 ====================
install_argon() {
    echo "-------------------------------------------------"
    echo "🎨 正在准备部署大雕经典 Argon 磨砂玻璃全局主题..."
    
    ARCH=$(cat /etc/apk/arch 2>/dev/null || echo "aarch64_cortex-a53")
    LUCI_REPO="https://downloads.immortalwrt.org/snapshots/packages/$ARCH/luci/packages.adb"
    
    if [ "$GLOBAL_UPDATED" -ne 1 ]; then
        update_source
    fi
    
    echo "-------------------------------------------------"
    echo "🚀 正在通过临时高级专线，强灌 Argon 主题及控制台面板..."
    apk --allow-untrusted --repository "$LUCI_REPO" add \
        luci-theme-argon \
        luci-app-argon-config \
        luci-i18n-argon-config-zh-cn
        
    if [ $? -eq 0 ]; then
        echo "🔄 正在激活 Argon 为系统默认全局外观..."
        uci set luci.main.mediaurlbase='/luci-static/argon'
        uci commit luci
        
        optimize_ntp
        refresh_system
        echo "================================================="
        echo "✅ 🎉 颜值拉满！Argon 磨砂玻璃全套组件已成功接管后台！"
        echo "================================================="
    else
        echo "❌ 安装失败，请查看上方 apk 报错。"
    fi
}

uninstall_argon() {
    echo "-------------------------------------------------"
    echo "🗑️ 正在启动 Argon 主题安全卸载程序..."
    uci set luci.main.mediaurlbase='/luci-static/bootstrap'
    uci commit luci
    apk del luci-theme-argon luci-app-argon-config luci-i18n-argon-config-zh-cn 2>/dev/null
    refresh_system
    echo "✅ 🎉 还原完毕！系统网页外观已完美恢复官方原生皮肤！"
}

# ==================== 主菜单逻辑 ====================
while true; do
    echo "================================================="
    echo "  ${SYS_TITLE} 维护工具箱 (固件完美集成版)"
    echo "================================================="
    echo "💡 请选择操作："
    echo "1) 一键闪电安装 PassWall (享用预装内核 + 自动分流优化)"
    echo "2) 彻底安全卸载 PassWall"
    echo "3) 一键安装 / 强制激活大雕 Argon 磨砂主题"
    echo "4) 一键彻底卸载 Argon 主题"
    echo "5) 退出工具箱"
    echo "-------------------------------------------------"
    printf "请输入对应数字 [1-5]: "
    read choice
    case $choice in
        1) install_passwall ; echo "" ;;
        2) uninstall_passwall ; echo "" ;;
        3) install_argon ; echo "" ;;
        4) uninstall_argon ; echo "" ;;
        5) echo "👋 已退出。" ; exit 0 ;;
        *) echo "❌ 输入错误。" ; echo "" ; sleep 1 ;;
    esac
done
