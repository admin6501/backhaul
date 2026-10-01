#!/usr/bin/env bash

set -euo pipefail

BACKHAUL_DIR="/root/backhaul-core"
# Match the main builder's public default on both ends of the tunnel.
DEFAULT_IPX_PSK="YmFja2hhdWwtZGVmYXVsdC1wc2stY2hhbmdlLW1lISE="

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
NC='\033[0m'

line() {
    echo -e "${GRAY}────────────────────────────────────────────────────────────${NC}"
}

ok() {
    echo -e "${GREEN}[✓]${NC} $1"
}

info() {
    echo -e "${CYAN}[i]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

error() {
    echo -e "${RED}[✗]${NC} $1"
}

ask() {
    local prompt="$1"
    local default="${2:-}"
    local value

    if [[ -n "$default" ]]; then
        read -r -p "$(echo -e "${CYAN}${prompt}${NC} [${WHITE}${default}${NC}]: ")" value || return 1
        echo "${value:-$default}"
    else
        while true; do
            read -r -p "$(echo -e "${CYAN}${prompt}${NC}: ")" value || return 1

            if [[ -n "$value" ]]; then
                echo "$value"
                return
            fi

            warn "This value cannot be empty." >&2
        done
    fi
}

ask_number() {
    local prompt="$1"
    local default="$2"
    local value

    while true; do
        read -r -p "$(echo -e "${CYAN}${prompt}${NC} [${WHITE}${default}${NC}]: ")" value || return 1
        value="${value:-$default}"

        if [[ "$value" =~ ^[0-9]+$ ]]; then
            echo "$value"
            return
        fi

        error "Please enter a valid number." >&2
    done
}

ask_bool() {
    local prompt="$1"
    local default="$2"
    local value

    while true; do
        read -r -p "$(echo -e "${CYAN}${prompt}${NC} [${WHITE}${default}${NC}]: ")" value || return 1
        value="${value:-$default}"

        case "$value" in
            true|false)
                echo "$value"
                return
                ;;
            *)
                error "Please enter only true or false." >&2
                ;;
        esac
    done
}

valid_tun_addr() {
    local address="$1" ip a b c d octet
    [[ "$address" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/24$ ]] || return 1
    ip="${address%/24}"
    IFS='.' read -r a b c d <<< "$ip"
    for octet in "$a" "$b" "$c" "$d"; do
        if [[ "$octet" != "0" && "$octet" == 0* ]] || (( 10#$octet > 255 )); then
            return 1
        fi
    done
    (( 10#$d > 0 && 10#$d < 255 ))
}

ask_tun_addr() {
    local label="$1" default="$2" address
    while true; do
        address="$(ask "$label" "$default")" || return 1
        if valid_tun_addr "$address"; then
            printf '%s\n' "$address"
            return 0
        fi
        error "Use a valid IPv4 host address ending in /24 (not .0 or .255)." >&2
    done
}

toml_escape() {
    local value="$1"

    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"

    printf '%s' "$value"
}

generate_config() {
    local config_file="$1"

    cat > "$config_file" <<EOF
[transport]
type = "$(toml_escape "$TRANSPORT_TYPE")"
heartbeat_interval = $HEARTBEAT_INTERVAL
heartbeat_timeout = $HEARTBEAT_TIMEOUT

[tun]
encapsulation = "$(toml_escape "$ENCAPSULATION")"
name = "$(toml_escape "$TUN_NAME")"
local_addr = "$(toml_escape "$LOCAL_ADDR")"
remote_addr = "$(toml_escape "$REMOTE_ADDR")"
health_port = $HEALTH_PORT
mtu = $MTU

[ipx]
mode = "$(toml_escape "$MODE")"
profile = "$(toml_escape "$PROFILE")"
listen_ip = "$(toml_escape "$LISTEN_IP")"
dst_ip = "$(toml_escape "$DST_IP")"
spoof_src_ip = "$(toml_escape "$SPOOF_SRC_IP")"
spoof_dst_ip = "$(toml_escape "$SPOOF_DST_IP")"
interface = "$(toml_escape "$INTERFACE")"

[security]
enable_encryption = $ENABLE_ENCRYPTION
algorithm = "$(toml_escape "$ALGORITHM")"
psk = "$(toml_escape "$PSK")"
kdf_iterations = $KDF_ITERATIONS

[tuning]
auto_tuning = $AUTO_TUNING
tuning_profile = "$(toml_escape "$TUNING_PROFILE")"
workers = $WORKERS
channel_size = $CHANNEL_SIZE
so_sndbuf = $SO_SNDBUF
batch_size = $BATCH_SIZE

[logging]
log_level = "$(toml_escape "$LOG_LEVEL")"
EOF

    if [[ "$ROLE" == "1" ]]; then
        cat >> "$config_file" <<EOF

[ports]
forwarder = "$(toml_escape "$FORWARDER")"
mapping = [
    "$(toml_escape "$PORT_MAPPING")",
]
EOF
    fi
}

if [[ "${EUID}" -ne 0 ]]; then
    error "This script must be run as root."
    echo
    echo "Run:"
    echo "bash $0"
    exit 1
fi

if [[ ! -d "$BACKHAUL_DIR" ]]; then
    echo
    line
    error "Backhaul is not installed on this server."
    echo
    echo -e "${YELLOW}Required directory does not exist:${NC}"
    echo -e "${WHITE}$BACKHAUL_DIR${NC}"
    echo
    echo -e "${GRAY}No directory or configuration file was created.${NC}"
    line
    exit 1
fi

clear 2>/dev/null || true

echo
echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${WHITE}              BACKHAUL TUNNEL BUILDER                    ${CYAN}║${NC}"
echo -e "${CYAN}║${GRAY}          Professional Configuration Generator            ${CYAN}║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo

echo -e "${WHITE}This tool generates Backhaul tunnel configurations.${NC}"
echo -e "${GRAY}All available configuration values can be customized.${NC}"
echo

line

echo -e "${YELLOW}Do you want to start configuration creation?${NC}"
echo

read -r -p "$(echo -e "${CYAN}Continue? [y/N]: ${NC}")" CONFIRM

case "$CONFIRM" in
    y|Y)
        ;;
    *)
        echo
        warn "Operation cancelled."
        exit 0
        ;;
esac

echo

line

echo -e "${WHITE}Select server role:${NC}"
echo

echo -e "${GREEN}1)${NC} Iran / Server"
echo -e "${BLUE}2)${NC} Outside / Client"
echo

while true; do
    read -r -p "$(echo -e "${CYAN}Select role [1/2]: ${NC}")" ROLE

    case "$ROLE" in
        1)
            ROLE_NAME="Iran / Server"
            MODE="server"
            DEFAULT_LOCAL="10.10.10.1/24"
            DEFAULT_REMOTE="10.10.10.2/24"
            break
            ;;
        2)
            ROLE_NAME="Outside / Client"
            MODE="client"
            DEFAULT_LOCAL="10.10.10.2/24"
            DEFAULT_REMOTE="10.10.10.1/24"
            break
            ;;
        *)
            error "Invalid selection. Please choose 1 or 2."
            ;;
    esac
