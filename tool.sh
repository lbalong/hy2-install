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
    echo "🔄 正在同步本地软件源索引以准备自动构建依赖链..."
    apk update
    
    echo "🌐 正在连线 PassWall GitHub 官方获取最新 Release 矩阵..."
    API_URL="https://api.github.com/repos/Openwrt-Passwall/openwrt-passwall/releases/latest"
    
    # 动态抓取 GitHub 最新 Release 的 Tag 版本号
    LATEST_TAG=$(curl -sLk "$API_URL" | grep '"tag_name":' | head -n 1 | cut -d '"' -f 4)
    
    # 精准提取适合 25.12 APK 架构的主程序与语言包下载直链（排除 .ipk 后缀）
    LUCI_APK_URL=$(curl -sLk "$API_URL" | grep "browser_download_url" | grep -E "luci-app-passwall_.*\.apk" | grep -v "zh-cn" | head -n 1 | cut -d '"' -f 4)
    LANG_APK_URL=$(curl -sLk "$API_URL" | grep "browser_download_url" | grep -E "luci-i18n-passwall-zh-cn_.*\.apk" | head -n 1 | cut -d '"' -f 4)
    
    if [ -z "$LUCI_APK_URL" ] || [ -z "$LANG_APK_URL" ]; then
        echo "❌ 错误：未能从 GitHub 官方 Releases 中解析到 25.12 专属的 .apk 安装包。"
        echo "💡 提示：网络可能受到干扰，请确保软路由当前的国际网络畅通。"
        return 1
    fi

    # 获取本地已安装的版本号 (利用 apk list 查验)
    CURRENT_VER=$(apk list -I luci-app-passwall 2>/dev/null | head -n 1 | awk '{print $1}' | sed 's/luci-app-passwall-//')
    if [ -z "$CURRENT_VER" ]; then
        CURRENT_VER="未安装 (系统将自动执行首次完整初装)"
    fi

    echo "-------------------------------------------------"
    echo "📊 PassWall 版本比对 (数据源: GitHub 官方)"
    echo "   • 当前系统版本: ${CURRENT_VER}"
    echo "   • 官方最新版本: ${LATEST_TAG}"
    echo "-------------------------------------------------"

    # Y/N 拦截确认机制
    printf "❓ 是否确认下载官方最新版并执行安装/升级？[y/N]: "
    read confirm
    case "$confirm" in
        [yY][eE][sS]|[yY])
            echo "📥 正在从官方下载主程序包..."
            curl -sLk "$LUCI_APK_URL" -o /tmp/passwall_core.apk
            echo "📥 正在从官方下载语言汉化包..."
            curl -sLk "$LANG_APK_URL" -o /tmp/passwall_zh.apk
            
            if [ ! -f /tmp/passwall_core.apk ] || [ ! -f /tmp/passwall_zh.apk ]; then
                echo "❌ 错误：文件下载失败，请检查软路由到 GitHub 的连通性。"
                rm -f /tmp/passwall_core.apk /tmp/passwall_zh.apk
                return 1
            fi
            
            echo "📦 正在调用 APK 核心执行本地部署并全自动补齐周边依赖..."
            # --allow-untrusted 用于允许安装第三方维护的未签名包
            apk add --allow-untrusted /tmp/passwall_core.apk /tmp/passwall_zh.apk
            
            if [ $? -eq 0 ]; then
                refresh_luci
                echo "✅ PassWall 官方最新版部署成功！原有节点数据与分流规则完美保留。"
            else
                echo "❌ 安装失败，请检查上方 apk 核心错误输出。"
            fi
            
            # 清理临时文件
            rm -f /tmp/passwall_core.apk /tmp/passwall_zh.apk
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
    echo "1) 安装 / 升级 PassWall (直连 GitHub 官方源)"
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
