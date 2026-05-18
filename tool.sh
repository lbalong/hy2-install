#!/bin/sh

# 1. 环境基础合规性检查并引入系统全局变量
if [ ! -f /etc/openwrt_release ]; then
    echo "❌ 错误：未检测到标准的 OpenWrt/ImmortalWrt 系统文件，脚本退出。"
    exit 1
fi

# 注入系统发行版本信息
. /etc/openwrt_release
SYS_TITLE="${DISTRIB_DESCRIPTION:-$DISTRIB_ID $DISTRIB_RELEASE}"

# 深度清理 25.12 JS 后台的幽灵缓存
refresh_luci() {
    echo "🔄 正在深度清理系统网页缓存..."
    rm -rf /tmp/luci-indexcache /tmp/luci-modulecache 2>/dev/null
    
    echo "🔄 正在重载系统 RPC 守护进程与网页服务..."
    /etc/init.d/rpcd restart 2>/dev/null
    /etc/init.d/uhttpd restart 2>/dev/null
    /etc/init.d/nginx restart 2>/dev/null
}

# ==================== PassWall 模块 ====================
install_passwall() {
    echo "-------------------------------------------------"
    echo "🔄 正在同步本地软件源索引 (apk update)..."
    apk update
    echo "-------------------------------------------------"
    echo "🔍 正在读取当前系统的 PassWall 版本状态..."

    # 1. 修正：统一采用 apk list -I 提取当前系统实际已安装的版本号
    CURRENT_VER=$(apk list -I luci-app-passwall 2>/dev/null | head -n 1 | awk '{print $1}' | sed 's/^luci-app-passwall-//')
    if [ -z "$CURRENT_VER" ]; then
        CURRENT_VER="未安装 (系统将执行首次完整初装)"
    fi

    # 2. 提取当前系统官方软件源中收录的最新可用版本号
    LATEST_VER=$(apk list luci-app-passwall 2>/dev/null | head -n 1 | awk '{print $1}' | sed 's/^luci-app-passwall-//')
    if [ -z "$LATEST_VER" ]; then
        echo "❌ 错误：在当前官方软件源中未检测到 luci-app-passwall 组件，请检查网络。"
        return 1
    fi

    # 3. 打印版本比对看板
    echo "📊 PassWall 版本比对："
    echo "   • 当前已安装版本: ${CURRENT_VER}"
    echo "   • 软件源最新版本: ${LATEST_VER}"
    echo "-------------------------------------------------"

    if [ "$CURRENT_VER" = "$LATEST_VER" ]; then
        echo "💡 提示：您当前拥有的已经是该系统源内的最新版本。"
    fi

    # 4. Y/N 拦截确认机制
    printf "❓ 是否确认执行安装/升级流程？[y/N]: "
    read confirm
    case "$confirm" in
        [yY][eE][sS]|[yY])
            echo "🚀 正在通过 APK 核心部署 PassWall 及其全部周边依赖..."
            apk add luci-app-passwall luci-i18n-passwall-zh-cn
            if [ $? -eq 0 ]; then
                refresh_luci
                echo "✅ PassWall 操作成功！原节点配置与分流规则已完美保留。"
                echo "💡 提示：由于浏览器本身存在强缓存，若菜单仍未出现，请在网页端按 [Ctrl + F5] 强制刷新浏览器。"
            else
                echo "❌ 操作失败，请检查上方 apk 核心错误输出。"
            fi
            ;;
        *)
            echo "🛑 操作已取消，返回主菜单。"
            ;;
    esac
}

uninstall_passwall() {
    echo "-------------------------------------------------"
    echo "🗑️ 正在安全卸载 PassWall 组件..."
    
    if [ -f /etc/init.d/passwall ]; then
        echo "🛑 正在停止 PassWall 后台进程..."
        /etc/init.d/passwall stop 2>/dev/null
    fi
    
    apk del luci-app-passwall luci-i18n-passwall-zh-cn
    refresh_luci
    echo "✅ PassWall 卸载指令执行完毕，页面已干净抹去。"
}

# ==================== 主菜单逻辑 ====================
while true; do
    echo "================================================="
    echo "  ${SYS_TITLE} 维护工具箱"
    echo "================================================="
    echo "底层包管理器: apk"
    echo "-------------------------------------------------"
    echo "💡 请选择需要执行的操作："
    echo "1) 安装 / 升级 PassWall"
    echo "2) 安全卸载 PassWall"
    echo "3) 退出脚本"
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
            echo "❌ 输入错误，请输入数字 1、2 或 3。"
            echo ""
            sleep 1
            ;;
    esac
done
