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

# 1. Install Cloudflare WARP Repository and Package
install_warp() {
    case "$OS_ID" in
        ubuntu|debian)
            info "Installing dependencies for Debian/Ubuntu..."
            apt-get update -y
            apt-get install -y curl gpg lsb-release ca-certificates

            info "Adding Cloudflare GPG Key..."
            curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor -o /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg

            info "Adding Cloudflare Repository..."
            echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/cloudflare-client.list

            info "Installing cloudflare-warp..."
            apt-get update -y
            apt-get install -y cloudflare-warp
            ;;
        centos|rhel|rocky|alma)
            info "Installing dependencies for RHEL/CentOS-like system..."
            yum install -y curl ca-certificates

            info "Adding Cloudflare Repository & GPG Key..."
            rpm --import https://pkg.cloudflareclient.com/pubkey.gpg
            curl -fsSL https://pkg.cloudflareclient.com/cloudflare-warp-ascii.repo | tee /etc/yum.repos.d/cloudflare-warp.repo

            info "Installing cloudflare-warp..."
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

info "Starting and enabling cloudflare-warp service..."
systemctl daemon-reload
systemctl enable warp-svc
systemctl restart warp-svc

sleep 2

# 2. Configure Cloudflare WARP (SOCKS5 Mode on Port 40000)
info "Configuring Cloudflare WARP..."
info "Registering a new client..."
warp-cli --accept-tos registration new || warn "Registration returned an error, client may be already registered."

info "Setting mode to SOCKS5 proxy..."
warp-cli --accept-tos mode proxy

info "Setting proxy port to 40000..."
warp-cli --accept-tos proxy port 40000

info "Connecting to Cloudflare WARP..."
warp-cli --accept-tos connect

info "Enabling Always-On..."
warp-cli --accept-tos enable-always-on

# 3. Connection Verification
info "Waiting for WARP connection to establish (approx. 5 seconds)..."
sleep 5

WARP_CHECK=$(curl -s --socks5-hostname 127.0.0.1:40000 https://www.cloudflare.com/cdn-cgi/trace | grep "warp=")

if [[ "$WARP_CHECK" == *"warp=on"* || "$WARP_CHECK" == *"warp=plus"* ]]; then
    success "Cloudflare WARP SOCKS5 proxy is successfully connected and running on port 40000!"
else
    warn "WARP connection verification failed or is pending. Please run 'warp-cli status' manually to diagnose."
fi

info "Testing Google Gemini API accessibility through WARP..."
GEMINI_TEST=$(curl -s -I -o /dev/null -w "%{http_code}" --socks5-hostname 127.0.0.1:40000 https://generativelanguage.googleapis.com/)
if [ "$GEMINI_TEST" -eq 200 ] || [ "$GEMINI_TEST" -eq 403 ] || [ "$GEMINI_TEST" -eq 404 ]; then
    success "Successfully connected to Gemini API Endpoint via WARP (HTTP $GEMINI_TEST)!"
else
    warn "Unable to reach Gemini API Endpoint (HTTP $GEMINI_TEST). Please check your VPS internet connectivity."
fi
