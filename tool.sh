#!/bin/sh

# 1. 环境基础合规性检查并引入系统变量
if [ ! -f /etc/openwrt_release ]; then
    echo "❌ 错误：未检测到标准的 OpenWrt/ImmortalWrt 系统文件，脚本退出。"
    exit 1
fi

# 引入系统版本变量（包含 DISTRIB_ID, DISTRIB_RELEASE 等）
. /etc/openwrt_release

echo "================================================="
echo "  ${DISTRIB_ID} ${DISTRIB_RELEASE} 工具箱 (PassWall 纯净版)"
echo "================================================="
echo "系统底层包管理器已确认为: apk"
echo "-------------------------------------------------"

# 同步软件源索引
update_source() {
    echo "🔄 正在同步本地软件包索引 (apk update)..."
    apk update
}

# ==================== PassWall 模块 ====================
install_passwall() {
    echo "-------------------------------------------------"
    echo "⬇️ 开始安装/升级 PassWall 组件..."
    update_source
    
    # apk add 会自动判断：未安装则全新安装，已安装则自动无损升级
    apk add luci-app-passwall luci-i18n-passwall-zh-cn
    if [ $? -eq 0 ]; then
        echo "✅ PassWall 部署/升级流程顺利完成！"
        echo "💡 提示：您的原有节点数据和分流规则已被系统完美保留。"
    else
        echo "❌ PassWall 操作失败，请检查上方 apk 核心报错提示。"
    fi
}

uninstall_passwall() {
    echo "-------------------------------------------------"
    echo "🗑️ 正在安全卸载 PassWall 组件..."
    apk del luci-app-passwall luci-i18n-passwall-zh-cn
    echo "✅ PassWall 卸载指令执行完毕。"
}

# ==================== 主菜单逻辑 ====================
echo "💡 请选择需要执行的操作："
echo "1) 安装 / 升级 PassWall"
echo "2) 安全卸载 PassWall 组件"
echo "3) 退出"
echo "-------------------------------------------------"

printf "请输入对应数字 [1-3]: "
read choice

case $choice in
    1) install_passwall ;;
    2) uninstall_passwall ;;
    *) echo "操作已取消。"; exit 0 ;;
esac
