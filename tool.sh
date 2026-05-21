#!/bin/sh

# 1. 环境基础合规性检查
if [ ! -f /etc/openwrt_release ]; then
    echo "❌ 错误：未检测到标准的 OpenWrt/ImmortalWrt 系统文件，脚本退出。"
    exit 1
fi

. /etc/openwrt_release
SYS_TITLE="${DISTRIB_DESCRIPTION:-$DISTRIB_ID $DISTRIB_RELEASE}"

ARCH=$(cat /etc/apk/arch 2>/dev/null || echo "aarch64_cortex-a53")
REPO_FILE="/etc/apk/repositories"
HAS_UPDATED=0

# 🎯 2. 全局唯一自适应更新函数（绝不重复对账）
do_apk_update() {
    if [ "$HAS_UPDATED" -eq 0 ]; then
        echo "-------------------------------------------------"
        echo "🔄 正在同步 APK 软件包索引 (apk update)..."
        rm -rf /var/cache/apk/* /tmp/luci-*cache /tmp/apk* 2>/dev/null
        apk update
        HAS_UPDATED=1
    fi
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

# 🎯 3. NTP 时间服务器智能对账去重函数
optimize_ntp() {
    echo "-------------------------------------------------"
    echo "⚙️ 正在智能调优 NTP 时间服务器名单..."
    local modified=0
    for server in "ntp.aliyun.com" "ntp.tencent.com" "ntp.ntsc.ac.cn" "time.apple.com"; do
        if ! uci get system.ntp.server 2>/dev/null | grep -q "$server"; then
            uci add_list system.ntp.server="$server"
            echo "➕ 成功追加国内优质时间源: $server"
            modified=1
        fi
    done
    if [ "$modified" -eq 1 ]; then
        uci commit system
        /etc/init.d/system restart 2>/dev/null
        echo "✅ 系统时间服务已成功合闸生效！"
    fi
}

# ==================== 核心模块 1：PassWall ====================
install_passwall() {
    echo "-------------------------------------------------"
    echo "🔍 正在核对 PassWall 软件源物理接入状态..."
    local need_update=0
    if ! grep -q "openwrt-passwall-build" "$REPO_FILE"; then
        echo "📥 正在向 /etc/apk/repositories 直接灌入 PassWall 扩展源..."
        mkdir -p /etc/apk/keys
        curl -sLk "https://master.dl.sourceforge.net/project/openwrt-passwall-build/apk.pub" -o /etc/apk/keys/passwall.pub
        echo "https://master.dl.sourceforge.net/project/openwrt-passwall-build/releases/packages-25.12/$ARCH/passwall_luci/packages.adb" >> "$REPO_FILE"
        echo "https://master.dl.sourceforge.net/project/openwrt-passwall-build/releases/packages-25.12/$ARCH/passwall_packages/packages.adb" >> "$REPO_FILE"
        echo "✅ 软件源物理接入完毕。"
        need_update=1
    fi

    if [ "$need_update" -eq 1 ] || [ "$HAS_UPDATED" -eq 0 ]; then
        HAS_UPDATED=0  
        do_apk_update
    fi

    if apk info -e luci-app-passwall >/dev/null 2>&1; then
        CURRENT_VER=$(apk list -I luci-app-passwall 2>/dev/null | head -n 1 | awk '{print $1}' | sed 's/luci-app-passwall-//')
    else
        CURRENT_VER="未安装"
    fi
    LATEST_VER=$(apk list luci-app-passwall 2>/dev/null | head -n 1 | awk '{print $1}' | sed 's/luci-app-passwall-//')

    echo "📊 PassWall 版本看板："
    echo "   • 当前本地已安装: ${CURRENT_VER}"
    echo "   • 软件源最新可用: ${LATEST_VER}"
    echo "-------------------------------------------------"
    printf "❓ 是否确认执行安装/升级流程？[y/N]: "
    read confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        echo "🚀 正在闪电补齐缺失的 PassWall 外壳组件..."
        apk add --allow-untrusted luci-app-passwall luci-i18n-passwall-zh-cn geoview chinadns-ng
        if [ $? -eq 0 ]; then
            optimize_ntp
            refresh_system
            echo "✅ 🎉 PassWall 闪电部署成功！"
        else
            echo "❌ 安装失败。"
        fi
    fi
}

uninstall_passwall() {
    echo "-------------------------------------------------"
    echo "🗑️ 正在安全拔除 PassWall 组件..."
    [ -f /etc/init.d/passwall ] && /etc/init.d/passwall stop 2>/dev/null
    apk del luci-app-passwall luci-i18n-passwall-zh-cn geoview chinadns-ng hysteria 2>/dev/null
    sed -i '/openwrt-passwall-build/d' "$REPO_FILE" 2>/dev/null
    rm -f /etc/apk/keys/passwall.pub 2>/dev/null
    rm -rf /etc/config/passwall /usr/share/passwall /var/etc/passwall 2>/dev/null
    refresh_system
    echo "✅ 洗地完毕！"
}

# ==================== 核心模块 2：HomeProxy ====================
install_homeproxy() {
    echo "-------------------------------------------------"
    echo "🚀 正在通过临时高级通道，接入专属 HomeProxy 核心外壳..."
    do_apk_update
    LUCI_REPO="https://downloads.immortalwrt.org/snapshots/packages/$ARCH/luci/packages.adb"
    apk --allow-untrusted --repository "$LUCI_REPO" add luci-app-homeproxy luci-i18n-homeproxy-zh-cn
    if [ $? -eq 0 ]; then
        optimize_ntp
        refresh_system
        echo "✅ 🎉 基于 sing-box 1.12.17 的 HomeProxy 已满血复活！"
    else
        echo "❌ 安装失败。"
    fi
}

uninstall_homeproxy() {
    echo "-------------------------------------------------"
    echo "🗑️ 正在卸载 HomeProxy 面板..."
    [ -f /etc/init.d/homeproxy ] && /etc/init.d/homeproxy stop 2>/dev/null
    apk del luci-app-homeproxy luci-i18n-homeproxy-zh-cn 2>/dev/null
    rm -rf /etc/config/homeproxy /usr/share/homeproxy /var/run/homeproxy* 2>/dev/null
    refresh_system
    echo "✅ HomeProxy 已卸载干净。"
}

# ==================== 核心模块 3：Argon 主题 ====================
install_argon() {
    echo "-------------------------------------------------"
    echo "🎨 正在准备部署大雕经典 Argon 磨砂玻璃全局主题..."
    do_apk_update
    LUCI_REPO="https://downloads.immortalwrt.org/snapshots/packages/$ARCH/luci/packages.adb"
    apk --allow-untrusted --repository "$LUCI_REPO" add luci-theme-argon luci-app-argon-config luci-i18n-argon-config-zh-cn
    if [ $? -eq 0 ]; then
        uci set luci.main.mediaurlbase='/luci-static/argon'
        uci commit luci
        refresh_system
        echo "✅ 🎉 颜值拉满！Argon 磨砂玻璃主题已成功激活！"
    else
        echo "❌ 安装失败。"
    fi
}

uninstall_argon() {
    echo "-------------------------------------------------"
    echo "🗑️ 正在启动 Argon 主题安全卸载程序..."
    uci set luci.main.mediaurlbase='/luci-static/bootstrap'
    uci commit luci
    apk del luci-theme-argon luci-app-argon-config luci-i18n-argon-config-zh-cn 2>/dev/null
    refresh_system
    echo "✅ 🎉 还原完毕！"
}

# ==================== 核心模块 4：视觉瘦身版动态温度卡片 ====================
install_web_thermal() {
    echo "-------------------------------------------------"
    echo "🛠️ 正在全自动部署【精简版硬件温度监控面板】..."

    cat << 'EOF' > /usr/share/rpcd/acl.d/luci-thermal.json
{
	"luci": {
		"read": {
			"file": [
				"/sys/class/thermal/thermal_zone0/temp",
				"/sys/class/thermal/thermal_zone0/type",
				"/sys/class/thermal/thermal_zone1/temp",
				"/sys/class/thermal/thermal_zone1/type",
				"/sys/class/thermal/thermal_zone2/temp",
				"/sys/class/thermal/thermal_zone2/type"
			]
		}
	}
}
EOF

    cat << 'EOF' > /www/luci-static/resources/view/status/include/15_thermal.js
'use strict';
'require baseclass';
'require fs';

return baseclass.extend({
	title: '硬件温度',

	load: function() {
		var zones = ['thermal_zone0', 'thermal_zone1', 'thermal_zone2'];
		var promises = zones.map(function(zone) {
			return Promise.all([
				fs.read('/sys/class/thermal/' + zone + '/type').catch(function() { return null; }),
				fs.read('/sys/class/thermal/' + zone + '/temp').catch(function() { return null; })
			]);
		});
		return Promise.all(promises);
	},

	render: function(data) {
		if (!data) return null;
		var rows = [];

		for (var i = 0; i < data.length; i++) {
			var type = data[i][0];
			var temp = data[i][1];

			if (!type || !temp || !temp.trim()) continue;

			type = type.trim().toLowerCase();
			var tempVal = (parseInt(temp.trim(), 10) / 1000).toFixed(1) + ' °C';
			var displayName = '其他 (' + type.toUpperCase() + ')';

			if (type.indexOf('cpu') !== -1 || type.indexOf('soc') !== -1) {
				displayName = 'CPU 核心';
			} else if (type.indexOf('wifi') !== -1 || type.indexOf('wlan') !== -1 || type.indexOf('mt7') !== -1) {
				displayName = 'WiFi 无线';
			}

			rows.push(E('div', { 'class': 'tr' }, [
				E('div', { 'class': 'td left', 'width': '33%' }, displayName),
				E('div', { 'class': 'td left' }, tempVal)
			]));
		}

		if (rows.length === 0) return null;

		return E('div', { 'class': 'cbi-section' }, [
			E('div', { 'class': 'luci-card' }, [
				E('div', { 'class': 'table' }, rows)
			])
		]);
	}
});
EOF

    /etc/init.d/rpcd restart 2>/dev/null
    refresh_system
    echo "================================================="
    echo "✅ 🎉 报告老哥：超精简高颜值温度面板已重新注入！"
    echo "================================================="
}

# ==================== 主菜单逻辑 ====================
while true; do
    echo "================================================="
    echo "  ${SYS_TITLE} 维护工具箱 (双剑合璧完美集成版)"
    echo "================================================="
    echo "💡 请选择操作："
    echo "1) 一键闪电安装 PassWall"
    echo "2) 彻底安全卸载 PassWall"
    echo "3) 一键闪电安装 HomeProxy"
    echo "4) 彻底安全卸载 HomeProxy"
    echo "5) 一键安装 / 强制激活大雕 Argon 磨砂主题"
    echo "6) 一键彻底卸载 Argon 主题"
    echo "7) 一键网页动态集成全套温度面板 (含CPU与WiFi自动对账)"
    echo "8) 退出工具箱"
    echo "-------------------------------------------------"
    printf "请输入对应数字 [1-8]: "
    read choice
    case $choice in
        1) install_passwall ; echo "" ;;
        2) uninstall_passwall ; echo "" ;;
        3) install_homeproxy ; echo "" ;;
        4) uninstall_homeproxy ; echo "" ;;
        5) install_argon ; echo "" ;;
        6) uninstall_argon ; echo "" ;;
        7) install_web_thermal ; echo "" ;;
        8) echo "👋 已退出。" ; exit 0 ;;
        *) echo "❌ 输入错误。" ; echo "" ; sleep 1 ;;
    esac
done
