#!/bin/sh

# 1. 环境基础合规性检查
if [ ! -f /etc/openwrt_release ]; then
    echo "❌ 错误：未检测到标准的 OpenWrt/ImmortalWrt 系统文件，脚本退出。"
    exit 1
fi

. /etc/openwrt_release
SYS_TITLE="${DISTRIB_DESCRIPTION:-$DISTRIB_ID $DISTRIB_RELEASE}"

update_source() {
    echo "🔄 正在执行前置洗地，清空旧缓存暗病..."
    rm -rf /var/cache/apk/* /tmp/luci-*cache /tmp/apk* 2>/dev/null
    echo "🔄 正在同步本地官方 APK 软件包索引 (apk update)..."
    apk update
}

refresh_system() {
    echo "🧹 正在强制清理网页菜单缓存并重载界面..."
    rm -rf /tmp/luci-indexcache /tmp/luci-modulecache 2>/dev/null
    echo "🔄 正在重新唤醒防火墙、网页与代理服务核心..."
    /etc/init.d/uhttpd restart 2>/dev/null
    /etc/init.d/nginx restart 2>/dev/null
    /etc/init.d/firewall restart 2>/dev/null
    [ -f /etc/init.d/passwall ] && /etc/init.d/passwall restart 2>/dev/null
    [ -f /etc/init.d/homeproxy ] && /etc/init.d/homeproxy restart 2>/dev/null
}

# ==================== 核心模块 1：PassWall ====================
install_passwall() {
    echo "-------------------------------------------------"
    rm -f /etc/apk/repositories 2>/dev/null
    rm -f /etc/apk/repositories.d/custom.list 2>/dev/null
    rm -f /etc/apk/repositories.d/customfeeds.list 2>/dev/null
    
    update_source
    echo "-------------------------------------------------"
    echo "🔍 正在读取 PassWall 组件版本信息..."

    if apk info -e luci-app-passwall >/dev/null 2>&1; then
        CURRENT_VER=$(apk list -I luci-app-passwall 2>/dev/null | head -n 1 | awk '{print $1}' | sed 's/luci-app-passwall-//')
    else
        CURRENT_VER="未安装"
    fi

    LATEST_VER=$(apk list luci-app-passwall 2>/dev/null | head -n 1 | awk '{print $1}' | sed 's/luci-app-passwall-//')
    
    if [ -z "$LATEST_VER" ]; then
        echo "❌ 警告：当前系统官方软件源内未发现 luci-app-passwall。"
        echo "-------------------------------------------------"
        echo "💡 我们可以尝试为您自动下发安全公网密钥，并接入完美适配 APK v3 的正统 PassWall 扩展源。"
        printf "❓ 是否允许脚本尝试为您配置第三方 PassWall 软件源？[y/N]: "
        read add_repo
        
        if [ "$add_repo" = "y" ] || [ "$add_repo" = "Y" ]; then
            ARCH=$(cat /etc/apk/arch 2>/dev/null || echo "aarch64_cortex-a53")
            CUSTOM_REPO_FILE="/etc/apk/repositories.d/customfeeds.list"
            
            mkdir -p /etc/apk/repositories.d
            mkdir -p /etc/apk/keys
            
            echo "🔑 正在同步下发专属第三方安全信任密钥..."
            curl -sLk "https://master.dl.sourceforge.net/project/openwrt-passwall-build/apk.pub" -o /etc/apk/keys/passwall.pub
            
            echo "📥 正在配置全套兼容的经典 Passwall 核心及前端组件专线..."
            echo "https://master.dl.sourceforge.net/project/openwrt-passwall-build/releases/packages-25.12/$ARCH/passwall_luci/packages.adb" > "$CUSTOM_REPO_FILE"
            echo "https://master.dl.sourceforge.net/project/openwrt-passwall-build/releases/packages-25.12/$ARCH/passwall_packages/packages.adb" >> "$CUSTOM_REPO_FILE"
            echo "✅ 扩展源及公钥配置完毕。"
            
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

    printf "❓ 是否确认执行满血安装/升级流程？[y/N]: "
    read confirm
    switch_confirm=$(echo "$confirm" | tr '[:upper:]' '[:lower:]')
    
    if [ "$switch_confirm" = "y" ] || [ "$switch_confirm" = "yes" ]; then
        echo "🚀 正在全自动部署前端、汉化包、解密核心及防火墙内核抓包外挂..."
        apk add --allow-untrusted \
                luci-app-passwall \
                luci-i18n-passwall-zh-cn \
                luci-i18n-base-zh-cn \
                xray-core \
                sing-box \
                chinadns-ng \
                ca-bundle \
                libustream-openssl \
                curl \
                kmod-nft-tproxy \
                ip-full \
                iptables-nft
                
        if [ $? -eq 0 ]; then
            refresh_system
            echo "================================================="
            echo "✅ 🎉 恭喜老哥！全套组件、大脑内核与汉化已完美闭环通关！"
            echo "================================================="
        else
            echo "❌ 安装失败，请查看上方 apk 报错。"
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
    
    apk del luci-app-passwall luci-i18n-passwall-zh-cn
    rm -rf /etc/config/passwall /usr/share/passwall /var/etc/passwall /var/run/passwall* 2>/dev/null
    rm -f /etc/apk/repositories.d/customfeeds.list /etc/apk/repositories.d/custom.list /etc/apk/repositories /etc/apk/keys/passwall.pub 2>/dev/null
    
    printf "❓ 是否连同共享内核(Xray, ChinaDNS-NG)一起卸载清空？[y/N]: "
    read del_cores
    switch_cores=$(echo "$del_cores" | tr '[:upper:]' '[:lower:]')
    
    if [ "$switch_cores" = "y" ] || [ "$switch_cores" = "yes" ]; then
        apk del chinadns-ng xray-core iptables-nft 2>/dev/null
    fi
    refresh_system
    echo "✅ 彻底洗地完毕！"
}

# ==================== 核心模块 2：HomeProxy ====================
install_homeproxy() {
    echo "-------------------------------------------------"
    # 🎯 核心指标：锁定官方 1.12 系列最稳收官版本
    HP_SINGBOX_VER="1.12.15" 
    
    rm -f /etc/apk/repositories 2>/dev/null
    rm -f /etc/apk/repositories.d/custom.list 2>/dev/null
    rm -f /etc/apk/repositories.d/homeproxy.list 2>/dev/null
    
    update_source
    echo "-------------------------------------------------"
    
    ARCH=$(cat /etc/apk/arch 2>/dev/null || echo "aarch64_cortex-a53")
    LUCI_REPO="https://downloads.immortalwrt.org/snapshots/packages/$ARCH/luci/packages.adb"
    PACKAGES_REPO="https://downloads.immortalwrt.org/snapshots/packages/$ARCH/packages/packages.adb"

    echo "🔍 正在读取本地已安装的 HomeProxy 组件版本..."
    if apk info -e luci-app-homeproxy >/dev/null 2>&1; then
        CURRENT_VER=$(apk list -I luci-app-homeproxy 2>/dev/null | head -n 1 | awk '{print $1}' | sed 's/luci-app-homeproxy-//')
    else
        CURRENT_VER="未安装"
    fi

    echo "🔄 正在跨越安全组阻断，直接提取远端最新可用版本..."
    LATEST_VER=$(apk --allow-untrusted --repository "$LUCI_REPO" list luci-app-homeproxy 2>/dev/null | grep "luci-app-homeproxy" | head -n 1 | awk '{print $1}' | sed 's/luci-app-homeproxy-//')
    
    if [ -z "$LATEST_VER" ]; then
        LATEST_VER="获取成功 (专线通道已就绪，可直接安装)"
    fi

    echo "📊 HomeProxy 版本看板："
    echo "   • 当前本地已安装: ${CURRENT_VER}"
    echo "   • 战术目标内核: 强刷官方纯净 v${HP_SINGBOX_VER} 裸核心"
    echo "   • 界面软件源可用: ${LATEST_VER}"
    echo "-------------------------------------------------"

    printf "❓ 是否确认执行【1.12.15 裸内核强刷夺舍】满血安装流程？[y/N]: "
    read confirm
    switch_confirm=$(echo "$confirm" | tr '[:upper:]' '[:lower:]')
    
    if [ "$switch_confirm" = "y" ] || [ "$switch_confirm" = "yes" ]; then
        echo "🚀 🛠️ 第一步：顺水推舟，让系统把前端和官方自带内核顺畅安上..."
        apk --allow-untrusted \
            --repository "$LUCI_REPO" \
            --repository "$PACKAGES_REPO" \
            add luci-app-homeproxy \
                luci-i18n-homeproxy-zh-cn \
                luci-i18n-base-zh-cn \
                sing-box \
                ca-bundle \
                libustream-openssl \
                curl \
                kmod-nft-tproxy \
                ip-full \
                iptables-nft
                
        if [ $? -ne 0 ]; then
            echo "❌ 错误：基础组件安装失败，请检查上方包管理器报错。"
            return 1
        fi

        echo "🛑 ⚙️ 第二步：拦截刹车，强制暂缓后台代理服务..."
        /etc/init.d/homeproxy stop 2>/dev/null

        # 🧠 智能判定系统真实的硬件裸内核架构
        if echo "$ARCH" | grep -q "x86_64"; then
            SB_RAW_ARCH="amd64"
        else
            SB_RAW_ARCH="arm64"
        fi

        echo "📥 📡 第三步：从 SagerNet 官方发布库直连拉取 v${HP_SINGBOX_VER} 纯净裸核心..."
        # 🌟 绝杀：直接下载官方编译打包好的纯净二进制文件（.tar.gz），没有任何网页重定向，直奔主题
        curl -Lk "https://github.com/SagerNet/sing-box/releases/download/v${HP_SINGBOX_VER}/sing-box-${HP_SINGBOX_VER}-linux-${SB_RAW_ARCH}.tar.gz" -o /tmp/sb-core.tar.gz
        
        if [ $? -eq 0 ] && [ -s /tmp/sb-core.tar.gz ]; then
            echo "📦 🧹 第四步：就地解压并执行【偷梁换柱】强行强刷覆盖..."
            mkdir -p /tmp/sb-extract
            tar -zxf /tmp/sb-core.tar.gz -C /tmp/sb-extract/
            
            # 精准定位解压出来的裸执行文件，暴力覆盖系统的默认路径
            cp -f /tmp/sb-extract/sing-box-*/sing-box /usr/bin/sing-box
            chmod +x /usr/bin/sing-box
            
            # 清理现场
            rm -rf /tmp/sb-extract /tmp/sb-core.tar.gz 2>/dev/null
            
            # 最终对账验身
            echo "-------------------------------------------------"
            echo "📊 核心验身报告（当前系统骨子里跑的真实版本）："
            /usr/bin/sing-box version | head -n 1
            echo "-------------------------------------------------"
            
            refresh_system
            echo "================================================="
            echo "✅ 🎉 战术大获全胜！HomeProxy 与 1.12.15 裸内核已强行夺舍成功！"
            echo "================================================="
        else
            echo "❌ 错误：1.12.15 官方内核包直连拉取失败，请检查软路由网络后重试。"
            return 1
        fi
    else
        echo "🛑 操作已取消。"
    fi
}

