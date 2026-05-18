#!/bin/sh

# 1. 环境基础合规性检查
if [ ! -f /etc/openwrt_release ]; then
    echo "❌ 错误：未检测到标准的 OpenWrt/ImmortalWrt 系统文件，脚本退出。"
    exit 1
fi

echo "================================================="
echo "  ImmortalWrt 25.12 专属工具箱 (基于 APK 核心)"
echo "================================================="
echo "系统底层包管理器已确认为: apk (Alpine Package Keeper)"
echo "-------------------------------------------------"

# 2. 刷新 APK 软件源索引
update_source() {
    echo "🔄 正在同步本地软件包索引 (apk update)..."
    apk update
}

# ==================== PassWall 模块 ====================
install_passwall() {
    echo "-------------------------------------------------"
    echo "⬇️ 开始安装/升级 PassWall 节点组件..."
    update_source
    # apk add 会自动判断：未安装则全装，已安装则自动无损升级
    apk add luci-app-passwall luci-i18n-passwall-zh-cn
    if [ $? -eq 0 ]; then
        echo "✅ PassWall 部署/升级流程顺利完成。"
    else
        echo "❌ PassWall 操作失败，请查看上方 apk 报错提示。"
    fi
}

uninstall_passwall() {
    echo "-------------------------------------------------"
    echo "🗑️ 正在安全卸载 PassWall 组件..."
    apk del luci-app-passwall luci-i18n-passwall-zh-cn
    echo "✅ PassWall 卸载指令执行完毕。"
}

# ==================== iStore 模块 ====================
install_istore() {
    echo "-------------------------------------------------"
    echo "⬇️ 开始安装/修复 iStore 软件中心..."
    update_source
    
    # 25.12 环境下直接调用编译好的原生 apk 封装包
    apk add luci-app-store
    if [ $? -eq 0 ]; then
        echo "🔄 正在重载网页服务以刷新菜单..."
        /etc/init.d/uhttpd restart 2>/dev/null
        /etc/init.d/nginx restart 2>/dev/null
        echo "✅ iStore 应用商店部署完毕，请完全刷新软路由网页查看菜单。"
    else
        echo "❌ iStore 安装失败，可能是当前架构源中暂未收录该版本的 apk 包。"
    fi
}

uninstall_istore() {
    echo "-------------------------------------------------"
    echo "🗑️ 正在安全卸载 iStore 软件中心..."
    apk del luci-app-store
    echo "🔄 正在重载网页服务以刷新菜单..."
    /etc/init.d/uhttpd restart 2>/dev/null
    /etc/init.d/nginx restart 2>/dev/null
    echo "✅ iStore 卸载指令执行完毕。"
}

# ==================== 主菜单逻辑 ====================
echo "💡 请选择需要执行的操作："
echo "1) 安装 / 自动升级 PassWall"
echo "2) 安装 / 自动修复 iStore 商店"
echo "3) 同时安装以上两项组件 (毕业配置)"
echo "-------------------------------------------------"
echo "4) 仅 卸载 PassWall"
echo "5) 仅 卸载 iStore 商店"
echo "6) 同时卸载以上两项组件 (恢复纯净系统)"
echo "7) 退出"
echo "-------------------------------------------------"

printf "请输入对应数字 [1-7]: "
read choice

case $choice in
    1) install_passwall ;;
    2) install_istore ;;
    3) install_passwall; install_istore ;;
    4) uninstall_passwall ;;
    5) uninstall_istore ;;
    6) uninstall_passwall; uninstall_istore ;;
    *) echo "操作已取消。"; exit 0 ;;
esac
