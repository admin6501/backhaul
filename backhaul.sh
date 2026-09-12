SCRIPT_VERSION="v1.0.0"
service_dir="/etc/systemd/system"
config_dir="/root/backhaul-core"
CERT_DIR="/root/backhaul-core/cert_files"
CERT_FILE="$CERT_DIR/cert.crt"
KEY_FILE="$CERT_DIR/cert.key"
mkdir -p "$CERT_DIR"
if [[ $EUID -ne 0 ]]; then
echo "This script must be run as root"
sleep 1
exit 1
fi
colorize() {
local color="$1"
local text="$2"
local style="${3:-normal}"
local black="\033[30m" red="\033[31m" green="\033[32m" yellow="\033[33m"
local blue="\033[34m" magenta="\033[35m" cyan="\033[36m" white="\033[37m"
local reset="\033[0m" normal="\033[0m" bold="\033[1m" underline="\033[4m"
local color_code
case $color in
black) color_code=$black ;; red) color_code=$red ;;
green) color_code=$green ;; yellow) color_code=$yellow ;;
blue) color_code=$blue ;; magenta) color_code=$magenta ;;
cyan) color_code=$cyan ;; white) color_code=$white ;;
*) color_code=$reset ;;
esac
local style_code
case $style in
bold) style_code=$bold ;; underline) style_code=$underline ;;
normal | *) style_code=$normal ;;
esac
echo -e "${style_code}${color_code}${text}${reset}"
}
press_key() {
read -r -p "Press any key to continue..."
}
prompt_with_default() {
local prompt="$1"
local default="$2"
local var_name="$3"
local input
echo -ne "[-] $prompt (default: $default): "
read -r input
eval "$var_name=\"${input:-$default}\""
}
prompt_boolean() {
local prompt="$1"
local default="$2"
local var_name="$3"
while true; do
prompt_with_default "$prompt [true/false]" "$default" "$var_name"
local value="${!var_name}"
if [[ "$value" == "true" || "$value" == "false" ]]; then
break
fi
colorize red "Invalid input. Please enter 'true' or 'false'."
done
}
validate_cidr() {
local cidr="$1"
if [[ ! "$cidr" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/([0-9]{1,2})$ ]]; then
return 1
fi
IFS='/' read -r ip mask <<< "$cidr"
IFS='.' read -r a b c d <<< "$ip"
if (( a<0 || a>255 || b<0 || b>255 || c<0 || c>255 || d<0 || d>255 )); then
return 1
fi
if (( mask < 1 || mask > 32 )); then
return 1
fi
local ip_int=$(( (a << 24) | (b << 16) | (c << 8) | d ))
local mask_int
if (( mask == 32 )); then
mask_int=0xFFFFFFFF
else
mask_int=$(( (0xFFFFFFFF << (32 - mask)) & 0xFFFFFFFF ))
fi
local net_int=$(( ip_int & mask_int ))
local broadcast_int=$(( net_int | (~mask_int & 0xFFFFFFFF) ))
if (( ip_int == net_int )); then
return 1
fi
if (( ip_int == broadcast_int )); then
return 1
fi
return 0
}
install_jq() {
if ! command -v jq &> /dev/null; then
if command -v apt-get &> /dev/null; then
colorize yellow "Installing jq..."
apt-get update && apt-get install -y jq
elif command -v dnf &> /dev/null; then
colorize yellow "Installing jq..."
dnf install -y jq
elif command -v yum &> /dev/null; then
colorize yellow "Installing jq..."
yum install -y jq
else
colorize red "Error: Unsupported package manager. Please install jq manually."
press_key
return 1
fi
fi
}

BACKHAUL_REPO="https://github.com/admin6501/backhaul.git"
BACKHAUL_INSTALL_DIR="/root/backhaul-core"

install_backhaul_core() {
clear
colorize cyan "━━━ Backhaul Core Installation ━━━" bold
echo

if [[ -f "${config_dir}/backhaul_premium" ]]; then
colorize green "Backhaul Core is already installed." bold
echo "Location: ${config_dir}/backhaul_premium"
if [[ -x "${config_dir}/backhaul_premium" ]]; then
local version
version=$("${config_dir}/backhaul_premium" -v 2>/dev/null || true)
[[ -n "$version" ]] && echo "Version: $version"
fi
press_key
return 0
fi

if ! command -v git >/dev/null 2>&1; then
colorize yellow "Git is not installed. Installing Git..."
if command -v apt-get >/dev/null 2>&1; then
apt-get update && apt-get install -y git || { colorize red "Failed to install Git."; press_key; return 1; }
elif command -v dnf >/dev/null 2>&1; then
dnf install -y git || { colorize red "Failed to install Git."; press_key; return 1; }
elif command -v yum >/dev/null 2>&1; then
yum install -y git || { colorize red "Failed to install Git."; press_key; return 1; }
else
colorize red "Unsupported package manager. Please install Git manually."
press_key
return 1
fi
fi

local tmp_dir
tmp_dir=$(mktemp -d)
colorize yellow "Cloning Backhaul repository..."
if ! git clone --depth 1 "$BACKHAUL_REPO" "$tmp_dir/backhaul"; then
colorize red "Failed to clone Backhaul repository."
rm -rf "$tmp_dir"
press_key
return 1
fi

if [[ ! -f "$tmp_dir/backhaul/backhaul-core/backhaul_premium" ]]; then
colorize red "backhaul_premium was not found in the cloned repository."
rm -rf "$tmp_dir"
press_key
return 1
fi

mkdir -p "$BACKHAUL_INSTALL_DIR"
cp -a "$tmp_dir/backhaul/backhaul-core/." "$BACKHAUL_INSTALL_DIR/"
chmod +x "$BACKHAUL_INSTALL_DIR/backhaul_premium"
rm -rf "$tmp_dir"

colorize green "✔ Backhaul Core installed successfully." bold
echo "Repository: $BACKHAUL_REPO"
echo "Location: $BACKHAUL_INSTALL_DIR/backhaul_premium"
local version
version=$("$BACKHAUL_INSTALL_DIR/backhaul_premium" -v 2>/dev/null || true)
[[ -n "$version" ]] && echo "Version: $version"
press_key
}

