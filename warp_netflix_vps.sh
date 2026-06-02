name: WARP Netflix One-Click Unlocker

on:
  workflow_dispatch: # 在 GitHub 页面生成手动运行按钮

jobs:
  warp-unlock:
    runs-on: ubuntu-latest

    steps:
    - name: 真正的全自动一键刷奈飞 IP
      run: |
        # 1. 强制非交互模式，防止安装时弹窗卡住
        export DEBIAN_FRONTEND=noninteractive
        
        # 2. 安装官方 WARP 客户端与必要工具
        echo "=================================================="
        echo "🚀 正在安装官方 WARP 客户端及依赖..."
        echo "=================================================="
        sudo apt-get update -y -qq
        sudo apt-get install -y -qq wireguard-tools curl jq cloudflare-warp > /dev/null 2>&1
        
        # 3. 初始化并启动 WARP（配置为SOCKS5代理模式，防止GitHub断网）
        sudo warp-cli --accept-tos registration register > /dev/null 2>&1
        sudo warp-cli --accept-tos mode proxy > /dev/null 2>&1
        sudo warp-cli --accept-tos connect > /dev/null 2>&1
        sleep 3
        
        # 4. 开始循环刷 IP 测试奈飞非自制剧
        NETFLIX_ID="81280942"
        MAX_ATTEMPTS=30
        ATTEMPT=1
        SUCCESS=0
        
        echo "=================================================="
        echo "🔍 开始循环筛选解锁奈飞非自制剧的 IP..."
        echo "=================================================="
        
        while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
            # 请求奈飞非自制剧页面
            STATUS_CODE=$(curl -s -o /dev/null --socks5-hostname 127.0.0.1:40000 -w "%{http_code}" --user-agent "Mozilla/5.0" "https://www.netflix.com/title/${NETFLIX_ID}")
            
            if [ "$STATUS_CODE" -eq 200 ]; then
                echo "[+] 第 ${ATTEMPT} 次尝试：🎉 成功刷到解锁 IP！"
                SUCCESS=1
                break
            else
                echo "[-] 第 ${ATTEMPT} 次尝试：未解锁 (HTTP ${STATUS_CODE})。正在刷新 IP..."
                # 断开并重连以更换 IP
                sudo warp-cli --accept-tos disconnect > /dev/null 2>&1
                sleep 1
                sudo warp-cli --accept-tos connect > /dev/null 2>&1
                sleep 3
            fi
            ATTEMPT=$((ATTEMPT + 1))
        done
        
        # 5. 如果成功，提取配置并打印
        if [ $SUCCESS -eq 1 ]; then
            echo "=================================================="
            echo " 🎉 奈飞非自制剧解锁成功！"
            echo "=================================================="
            
            # 获取节点地理信息
            IP_INFO=$(curl -s --socks5-hostname 127.0.0.1:40000 https://ifconfig.co/json)
            echo "[出口IP]: $(echo $IP_INFO | jq -r .ip)"
            echo "[国别/城市]: $(echo $IP_INFO | jq -r .country_iso) / $(echo $IP_INFO | jq -r .city)"
            
            # 下载 wgcf 并提取标准的 WireGuard 配置文件
            WGCF_VERSION=$(curl -s "https://api.github.com/repos/ViRb3/wgcf/releases/latest" | jq -r .name)
            [[ -z "$WGCF_VERSION" ]] && WGCF_VERSION="2.2.22"
            curl -fsSL -o wgcf https://github.com/ViRb3/wgcf/releases/download/${WGCF_VERSION}/wgcf_${WGCF_VERSION}_linux_amd64
            chmod +x wgcf
            ./wgcf register --accept-tos > /dev/null 2>&1
            ./wgcf generate > /dev/null 2>&1
            
            echo ""
            echo "👇 【直接复制下方内容到你的 WireGuard 客户端中使用】:"
            echo "--------------------------------------------------"
            cat wgcf-profile.conf
            echo "--------------------------------------------------"
        else
            echo "❌ 刷了 ${MAX_ATTEMPTS} 次仍未成功，请稍后重新运行任务重试。"
            exit 1
        fi