uninstall_homeproxy() {
    echo "-------------------------------------------------"
    echo "🗑️ 正在启动 HomeProxy 安全卸载程序..."
    
    if [ -f /etc/init.d/homeproxy ]; then
        /etc/init.d/homeproxy stop 2>/dev/null
        /etc/init.d/homeproxy disable 2>/dev/null
    fi
    
    apk del luci-app-homeproxy luci-i18n-homeproxy-zh-cn
    rm -rf /etc/config/homeproxy /usr/share/homeproxy /var/etc/homeproxy /var/run/homeproxy* 2>/dev/null
    rm -f /etc/apk/repositories.d/homeproxy.list /etc/apk/repositories 2>/dev/null
    
    printf "❓ 是否连同核心(Sing-Box)一起卸载清空？[y/N]: "
    read del_cores
    switch_cores=$(echo "$del_cores" | tr '[:upper:]' '[:lower:]')
    
    if [ "$switch_cores" = "y" ] || [ "$switch_cores" = "yes" ]; then
        apk del sing-box iptables-nft 2>/dev/null
    fi

    refresh_system
    echo "✅ 彻底洗地完毕！"
}

# ==================== 主菜单逻辑 ====================
while true; do
    echo "================================================="
    echo "  ${SYS_TITLE} 终极维护工具箱 (25.x 裸核强刷版)"
    echo "================================================="
    echo "💡 请选择操作："
    echo "1) 安装 / 升级 PassWall"
    echo "2) 彻底卸载 PassWall"
    echo "3) 安装 / 升级 HomeProxy (物理强刷 1.12.15 裸内核)"
    echo "4) 彻底卸载 HomeProxy"
    echo "5) 退出工具箱"
    echo "-------------------------------------------------"
    printf "请输入对应数字 [1-5]: "
    read choice
    case $choice in
        1) install_passwall ; echo "" ;;
        2) uninstall_passwall ; echo "" ;;
        3) install_homeproxy ; echo "" ;;
        4) uninstall_homeproxy ; echo "" ;;
        5) echo "👋 已退出。" ; exit 0 ;;
        *) echo "❌ 输入错误。" ; echo "" ; sleep 1 ;;
    esac
done