install_jq
declare -A CONFIG
reset_config() {
CONFIG=()
}
prompt_connection_section() {
local mode="$1"  # server or client
colorize blue "━━━ Connection Configuration ━━━" bold
if [[ "$mode" == "server" ]]; then
prompt_with_default "Bind Address" ":8443" CONFIG[bind_addr]
if [[ -n "${CONFIG[bind_addr]}" && "${CONFIG[bind_addr]}" != *:* ]]; then
CONFIG[bind_addr]=":${CONFIG[bind_addr]}"
fi
else
while true; do
echo -ne "[*] IRAN Server Address [IP:Port] or [Domain:Port]: "
read -r CONFIG[remote_addr]
if [[ -z "${CONFIG[remote_addr]}" ]]; then
colorize red "Server address cannot be empty."
continue
fi
if [[ "${CONFIG[remote_addr]}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}:[0-9]{1,5}$ || \
"${CONFIG[remote_addr]}" =~ ^[a-zA-Z0-9.-]+:[0-9]{1,5}$ ]]; then
break
else
colorize red "Invalid format. Use IP:Port or Domain:Port."
fi
done
if [[ "${CONFIG[transport_type]}" == "ws" || "${CONFIG[transport_type]}" == "wss" || "${CONFIG[transport_type]}" == "wsmux" || "${CONFIG[transport_type]}" == "wssmux" || "${CONFIG[transport_type]}" == "xwsmux" ]]; then
echo -ne "[-] Edge IP/Domain (optional, press Enter to skip): "
read -r CONFIG[edge_ip]
fi
CONFIG[dial_timeout]="10"
CONFIG[retry_interval]="3"
fi
echo ""
}
VALID_ALGORITHMS=("aes-256-gcm" "chacha20-poly1305" "aes-128-gcm")
is_valid_algorithm() {
local input="$1"
for alg in "${VALID_ALGORITHMS[@]}"; do
if [[ "$input" == "$alg" ]]; then
return 0
fi
done
return 1
}
prompt_security_section() {
local is_ipx="$1"
colorize blue "━━━ Security Configuration ━━━" bold
if [[ "$is_ipx" == "true" ]]; then
prompt_boolean "Enable Encryption" "true" CONFIG[enable_encryption]
if [[ "${CONFIG[enable_encryption]}" == "true" ]]; then
echo
while true; do
colorize magenta "Available algorithms: aes-256-gcm, chacha20-poly1305, aes-128-gcm"
prompt_with_default "Algorithm" "aes-256-gcm" CONFIG[algorithm]
if is_valid_algorithm "${CONFIG[algorithm]}"; then
break
else
colorize red "Invalid algorithm selected. Please choose one from the list."
echo
fi
done
while true; do
prompt_with_default "PSK (32-byte base64)" "$(openssl rand -base64 32 2>/dev/null | tr -d '\n')" CONFIG[psk]
if [[ "${CONFIG[psk]}" =~ ^[A-Za-z0-9+/]{43}=$ ]]; then break; fi
colorize red "Invalid PSK. Use 32 random bytes in Base64 format."
done
prompt_with_default "KDF Iterations" "100000" CONFIG[kdf_iterations]
fi
else
prompt_with_default "Security Token" "your_token" CONFIG[token]
CONFIG[enable_encryption]="false"
fi
echo ""
}
prompt_transport_section() {
local mode="$1"
local is_ipx="false"
colorize blue "━━━ Transport Configuration ━━━" bold
local valid_transports=(tcp tcpmux xtcpmux ws wss wsmux wssmux xwsmux anytls tun spoof-tunnel)
echo "Available transports:"
printf '  • %s\n' "${valid_transports[@]}"
while true; do
echo -ne "Select transport: "
read -r CONFIG[transport_type]
[[ " ${valid_transports[*]} " =~ " ${CONFIG[transport_type]} " ]] && break
colorize red "Invalid transport."
done
if [[ "${CONFIG[transport_type]}" == "tun" ]]; then
echo
local encapsulations=(tcp ipx)
echo "Available encapsulations:"
printf '  • %s\n' "${encapsulations[@]}"
while true; do
echo -ne "Select encapsulation: "
read -r CONFIG[tun_encapsulation]
[[ " ${encapsulations[*]} " =~ " ${CONFIG[tun_encapsulation]} " ]] && break
colorize red "Invalid encapsulation."
done
fi
echo
if [[ "${CONFIG[tun_encapsulation]}" == "ipx" ]]; then
is_ipx="true"
fi
if [[ "$is_ipx" != "true" ]]; then
prompt_boolean "Enable TCP_NODELAY" "true" CONFIG[nodelay]
fi
if [[ "$mode" == "server" ]]; then
if [[ "${CONFIG[transport_type]}" == "tcp" ]]; then
prompt_boolean "Accept UDP over TCP" "false" CONFIG[accept_udp]
fi
if [[ ! "${CONFIG[transport_type]}" =~ ^(tun|ws)$ ]] && [[ "$is_ipx" != "true" ]]; then
prompt_boolean "Enable Proxy Protocol" "false" CONFIG[proxy_protocol]
fi
else
if [[ "${CONFIG[transport_type]}" != "tun" ]]; then
prompt_with_default "Connection Pool" "8" CONFIG[connection_pool]
fi
fi
CONFIG[heartbeat_interval]="10"
CONFIG[heartbeat_timeout]="25"
if [[ "$is_ipx" != "true" ]]; then
CONFIG[keepalive_period]="40"
fi
echo ""
}
prompt_mux_section() {
local transport="$1"
if [[ ! "$transport" =~ mux$ ]]; then
return
fi
colorize blue "━━━ Mux Configuration ━━━" bold
prompt_with_default "Mux Version [1 or 2]" "2" CONFIG[mux_version]
prompt_with_default "Mux Concurrency" "8" CONFIG[mux_concurrency]
CONFIG[mux_framesize]="32768"
CONFIG[mux_recievebuffer]="4194304"
CONFIG[mux_streambuffer]="2097152"
echo ""
}
prompt_tun_section() {
local transport="$1"
local mode="$2"
local is_ipx="$3"
[[ "$transport" != "tun" ]] && return
colorize blue "━━━ TUN Configuration ━━━" bold
prompt_with_default "TUN Device Name" "backhaul" CONFIG[tun_name]
local default_local default_remote
if [[ "$mode" == "server" ]]; then
default_local="10.10.10.1/24"
default_remote="10.10.10.2/24"
else
default_local="10.10.10.2/24"
default_remote="10.10.10.1/24"
fi
while true; do
prompt_with_default "TUN Local Address (CIDR)" "$default_local" CONFIG[tun_local_addr]
if validate_cidr "${CONFIG[tun_local_addr]}"; then
break
fi
local suggested=$(validate_cidr "${CONFIG[tun_local_addr]}" 2>&1)
colorize red "Invalid CIDR. Network address should be: $suggested"
done
while true; do
prompt_with_default "TUN Remote Address (CIDR)" "$default_remote" CONFIG[tun_remote_addr]
if validate_cidr "${CONFIG[tun_remote_addr]}"; then
break
fi
colorize red "Invalid CIDR format."
done
prompt_with_default "Health Port" "1234" CONFIG[tun_health_port]
if [[ "$is_ipx" == "true" ]]; then
prompt_with_default "MTU" "1320" CONFIG[tun_mtu]
else
prompt_with_default "MTU" "1500" CONFIG[tun_mtu]
fi
echo ""
}
prompt_spoof_tunnel_section() {
local mode="$1"
colorize blue "━━━ Spoof Tunnel Configuration ━━━" bold
prompt_with_default "TUN Device Name" "bh-tun" CONFIG[tun_name]
local default_local default_remote
if [[ "$mode" == "server" ]]; then
default_local="10.10.10.1/24"
default_remote="10.10.10.2/24"
else
default_local="10.10.10.2/24"
default_remote="10.10.10.1/24"
fi
while true; do
prompt_with_default "TUN Local Address (CIDR)" "$default_local" CONFIG[tun_local_addr]
if validate_cidr "${CONFIG[tun_local_addr]}"; then break; fi
colorize red "Invalid CIDR format."
done
while true; do
prompt_with_default "TUN Remote Address (CIDR)" "$default_remote" CONFIG[tun_remote_addr]
if validate_cidr "${CONFIG[tun_remote_addr]}"; then break; fi
colorize red "Invalid CIDR format."
done
prompt_with_default "Health Port" "1212" CONFIG[tun_health_port]
prompt_with_default "MTU" "1320" CONFIG[tun_mtu]
CONFIG[tun_encapsulation]="ipx"
CONFIG[ipx_mode]="$mode"
CONFIG[ipx_profile]="icmp"
if [[ "$mode" == "server" ]]; then
prompt_with_default "Listen IP" "" CONFIG[ipx_listen_ip]
prompt_with_default "Destination IP" "" CONFIG[ipx_dst_ip]
else
prompt_with_default "Listen IP" "" CONFIG[ipx_listen_ip]
prompt_with_default "Destination IP" "" CONFIG[ipx_dst_ip]
fi
prompt_with_default "Spoof Source IP" "" CONFIG[ipx_spoof_src_ip]
prompt_with_default "Spoof Destination IP" "" CONFIG[ipx_spoof_dst_ip]
local interface
interface=$(ip route show default | awk '{print $5}')
prompt_with_default "Network Interface" "$interface" CONFIG[ipx_interface]
prompt_boolean "Enable Encryption" "true" CONFIG[enable_encryption]
if [[ "${CONFIG[enable_encryption]}" == "true" ]]; then
while true; do
colorize magenta "Available algorithms: aes-256-gcm, chacha20-poly1305, aes-128-gcm"
prompt_with_default "Algorithm" "aes-128-gcm" CONFIG[algorithm]
if is_valid_algorithm "${CONFIG[algorithm]}"; then break; fi
colorize red "Invalid algorithm selected."
done
while true; do
prompt_with_default "PSK (Base64)" "$(openssl rand -base64 32 2>/dev/null | tr -d '\n')" CONFIG[psk]
if [[ "${CONFIG[psk]}" =~ ^[A-Za-z0-9+/]{43}=$ ]]; then break; fi
colorize red "Invalid PSK. Use 32 random bytes in Base64 format."
done
prompt_with_default "KDF Iterations" "100000" CONFIG[kdf_iterations]
fi
CONFIG[forwarder]="iptables"
CONFIG[auto_tuning]="true"
prompt_with_default "Kernel Tuning Profile" "balanced" CONFIG[tuning_profile]
prompt_with_default "Workers (0 = auto)" "0" CONFIG[workers]
CONFIG[channel_size]="10_000"
prompt_with_default "Batch Size" "2048" CONFIG[batch_size]
prompt_with_default "SO_SNDBUF (0 = auto)" "0" CONFIG[so_sndbuf]
prompt_with_default "Heartbeat Interval" "10" CONFIG[heartbeat_interval]
prompt_with_default "Heartbeat Timeout" "25" CONFIG[heartbeat_timeout]
prompt_with_default "Log Level" "info" CONFIG[log_level]
echo ""
}
prompt_tls_section() {
local mode="$1"
local transport="$2"
if [[ ! "$transport" =~ ^(anytls|wss|wssmux)$ ]]; then
return
fi
colorize blue "━━━ TLS Configuration ━━━" bold
if [[ "$transport" == "anytls" ]]; then
prompt_with_default "SNI" "www.digikala.com" CONFIG[tls_sni]
fi
if [[ "$mode" == "client" ]]; then
echo
return
fi
if [[ ! -f "$CERT_FILE" || ! -f "$KEY_FILE" ]]; then
colorize red "[*] TLS certificate or key missing, generating self-signed Ed25519 cert..."
openssl req -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -x509 -days 365 -sha256 -keyout "$KEY_FILE" -out  "$CERT_FILE" -subj "/CN=backhaul.com"
colorize green "[*] Generated $CERT_FILE and $KEY_FILE"
echo
fi
prompt_with_default "TLS Certificate Path" "$CERT_FILE" CONFIG[tls_cert]
prompt_with_default "TLS Key Path" "$KEY_FILE" CONFIG[tls_key]
echo ""
}
prompt_tuning_section() {
local is_ipx="$1"
local is_tun="$2"
colorize blue "━━━ Tuning Configuration ━━━" bold
prompt_boolean "Enable Auto Tuning" "true" CONFIG[auto_tuning]
echo
colorize magenta "Profiles: balanced, fast, latency, resource" normal
prompt_with_default "Kernel Tuning Profile" "balanced" CONFIG[tuning_profile]
prompt_with_default "Workers (0 = auto)" "0" CONFIG[workers]
if [[ "$is_tun" != "true" ]]; then
prompt_with_default "Channel Size" "4096" CONFIG[channel_size]
fi
if [[ "$is_tun" == "true" ]]; then
CONFIG[channel_size]="10_000"
fi
if [[ "$is_ipx" == "true" ]]; then
prompt_with_default "Batch Size" "2048" CONFIG[batch_size]
prompt_with_default "SO_SNDBUF (0 = auto)" "0" CONFIG[so_sndbuf]
else
prompt_with_default "TCP MSS (0 = auto)" "0" CONFIG[tcp_mss]
prompt_with_default "SO_RCVBUF (0 = auto)" "0" CONFIG[so_rcvbuf]
prompt_with_default "SO_SNDBUF (0 = auto)" "0" CONFIG[so_sndbuf]
fi
if [[ "$is_tun" != "true" ]] && [[ "$is_ipx" != "true" ]]; then
echo
colorize magenta "Buffer Profiles: extreme_low_cpu, ultra_low_cpu, low_cpu, balanced, low_memory" normal
prompt_with_default "Buffer Profile" "balanced" CONFIG[buffer_profile]
prompt_with_default "Read Timeout" "120" CONFIG[read_timeout]
fi
echo ""
}
prompt_logging_section() {
colorize blue "━━━ Logging Configuration ━━━" bold
colorize magenta "Levels: panic, fatal, error, warn, info, debug, trace"
prompt_with_default "Log Level" "info" CONFIG[log_level]
echo ""
}
prompt_accept_udp_section() {
local accept_udp="$1"
[[ "$accept_udp" != "true" ]] && return
CONFIG[ring_size]="64"
CONFIG[frame_size]="2048"
CONFIG[peer_idle_timeout_s]="120"
CONFIG[write_timeout_ms]="3"
}
prompt_ports_section() {
local mode="$1"
local is_tun="$2"
[[ "$mode" != "server" ]] && return
if [[ "${CONFIG[transport_type]}" == "spoof-tunnel" ]]; then
colorize blue "━━━ Port Mapping Configuration ━━━" bold
colorize magenta "Forwarder: iptables (fixed)"
echo "Supported formats: 443, 443=5000, 443=5000,80=8080"
echo -ne "Enter port mappings (comma-separated): "
read -r CONFIG[ports_mapping]
CONFIG[forwarder]="iptables"
echo ""
elif [[ "$is_tun" != "true" ]]; then
colorize blue "━━━ Port Mapping Configuration ━━━" bold
colorize green "Supported formats:"
echo "  1. 443           - Listen on 443, forward to 443"
echo "  2. 443=5000      - Listen on 443, forward to 5000"
echo "  3. 443-600       - Listen on range 443-600"
echo "  4. 443-600:5201  - Range forwarding to 5201"
echo ""
echo -ne "Enter port mappings (comma-separated): "
read -r CONFIG[ports_mapping]
echo ""
else
colorize blue "━━━ Port Mapping Configuration (tun helper) ━━━" bold
colorize magenta "Forwarder: use 'bbackhaul' for TCP support only, or 'iptables' for TCP + UDP support"
prompt_with_default "Forwarder (backhaul/iptables)" "backhaul" CONFIG[forwarder]
echo ""
colorize green "Supported formats:"
echo "  1. 443           - Listen on 443, forward to 443"
echo "  2. 443=5000      - Listen on 443, forward to 5000"
echo ""
echo -ne "Enter port mappings (comma-separated): "
read -r CONFIG[ports_mapping]
echo ""
fi
}
prompt_ipx_section() {
local is_ipx="$1"
local mode="$2"
[[ "$is_ipx" != "true" ]] && return
colorize blue "━━━ IPX Configuration ━━━" bold
CONFIG[ipx_mode]="$mode"
AVAILABLE_PROFILES=("icmp" "ipip" "udp" "tcp" "gre" "bip")
colorize magenta "Available profiles: ${AVAILABLE_PROFILES[*]}"
while true; do
prompt_with_default "Profile" "tcp" CONFIG[ipx_profile]
CONFIG[ipx_profile]="${CONFIG[ipx_profile],,}"
for profile in "${AVAILABLE_PROFILES[@]}"; do
if [[ "${CONFIG[ipx_profile]}" == "$profile" ]]; then
break 2
fi
done
colorize red "Invalid profile: ${CONFIG[ipx_profile]}"
echo
colorize yellow "Please choose one of: ${AVAILABLE_PROFILES[*]}"
done
prompt_with_default "Listen IP" $SERVER_IP CONFIG[ipx_listen_ip]
while :; do
prompt_with_default "Destination IP" "" CONFIG[ipx_dst_ip]
if [[ -n "${CONFIG[ipx_dst_ip]}" ]]; then
break
fi
colorize red "Destination IP cannot be empty."
done
interface=$(ip route show default | awk '{print $5}')
prompt_with_default "Network Interface" $interface CONFIG[ipx_interface]
if [[ "${CONFIG[ipx_profile]}" == "icmp" ]]; then
prompt_with_default "ICMP Type" "0" CONFIG[ipx_icmp_type]
prompt_with_default "ICMP Code" "0" CONFIG[ipx_icmp_code]
fi
echo ""
}
generate_toml_config() {
local mode="$1"
local output_file="$2"
local is_tun="$3"
local is_ipx="$4"
{
if [[ "$mode" == "server" ]] && [[ "$is_ipx" == "false" ]]; then
echo "[listener]"
echo "bind_addr = \"${CONFIG[bind_addr]}\""
echo ""
elif [[ "$is_ipx" == "false" ]]; then
echo "[dialer]"
echo "remote_addr = \"${CONFIG[remote_addr]}\""
[[ -n "${CONFIG[edge_ip]}" ]] && echo "edge_ip = \"${CONFIG[edge_ip]}\""
echo "dial_timeout = ${CONFIG[dial_timeout]}"
echo "retry_interval = ${CONFIG[retry_interval]}"
echo ""
fi
echo "[transport]"
if [[ "${CONFIG[transport_type]}" == "spoof-tunnel" ]]; then
echo "type = \"tun\""
else
echo "type = \"${CONFIG[transport_type]}\""
fi
[[ -n "${CONFIG[nodelay]}" ]] && echo "nodelay = ${CONFIG[nodelay]}"
[[ -n "${CONFIG[keepalive_period]}" ]] && echo "keepalive_period = ${CONFIG[keepalive_period]}"
if [[ "$mode" == "server" ]]; then
[[ -n "${CONFIG[accept_udp]}" ]] && echo "accept_udp = ${CONFIG[accept_udp]}"
[[ -n "${CONFIG[proxy_protocol]}" ]] && echo "proxy_protocol = ${CONFIG[proxy_protocol]}"
else
[[ -n "${CONFIG[connection_pool]}" ]] && [[ "${CONFIG[connection_pool]}" != "0" ]] && \
echo "connection_pool = ${CONFIG[connection_pool]}"
fi
[[ -n "${CONFIG[heartbeat_interval]}" ]] && echo "heartbeat_interval = ${CONFIG[heartbeat_interval]}"
[[ -n "${CONFIG[heartbeat_timeout]}" ]] && echo "heartbeat_timeout = ${CONFIG[heartbeat_timeout]}"
echo ""
if [[ "${CONFIG[transport_type]}" == "spoof-tunnel" ]]; then
echo "[tun]"
echo "encapsulation = \"ipx\""
echo "name = \"${CONFIG[tun_name]}\""
echo "local_addr = \"${CONFIG[tun_local_addr]}\""
echo "remote_addr = \"${CONFIG[tun_remote_addr]}\""
echo "health_port = ${CONFIG[tun_health_port]}"
echo "mtu = ${CONFIG[tun_mtu]}"
echo ""
echo "[ipx]"
echo "mode = \"${CONFIG[ipx_mode]}\""
echo "profile = \"icmp\""
echo "listen_ip = \"${CONFIG[ipx_listen_ip]}\""
echo "dst_ip = \"${CONFIG[ipx_dst_ip]}\""
echo "spoof_src_ip = \"${CONFIG[ipx_spoof_src_ip]}\""
echo "spoof_dst_ip = \"${CONFIG[ipx_spoof_dst_ip]}\""
echo "interface = \"${CONFIG[ipx_interface]}\""
echo ""
else
if [[ "$is_tun" == "true" ]]; then
echo "[tun]"
echo "encapsulation = \"${CONFIG[tun_encapsulation]}\""
echo "name = \"${CONFIG[tun_name]}\""
echo "local_addr = \"${CONFIG[tun_local_addr]}\""
echo "remote_addr = \"${CONFIG[tun_remote_addr]}\""
echo "health_port = ${CONFIG[tun_health_port]}"
echo "mtu = ${CONFIG[tun_mtu]}"
echo ""
fi
fi
if [[ "$is_ipx" == "true" ]] && [[ "${CONFIG[transport_type]}" != "spoof-tunnel" ]]; then
echo "[ipx]"
echo "mode = \"${CONFIG[ipx_mode]}\""
echo "profile = \"${CONFIG[ipx_profile]}\""
echo "listen_ip = \"${CONFIG[ipx_listen_ip]}\""
echo "dst_ip = \"${CONFIG[ipx_dst_ip]}\""
echo "interface = \"${CONFIG[ipx_interface]}\""
[[ -n "${CONFIG[ipx_icmp_type]}" ]] && echo "icmp_type = ${CONFIG[ipx_icmp_type]}"
[[ -n "${CONFIG[ipx_icmp_code]}" ]] && echo "icmp_code = ${CONFIG[ipx_icmp_code]}"
echo ""
fi
if [[ "${CONFIG[transport_type]}" =~ mux$ ]]; then
echo "[mux]"
echo "mux_version = ${CONFIG[mux_version]}"
echo "mux_framesize = ${CONFIG[mux_framesize]}"
echo "mux_recievebuffer = ${CONFIG[mux_recievebuffer]}"
echo "mux_streambuffer = ${CONFIG[mux_streambuffer]}"
[[ -n "${CONFIG[mux_concurrency]}" ]] && echo "mux_concurrency = ${CONFIG[mux_concurrency]}"
echo ""
fi
echo "[security]"
if [[ "$is_ipx" == "true" ]]; then
echo "enable_encryption = ${CONFIG[enable_encryption]}"
[[ "${CONFIG[enable_encryption]}" == "true" ]] && {
echo "algorithm = \"${CONFIG[algorithm]}\""
echo "psk = \"${CONFIG[psk]}\""
echo "kdf_iterations = ${CONFIG[kdf_iterations]}"
}
else
echo "token = \"${CONFIG[token]}\""
fi
echo ""
if [[ -n "${CONFIG[tls_sni]}" || -n "${CONFIG[tls_cert]}" ]]; then
echo "[tls]"
[[ -n "${CONFIG[tls_sni]}" ]]  && echo "sni = \"${CONFIG[tls_sni]}\""
[[ -n "${CONFIG[tls_cert]}" ]] && echo "tls_cert = \"${CONFIG[tls_cert]}\""
[[ -n "${CONFIG[tls_key]}" ]]  && echo "tls_key = \"${CONFIG[tls_key]}\""
echo ""
fi
echo "[tuning]"
[[ -n "${CONFIG[auto_tuning]}" ]]     && echo "auto_tuning = ${CONFIG[auto_tuning]}"
[[ -n "${CONFIG[tuning_profile]}" ]]  && echo "tuning_profile = \"${CONFIG[tuning_profile]}\""
[[ -n "${CONFIG[workers]}" ]]         && echo "workers = ${CONFIG[workers]}"
[[ -n "${CONFIG[channel_size]}" ]]    && echo "channel_size = ${CONFIG[channel_size]}"
[[ -n "${CONFIG[tcp_mss]}" ]]         && echo "tcp_mss = ${CONFIG[tcp_mss]}"
[[ -n "${CONFIG[so_rcvbuf]}" ]]       && echo "so_rcvbuf = ${CONFIG[so_rcvbuf]}"
[[ -n "${CONFIG[so_sndbuf]}" ]]       && echo "so_sndbuf = ${CONFIG[so_sndbuf]}"
[[ -n "${CONFIG[buffer_profile]}" ]]  && echo "buffer_profile = \"${CONFIG[buffer_profile]}\""
[[ -n "${CONFIG[batch_size]}" ]]      && echo "batch_size = ${CONFIG[batch_size]}"
[[ -n "${CONFIG[read_timeout]}" ]]    && echo "read_timeout = ${CONFIG[read_timeout]}"
echo ""
if [[ "${CONFIG[accept_udp]}" == "true" ]]; then
echo "[accept_udp]"
echo "ring_size = ${CONFIG[ring_size]}"
echo "frame_size = ${CONFIG[frame_size]}"
echo "peer_idle_timeout_s = ${CONFIG[peer_idle_timeout_s]}"
echo "write_timeout_ms = ${CONFIG[write_timeout_ms]}"
echo ""
fi
echo "[logging]"
echo "log_level = \"${CONFIG[log_level]}\""
echo ""
if [[ "$mode" == "server" ]] ; then
echo "[ports]"
[[ -n "${CONFIG[forwarder]}" ]]  && echo "forwarder = \"${CONFIG[forwarder]}\""
echo "mapping = ["
IFS=',' read -r -a ports <<< "${CONFIG[ports_mapping]}"
for port in "${ports[@]}"; do
[[ -n "$port" ]] && echo "    \"${port// /}\","
done
echo "]"
fi
} > "$output_file"
}
configure_server() {
local mode="$1"  # server or client
local mode_name
if [[ "$mode" == "server" ]]; then
mode_name="IRAN (Server)"
else
mode_name="KHAREJ (Client)"
fi
clear
colorize cyan "Configuring $mode_name" bold
echo ""
reset_config
prompt_transport_section "$mode"
local is_tun="false"
local is_ipx="false"
[[ "${CONFIG[transport_type]}" == "tun" || "${CONFIG[transport_type]}" == "spoof-tunnel" ]] && is_tun="true"
[[ "${CONFIG[tun_encapsulation]}" == "ipx" || "${CONFIG[transport_type]}" == "spoof-tunnel" ]] && is_ipx="true"
if [[ "${CONFIG[transport_type]}" == "spoof-tunnel" ]]; then
prompt_spoof_tunnel_section "$mode"
prompt_ports_section "$mode" "$is_tun"
elif [[ "${CONFIG[transport_type]}" == "tun" ]]; then
prompt_tun_section "${CONFIG[transport_type]}" "$mode" "$is_ipx"
prompt_ipx_section "$is_ipx" "$mode"
prompt_security_section "$is_ipx"
prompt_accept_udp_section "${CONFIG[accept_udp]}"
prompt_mux_section "${CONFIG[transport_type]}"
prompt_tls_section "$mode" "${CONFIG[transport_type]}"
prompt_tuning_section "$is_ipx" "$is_tun"
prompt_logging_section
prompt_ports_section "$mode" "$is_tun"
else
prompt_connection_section "$mode"
prompt_security_section "$is_ipx"
prompt_accept_udp_section "${CONFIG[accept_udp]}"
prompt_mux_section "${CONFIG[transport_type]}"
prompt_tls_section "$mode" "${CONFIG[transport_type]}"
prompt_tuning_section "$is_ipx" "$is_tun"
prompt_logging_section
prompt_ports_section "$mode" "$is_tun"
fi
local tunnel_port
if [[ "$mode" == "server" ]]; then
tunnel_port=$(echo "${CONFIG[bind_addr]}" | grep -oP ':\K[0-9]+$')
else
tunnel_port=$(echo "${CONFIG[remote_addr]}" | grep -oP ':\K[0-9]+$')
fi
if [[ "${CONFIG[transport_type]}" == "spoof-tunnel" ]]; then
tunnel_port="${CONFIG[tun_health_port]}"
elif [[ -z "$tunnel_port" ]]; then
tunnel_port=$(echo "${CONFIG[tun_health_port]}")
fi
local config_file
if [[ "$mode" == "server" ]]; then
config_file="${config_dir}/iran${tunnel_port}.toml"
else
config_file="${config_dir}/kharej${tunnel_port}.toml"
fi
generate_toml_config "$mode" "$config_file" "$is_tun" "$is_ipx"
local service_type
[[ "$mode" == "server" ]] && service_type="iran" || service_type="kharej"
create_systemd_service "$service_type" "$tunnel_port" "$config_file"
echo ""
colorize green "✔ Configuration completed successfully!" bold
echo ""
press_key
}
create_systemd_service() {
local type="$1"
local port="$2"
local config_file="$3"
local service_file="${service_dir}/backhaul-${type}${port}.service"
local desc_type="$(tr '[:lower:]' '[:upper:]' <<< "${type:0:1}")${type:1}"
cat > "$service_file" <<EOF
[Unit]
Description=Backhaul $desc_type Port $port
After=network.target
[Service]
Type=simple
User=root
ExecStart=${config_dir}/backhaul_premium -c $config_file
Restart=always
RestartSec=3
LimitNOFILE=1048576
TasksMax=infinity
LimitMEMLOCK=infinity
StandardOutput=journal
StandardError=journal
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now "backhaul-${type}${port}.service" >/dev/null 2>&1
colorize green "✔ Service backhaul-${type}${port} created and started" bold
}
SERVER_IP=$(hostname -I | awk '{print $1}')
SERVER_COUNTRY=$(curl -sS --max-time 1 "http://ipwhois.app/json/$SERVER_IP" 2>/dev/null | jq -r '.country')
SERVER_ISP=$(curl -sS --max-time 1 "http://ipwhois.app/json/$SERVER_IP" 2>/dev/null | jq -r '.isp')
display_logo() {
echo -e "\033[36m"
cat << "EOF"
▗▄▄▖  ▗▄▖  ▗▄▄▖▗▖ ▗▖▗▖ ▗▖ ▗▄▖ ▗▖ ▗▖▗▖
▐▌ ▐▌▐▌ ▐▌▐▌   ▐▌▗▞▘▐▌ ▐▌▐▌ ▐▌▐▌ ▐▌▐▌
▐▛▀▚▖▐▛▀▜▌▐▌   ▐▛▚▖ ▐▛▀▜▌▐▛▀▜▌▐▌ ▐▌▐▌
▐▙▄▞▘▐▌ ▐▌▝▚▄▄▖▐▌ ▐▌▐▌ ▐▌▐▌ ▐▌▝▚▄▞▘▐▙▄▄▖
Lightning-fast reverse tunneling solution
EOF
echo -e "\033[0m\033[32m"
echo -e "Script Version: \033[33m${SCRIPT_VERSION}\033[32m"
[[ -f "${config_dir}/backhaul_premium" ]] && \
echo -e "Core Version: \033[33m$($config_dir/backhaul_premium -v)\033[32m"
}
display_server_info() {
echo -e "\e[93m═══════════════════════════════════════════\e[0m"
echo -e "\033[36mIP Address:\033[0m $SERVER_IP"
echo -e "\033[36mLocation:\033[0m $SERVER_COUNTRY"
echo -e "\033[36mDatacenter:\033[0m $SERVER_ISP"
}
display_backhaul_core_status() {
if [[ -f "${config_dir}/backhaul_premium" ]]; then
echo -e "\033[36mBackhaul Core:\033[0m \033[32mInstalled\033[0m"
else
echo -e "\033[36mBackhaul Core:\033[0m \033[31mNot installed\033[0m"
fi
echo -e "\e[93m═══════════════════════════════════════════\e[0m"
}
check_config_backup() {
missing_services=()
for config in "${config_dir}"/iran*.toml "${config_dir}"/kharej*.toml; do
[ -e "$config" ] || continue
fname=$(basename "$config")
if [[ "$fname" =~ ^(iran|kharej)([0-9]+)\.toml$ ]]; then
location="${BASH_REMATCH[1]}"
tunnel_port="${BASH_REMATCH[2]}"
service_file="${service_dir}/backhaul-${location}${tunnel_port}.service"
if [[ ! -f "$service_file" ]]; then
missing_services+=("$service_file:$location:$tunnel_port")
fi
fi
done
[[ ${#missing_services[@]} -eq 0 ]] && return 0
echo
colorize red "Missing service files:" bold
for entry in "${missing_services[@]}"; do
service_file="${entry%%:*}"
location="${entry#*:}"; location="${location%%:*}"
tunnel_port="${entry##*:}"
echo "- $service_file (type: $location, port: $tunnel_port)"
done
echo
read -r -p "Do you want to create missing service files? (y/n): " confirm
if [[ "$confirm" =~ ^[Yy]$ ]]; then
for entry in "${missing_services[@]}"; do
service_file="${entry%%:*}"
location="${entry#*:}"; location="${location%%:*}"
tunnel_port="${entry##*:}"
config_file="${config_dir}/${location}${tunnel_port}.toml"
desc_loc="$(tr '[:lower:]' '[:upper:]' <<< "${location:0:1}")${location:1}"
cat > "$service_file" <<EOF
[Unit]
Description=Backhaul $desc_loc Port $tunnel_port
After=network.target
[Service]
Type=simple
User=root
ExecStart=${config_dir}/backhaul_premium -c $config_file
Restart=always
RestartSec=3
LimitNOFILE=1048576
TasksMax=infinity
LimitMEMLOCK=infinity
StandardOutput=journal
StandardError=journal
[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now "$(basename "$service_file")"
echo "Created and started $(basename "$service_file")"
done
fi
sleep 2
}
check_config_backup
check_tunnel_status() {
if ! ls "$config_dir"/*.toml 1> /dev/null 2>&1; then
colorize red "No config files found." bold
press_key
return 1
fi
clear
colorize yellow "Checking all services status..." bold
sleep 1
echo
for config_path in "$config_dir"/{iran,kharej}*.toml; do
[ -f "$config_path" ] || continue
config_name=$(basename "$config_path")
config_name="${config_name%.toml}"
service_name="backhaul-${config_name}.service"
if [[ "$config_name" =~ ^iran([0-9]+)$ ]]; then
port="${BASH_REMATCH[1]}"
if systemctl is-active --quiet "$service_name"; then
colorize green "Iran service (port $port) is running"
else
colorize red "Iran service (port $port) is not running"
fi
elif [[ "$config_name" =~ ^kharej([0-9]+)$ ]]; then
port="${BASH_REMATCH[1]}"
if systemctl is-active --quiet "$service_name"; then
colorize green "Kharej service (port $port) is running"
else
colorize red "Kharej service (port $port) is not running"
fi
fi
done
echo
press_key
}
auto_restart_file() {
echo "/etc/cron.d/backhaul-auto-restart-$1"
}
auto_restart_status() {
local service="$1"
local cron_file
cron_file="$(auto_restart_file "$service")"
if [[ -f "$cron_file" ]]; then
awk 'NF && $1 !~ /^#/ {print}' "$cron_file"
else
echo "Auto Restart: disabled"
fi
press_key
}
remove_auto_restart() {
local service="$1"
local cron_file
cron_file="$(auto_restart_file "$service")"
rm -f "$cron_file"
colorize green "Auto Restart removed for $service" bold
press_key
}
add_auto_restart() {
local service="$1"
local hours
local cron_file
while true; do
echo -ne "Restart every how many hours [1-24]: "
read -r hours
if [[ "$hours" =~ ^([1-9]|1[0-9]|2[0-4])$ ]]; then break; fi
colorize red "Enter a number from 1 to 24."
done
cron_file="$(auto_restart_file "$service")"
cat > "$cron_file" <<EOF
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
0 */$hours * * * root systemctl restart $service
EOF
chmod 644 "$cron_file"
colorize green "Auto Restart enabled: every $hours hour(s)" bold
press_key
}
auto_restart_menu() {
local service="$1"
clear
colorize cyan "Auto Restart: $service" bold
echo
colorize green "1) Add / Change Auto Restart"
echo "2) Remove Auto Restart"
echo "3) Show Auto Restart Status"
echo "0) Return"
echo
read -r -p "Enter your choice: " ar_choice
case "$ar_choice" in
1) add_auto_restart "$service" ;;
2) remove_auto_restart "$service" ;;
3) auto_restart_status "$service" ;;
0) return ;;
*) colorize red "Invalid option!" && sleep 1 ;;
esac
}
# ---- Per-tunnel management helpers ----
tunnel_backup_dir="${config_dir}/backups"
backup_tunnel_config() {
local config_path="$1" name stamp backup
[[ -f "$config_path" ]] || return 1
mkdir -p "$tunnel_backup_dir"
name="$(basename "$config_path" .toml)"
stamp="$(date +%Y%m%d-%H%M%S)"
backup="$tunnel_backup_dir/${name}-${stamp}.toml"
cp -a -- "$config_path" "$backup" || return 1
printf '%s\n' "$backup"
}

cron_interval_hours() {
local service="$1" f
f="$(auto_restart_file "$service")"
[[ -f "$f" ]] || return 1
awk '$1 ~ /^0$/ && $2 ~ /^\\*\\/([1-9]|1[0-9]|2[0-4])$/ {sub(/^\\*\\//,"",$2); print $2; exit}' "$f"
}

toml_replace_key() {
local file="$1" section="$2" key="$3" value="$4" out
[[ -f "$file" ]] || return 1
out="${file}.tmp.$$"
awk -v target_section="$section" -v target_key="$key" -v new_value="$value" '
BEGIN { sec=""; changed=0 }
/^[[:space:]]*\[[^]]+\][[:space:]]*$/ {
  sec=$0; gsub(/^[[:space:]]*\[/,"",sec); gsub(/\][[:space:]]*$/,"",sec)
}
{
  line=$0
  if (sec == target_section && line ~ "^[[:space:]]*" target_key "[[:space:]]*=") {
    print target_key " = " new_value
    changed=1
  } else print line
}
END { if (!changed) exit 2 }
' "$file" > "$out" || { rm -f "$out"; return 1; }
cat "$out" > "$file" && rm -f "$out"
}

