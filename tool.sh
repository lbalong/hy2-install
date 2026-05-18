#!/bin/sh

# 1. 环境基础合规性检查并引入系统全局变量
if [ ! -f /etc/openwrt_release ]; then
    echo "❌ 错误：未检测到标准的 OpenWrt/ImmortalWrt 系统文件，脚本退出。"
    exit 1
fi

# 注入系统发行版本信息
. /etc/openwrt_release
SYS_TITLE="${DISTRIB_DESCRIPTION:-$DISTRIB_ID $DISTRIB_RELEASE}"

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
    echo "🔄 正在同步本地软件源索引 (apk update)..."
    apk update
    
    echo "📦 正在通过 APK 核心执行 PassWall 部署/升级..."
    # 直接交由本地 apk 管理器处理：未安装则全新安装，已安装则自动无损覆盖升级
    apk add luci-app-passwall luci-i18n-passwall-zh-cn
    
    if [ $? -eq 0 ]; then
        refresh_luci
        echo "✅ PassWall 操作成功！原节点配置与分流规则已完美保留。"
    else
        echo "❌ 操作失败，请检查上方 apk 核心错误输出。"
        echo "💡 提示：如果提示找不到包，说明你当前固件用的镜像源（如 vsean 测试源）暂时没收录该组件。"
    fi
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
    echo "✅ PassWall 卸载指令执行完毕，页面已清理。"
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
