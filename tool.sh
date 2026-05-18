#!/bin/sh

# 1. 环境基础合规性检查
if [ ! -f /etc/openwrt_release ]; then
    echo "❌ 错误：未检测到标准的 OpenWrt/ImmortalWrt 系统文件，脚本退出。"
    exit 1
fi

echo "================================================="
echo "  ImmortalWrt 25.12 专属工具箱 (纯净 APK 核心)"
echo "================================================="
echo "当前系统底层包管理器已确认为: apk"
echo "-------------------------------------------------"

# ==================== PassWall 模块 ====================
install_passwall() {
    echo "-------------------------------------------------"
    echo "⬇️ 开始安装/无损升级 PassWall 组件..."
    echo "🔄 正在同步本地 APK 软件源索引..."
    apk update
    
    echo "🌐 正在通过 GitHub API 获取最新版 PassWall (25.12+ APK)..."
    cd /tmp
    
    # 获取最新稳定版 Release 的数据并精准解析 25.12 专属的 APK 链接
    API_URL="https://api.github.com/repos/Openwrt-Passwall/openwrt-passwall/releases/latest"
    
    LUCI_URL=$(curl -s $API_URL | grep "browser_download_url" | grep "25.12" | grep "luci-app-passwall" | grep -v "zh-cn" | head -n 1 | cut -d '"' -f 4)
    LANG_URL=$(curl -s $API_URL | grep "browser_download_url" | grep "25.12" | grep "luci-i18n-passwall-zh-cn" | head -n 1 | cut -d '"' -f 4)
    
    if [ -z "$LUCI_URL" ] || [ -z "$LANG_URL" ]; then
        echo "❌ 错误：无法从 GitHub 获取到 25.12+ 专属的 APK 下载地址。"
        echo "💡 提示：请确保软路由当前的国际网络通畅，以便脚本能顺利连接 GitHub API。"
        return 1
    fi
    
    echo "📥 正在下载 luci-app-passwall 主程序..."
    wget --no-check-certificate -qO passwall_core.apk "$LUCI_URL"
    echo "📥 正在下载 汉化语言包..."
    wget --no-check-certificate -qO passwall_zh.apk "$LANG_URL"
    
    echo "📦 正在执行本地无损安装 (APK 核心会自动从官方源补齐 xray/sing-box 等核心依赖)..."
    # apk add 针对本地未签名文件需要加 --allow-untrusted 参数
    apk add --allow-untrusted ./passwall_core.apk ./passwall_zh.apk
    
    if [ $? -eq 0 ]; then
        echo "✅ PassWall 安装/无损升级流程顺利完成！已为您完整保留原有节点数据。"
    else
        echo "❌ 安装失败，请查看上方的 apk 核心报错提示。"
    fi
    
    # 清理现场残留
    rm -f ./passwall_core.apk ./passwall_zh.apk
}

uninstall_passwall() {
    echo "-------------------------------------------------"
    echo "🗑️ 正在安全卸载 PassWall 组件..."
    # apk del 会干净利落地移除组件，且不会动你 /etc/config/ 里的核心节点配置文件
    apk del luci-app-passwall luci-i18n-passwall-zh-cn
    echo "✅ PassWall 卸载指令执行完毕，已恢复系统纯净度。"
}

# ==================== 主菜单逻辑 ====================
echo "💡 请选择需要执行的操作："
echo "1) 全新安装 / 无损升级 PassWall (25.12+ APK 专属流)"
echo "2) 卸载 PassWall 节点组件"
echo "3) 退出"
echo "-------------------------------------------------"

printf "请输入对应数字 [1-3]: "
read choice

case $choice in
    1) install_passwall ;;
    2) uninstall_passwall ;;
    *) echo "操作已取消。"; exit 0 ;;
esac
