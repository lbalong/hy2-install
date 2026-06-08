/bin/sh
# ==============================================================================
#  OpenWrt iStore 一键安装脚本 (One-Click iStore Installer)
#  作者: GitHub Deployer
#  适用系统: OpenWrt 21.02 / 22.03 / 23.05 / 25.12 及以上版本
#  支持架构: 推荐 x86_64, arm64 (其他架构如果 opkg 兼容亦可尝试)
# ==============================================================================
# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # 无颜色
# 打印横幅
clear
echo -e "${CYAN}======================================================${NC}"
echo -e "${GREEN}        OpenWrt iStore 插件商店一键安装工具${NC}"
echo -e "${BLUE}  支持官方 OpenWrt / ImmortalWrt 以及各类定制固件${NC}"
echo -e "${CYAN}======================================================${NC}"
echo ""
# 检查是否以 root 权限运行
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}[错误] 请使用 root 用户或通过 sudo 运行此脚本！${NC}"
    exit 1
fi
# 1. 检测系统是否为 OpenWrt
echo -e "${YELLOW}[1/6] 正在检测系统环境...${NC}"
if [ ! -f "/etc/openwrt_release" ]; then
    echo -e "${RED}[错误] 未检测到 /etc/openwrt_release，此脚本仅适用于 OpenWrt 系统！${NC}"
    # 允许用户强制继续，以防某些极个别定制固件删除了该文件
    read -p "是否强制继续？(y/N): " force_run
    if [ "$force_run" != "y" ] && [ "$force_run" != "Y" ]; then
        exit 1
    fi
else
    . /etc/openwrt_release
    echo -e "${GREEN}[成功] 检测到系统: ${DISTRIB_DESCRIPTION:-OpenWrt}${NC}"
    echo -e "${GREEN}[成功] 系统版本: ${DISTRIB_RELEASE:-未知}${NC}"
fi
# 检测 CPU 架构
ARCH=$(sed -n -e 's/^Architecture: *\([^ ]\+\) *$/\1/p' /rom/usr/lib/opkg/info/libc.control /usr/lib/opkg/info/libc.control 2>/dev/null | head -n 1)
echo -e "${GREEN}[成功] 设备架构: ${ARCH:-未知}${NC}"
# 如果架构不是常见推荐的架构，给予警告提示
if [ "$ARCH" != "x86_64" ] && [ "$ARCH" != "aarch64_cortex-a53" ] && [ "$ARCH" != "aarch64_generic" ]; then
    echo -e "${YELLOW}[警告] iStore 官方主要对 x86_64 和 arm64 (aarch64) 架构进行优化。${NC}"
    echo -e "${YELLOW}       当前架构为 [${ARCH:-未知}]，安装程序仍将尝试运行，但部分插件可能不兼容。${NC}"
fi
echo ""
# 2. 检查并准备依赖项 (curl, tar, zcat)
echo -e "${YELLOW}[2/6] 正在检查基础依赖项...${NC}"
# 更新 opkg 源的标记，避免重复更新
OPKG_UPDATED=0
check_and_install_pkg() {
    local pkg=$1
    if ! command -v "$pkg" >/dev/null 2>&1; then
        echo -e "${YELLOW}[提示] 未检测到 ${pkg}，尝试自动安装...${NC}"
        if [ "$OPKG_UPDATED" -eq 0 ]; then
            echo -e "${BLUE}正在更新 opkg 软件包列表...${NC}"
            opkg update
            OPKG_UPDATED=1
        fi
        opkg install "$pkg"
        if ! command -v "$pkg" >/dev/null 2>&1; then
            echo -e "${RED}[错误] 无法安装 ${pkg}，请手动运行 'opkg update && opkg install ${pkg}' 后重试。${NC}"
            return 1
        fi
    fi
    return 0
}
check_and_install_pkg "curl" || exit 1
check_and_install_pkg "tar" || exit 1
# 检测 zcat / gunzip
if ! command -v zcat >/dev/null 2>&1 && ! command -v gunzip >/dev/null 2>&1; then
    check_and_install_pkg "gzip" || exit 1
