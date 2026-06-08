#!/bin/bash
# ==============================================================================
# Cloudflare WARP Gemini Unlocker - VPS One-Click Installer
# ==============================================================================
# Supported OS: Debian, Ubuntu, CentOS, RHEL, Rocky Linux, AlmaLinux
# Purpose: Install Cloudflare WARP in SOCKS5 proxy mode (Port 40000)
#          to bypass Google Gemini datacenter IP restrictions.
# ==============================================================================
# Output formatting colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
PLAIN='\033[0'
# Print helper functions
info() { echo -e "${BLUE}[INFO]${PLAIN} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${PLAIN} $1"; }
warn() { echo -e "${YELLOW}[WARNING]${PLAIN} $1"; }
error() { echo -e "${RED}[ERROR]${PLAIN} $1"; exit 1; }
# Check root privilege
if [ "$EUID" -ne 0 ]; then
    error "Please run this script as root (use sudo)."
fi
# Detect system architecture
ARCH=$(uname -m)
if [ "$ARCH" != "x86_64" ] && [ "$ARCH" != "aarch64" ]; then
    error "Unsupported architecture: $ARCH. Cloudflare WARP only supports amd64 (x86_64) and arm64 (aarch64)."
fi
# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID=$ID
    OS_LIKE=$ID_LIKE
else
    error "Cannot determine the OS version. File /etc/os-release not found."
fi
info "Detecting system OS: $OS_ID ($ARCH)"
# ------------------------------------------------------------------------------
# 1. Install Cloudflare WARP Repository and Package
# ------------------------------------------------------------------------------
install_warp() {
    case "$OS_ID" in
        ubuntu|debian)
            info "Installing/updating dependencies for Debian/Ubuntu..."
            apt-get update -y
            apt-get install -y curl gpg lsb-release ca-certificates
            info "Adding Cloudflare GPG Key..."
            curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor -o /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
            info "Adding Cloudflare Repository..."
            echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/cloudflare-client.list
            info "Installing/updating cloudflare-warp..."
            apt-get update -y
            apt-get install -y cloudflare-warp
            ;;
        centos|rhel|rocky|alma)
            info "Installing/updating dependencies for RHEL/CentOS-like system..."
            yum install -y curl ca-certificates
            info "Adding Cloudflare Repository & GPG Key..."
            rpm --import https://pkg.cloudflareclient.com/pubkey.gpg
            curl -fsSL https://pkg.cloudflareclient.com/cloudflare-warp-ascii.repo | tee /etc/yum.repos.d/cloudflare-warp.repo
            info "Installing/updating cloudflare-warp..."
            yum update -y
            yum install -y cloudflare-warp
            ;;
        *)
            if [[ "$OS_LIKE" =~ "debian" || "$OS_LIKE" =~ "ubuntu" ]]; then
                info "System looks like Debian/Ubuntu. Proceeding with apt install..."
                apt-get update -y
                apt-get install -y curl gpg lsb-release ca-certificates
                curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor -o /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
                CODENAME=$(lsb_release -cs)
                echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $CODENAME main" | tee /etc/apt/sources.list.d/cloudflare-client.list
                apt-get update -y
                apt-get install -y cloudflare-warp
            elif [[ "$OS_LIKE" =~ "rhel" || "$OS_LIKE" =~ "centos" || "$OS_LIKE" =~ "fedora" ]]; then
                info "System looks like RHEL/CentOS. Proceeding with yum install..."
                yum install -y curl ca-certificates
                rpm --import https://pkg.cloudflareclient.com/pubkey.gpg
                curl -fsSL https://pkg.cloudflareclient.com/cloudflare-warp-ascii.repo | tee /etc/yum.repos.d/cloudflare-warp.repo
                yum update -y
                yum install -y cloudflare-warp
            else
                error "Unsupported OS: $OS_ID. Please install cloudflare-warp manually."
            fi
            ;;
    esac
}
install_warp
# Ensure warp-svc is running
info "Starting and enabling cloudflare-warp service..."
systemctl daemon-reload
systemctl enable warp-svc
systemctl restart warp-svc
# Wait for warp-svc to initialize
sleep 2
# ------------------------------------------------------------------------------
# 2. Configure Cloudflare WARP (SOCKS5 Mode on Port 40000)
# ------------------------------------------------------------------------------
info "Configuring Cloudflare WARP..."
# Clean up stale/old registration to ensure a fresh, working identity
info "Resetting existing WARP registration..."
warp-cli --accept-tos registration delete >/dev/null 2>&1 || true
# Register new account
info "Registering a new client..."
if ! warp-cli --accept-tos registration new; then
    error "Failed to register new WARP client. Please check warp-svc service status."