done

echo
ok "Selected role: $ROLE_NAME"
echo

line

while true; do
    read -r -p "$(echo -e "${CYAN}Enter configuration filename: ${NC}")" CONFIG_NAME

    CONFIG_NAME="${CONFIG_NAME%.toml}"

    if [[ "$CONFIG_NAME" =~ ^[A-Za-z0-9._-]+$ ]] && [[ -n "$CONFIG_NAME" ]]; then
        break
    fi

    error "Invalid filename."
    echo -e "${GRAY}Use only English letters, numbers, dots, hyphens and underscores.${NC}"
done

CONFIG_FILE="$BACKHAUL_DIR/${CONFIG_NAME}.toml"

if [[ -e "$CONFIG_FILE" ]]; then
    echo
    warn "This configuration file already exists:"
    echo -e "${WHITE}$CONFIG_FILE${NC}"
    echo

    read -r -p "$(echo -e "${YELLOW}Overwrite this file? [y/N]: ${NC}")" OVERWRITE

    case "$OVERWRITE" in
        y|Y)
            ;;
        *)
            warn "Operation cancelled."
            exit 0
            ;;
    esac
fi

line

echo -e "${MAGENTA}▸ Transport${NC}"
echo

TRANSPORT_TYPE="$(ask "Transport Type" "tun")"
HEARTBEAT_INTERVAL="$(ask_number "Heartbeat Interval" "10")"
HEARTBEAT_TIMEOUT="$(ask_number "Heartbeat Timeout" "25")"

line

echo -e "${MAGENTA}▸ TUN${NC}"
echo

ENCAPSULATION="$(ask "Encapsulation" "ipx")"
TUN_NAME="$(ask "TUN Name" "bh-tun")"

LOCAL_ADDR="$(ask_tun_addr "Local Address" "$DEFAULT_LOCAL")"
REMOTE_ADDR="$(ask_tun_addr "Remote Address" "$DEFAULT_REMOTE")"

HEALTH_PORT="$(ask_number "Health Port" "1212")"
MTU="$(ask_number "MTU" "1320")"

line

echo -e "${MAGENTA}▸ IPX${NC}"
echo

