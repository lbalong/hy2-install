#!/bin/sh

# 1. 环境基础合规性检查
if [ ! -f /etc/openwrt_release ]; then
    echo "❌ 错误：未检测到标准的 OpenWrt/ImmortalWrt 系统文件，脚本退出。"
    exit 1
fi

. /etc/openwrt_release
SYS_TITLE="${DISTRIB_DESCRIPTION:-$DISTRIB_ID $DISTRIB_RELEASE}"

# 📊 状态账本：记录本轮脚本运行中，是否已经执行过全局索引同步
GLOBAL_UPDATED=0

# 🎯 2. 前置自动补齐 curl 命令及 HTTPS 证书链
if ! command -v curl >/dev/null 2>&1; then
    echo "🌐 检测到原厂系统未打包 curl 命令，正在全自动为您铺设底层网络水管..."
    rm -rf /var/cache/apk/* /tmp/apk* 2>/dev/null
    apk update >/dev/null 2>&1
    apk add curl ca-bundle libustream-openssl >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "❌ 严重错误：底层 curl 组件补齐失败，请检查软路由国内网络是否通畅！"
        exit 1
    fi
    echo "✅ curl 核心及安全证书链已满血就位。"
    GLOBAL_UPDATED=1
fi

update_source() {
    echo "🔄 正在执行前置洗地，清空旧缓存暗病..."
    rm -rf /var/cache/apk/* /tmp/luci-*cache /tmp/apk* 2>/dev/null
    echo "🔄 正在同步本地 APK 软件包索引 (apk update)..."
    apk update
    GLOBAL_UPDATED=1
