#!/bin/bash
clear
echo "=========================================================="
echo "   🛡️ Cloudflare 小黄云专属：DNS API 证书全自动签发脚本"
echo "=========================================================="

# 1. 收集信息
read -p " 🔑 请输入你的 CF Token: " CF_Token
read -p " 👤 请输入你的 CF Account ID (32位字符): " CF_Account_ID
read -p " 🌐 请输入你的完整域名 (如 jp8.099889.xyz): " DOMAIN

if [ -z "$CF_Token" ] || [ -z "$CF_Account_ID" ] || [ -z "$DOMAIN" ]; then
    echo " ❌ 错误：输入信息不完整，脚本退出。"
    exit 1
fi

# 2. 注入当前环境
export CF_Token="$CF_Token"
export CF_Account_ID="$CF_Account_ID"

# 3. 检查并安装 acme.sh
if [ ! -f "/root/.acme.sh/acme.sh" ]; then
    echo " 📦 正在安装 acme.sh..."
    curl https://get.acme.sh | sh -s email=admin@$DOMAIN
    source /root/.bashrc
fi

# 4. 执行 DNS API 申请
echo " ⏳ 正在通过 Cloudflare DNS API 申请证书，请耐心等待约 2-3 分钟..."
/root/.acme.sh/acme.sh --issue --dns dns_cf -d "$DOMAIN" --server letsencrypt

# 5. 判定并转移证书，完美适配 vless-1.sh 后门
if [ $? -eq 0 ]; then
    echo " ✅ 证书申请成功！正在强行注入节点脚本环境..."
    
    # 创建 vless-1.sh 需要的所有目标文件夹
    mkdir -p /root/.acme.sh/${DOMAIN}_ecc/
    mkdir -p /root/cert/
    
    # 方式A：暴力注入 _ecc 后门目录
    cp /root/.acme.sh/${DOMAIN}*/*.cer /root/.acme.sh/${DOMAIN}_ecc/ 2>/dev/null || true
    cp /root/.acme.sh/${DOMAIN}*/*.key /root/.acme.sh/${DOMAIN}_ecc/ 2>/dev/null || true
    
    # 方式B：规范化安装到 /root/cert/ 通用目录
    /root/.acme.sh/acme.sh --install-cert -d "$DOMAIN" --ecc \
        --fullchain-file /root/cert/fullchain.cer \
        --key-file /root/cert/private.key >/dev/null 2>&1
        
    echo "=========================================================="
    echo " 🎉 准备就绪！环境已完美铺垫。"
    echo " 👉 下一步：请直接运行 bash vless-1.sh，它将自动识别并复用该证书！"
    echo "=========================================================="
else
    echo "=========================================================="
    echo " ❌ 证书申请失败，请向上滚动查看红色报错信息。"
    echo " 💡 常见原因：CF Token/ID 填错，或者域名没有在 CF 解析。"
    echo "=========================================================="
fi
