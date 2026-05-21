#!/bin/sh

# 1. 环境基础合规性检查
if [ ! -f /etc/openwrt_release ]; then
    echo "❌ 错误：未检测到标准的 OpenWrt/ImmortalWrt 系统文件，脚本退出。"
    exit 1
fi

. /etc/openwrt_release
SYS_TITLE="${DISTRIB_DESCRIPTION:-$DISTRIB_ID $DISTRIB_RELEASE}"

update_source() {
    echo "🔄 正在同步本地 APK 软件包索引 (apk update)..."
    apk update
}

refresh_luci() {
    echo "🔄 正在强制清理网页菜单缓存并重载界面..."
    rm -rf /tmp/luci-indexcache /tmp/luci-modulecache 2>/dev/null
    /etc/init.d/uhttpd restart 2>/dev/null
    /etc/init.d/nginx restart 2>/dev/null
}

# ==================== PassWall 核心模块 ====================
install_passwall() {
    echo "-------------------------------------------------"
    # 🧼 彻底清场：率先扬掉前几次失败运行产生的所有历史残留乱麻文件
    rm -f /etc/apk/repositories 2>/dev/null
    rm -f /etc/apk/repositories.d/custom.list 2>/dev/null
    rm -f /etc/apk/repositories.d/customfeeds.list 2>/dev/null
    
    update_source
    echo "-------------------------------------------------"
    echo "🔍 正在读取 PassWall 组件版本信息..."

    # 🛠️ 严格校准：只检测本地物理存在的实体包
    if apk info -e luci-app-passwall >/dev/null 2>&1; then
        CURRENT_VER=$(apk list -I luci-app-passwall 2>/dev/null | head -n 1 | awk '{print $1}' | sed 's/luci-app-passwall-//')
    else
        CURRENT_VER="未安装"
    fi

    LATEST_VER=$(apk list luci-app-passwall 2>/dev/null | head -n 1 | awk '{print $1}' | sed 's/luci-app-passwall-//')
    
    # 🌟 智能修复核心：完美驯服官方原版 OpenWrt 25 的硬核校验机制
    if [ -z "$LATEST_VER" ]; then
        echo "❌ 警告：当前系统官方软件源内未发现 luci-app-passwall（官方源默认不收录代理插件）。"
        echo "-------------------------------------------------"
        echo "💡 我们可以尝试为您自动下发安全公网密钥，并接入完美适配 APK v3 的正统 PassWall 扩展源。"
        printf "❓ 是否允许脚本尝试为您配置第三方 PassWall 软件源？[y/N]: "
        read add_repo
        
        if [ "$add_repo" = "y" ] || [ "$add_repo" = "Y" ]; then
            # 自动提取当前 OpenWrt 25 底层的真实硬件架构 (如 aarch64_cortex-a53)
            ARCH=$(cat /etc/apk/arch 2>/dev/null || echo "aarch64_cortex-a53")
            CUSTOM_REPO_FILE="/etc/apk/repositories.d/customfeeds.list"
            
            # 确保散装配置目录和密钥目录存在
            mkdir -p /etc/apk/repositories.d
            mkdir -p /etc/apk/keys
            
            # 🔐 核心超频 1：提前静默下发数字签名公钥，让原版 OpenWrt 25 给予 100% 官方合规信任
            echo "🔑 正在同步下发专属第三方安全信任密钥..."
            curl -sLk "https://master.dl.sourceforge.net/project/openwrt-passwall-build/apk.pub" -o /etc/apk/keys/passwall.pub
            
            # 🎯 核心超频 2：严格遵循 APK v3 规范，将 URL 尾部死死锁定到 /packages.adb 最终文件名！绝不让系统降级报错
            echo "📥 正在配置全套兼容的经典 Passwall 核心及前端组件专线..."
            echo "https://master.dl.sourceforge.net/project/openwrt-passwall-build/releases/packages-25.12/$ARCH/passwall_luci/packages.adb" > "$CUSTOM_REPO_FILE"
            echo "https://master.dl.sourceforge.net/project/openwrt-passwall-build/releases/packages-25.12/$ARCH/passwall_packages/packages.adb" >> "$CUSTOM_REPO_FILE"
            echo "✅ 扩展源及公钥配置完毕。"
            
            # 重新同步索引并二次获取真实可装版本
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

    if [ "$CURRENT_VER" = "$LATEST_VER" ] && [ "$CURRENT_VER" != "未安装" ]; then
        echo "💡 提示：您当前拥有的已经是源内最新版本。"
    fi

    printf "❓ 是否确认执行安装/升级流程？[y/N]: "
    read confirm
    switch_confirm=$(echo "$confirm" | tr '[:upper:]' '[:lower:]')
    
    if [ "$switch_confirm" = "y" ] || [ "$switch_confirm" = "yes" ]; then
        echo "🚀 正在通过 APK 引擎安全部署 PassWall 核心及中文包..."
        apk add luci-app-passwall luci-i18n-passwall-zh-cn
        if [ $? -eq 0 ]; then
            refresh_luci
            echo "✅ PassWall 部署成功！"
        else
            echo "❌ 安装失败，请查看上方 apk 报错。建议重装系统后在干净环境下运行。"
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
    
    # 1. 拔除前端外壳
    apk del luci-app-passwall luci-i18n-passwall-zh-cn
    
    # 2. 彻底扬掉所有残留的用户配置文件、GeoIP分流规则库和历史死尸目录
    echo "🧹 正在执行深层清除：擦除/etc/config及/usr/share残留..."
    rm -rf /etc/config/passwall \
           /usr/share/passwall \
           /var/etc/passwall \
           /var/run/passwall* 2>/dev/null
    
    # 3. 清理所有第三方自定义扩展源与授权密钥（彻底洗地恢复原厂纯净）
    rm -f /etc/apk/repositories.d/customfeeds.list 2>/dev/null
    rm -f /etc/apk/repositories.d/custom.list 2>/dev/null
    rm -f /etc/apk/repositories 2>/dev/null
    rm -f /etc/apk/keys/passwall.pub 2>/dev/null
    
    # 4. 提供硬核选项：是否连同底层内核一起端掉
    echo "-------------------------------------------------"
    printf "❓ 是否连同共享内核(Xray, Sing-Box, ChinaDNS-NG)一起卸载清空？[y/N]: "
    read del_cores
    switch_cores=$(echo "$del_cores" | tr '[:upper:]' '[:lower:]')
    
    if [ "$switch_cores" = "y" ] || [ "$switch_cores" = "yes" ]; then
        echo "💥 正在强制剥离底层核心组件..."
        apk del chinadns-ng xray-core sing-box dns2tcp trojan-plus 2>/dev/null
    else
        echo "💡 已保留底层共享内核，方便其他插件复用。"
    fi

    refresh_luci
    echo "✅ 彻底洗地完毕！系统环境已恢复如初。"
}

# ==================== 主菜单逻辑 ====================
while true; do
    echo "================================================="
    echo "  ${SYS_TITLE} 维护工具箱 (25.12 APKv3 终极版)"
    echo "================================================="
    echo "底层包管理器: apk"
    echo "-------------------------------------------------"
    echo "💡 请选择需要执行的操作："
    echo "1) 安装 / 升级 PassWall"
    echo "2) 彻底安全卸载 PassWall (含深层洗地)"
    echo "3) 退出工具箱"
    echo "-------------------------------------------------"

    printf "请输入对应数字 [1-3]: "
    read choice

    case $choice in
        1)
            install_passwall
            echo ""
            ;;
        2)
            uninstall_passwall
            echo ""
            ;;
        3)
            echo "👋 已退出工具箱。"
            exit 0
            ;;
        *)
            echo "❌ 输入错误，请输入 1、2 或 3。"
            echo ""
            sleep 1
            ;;
    esac
done