fi
# 安装 ca-certificates 避免 HTTPS 下载失败
if [ "$OPKG_UPDATED" -eq 0 ]; then
    echo -e "${BLUE}安装 ca-bundle / ca-certificates 以防止证书验证失败...${NC}"
    opkg update
    OPKG_UPDATED=1
fi
opkg install ca-bundle ca-certificates 2>/dev/null
echo -e "${GREEN}[成功] 基础依赖项检查完成！${NC}"
echo ""
# 3. 设置下载源并获取安装包名称
echo -e "${YELLOW}[3/6] 正在获取 iStore 最新安装包信息...${NC}"
ISTORE_REPO="https://istore.istoreos.com/repo/all/store"
ISTORE_REPO_FALLBACK="https://repo.istoreos.com/repo/all/store"
FCURL="curl --fail --show-error -sL"
# 尝试下载软件包列表 (带双源容灾备份)
download_package_list() {
    echo -e "${BLUE}正在从主服务器下载软件包列表...${NC}"
    if $FCURL "$ISTORE_REPO/Packages.gz" > /tmp/Packages.gz 2>/dev/null; then
        return 0
    fi
    echo -e "${YELLOW}[提示] 主服务器连接失败，尝试备用服务器...${NC}"
    if $FCURL "$ISTORE_REPO_FALLBACK/Packages.gz" > /tmp/Packages.gz; then
        # 备用连接成功，切换主源
        ISTORE_REPO="$ISTORE_REPO_FALLBACK"
        return 0
    fi
    return 1
}
if ! download_package_list; then
    echo -e "${RED}[错误] 无法获取 iStore 软件包列表，请检查路由器网络连接！${NC}"
    exit 1
fi
# 解析包名
echo -e "${BLUE}正在解析最新版 luci-app-store...${NC}"
if command -v zcat >/dev/null 2>&1; then
    IPK=$(zcat /tmp/Packages.gz | grep -m1 '^Filename: luci-app-store.*\.ipk$' | sed -n -e 's/^Filename: \(.\+\)$/\1/p')
else
    IPK=$(gunzip -c /tmp/Packages.gz | grep -m1 '^Filename: luci-app-store.*\.ipk$' | sed -n -e 's/^Filename: \(.\+\)$/\1/p')
fi
# 清理 Packages.gz
rm -f /tmp/Packages.gz
if [ -z "$IPK" ]; then
    echo -e "${RED}[错误] 解析 luci-app-store 软件包文件名失败。${NC}"
    exit 1
fi
echo -e "${GREEN}[成功] 查找到最新安装包: $IPK${NC}"
echo ""
# 4. 下载并解压 bootstrap 工具 (is-opkg)
echo -e "${YELLOW}[4/6] 正在引导 iStore 专用包管理器 (is-opkg)...${NC}"
# 下载 luci-app-store.ipk
echo -e "${BLUE}正在从 $ISTORE_REPO/$IPK 下载安装包...${NC}"
if ! $FCURL "$ISTORE_REPO/$IPK" > /tmp/luci-app-store.ipk; then
    echo -e "${RED}[错误] 下载 luci-app-store.ipk 失败！${NC}"
    exit 1
fi
# 从 IPK 中提取 is-opkg
echo -e "${BLUE}正在提取引导程序...${NC}"
if ! tar -xzO -f /tmp/luci-app-store.ipk data.tar.gz 2>/dev/null | tar -xzO ./bin/is-opkg 2>/dev/null > /tmp/is-opkg; then
    # 部分旧版 tar 不支持大写 O 或者路径不同，尝试备用解压方式
    ar x /tmp/luci-app-store.ipk data.tar.gz 2>/dev/null
    tar -xzf data.tar.gz ./bin/is-opkg -O 2>/dev/null > /tmp/is-opkg
    rm -f data.tar.gz control.tar.gz debian-binary 2>/dev/null
fi
if [ ! -s "/tmp/is-opkg" ]; then
    echo -e "${RED}[错误] 提取 is-opkg 失败！可能 tar 版本不兼容或安装包解压失败。${NC}"
    rm -f /tmp/luci-app-store.ipk
    exit 1