PROFILE="$(ask "Profile" "icmp")"
LISTEN_IP="$(ask "Listen IP")"
DST_IP="$(ask "Destination IP")"
SPOOF_SRC_IP="$(ask "Spoof Source IP")"
SPOOF_DST_IP="$(ask "Spoof Destination IP")"
INTERFACE="$(ask "Network Interface" "eth0")"

line

echo -e "${MAGENTA}▸ Security${NC}"
echo

ENABLE_ENCRYPTION="$(ask_bool "Enable Encryption" "true")"
ALGORITHM="$(ask "Encryption Algorithm" "aes-128-gcm")"
KDF_ITERATIONS="$(ask_number "KDF Iterations" "100000")"

echo
echo -e "${WHITE}PSK Configuration${NC}"
echo

echo -e "${GRAY}Press Enter to use the shared default, or enter the PSK used on the other server.${NC}"
echo

while true; do
    read -r -p "$(echo -e "${CYAN}PSK (Enter = shared default): ${NC}")" PSK
    echo
    PSK="${PSK:-$DEFAULT_IPX_PSK}"
    if [[ "$PSK" =~ ^[A-Za-z0-9+/]{43}=$ ]]; then
        if [[ "$PSK" == "$DEFAULT_IPX_PSK" ]]; then
            PSK_SOURCE="Shared default"
        else
            PSK_SOURCE="Custom"
        fi
        break
    fi
    error "Invalid PSK format. Use a Base64-encoded 32-byte key (44 characters ending in =)."
done

line

echo -e "${MAGENTA}▸ Tuning${NC}"
echo

AUTO_TUNING="$(ask_bool "Auto Tuning" "true")"
TUNING_PROFILE="$(ask "Tuning Profile" "balanced")"
WORKERS="$(ask_number "Workers" "0")"
CHANNEL_SIZE="$(ask_number "Channel Size" "10000")"
SO_SNDBUF="$(ask_number "SO Send Buffer" "0")"
BATCH_SIZE="$(ask_number "Batch Size" "2048")"

line

echo -e "${MAGENTA}▸ Logging${NC}"
echo

LOG_LEVEL="$(ask "Log Level" "info")"

FORWARDER=""
PORT_MAPPING=""

if [[ "$ROLE" == "1" ]]; then
    line

    echo -e "${MAGENTA}▸ Ports${NC}"
    echo

    FORWARDER="$(ask "Port Forwarder" "iptables")"
    PORT_MAPPING="$(ask "Port Mapping" "30814=30814")"
fi

line

echo -e "${WHITE}Configuration Summary${NC}"
echo

echo -e "${CYAN}Role:${NC}             $ROLE_NAME"
echo -e "${CYAN}Mode:${NC}             $MODE"
echo -e "${CYAN}Config:${NC}           $CONFIG_FILE"
echo -e "${CYAN}Local Address:${NC}    $LOCAL_ADDR"
echo -e "${CYAN}Remote Address:${NC}   $REMOTE_ADDR"
echo -e "${CYAN}Listen IP:${NC}        $LISTEN_IP"
echo -e "${CYAN}Destination IP:${NC}   $DST_IP"
echo -e "${CYAN}Interface:${NC}        $INTERFACE"
echo -e "${CYAN}Encryption:${NC}       $ENABLE_ENCRYPTION"
echo -e "${CYAN}Algorithm:${NC}        $ALGORITHM"
echo -e "${CYAN}PSK Source:${NC}       $PSK_SOURCE"

echo
echo -e "${YELLOW}PSK:${NC}"
echo -e "${WHITE}$PSK${NC}"
echo

line

read -r -p "$(echo -e "${CYAN}Create configuration with these settings? [Y/n]: ${NC}")" FINAL_CONFIRM

case "$FINAL_CONFIRM" in
    n|N)
        echo
        warn "Operation cancelled."
        exit 0
        ;;
esac

echo
info "Generating configuration..."

generate_config "$CONFIG_FILE"

chmod 600 "$CONFIG_FILE"

echo
line

echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║${WHITE}              CONFIG CREATED SUCCESSFULLY                ${GREEN}║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo

ok "Configuration created successfully."
echo

echo -e "${CYAN}Config Path:${NC}"
echo -e "${WHITE}$CONFIG_FILE${NC}"

echo
echo -e "${CYAN}Role:${NC} $ROLE_NAME"
echo -e "${CYAN}Mode:${NC} $MODE"

echo
echo -e "${YELLOW}PSK:${NC}"
echo -e "${WHITE}$PSK${NC}"

echo
line

echo
echo -e "${GREEN}Backhaul tunnel is ready to run.${NC}"
echo
echo -e "${WHITE}Run:${NC}"
echo -e "${CYAN}bash /root/backhaul.sh${NC}"
echo

line
echo
