#!/usr/bin/env bash
# =============================================================================
# LaserWeb4 – Raspberry Pi Service Installer
# =============================================================================
# Installs LaserWeb4 as a systemd service so it starts automatically on boot.
#
# Usage:
#   chmod +x install-service.sh
#   ./install-service.sh [OPTIONS]
#
# Options:
#   --port PORT        Web / comm-server port (default: 8000)
#   --user USER        System user to run the service (default: current user)
#   --install-dir DIR  Directory where LaserWeb4 lives (default: script dir)
#   --no-build         Skip npm install / webpack build steps
#   --uninstall        Stop and remove the laserweb service
#   --help             Show this help message
# =============================================================================

set -euo pipefail

# ── Colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
die()     { error "$*"; exit 1; }

# ── Defaults ──────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${SCRIPT_DIR}"
SERVICE_NAME="laserweb"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
LW_PORT=8000
LW_USER="${USER:-pi}"
SKIP_BUILD=false
UNINSTALL=false

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --port)        LW_PORT="$2";        shift 2 ;;
        --user)        LW_USER="$2";        shift 2 ;;
        --install-dir) INSTALL_DIR="$2";    shift 2 ;;
        --no-build)    SKIP_BUILD=true;     shift   ;;
        --uninstall)   UNINSTALL=true;      shift   ;;
        --help|-h)
            sed -n '/^# Usage:/,/^# ====/p' "$0" | sed 's/^# \?//'
            exit 0 ;;
        *) die "Unknown option: $1. Use --help for usage." ;;
    esac
done

# ── Uninstall path ─────────────────────────────────────────────────────────────
if $UNINSTALL; then
    info "Removing ${SERVICE_NAME} service…"
    sudo systemctl stop  "${SERVICE_NAME}" 2>/dev/null || true
    sudo systemctl disable "${SERVICE_NAME}" 2>/dev/null || true
    sudo rm -f "${SERVICE_FILE}"
    sudo systemctl daemon-reload
    success "Service '${SERVICE_NAME}' has been removed."
    exit 0
fi

# ── Banner ────────────────────────────────────────────────────────────────────
echo -e "\n${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}          LaserWeb4 – Raspberry Pi Service Installer            ${RESET}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"

echo -e "  Install directory : ${BOLD}${INSTALL_DIR}${RESET}"
echo -e "  Service user      : ${BOLD}${LW_USER}${RESET}"
echo -e "  Port              : ${BOLD}${LW_PORT}${RESET}"
echo -e "  Skip build        : ${BOLD}${SKIP_BUILD}${RESET}"
echo ""

# ── Sanity checks ─────────────────────────────────────────────────────────────
[[ -d "${INSTALL_DIR}" ]] || die "Install directory not found: ${INSTALL_DIR}"
[[ -f "${INSTALL_DIR}/package.json" ]] || \
    die "No package.json found in ${INSTALL_DIR}. Is this a LaserWeb4 directory?"

# Must run as a user that can sudo
if ! sudo -n true 2>/dev/null; then
    warn "This script needs sudo access to install the systemd service."
    warn "You may be prompted for your password."
fi

# Verify systemd is available
command -v systemctl >/dev/null 2>&1 || die "systemd not found. This script requires a systemd-based OS."

# ── Check / install prerequisites ─────────────────────────────────────────────
check_node() {
    if command -v node >/dev/null 2>&1; then
        local ver; ver=$(node -e "process.stdout.write(process.versions.node)")
        local major; major=$(echo "$ver" | cut -d. -f1)
        info "Node.js found: v${ver}"
        if [[ "$major" -lt 20 ]]; then
            warn "Node.js v${ver} is below the required v20. Attempting upgrade via NodeSource…"
            install_node20
        fi
    else
        warn "Node.js not found. Installing Node.js 20 via NodeSource…"
        install_node20
    fi
}

install_node20() {
    # Detect Debian/Ubuntu-based Raspberry Pi OS (Raspbian)
    if ! command -v apt-get >/dev/null 2>&1; then
        die "apt-get not found. Please install Node.js 20 manually and re-run with --no-build."
    fi
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt-get install -y nodejs
    success "Node.js $(node -v) installed."
}

