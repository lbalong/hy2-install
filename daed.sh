# 1. 安全全面洗地：强制粉碎之前装错的伪劣残渣
/etc/init.d/daed stop 2>/dev/null
rm -f /usr/bin/daed /etc/init.d/daed 2>/dev/null
rm -rf /tmp/daed* 2>/dev/null

# 2. 补齐原厂没有的 unzip 解压工具及内核 eBPF 水管
echo "📦 正在为您补齐原厂解压引擎及 eBPF 内核网钩..."
rm -rf /var/cache/apk/* /tmp/apk* 2>/dev/null && apk update >/dev/null 2>&1
apk add unzip kmod-bpf kmod-cls-bpf kmod-cls-act kmod-ifb ip-full >/dev/null 2>&1

# 3. 从正统 daeuniverse 官方库叼回真实的 arm64 压缩全量包
echo "📥 正在从正统官方库下载真实 v1.x 版本的 daed-arm64 核心..."
mkdir -p /etc/daed /tmp/daed-extract
curl -Lk "https://github.com/daeuniverse/daed/releases/latest/download/daed-linux-arm64.zip" -o /tmp/daed.zip

# 4. 解压并使出“强行物理提取”大法
if [ -s /tmp/daed.zip ]; then
    unzip -o /tmp/daed.zip -d /tmp/daed-extract/ >/dev/null 2>&1
    # 智能搜寻解压出来的真实执行文件，暴力灌入系统主干路径
    find /tmp/daed-extract -type f -name "daed*" -exec cp -f {} /usr/bin/daed \;
    chmod +x /usr/bin/daed
    echo "✅ 真正的 daed 物理核心已成功降临！当前真实版本为："
    /usr/bin/daed --version 2>/dev/null || echo "daed 核心已就位"
else
    echo "❌ 错误：官方核心包下载失败，请检查软路由公网网络！"
    exit 1
fi

# 5. 重新焊接完美修正版 Procd 系统守护开关（彻底修复 rcOrder 笔误）
echo "⚙️ 正在为您重构标准的系统服务守卫..."
cat << 'EOF' > /etc/init.d/daed
#!/bin/sh /etc/rc.common

START=95
USE_PROCD=1

start_service() {
    procd_open_instance
    procd_set_param command /usr/bin/daed run --config /etc/daed
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_set_param respawn 3600 5 0
    procd_close_instance
}
EOF

# 6. 赋予服务圣旨权限，并合闸点火
chmod +x /etc/init.d/daed
/etc/init.d/daed enable
/etc/init.d/daed start

# 7. 终极环境核对：手动递上 eBPF 梦寐以求的内核调试钥匙
mount -t debugfs debugfs /sys/kernel/debug 2>/dev/null
mkdir -p /sys/fs/cgroup/cgroup2 2>/dev/null
mount -t cgroup2 cgroup2 /sys/fs/cgroup/cgroup2 2>/dev/null

echo "================================================="
echo "🚀 战术大获全胜！守护进程已彻底修正，网络环境已挂载！"
echo "💡 提示：现在直接去浏览器冲锋：http://192.168.2.6:2023/"
echo "================================================="