toml_get_key() {
local file="$1" section="$2" key="$3"
awk -v target_section="$section" -v target_key="$key" '
BEGIN { sec="" }
/^[[:space:]]*\[[^]]+\][[:space:]]*$/ {
  sec=$0; gsub(/^[[:space:]]*\[/,"",sec); gsub(/\][[:space:]]*$/,"",sec)
}
sec == target_section && $0 ~ "^[[:space:]]*" target_key "[[:space:]]*=" {
  sub("^[[:space:]]*" target_key "[[:space:]]*=[[:space:]]*","")
  gsub(/^[[:space:]]+|[[:space:]]+$/,"")
  gsub(/^\"|\"$/ ,"")
  print; exit
}' "$file"
}

prompt_edit_value() {
local label="$1" current="$2" var="$3" input
printf '%s' "[-] $label (current: $current, Enter=keep): "
read -r input
if [[ -n "$input" ]]; then printf -v "$var" '%s' "$input"; else printf -v "$var" '%s' "$current"; fi
}

edit_tunnel_config() {
local file="$1" name="$2" backup mode section key current input backup_path changed=0
[[ -f "$file" ]] || { colorize red "Configuration file not found."; press_key; return; }
backup_path="$(backup_tunnel_config "$file")" || { colorize red "Could not create backup."; press_key; return; }
clear
colorize cyan "Edit Configuration: $name" bold
echo "Backup: $backup_path"
echo
if grep -q '^type = "tun"$' "$file" && grep -q '^encapsulation = "ipx"$' "$file"; then mode="ipx"; else mode="normal"; fi
while true; do
  echo "1) MTU"
  echo "2) Health Port"
  echo "3) Heartbeat Interval"
  echo "4) Heartbeat Timeout"
  echo "5) Encryption"
  echo "6) Algorithm"
  echo "7) PSK"
  echo "8) KDF Iterations"
  echo "9) Tuning Profile"
  echo "10) Workers"
  echo "11) Channel Size"
  echo "12) SO_SNDBUF"
  echo "13) Batch Size"
  echo "14) Log Level"
  if [[ "$mode" == "ipx" ]]; then
    echo "15) TUN Local Address"
    echo "16) TUN Remote Address"
    echo "17) Spoof Source IP"
    echo "18) Spoof Destination IP"
    echo "19) IPX Interface"
    echo "20) IPX Listen IP"
    echo "21) IPX Destination IP"
  fi
  if grep -q '^\[ports\]$' "$file"; then echo "22) Port Mappings"; fi
  echo "0) Save & Return"
  echo
  read -r -p "Select setting: " input
  [[ "$input" == "0" ]] && break
  case "$input" in
    1) section="tun"; key="mtu"; label="MTU";;
    2) section="tun"; key="health_port"; label="Health Port";;
    3) section="transport"; key="heartbeat_interval"; label="Heartbeat Interval";;
    4) section="transport"; key="heartbeat_timeout"; label="Heartbeat Timeout";;
    5) section="security"; key="enable_encryption"; label="Enable Encryption";;
    6) section="security"; key="algorithm"; label="Algorithm";;
    7) section="security"; key="psk"; label="PSK";;
    8) section="security"; key="kdf_iterations"; label="KDF Iterations";;
    9) section="tuning"; key="tuning_profile"; label="Tuning Profile";;
    10) section="tuning"; key="workers"; label="Workers";;
    11) section="tuning"; key="channel_size"; label="Channel Size";;
    12) section="tuning"; key="so_sndbuf"; label="SO_SNDBUF";;
    13) section="tuning"; key="batch_size"; label="Batch Size";;
    14) section="logging"; key="log_level"; label="Log Level";;
    15) section="tun"; key="local_addr"; label="TUN Local Address";;
    16) section="tun"; key="remote_addr"; label="TUN Remote Address";;
    17) section="ipx"; key="spoof_src_ip"; label="Spoof Source IP";;
    18) section="ipx"; key="spoof_dst_ip"; label="Spoof Destination IP";;
    19) section="ipx"; key="interface"; label="IPX Interface";;
    20) section="ipx"; key="listen_ip"; label="IPX Listen IP";;
    21) section="ipx"; key="dst_ip"; label="IPX Destination IP";;
    22) section="ports"; key="mapping"; label="Port Mappings";;
    *) colorize red "Invalid option."; sleep 1; continue;;
  esac
  current="$(toml_get_key "$file" "$section" "$key")"
  if [[ "$key" == "mapping" ]]; then
    echo "Current: $current"
    echo "For multiple mappings use comma-separated values, e.g. 443,443=8443"
    read -r -p "New mappings (Enter=keep): " input
    [[ -z "$input" ]] && continue
    local array_value
    array_value="["
    IFS=',' read -r -a _maps <<< "$input"
    for m in "${_maps[@]}"; do m="${m// /}"; [[ -n "$m" ]] && array_value="$array_value\"$m\", "; done
    array_value="${array_value%, }]"
    # Replace the complete mapping array safely with a compact single-line array.
    awk -v section="ports" -v key="mapping" -v val="$array_value" 'BEGIN{sec="";done=0}
      /^[[:space:]]*\[[^]]+\][[:space:]]*$/ {sec=$0;gsub(/^[[:space:]]*\[/,"",sec);gsub(/\][[:space:]]*$/,"",sec)}
      sec==section && $0 ~ /^[[:space:]]*mapping[[:space:]]*=/ {print "mapping = " val; done=1; next}
      sec==section && done==0 && $0 ~ /^[[:space:]]*"/ {next}
      {print}' "$file" > "${file}.tmp.$$" && cat "${file}.tmp.$$" > "$file" && rm -f "${file}.tmp.$$"
  else
    if [[ "$key" == "psk" ]]; then
      input="$(openssl rand -base64 32 2>/dev/null | tr -d '\n')"
      echo "A new random PSK will be generated."
      read -r -p "Press Enter to accept generated PSK, or type a new PSK: " current_input
      [[ -n "$current_input" ]] && input="$current_input"
      [[ ! "$input" =~ ^[A-Za-z0-9+/]{43}=$ ]] && { colorize red "Invalid PSK."; sleep 1; continue; }
      value="\"$input\""
    else
      prompt_edit_value "$label" "$current" input
      [[ -z "$input" ]] && continue
      case "$key" in
        enable_encryption) [[ "$input" == true || "$input" == false ]] || { colorize red "Use true or false."; sleep 1; continue; };;
        algorithm) is_valid_algorithm "$input" || { colorize red "Invalid algorithm."; sleep 1; continue; };;
        mtu|health_port|heartbeat_interval|heartbeat_timeout|kdf_iterations|workers|channel_size|so_sndbuf|batch_size) [[ "$input" =~ ^[0-9]+$ ]] || { colorize red "Enter a number."; sleep 1; continue; };;
        *) [[ "$input" != *'"'* ]] || { colorize red 'Double quotes are not allowed here.'; sleep 1; continue; };;
      esac
      case "$key" in
        enable_encryption) value="$input";;
        mtu|health_port|heartbeat_interval|heartbeat_timeout|kdf_iterations|workers|channel_size|so_sndbuf|batch_size) value="$input";;
        *) value="\"$input\"";;
      esac
    fi
    if ! toml_replace_key "$file" "$section" "$key" "$value"; then
      colorize red "Could not update $section.$key"
    else
      changed=1
      colorize green "Updated $section.$key"
    fi
  fi
