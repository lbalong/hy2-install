#!/bin/bash

# ==============================================================================
# Cloudflare WARP Gemini Unlocker - VPS One-Click Installer (Ultra Robust Edition)
# ==============================================================================
# Supported OS: Debian, Ubuntu, CentOS, RHEL, Rocky Linux, AlmaLinux
# Virtualization: Compatible with KVM, OpenVZ, LXC, Docker (100% User-space)
# Port target: SOCKS5 proxy on 127.0.0.1:40000
# Technology: wgcf (WARP account registration) + wireproxy (Go-based SOCKS5 proxy)
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
if [ "$ARCH" = "x86_64" ]; then
    WGCF_ARCH="amd64"
    WP_ARCH="amd64"
elif [ "$ARCH" = "aarch64" ]; then
    WGCF_ARCH="arm64"
    WP_ARCH="arm64"
else
    error "Unsupported architecture: $ARCH. Only amd64 (x86_64) and arm64 (aarch64) are supported."
fi

# Detect OS package manager
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID=$ID
else
    error "Cannot determine the OS version."
fi

# 1. Clean Up Buggy Official Cloudflare-WARP Client
info "Disabling official cloudflare-warp client to prevent conflicts..."
systemctl stop warp-svc >/dev/null 2>&1 || true
systemctl disable warp-svc >/dev/null 2>&1 || true

# 2. Install Dependencies
info "Installing required packages..."
if [ "$OS_ID" = "ubuntu" ] || [ "$OS_ID" = "debian" ]; then
    apt-get update -y
    apt-get install -y curl tar wget ca-certificates
else
    yum install -y curl tar wget ca-certificates
fi

# 3. Download wgcf and wireproxy
info "Downloading wgcf and wireproxy..."
mkdir -p /usr/local/bin

# Wgcf (WARP Configuration Generator)
wget -qO /usr/local/bin/wgcf "https://github.com/ViRb3/wgcf/releases/latest/download/wgcf_linux_${WGCF_ARCH}"
chmod +x /usr/local/bin/wgcf

# Wireproxy (Go-based user-space WireGuard-to-SOCKS5 client)
curl -fsSL "https://github.com/windtf/wireproxy/releases/latest/download/wireproxy_linux_${WP_ARCH}.tar.gz" | tar -xz -C /usr/local/bin/
chmod +x /usr/local/bin/wireproxy

# 4. Generate WARP WireGuard Account
info "Registering a new Cloudflare WARP account via wgcf..."
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR" || error "Failed to create temp directory."

# Perform registration
if ! /usr/local/bin/wgcf register --accept-tos; then
    error "wgcf registration failed. See the error message above for details."
fi

# Generate Profile
/usr/local/bin/wgcf generate >/dev/null 2>&1
if [ ! -f "wgcf-profile.conf" ]; then
    error "Failed to generate WireGuard profile."
fi

# Extract keys and addresses
PRIVATE_KEY=$(grep -i "PrivateKey" wgcf-profile.conf | awk -F'= ' '{print $2}' | tr -d '\r')
ADDRESS_V4=$(grep -i "Address" wgcf-profile.conf | grep -E "172\.|10\." | awk -F'= ' '{print $2}' | tr -d '\r')
if [ -z "$ADDRESS_V4" ]; then
    ADDRESS_V4=$(grep -i "Address" wgcf-profile.conf | head -n 1 | awk -F'= ' '{print $2}' | tr -d '\r')
fi
ADDRESS_V6=$(grep -i "Address" wgcf-profile.conf | grep ":" | awk -F'= ' '{print $2}' | tr -d '\r')
PUBLIC_KEY="bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wRwGF0="

# Clean up temp files
cd - >/dev/null 2>&1
rm -rf "$TEMP_DIR"

# 5. Probing Endpoints & Ports
ENDPOINTS=(
    "162.159.193.10:500"
    "162.159.193.10:4500"
    "162.159.192.1:500"
    "162.159.192.1:4500"
    "188.114.96.1:500"
    "188.114.96.1:4500"
    "engage.cloudflareclient.com:2408"
)

CONNECTED=false
ACTIVE_EP=""

for EP in "${ENDPOINTS[@]}"; do
    info "Probing endpoint $EP using wireproxy..."
    
    # Write temporary wireproxy configuration
    cat > /etc/wireproxy.conf <<EOF
[WG]
SelfInterfaceIPv4 = $ADDRESS_V4
SelfInterfaceIPv6 = $ADDRESS_V6
PrivateKey = $PRIVATE_KEY
DNS = 1.1.1.1

[Peer]
PublicKey = $PUBLIC_KEY
Endpoint = $EP

[Socks5]
BindAddress = 127.0.0.1:40000
EOF

    # Start wireproxy in background
    /usr/local/bin/wireproxy -c /etc/wireproxy.conf >/dev/null 2>&1 &
    WP_PID=$!
    
    # Wait up to 5 seconds and test proxy connection
    for i in {1..5}; do
        if curl -s -I --socks5-hostname 127.0.0.1:40000 https://www.cloudflare.com/cdn-cgi/trace | grep -q "warp="; then
            CONNECTED=true
            ACTIVE_EP=$EP
            break 2
        fi
        sleep 1
    done
    
    # Failed, kill this background process and try next
    kill $WP_PID >/dev/null 2>&1
    wait $WP_PID >/dev/null 2>&1 || true
done

if [ "$CONNECTED" = true ]; then
    success "Successfully connected to WARP via endpoint: $ACTIVE_EP!"
    # Clean up the background process (systemd will manage it next)
    kill $WP_PID >/dev/null 2>&1
    wait $WP_PID >/dev/null 2>&1 || true
else
    error "Could not establish WARP connection. All IP endpoints failed. Please check VPS firewall settings."
fi

# 6. Configure Systemd Service
info "Configuring wireproxy systemd service..."

cat > /etc/systemd/system/wireproxy.service <<EOF
[Unit]
Description=Wireproxy SOCKS5 Tunnel for Cloudflare WARP
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/wireproxy -c /etc/wireproxy.conf
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable wireproxy
systemctl restart wireproxy

# Give it a second to start under systemd
sleep 2

# 7. Verification & Output
# Test connection via SOCKS5 proxy
WARP_CHECK=$(curl -s --socks5-hostname 127.0.0.1:40000 https://www.cloudflare.com/cdn-cgi/trace | grep "warp=")

if [[ "$WARP_CHECK" == *"warp=on"* || "$WARP_CHECK" == *"warp=plus"* ]]; then
    success "Cloudflare WARP SOCKS5 proxy is successfully running on port 40000!"
else
    error "WARP SOCKS5 proxy failed to establish under systemd."
fi

# Test Gemini API endpoint connectivity
info "Testing Google Gemini API accessibility through SOCKS5 proxy..."
GEMINI_TEST=$(curl -s -I -o /dev/null -w "%{http_code}" --socks5-hostname 127.0.0.1:40000 https://generativelanguage.googleapis.com/)
if [ "$GEMINI_TEST" -eq 200 ] || [ "$GEMINI_TEST" -eq 403 ] || [ "$GEMINI_TEST" -eq 404 ]; then
    success "Successfully connected to Gemini API Endpoint via WARP (HTTP $GEMINI_TEST)!"
else
    warn "Unable to reach Gemini API Endpoint (HTTP $GEMINI_TEST)."
fi

echo -e "\n=========================================================================="
success "WARP SOCKS5 installation and configuration completed!"
echo -e "=========================================================================="
echo -e "Local SOCKS5 proxy address: 127.0.0.1:40000"
echo -e "=========================================================================="