fi
chmod 755 /tmp/is-opkg
echo -e "${GREEN}[成功] 成功引导 is-opkg 包管理器！${NC}"
echo ""
# 5. 执行 iStore 安装与依赖解析
echo -e "${YELLOW}[5/6] 正在运行 iStore 安装程序...${NC}"
echo -e "${BLUE}正在更新 iStore 软件源 feeds...${NC}"
/tmp/is-opkg update
echo -e "${BLUE}正在安装依赖包: luci-lib-taskd, luci-lib-xterm...${NC}"
/tmp/is-opkg opkg install --force-reinstall luci-lib-taskd luci-lib-xterm
echo -e "${BLUE}正在安装 iStore 主程序...${NC}"
/tmp/is-opkg opkg install --force-reinstall luci-app-store
INSTALL_STATUS=$?
if [ $INSTALL_STATUS -ne 0 ]; then
    echo -e "${RED}[错误] 安装 luci-app-store 失败，退出码: $INSTALL_STATUS${NC}"
    rm -f /tmp/luci-app-store.ipk /tmp/is-opkg
    exit $INSTALL_STATUS
fi
# 检查并安装 taskd 后台任务守护进程
if [ ! -s "/etc/init.d/tasks" ]; then
    echo -e "${BLUE}正在补充安装后台守护依赖: taskd...${NC}"
    /tmp/is-opkg opkg install --force-reinstall taskd
fi
# 兼容性检测：针对较新/旧版 LuCI，确保安装了 luci-compat
if [ ! -s "/usr/lib/lua/luci/cbi.lua" ]; then
    echo -e "${BLUE}检测到当前 OpenWrt 版本可能较新，正在补全安装 luci-compat 兼容包...${NC}"
    /tmp/is-opkg opkg install luci-compat >/dev/null 2>&1
    # 如果 is-opkg 安装 luci-compat 失败，尝试用系统原生 opkg 安装
    if [ $? -ne 0 ]; then
        opkg install luci-compat >/dev/null 2>&1
    fi
fi
# 清理临时文件
rm -f /tmp/luci-app-store.ipk /tmp/is-opkg
echo -e "${GREEN}[成功] iStore 插件商店及依赖安装完成！${NC}"
echo ""
# 6. 清理缓存并重启 Web 服务
echo -e "${YELLOW}[6/6] 正在优化系统缓存并重启 Web 服务...${NC}"
# 清理 LuCI 缓存
rm -rf /tmp/luci-indexcache /tmp/luci-modulecache /var/luci-indexcache
# 重启相关服务
RESTARTED=0
if [ -x "/etc/init.d/uhttpd" ]; then
    echo -e "${BLUE}正在重启 uhttpd Web 服务...${NC}"
    /etc/init.d/uhttpd restart
    RESTARTED=1
fi
if [ -x "/etc/init.d/nginx" ]; then
    echo -e "${BLUE}正在重启 nginx Web 服务...${NC}"
    /etc/init.d/nginx restart
    RESTARTED=1
fi
if [ -x "/etc/init.d/rpcd" ]; then
    echo -e "${BLUE}正在重启 rpcd 路由通信服务...${NC}"
    /etc/init.d/rpcd restart
fi
echo -e "${GREEN}[成功] 服务重启完成！${NC}"
echo ""
# ==============================================================================
#  安装完成提示
# ==============================================================================
echo -e "${GREEN}======================================================${NC}"
echo -e "${GREEN}        恭喜！iStore 插件商店安装成功！${NC}"
echo -e "${GREEN}======================================================${NC}"
echo -e "${CYAN}使用说明:${NC}"
echo -e " 1. 请刷新浏览器，或者清理浏览器缓存重新登录 OpenWrt 后台。"
echo -e " 2. 在左侧菜单栏即可看到 【iStore】（通常在顶部或【系统】/【服务】子菜单下）。"
if [ "$RESTARTED" -eq 0 ]; then
    echo -e "${YELLOW}提示: 未检测到 uhttpd 或 nginx，如果网页无法打开或菜单未显示，请手动重启路由器。${NC}"
fi
echo -e "${CYAN}======================================================${NC}"
exit 0