check_build_tools() {
    info "Checking build tools (build-essential, python3, libusb, libudev)…"
    local pkgs=()
    for pkg in build-essential python3 make g++ pkg-config libusb-1.0-0-dev libudev-dev; do
        dpkg -s "$pkg" &>/dev/null || pkgs+=("$pkg")
    done
    if [[ ${#pkgs[@]} -gt 0 ]]; then
        info "Installing missing packages: ${pkgs[*]}"
        sudo apt-get update -qq
        sudo apt-get install -y "${pkgs[@]}"
        success "Build tools installed."
    else
        success "Build tools already present."
    fi
}

check_git_submodules() {
    if [[ -f "${INSTALL_DIR}/.gitmodules" ]]; then
        info "Initialising git submodules…"
        git -C "${INSTALL_DIR}" submodule update --init --recursive
        success "Submodules up to date."
    fi
}

# ── Build steps ───────────────────────────────────────────────────────────────
build_laserweb() {
    cd "${INSTALL_DIR}"
    info "Installing npm dependencies…"
    npm install
    success "npm install complete."

    info "Building frontend bundle (webpack)…"
    npm run bundle-dev
    success "Frontend bundle built."

    info "Syncing frontend → lw.comm-server/app/ …"
    npm run sync-frontend
    success "Frontend synced."
}

# ── Find node executable ───────────────────────────────────────────────────────
find_node() {
    # Prefer the node visible to the target user; fall back to which
    local node_bin
    node_bin=$(command -v node)
    # Resolve symlink so the service unit gets a stable path
    node_bin=$(readlink -f "${node_bin}" 2>/dev/null || echo "${node_bin}")
    echo "${node_bin}"
}

# ── Write systemd unit ─────────────────────────────────────────────────────────
write_service() {
    local node_bin server_js
    node_bin=$(find_node)
    server_js="${INSTALL_DIR}/node_modules/lw.comm-server/server.js"

    [[ -f "${server_js}" ]] || \
        die "Server entry point not found: ${server_js}\nRun without --no-build first, or check your install."

    info "Writing systemd unit to ${SERVICE_FILE} …"

    sudo tee "${SERVICE_FILE}" > /dev/null <<EOF
[Unit]
Description=LaserWeb4 comm-server
Documentation=https://github.com/LaserWeb/LaserWeb4
After=network.target

[Service]
ExecStart=${node_bin} ${server_js}
WorkingDirectory=${INSTALL_DIR}/node_modules/lw.comm-server
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${SERVICE_NAME}
User=${LW_USER}
Environment=NODE_ENV=production
Environment=PORT=${LW_PORT}
# Ensure the user's PATH includes the node bin directory
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

[Install]
WantedBy=multi-user.target
EOF

    success "Service unit written."
}

# ── Enable & start ─────────────────────────────────────────────────────────────
enable_service() {
    info "Reloading systemd daemon…"
    sudo systemctl daemon-reload

    info "Enabling ${SERVICE_NAME} to start on boot…"
    sudo systemctl enable "${SERVICE_NAME}"

    # Stop any previous instance gracefully before starting fresh
    sudo systemctl stop "${SERVICE_NAME}" 2>/dev/null || true

    info "Starting ${SERVICE_NAME}…"
    sudo systemctl start "${SERVICE_NAME}"

    sleep 2
    if sudo systemctl is-active --quiet "${SERVICE_NAME}"; then
        success "Service '${SERVICE_NAME}' is running."
    else
        error "Service failed to start. Check logs with:"
        echo -e "  ${CYAN}journalctl -u ${SERVICE_NAME} -n 50 --no-pager${RESET}"
        exit 1
    fi
}

# ── Add user to dialout for serial port access ─────────────────────────────────
setup_serial_access() {
    if ! groups "${LW_USER}" | grep -q dialout; then
        info "Adding ${LW_USER} to 'dialout' group (required for serial/USB ports)…"
        sudo usermod -aG dialout "${LW_USER}"
        warn "Group change takes effect on next login / reboot."
    else
        success "${LW_USER} is already in the 'dialout' group."
    fi
}

# ── Open firewall port (ufw) if present ───────────────────────────────────────
open_firewall() {
    if command -v ufw >/dev/null 2>&1 && sudo ufw status | grep -q "Status: active"; then
        info "ufw is active – allowing port ${LW_PORT}/tcp…"
        sudo ufw allow "${LW_PORT}/tcp" comment "LaserWeb4"
        success "Firewall rule added."
    fi
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    check_node

    if ! $SKIP_BUILD; then
        check_build_tools
        check_git_submodules
        build_laserweb
    else
        info "Skipping build (--no-build specified)."
    fi

    setup_serial_access
    write_service
    open_firewall
    enable_service

    echo ""
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${GREEN}${BOLD}  Installation complete!${RESET}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo ""
    echo -e "  LaserWeb4 is now available at:"
    echo -e "    ${BOLD}http://$(hostname -I | awk '{print $1}'):${LW_PORT}${RESET}"
    echo ""
    echo -e "  Useful commands:"
    echo -e "    ${CYAN}sudo systemctl status  ${SERVICE_NAME}${RESET}   – service status"
    echo -e "    ${CYAN}sudo systemctl restart ${SERVICE_NAME}${RESET}   – restart service"
    echo -e "    ${CYAN}sudo systemctl stop    ${SERVICE_NAME}${RESET}   – stop service"
    echo -e "    ${CYAN}journalctl -u ${SERVICE_NAME} -f${RESET}         – follow logs"
    echo ""
    echo -e "  To uninstall: ${CYAN}./install-service.sh --uninstall${RESET}"
    echo ""
}

main "$@"