done
if (( changed )); then
  systemctl daemon-reload
  if systemctl restart "backhaul-${name}.service" >/dev/null 2>&1; then
    colorize green "Configuration saved and service restarted." bold
  else
    colorize yellow "Configuration saved, but service restart failed. Check status/logs." bold
  fi
else
  colorize green "No changes made."
fi
press_key
}

test_tunnel_connectivity() {
local file="$1" name="$2" service="backhaul-${2}.service" remote tun_name interface health
clear
colorize cyan "Connectivity Test: $name" bold
echo
if systemctl is-active --quiet "$service"; then colorize green "[✓] Service is running"; else colorize red "[✗] Service is not running"; fi
if grep -q '^type = "tun"$' "$file"; then
  tun_name="$(toml_get_key "$file" tun name)"
  interface="$(toml_get_key "$file" ipx interface)"
  remote="$(toml_get_key "$file" tun remote_addr | cut -d/ -f1)"
  [[ -n "$tun_name" ]] && ip link show "$tun_name" >/dev/null 2>&1 && colorize green "[✓] TUN device: $tun_name" || colorize red "[✗] TUN device is not present"
  [[ -n "$interface" ]] && ip link show "$interface" >/dev/null 2>&1 && colorize green "[✓] Network interface: $interface" || colorize yellow "[!] Network interface not found: $interface"
  if [[ -n "$remote" ]] && command -v ping >/dev/null 2>&1 && ping -c 1 -W 2 "$remote" >/dev/null 2>&1; then colorize green "[✓] Remote TUN address responds: $remote"; else colorize yellow "[!] Remote TUN address did not respond: ${remote:-unknown}"; fi
else
  remote="$(toml_get_key "$file" dialer remote_addr | sed 's/^[^:]*:\/\///' | cut -d: -f1)"
  [[ -z "$remote" ]] && remote="$(toml_get_key "$file" listener bind_addr)"
  [[ -n "$remote" ]] && colorize cyan "[i] Endpoint: $remote"
fi
health="$(toml_get_key "$file" tun health_port)"
if [[ -n "$health" ]] && command -v ss >/dev/null 2>&1; then
  if ss -lnt 2>/dev/null | awk '{print $4}' | grep -Eq "(:|\\.)${health}$"; then colorize green "[✓] Health port is listening: $health"; else colorize yellow "[!] Health port is not listening: $health"; fi
fi
if command -v ip >/dev/null 2>&1; then
  colorize cyan "[i] Default route: $(ip route show default | head -1)"
fi
press_key
}