fi
# Set mode to proxy
info "Setting mode to SOCKS5 proxy..."
warp-cli --accept-tos mode proxy
# Set proxy port to 40000
info "Setting proxy port to 40000..."
warp-cli --accept-tos proxy port 40000
# Connect to WARP
info "Connecting to Cloudflare WARP..."
warp-cli --accept-tos connect
# Note: 'enable-always-on' is deprecated in latest versions, connection state is persisted automatically by warp-svc.
# ------------------------------------------------------------------------------
# 3. Connection Verification
# ------------------------------------------------------------------------------
info "Waiting for WARP connection to establish (up to 10 seconds)..."
CONNECTED=false
for i in {1..10}; do
    WARP_STATUS=$(warp-cli status)
    if [[ "$WARP_STATUS" == *"Connected"* || "$WARP_STATUS" == *"connected"* ]]; then
        CONNECTED=true
        break
    fi
    sleep 1
done
if [ "$CONNECTED" = true ]; then
    success "Cloudflare WARP client status is: Connected!"
else
    warn "WARP connection is taking longer than expected. Current status:"
    warp-cli status
fi
# Test connection via SOCKS5 proxy
WARP_CHECK=$(curl -s --socks5-hostname 127.0.0.1:40000 https://www.cloudflare.com/cdn-cgi/trace | grep "warp=")
if [[ "$WARP_CHECK" == *"warp=on"* || "$WARP_CHECK" == *"warp=plus"* ]]; then
    success "Cloudflare WARP SOCKS5 proxy is successfully routed and running on port 40000!"
else
    warn "WARP SOCKS5 proxy routing test failed or is pending. Output of trace: $WARP_CHECK"
fi
# Test Gemini API endpoint connectivity
info "Testing Google Gemini API accessibility through WARP..."
GEMINI_TEST=$(curl -s -I -o /dev/null -w "%{http_code}" --socks5-hostname 127.0.0.1:40000 https://generativelanguage.googleapis.com/)
if [ "$GEMINI_TEST" -eq 200 ] || [ "$GEMINI_TEST" -eq 403 ] || [ "$GEMINI_TEST" -eq 404 ]; then
    success "Successfully connected to Gemini API Endpoint via WARP (HTTP $GEMINI_TEST)!"
else
    warn "Unable to reach Gemini API Endpoint (HTTP $GEMINI_TEST). SOCKS5 Proxy may not be fully resolved yet."
fi
# ------------------------------------------------------------------------------
# 4. Outbound Configurations & Help Instructions
# ------------------------------------------------------------------------------
echo -e "\n=========================================================================="
success "WARP SOCKS5 installation and configuration completed!"
echo -e "=========================================================================="
echo -e "${YELLOW}Local SOCKS5 proxy address:${PLAIN} ${GREEN}127.0.0.1:40000${PLAIN}"
echo -e "=========================================================================="
echo -e "\n${BLUE}[How to use this in Xray/Sing-box/X-ui]${PLAIN}"
echo -e "Add a SOCKS outbound pointing to ${GREEN}127.0.0.1:40000${PLAIN}, and set routing rules for Gemini.\n"
echo -e "${BLUE}1. Xray/V2ray config.json Snippet:${PLAIN}"
cat << 'EOF'
"outbounds": [
  {
    "protocol": "socks",
    "tag": "warp-outbound",
    "settings": {
      "servers": [
        {
          "address": "127.0.0.1",
          "port": 40000
        }
      ]
    }
  }
],
"routing": {
  "domainStrategy": "IPIfNonMatch",
  "rules": [
    {
      "type": "field",
      "outboundTag": "warp-outbound",
      "domain": [
        "domain:gemini.google.com",
        "domain:generativelanguage.googleapis.com",
        "domain:aistudio.google.com",
        "domain:alkalimina-pa.clients6.google.com"
      ]
    }
  ]
}
EOF
echo -e "\n${BLUE}2. Sing-box config.json Snippet:${PLAIN}"
cat << 'EOF'
"outbounds": [
  {
    "type": "socks",
    "tag": "warp-outbound",
    "server": "127.0.0.1",
    "server_port": 40000
  }
],
"route": {
  "rules": [
    {
      "domain": [
        "gemini.google.com",
        "generativelanguage.googleapis.com",
        "aistudio.google.com",
        "alkalimina-pa.clients6.google.com"
      ],
      "outbound": "warp-outbound"
    }
  ]
}
EOF
echo -e "\n${BLUE}3. X-UI / 3x-ui Dashboard Setup:${PLAIN}"
echo -e "  - In ${YELLOW}Outbounds${PLAIN}, add a ${GREEN}socks${PLAIN} protocol outbound with IP ${GREEN}127.0.0.1${PLAIN} and Port ${GREEN}40000${PLAIN}. Set tag to ${GREEN}warp-outbound${PLAIN}."
echo -e "  - In ${YELLOW}Routing Rules${PLAIN}, add a rule with Domain matching: "
echo -e "    ${BLUE}domain:gemini.google.com, domain:generativelanguage.googleapis.com, domain:aistudio.google.com, domain:alkalimina-pa.clients6.google.com${PLAIN}"
echo -e "    and set its Outbound Tag to ${GREEN}warp-outbound${PLAIN}."
echo -e "  - Ensure ${RED}Sniffing (流量嗅探)${PLAIN} is enabled in your inbounds."
echo -e "=========================================================================="
