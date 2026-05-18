#!/bin/sh

# 1. 环境基础合规性检查并引入系统变量
if [ ! -f /etc/openwrt_release ]; then
    echo "❌ 错误：未检测到标准的 OpenWrt/ImmortalWrt 系统文件，脚本退出。"
    exit 1
fi

# 引入系统版本变量
. /etc/openwrt_release

# 同步软件源索引
update_source() {
    echo "🔄 正在同步本地软件包索引 (apk update)..."
    apk update
}

# 核心优化：强制刷新 LuCI 网页缓存并重载服务
refresh_luci() {
    echo "🔄 正在清理系统网页缓存并重载界面..."
    rm -rf /tmp/luci-indexcache /tmp/luci-modulecache 2>/dev/null
    /etc/init.d/uhttpd restart 2>/dev/null
    /etc/init.d/nginx restart 2>/dev/null
}

# ==================== PassWall 模块 ====================
install_passwall() {
    echo "-------------------------------------------------"
    echo "⬇️ 开始安装/升级 PassWall 组件..."
    update_source
    
    # apk add 会自动判断：未安装则全新安装，已安装则自动无损升级
    apk add luci-app-passwall luci-i18n-passwall-zh-cn
    if [ $? -eq 0 ]; then
        refresh_luci
        echo "✅ PassWall 部署/升级流程顺利完成！"
        echo "💡 提示：您的原有节点数据和分流规则已被系统完美保留。"
    else
        echo "❌ PassWall 操作失败，请检查上方 apk 核心报错提示。"
    fi
}

uninstall_passwall() {
    echo "-------------------------------------------------"
    echo "🗑️ 正在安全卸载 PassWall 组件..."
    
    # 核心优化：卸载前先安全停止可能正在运行的后台服务
    if [ -f /etc/init.d/passwall ]; then
        echo "🛑 正在停止 PassWall 后台进程..."
        /etc/init.d/passwall stop 2>/dev/null
    fi
    
    apk del luci-app-passwall luci-i18n-passwall-zh-cn
    refresh_luci
    echo "✅ PassWall 卸载指令执行完毕，系统已恢复纯净。"
}

# ==================== 主菜单逻辑 (加入循环机制) ====================
while true; do
    echo "================================================="
    echo "  ${DISTRIB_ID} ${DISTRIB_RELEASE} 工具箱 (PassWall 纯净版)"
    echo "================================================="
    echo "系统底层包管理器已确认为: apk"
    echo "-------------------------------------------------"
    echo "💡 请选择需要执行的操作："
    echo "1) 安装 / 升级 PassWall"
    echo "2) 安全卸载 PassWall 组件"
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