tunnel_information() {
local file="$1" name="$2" service="backhaul-${2}.service" val cronh
clear
colorize cyan "Tunnel Information: $name" bold
echo
printf 'Config: %s\n' "$file"
printf 'Service: %s\n' "$service"
val="$(toml_get_key "$file" transport type)"; printf 'Transport: %s\n' "${val:-unknown}"
val="$(toml_get_key "$file" tun encapsulation)"; [[ -n "$val" ]] && printf 'Encapsulation: %s\n' "$val"
val="$(toml_get_key "$file" ipx mode)"; [[ -n "$val" ]] && printf 'IPX Mode: %s\n' "$val"
val="$(toml_get_key "$file" ipx profile)"; [[ -n "$val" ]] && printf 'IPX Profile: %s\n' "$val"
for pair in 'tun local_addr:Local Address' 'tun remote_addr:Remote Address' 'tun name:TUN Device' 'tun health_port:Health Port' 'tun mtu:MTU' 'ipx interface:Interface' 'ipx listen_ip:Listen IP' 'ipx dst_ip:Destination IP' 'ipx spoof_src_ip:Spoof Source IP' 'ipx spoof_dst_ip:Spoof Destination IP' 'security enable_encryption:Encryption' 'security algorithm:Algorithm' 'tuning tuning_profile:Tuning Profile' 'tuning workers:Workers' 'tuning batch_size:Batch Size' 'logging log_level:Log Level'; do
  section="${pair%% *}"; rest="${pair#* }"; key="${rest%%:*}"; label="${rest#*:}"; val="$(toml_get_key "$file" "$section" "$key")"; [[ -n "$val" ]] && printf '%s: %s\n' "$label" "$val"
done
if grep -q '^psk = ' "$file"; then echo 'PSK: ********'; fi
if grep -q '^\[ports\]$' "$file"; then val="$(toml_get_key "$file" ports mapping)"; [[ -n "$val" ]] && printf 'Port Mapping: %s\n' "$val"; fi
if systemctl is-enabled --quiet "$service" 2>/dev/null; then colorize green 'Service: enabled'; else colorize yellow 'Service: disabled'; fi
if systemctl is-active --quiet "$service" 2>/dev/null; then colorize green 'Status: running'; else colorize red 'Status: stopped'; fi
cronh="$(cron_interval_hours "$service" || true)"; if [[ -n "$cronh" ]]; then colorize green "Auto Restart: every $cronh hour(s)"; else colorize yellow 'Auto Restart: disabled'; fi
press_key
}

