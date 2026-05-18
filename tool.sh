#!/bin/sh

# 1. 环境基础合规性检查并引入系统全局变量
if [ ! -f /etc/openwrt_release ]; then
    echo "❌ 错误：未检测到标准的 OpenWrt/ImmortalWrt 系统文件，脚本退出。"
    exit 1
fi

# 注入系统发行版本信息
. /etc/openwrt_release

# 动态生成纯净标题：优先使用系统全称描述，若无则拼装 ID 和版本号
SYS_TITLE="${DISTRIB_DESCRIPTION:-$DISTRIB_ID $DISTRIB_RELEASE}"

# 同步软件源索引
update_source() {
    echo "🔄 正在同步本地软件包索引 (apk update)..."
    apk update
}

# 强制刷新 LuCI 网页缓存并重载服务
refresh_luci() {
    echo "🔄 正在清理系统网页缓存并重载界面..."
    rm -rf /tmp/luci-indexcache /tmp/luci-modulecache 2>/dev/null
    /etc/init.d/uhttpd restart 2>/dev/null
    /etc/init.d/nginx restart 2>/dev/null
}

# ==================== PassWall 模块 ====================
install_passwall() {
    echo "-------------------------------------------------"
    update_source
    echo "-------------------------------------------------"
    echo "🔍 正在读取 PassWall 组件版本信息..."

    # 1. 提取当前系统已安装的版本号
    CURRENT_VER=$(apk info luci-app-passwall 2>/dev/null | grep -E '^luci-app-passwall' | head -n 1 | sed 's/luci-app-passwall-//' | awk '{print $1}')
    if [ -z "$CURRENT_VER" ]; then
        CURRENT_VER="未安装"
    fi

    # 2. 提取当前软件源中收录的最新版本号
    LATEST_VER=$(apk list luci-app-passwall 2>/dev/null | grep -E '^luci-app-passwall' | head -n 1 | sed 's/luci-app-passwall-//' | awk '{print $1}')
    if [ -z "$LATEST_VER" ]; then
        echo "❌ 错误：在当前软件源中未检测到 luci-app-passwall，请检查网络或更换镜像源。"
        return 1
    fi

    # 3. 打印版本对比看板
    echo "📊 PassWall 版本比对："
    echo "   • 当前已安装版本: ${CURRENT_VER}"
    echo "   • 软件源最新版本: ${LATEST_VER}"
    echo "-------------------------------------------------"

    # 如果版本一致，给予人性化提示
    if [ "$CURRENT_VER" = "$LATEST_VER" ]; then
        echo "💡 提示：您当前拥有的已经是源内最新版本。"
    fi

    # 4. Y/N 拦截确认机制
    printf "❓ 是否确认继续执行安装/升级流程？[y/N]: "
    read confirm
    case "$confirm" in
        [yY][eE][sS]|[yY])
            echo "🚀 开始部署 PassWall 组件..."
            apk add luci-app-passwall luci-i18n-passwall-zh-cn
            if [ $? -eq 0 ]; then
                refresh_luci
                echo "✅ PassWall 操作成功！原节点配置已完美保留。"
            else
                echo "❌ 操作失败，请检查上方 apk 核心错误输出。"
            fi
            ;;
        *)
            echo "🛑 操作已取消，正在返回主菜单。"
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
    echo "✅ PassWall 卸载指令执行完毕。"
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
