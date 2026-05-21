#!/bin/sh

# 1. 环境基础合规性检查
if [ ! -f /etc/openwrt_release ]; then
    echo "❌ 错误：未检测到标准的 OpenWrt/ImmortalWrt 系统文件，脚本退出。"
    exit 1
fi

. /etc/openwrt_release
SYS_TITLE="${DISTRIB_DESCRIPTION:-$DISTRIB_ID $DISTRIB_RELEASE}"

update_source() {
    echo "🔄 正在同步本地 APK 软件包索引 (apk update --allow-untrusted)..."
    # 挂载免检参数，强行吃下第三方源的索引
    apk update --allow-untrusted
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
    # 🧼 核心修复：斩草除根！率先扬掉前几次失败运行残留在根目录的毒瘤文件
    rm -f /etc/apk/repositories 2>/dev/null
    
    update_source
    echo "-------------------------------------------------"
    echo "🔍 正在读取 PassWall 组件版本信息..."

    # 🛠️ 严格校准：只检测本地物理存在的实体包，绝不读取云端索引
    if apk info -e luci-app-passwall >/dev/null 2>&1; then
        CURRENT_VER=$(apk list -I luci-app-passwall 2>/dev/null | head -n 1 | awk '{print $1}' | sed 's/luci-app-passwall-//')
    else
        CURRENT_VER="未安装"
    fi

    LATEST_VER=$(apk list luci-app-passwall 2>/dev/null | head -n 1 | awk '{print $1}' | sed 's/luci-app-passwall-//')
    
    # 🌟 智能修复核心：专治官方原版源缺失代理插件的断水问题
    if [ -z "$LATEST_VER" ]; then
        echo "❌ 警告：当前系统官方软件源内未发现 luci-app-passwall（官方源默认不收录代理插件）。"
        echo "-------------------------------------------------"
        echo "💡 我们可以尝试为您自动接入社区高频维护、完美适配 APK v3 的 Snapshots 扩展仓储。"
        printf "❓ 是否允许脚本尝试为您配置第三方 PassWall 软件源？[y/N]: "
        read add_repo
        if [[ "$add_repo" =~ ^[Yy]$ ]]; then
            # 自动提取当前 OpenWrt 25 底层的真实硬件架构 (如 aarch64_cortex-a53)
            ARCH=$(cat /etc/apk/arch 2>/dev/null || echo "aarch64_cortex-a53")
            CUSTOM_REPO_FILE="/etc/apk/repositories.d/custom.list"
            
            # 确保标准的散装配置目录存在，并原地强制刷新空白兜底文件，绝不报 grep 错误
            mkdir -p /etc/apk/repositories.d
            rm -f "$CUSTOM_REPO_FILE" 2>/dev/null
            touch "$CUSTOM_REPO_FILE"
            
            # 智能注入含有代理组件与依赖核心的 Snapshots 实时软件源
            echo "https://downloads.immortalwrt.org/snapshots/packages/$ARCH/luci" > "$CUSTOM_REPO_FILE"
            echo "https://downloads.immortalwrt.org/snapshots/packages/$ARCH/packages" >> "$CUSTOM_REPO_FILE"
            echo "https://downloads.immortalwrt.org/snapshots/packages/$ARCH/routing" >> "$CUSTOM_REPO_FILE"
            echo "✅ 扩展源已安全隔离写入: $CUSTOM_REPO_FILE"
            
            # 重新同步索引（带免检标记）并二次获取版本
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
    case "$confirm" in
        [yY][eE][sS]|[yY])
            echo "🚀 正在部署 PassWall 核心及中文包 (全面绕过安全证书签名)..."
            # 核心绝杀：通过 --allow-untrusted 强行将第三方软件灌入官方原版固件中
            apk add --allow-untrusted luci-app-passwall luci-i18n-passwall-zh-cn
            if [ $? -eq 0 ]; then
                refresh_luci
                echo "✅ PassWall 部署成功！"
            else
                echo "❌ 安装失败，请查看上方 apk 报错。建议重装系统后在干净环境下运行。"
            fi
            ;;
        *)
            echo "🛑 操作已取消。"
            ;;
    esac
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
    
    # 3. 清理可能注入的第三方自定义软件源配置（彻底洗地恢复纯净原厂）
    rm -f /etc/apk/repositories.d/custom.list 2>/dev/null
    rm -f /etc/apk/repositories 2>/dev/null
    
    # 4. 提供硬核选项：是否连同底层内核一起端掉
    echo "-------------------------------------------------"
    printf "❓ 是否连同共享内核(Xray, Sing-Box, ChinaDNS-NG)一起卸载清空？[y/N]: "
    read del_cores
    case "$del_cores" in
        [yY][eE][sS]|[yY])
            echo "💥 正在强制剥离底层核心组件..."
            apk del chinadns-ng xray-core sing-box dns2tcp trojan-plus 2>/dev/null
            ;;
        *)
            echo "💡 已保留底层共享内核，方便其他插件复用。"
            ;;
    esac

    refresh_luci
    echo "✅ 彻底洗地完毕！系统环境已恢复如初。"
}

# ==================== 主菜单逻辑 ====================
while true; do
    echo "================================================="
    echo "  ${SYS_TITLE} 维护工具箱 (25.12 APKv3 修正版)"
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