toggle_tunnel() {
local name="$1" service="backhaul-${1}.service" disabled_state="${config_dir}/.disabled-${1}" interval
clear
colorize cyan "Enable / Disable: $name" bold
echo
if systemctl is-active --quiet "$service" || systemctl is-enabled --quiet "$service" 2>/dev/null; then
  interval="$(cron_interval_hours "$service" || true)"
  [[ -n "$interval" ]] && printf '%s\n' "$interval" > "$disabled_state"
  rm -f "$(auto_restart_file "$service")"
  systemctl disable --now "$service" >/dev/null 2>&1
  systemctl daemon-reload
  colorize yellow "Tunnel disabled: $service" bold
else
  if ! systemctl enable --now "$service" >/dev/null 2>&1; then
    colorize red "Could not enable/start $service. Service file may be missing." bold
    press_key
    return 1
  fi
  if [[ -s "$disabled_state" ]]; then
    interval="$(cat "$disabled_state")"
    rm -f "$disabled_state"
    if [[ "$interval" =~ ^([1-9]|1[0-9]|2[0-4])$ ]]; then
      cat > "$(auto_restart_file "$service")" <<EOF
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
0 */$interval * * * root systemctl restart $service
EOF
      chmod 644 "$(auto_restart_file "$service")"
    fi
  fi
  colorize green "Tunnel enabled and started: $service" bold
fi
press_key
}

tunnel_management() {
if ! ls "$config_dir"/*.toml 1> /dev/null 2>&1; then
colorize red "No config files found." bold
press_key
return 1
fi
clear
colorize cyan "Existing services:" bold
echo
local index=1
declare -a configs
for config_path in "$config_dir"/{iran,kharej}*.toml; do
[ -f "$config_path" ] || continue
config_name=$(basename "$config_path")
if [[ "$config_name" =~ ^iran([0-9]+)\.toml$ ]]; then
port="${BASH_REMATCH[1]}"
configs+=("$config_path")
echo -e "\033[35m${index}\033[0m) \033[32mIran\033[0m (port: \033[33m$port\033[0m)"
((index++))
elif [[ "$config_name" =~ ^kharej([0-9]+)\.toml$ ]]; then
port="${BASH_REMATCH[1]}"
configs+=("$config_path")
echo -e "\033[35m${index}\033[0m) \033[32mKharej\033[0m (port: \033[33m$port\033[0m)"
((index++))
fi
done
echo
echo -ne "Enter your choice (0 to return): "
read -r choice
[[ "$choice" == "0" ]] && return
while ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#configs[@]} )); do
colorize red "Invalid choice."
echo -ne "Enter your choice (0 to return): "
read -r choice
[[ "$choice" == "0" ]] && return
done
selected_config="${configs[$((choice - 1))]}"
config_name=$(basename "${selected_config%.toml}")
service_name="backhaul-${config_name}.service"
clear
colorize cyan "Manage $config_name:" bold
echo
colorize red "1) Remove this tunnel"
colorize yellow "2) Restart this tunnel"
echo "3) View service logs"
echo "4) View service status"
echo "5) Auto Restart"
echo "6) Edit Configuration"
echo "7) Test Tunnel Connectivity"
echo "8) Tunnel Information"
echo "9) Enable / Disable Tunnel"
echo
read -r -p "Enter your choice (0 to return): " choice
case $choice in
1) destroy_tunnel "$selected_config" ;;
2) restart_service "$service_name" ;;
3) view_service_logs "$service_name" ;;
4) view_service_status "$service_name" ;;
5) auto_restart_menu "$service_name" ;;
6) edit_tunnel_config "$selected_config" "$config_name" ;;
7) test_tunnel_connectivity "$selected_config" "$config_name" ;;
8) tunnel_information "$selected_config" "$config_name" ;;
9) toggle_tunnel "$config_name" ;;
0) return ;;
*) colorize red "Invalid option!" && sleep 1 ;;
esac
}
destroy_tunnel() {
config_path="$1"
config_name=$(basename "${config_path%.toml}")
service_name="backhaul-${config_name}.service"
service_path="$service_dir/$service_name"
[ -f "$config_path" ] && rm -f "$config_path"
if [[ -f "$service_path" ]]; then
systemctl is-active --quiet "$service_name" && systemctl disable --now "$service_name" >/dev/null 2>&1
rm -f "$service_path"
fi
systemctl daemon-reload
rm -f "$(auto_restart_file "$service_name")"
echo
colorize green "Tunnel destroyed successfully!" bold
echo
press_key
}
restart_service() {
echo
colorize yellow "Restarting $1" bold
if systemctl cat "$1" >/dev/null 2>&1; then
if systemctl restart "$1"; then
colorize green "Service restarted successfully" bold
else
colorize red "Service restart failed" bold
fi
echo
else
colorize red "Service not found"
fi
press_key
}
view_service_logs() {
clear
journalctl -eu "$1" -f -o cat
}
view_service_status() {
clear
systemctl status "$1"
press_key
}
remove_core() {
if find "$config_dir" -type f -name "*.toml" | grep -q .; then
colorize red "Delete all services first."
sleep 3
return 1
fi
colorize yellow "Remove Backhaul-Core? (y/n)"
read -r confirm
if [[ $confirm == [yY] ]]; then
[[ -d "$config_dir" ]] && rm -rf "$config_dir"
colorize green "Backhaul-Core removed." bold
fi
press_key
}
configure_tunnel() {
[[ ! -x "${config_dir}/backhaul_premium" ]] && {
colorize red "Install Backhaul-Core first."
press_key
return 1
}
clear
echo ""
colorize green "1) Configure IRAN (Server)" bold
colorize magenta "2) Configure KHAREJ (Client)" bold
echo ""
read -r -p "Enter your choice: " configure_choice
case "$configure_choice" in
1) configure_server "server" ;;
2) configure_server "client" ;;
*) colorize red "Invalid option!" && sleep 1 ;;
esac
}
display_menu() {
clear
display_logo
display_server_info
display_backhaul_core_status
echo
colorize green " 1. Install Backhaul Core" bold
colorize green " 2. Configure a new tunnel" bold
colorize red " 3. Tunnel management" bold
colorize cyan " 4. Check tunnel status" bold
echo " 5. Remove Backhaul Core"
echo " 0. Exit"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}
read_option() {
read -r -p "Enter your choice [0-5]: " choice
case $choice in
1) install_backhaul_core ;;
2) configure_tunnel ;;
3) tunnel_management ;;
4) check_tunnel_status ;;
5) remove_core ;;
0) exit 0 ;;
*) colorize red "Invalid option!" && sleep 1 ;;
esac
}
while true; do
display_menu
read_option
done
