#!/bin/bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GREEN='\033[1;32m'; WHITE='\033[1;37m'; RED='\033[1;31m'; YELLOW='\033[1;33m'; DIM='\033[2m'; NC='\033[0m'; B='\033[1m'
DATA_DIR="$BASE_DIR/data"
CONFIG_FILE="$DATA_DIR/config.json"
UUID_FILE="$DATA_DIR/uuid.txt"
CUSTOM_IP_FILE="$DATA_DIR/custom_ip.txt"
KEEPALIVE_CONF="$DATA_DIR/keepalive.conf"
KEEPALIVE_PID="$DATA_DIR/keepalive.pid"
PROTOCOL_CONF="$DATA_DIR/protocol.conf"
LOG_DIR="$BASE_DIR/logs"
MOBILE_CONFIG_FILE="$BASE_DIR/configs-to-copy-for-mobile.txt"
XRAY_BIN="/usr/local/bin/xray"
XRAY_PORT=443
WS_PORT=8443
WS_PATH="/gtunnel-ws"
CONFIG_SERVER_KEY_FILE="$DATA_DIR/config-server.key"
CONFIG_SERVER_URL_FILE="$DATA_DIR/config-server.url"
CONFIG_SERVER_PID="$DATA_DIR/config-server.pid"
CONFIG_SERVER_PORT=8000

mkdir -p "$DATA_DIR" "$LOG_DIR"

[ ! -f "$CUSTOM_IP_FILE" ] && echo "94.130.50.12" > "$CUSTOM_IP_FILE"
CUSTOM_IP=$(cat "$CUSTOM_IP_FILE" 2>/dev/null || true)

[ ! -f "$KEEPALIVE_CONF" ] && echo "60" > "$KEEPALIVE_CONF"
[ ! -f "$PROTOCOL_CONF" ] && echo "both" > "$PROTOCOL_CONF"

if [ -z "${CODESPACE_NAME:-}" ]; then
	if command -v gh >/dev/null 2>&1; then
		CODESPACE_NAME=$(gh codespace list --limit 1 --json name --jq '.[0].name' 2>/dev/null || echo "unknown-codespace")
	else
		CODESPACE_NAME="unknown-codespace"
	fi
fi
PORT_DOMAIN="${CODESPACE_NAME}-${XRAY_PORT}.app.github.dev"
WS_DOMAIN="${CODESPACE_NAME}-${WS_PORT}.app.github.dev"

get_protocol() { cat "$PROTOCOL_CONF" 2>/dev/null || echo "xhttp"; }

# ==================== WS PORT HELPERS ====================
ensure_ws_port_public() {
	command -v gh >/dev/null 2>&1 && gh codespace ports visibility "${WS_PORT}:public" -c "$CODESPACE_NAME" >/dev/null 2>&1 || true
}

ensure_all_ports_public() {
	ensure_codespace_port_public
	[ "$(get_protocol)" = "both" ] && ensure_ws_port_public
	command -v gh >/dev/null 2>&1 && gh codespace ports visibility "${CONFIG_SERVER_PORT}:public" -c "$CODESPACE_NAME" >/dev/null 2>&1 || true
}

# ==================== PORT / PROCESS HELPERS ====================
is_port_open() {
	if command -v ss >/dev/null 2>&1; then
		sudo ss -tnl 2>/dev/null | grep -q ":${XRAY_PORT}"
	else
		sudo netstat -tnl 2>/dev/null | grep -q ":${XRAY_PORT}"
	fi
}

ensure_codespace_port_public() {
	command -v gh >/dev/null 2>&1 && gh codespace ports visibility "${XRAY_PORT}:public" -c "$CODESPACE_NAME" >/dev/null 2>&1 || true
}

start_xray() {
	sudo pkill -f "$XRAY_BIN run" 2>/dev/null || true
	sleep 0.5
	nohup sudo "$XRAY_BIN" run -c "$CONFIG_FILE" > "$LOG_DIR/xray.log" 2>&1 &
	disown
}

wait_for_port() {
	local i=0
	echo -ne "${DIM}Initializing Engine...${NC} "
	while ! is_port_open && [ "$i" -lt 15 ]; do
		echo -ne "■"
		sleep 1
		i=$((i + 1))
	done
	echo ""
	is_port_open
}

# ==================== KEEPALIVE ====================
keepalive_status() {
	if [ -f "$KEEPALIVE_PID" ] && kill -0 "$(cat "$KEEPALIVE_PID" 2>/dev/null)" 2>/dev/null; then
		echo -e "${GREEN}Active${NC}"
	else
		echo -e "${RED}Inactive${NC}"
	fi
}

_keepalive_loop() {
	local interval_sec="$1"
	local _beat_file="$DATA_DIR/.hb"
	while true; do
		# Local filesystem activity — resets codespace idle timer
		date +%s > "$_beat_file" 2>/dev/null || true

		# Self-ping: keeps the port warm and marks the codespace as active
		curl -s --max-time 4 "http://127.0.0.1:${XRAY_PORT}" >/dev/null 2>&1 || true

		# External ping: prevents network-level idle detection
		curl -s --max-time 5 https://github.com >/dev/null 2>&1 || true

		# Codespace public URL ping: tells GitHub the forwarded port is alive
		curl -s --max-time 6 "https://${PORT_DOMAIN}" >/dev/null 2>&1 || true

		# Watchdog: restart xray silently if it crashed
		if ! pgrep -f "$XRAY_BIN run" >/dev/null 2>&1; then
			start_xray >/dev/null 2>&1 || true
			sleep 3
			ensure_all_ports_public >/dev/null 2>&1 || true
		fi

		sleep "$interval_sec"
	done
}

start_keepalive() {
	local interval_sec=$1
	echo "$interval_sec" > "$KEEPALIVE_CONF"
	[ -f "$KEEPALIVE_PID" ] && kill "$(cat "$KEEPALIVE_PID" 2>/dev/null)" 2>/dev/null || true
	_keepalive_loop "$interval_sec" &
	echo $! > "$KEEPALIVE_PID"
	disown
}

stop_keepalive() {
	if [ -f "$KEEPALIVE_PID" ] && kill "$(cat "$KEEPALIVE_PID" 2>/dev/null)" 2>/dev/null; then
		rm -f "$KEEPALIVE_PID"
		echo -e "${RED}Keepalive stopped.${NC}"
	else
		rm -f "$KEEPALIVE_PID"
		echo -e "${WHITE}Keepalive was not running.${NC}"
	fi
	sleep 1
}

# ==================== QUOTA ====================
estimate_quota() {
	local uptime_sec remaining_sec hours_used mins_used hours_left mins_left dis_time
	uptime_sec=$(awk '{printf "%d", $1}' /proc/uptime 2>/dev/null || echo 0)
	remaining_sec=$(( 60 * 3600 - uptime_sec ))
	[ "$remaining_sec" -lt 0 ] && remaining_sec=0
	hours_used=$((uptime_sec / 3600))
	mins_used=$(( (uptime_sec % 3600) / 60 ))
	hours_left=$((remaining_sec / 3600))
	mins_left=$(( (remaining_sec % 3600) / 60 ))
	dis_time=$(date -d "+${remaining_sec} seconds" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "N/A")
	echo -e "  ${YELLOW}⚠  Estimated from container uptime — not GitHub API${NC}"
	echo -e "  Uptime consumed: ${WHITE}${hours_used}h ${mins_used}m${NC}"
	echo -e "  Remaining quota: ${GREEN}${hours_left}h ${mins_left}m${NC} ${DIM}(60h reference)${NC}"
	echo -e "  Estimated stop at: ${YELLOW}${dis_time}${NC}"
}

# ==================== LOGO ====================
draw_logo() {
	echo -e "${GREEN}${B}"
	echo "  ██████╗ ██████╗ ██████╗  █████╗ ██╗   ██╗"
	echo " ██╔════╝ ╚════██╗██╔══██╗██╔══██╗╚██╗ ██╔╝"
	echo " ██║  ███╗█████╔╝██████╔╝███████║ ╚████╔╝ "
	echo " ██║   ██║██╔═══╝ ██╔══██╗██╔══██║  ╚██╔╝  "
	echo " ╚██████╔╝███████╗██║  ██║██║  ██║   ██║   "
	echo "  ╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝   "
	echo -e "${NC}${WHITE}  G-Tunnel Panel | Made By CodeLeafy${NC}\n"
}

# ==================== CONFIG HTTP SERVER ====================
start_config_server() {
	# Use pre-configured secret from VPS orchestrator (GitHub Secrets API)
	if [ -n "${GTUNNEL_CONFIG_SECRET:-}" ]; then
		echo "$GTUNNEL_CONFIG_SECRET" > "$CONFIG_SERVER_KEY_FILE"
	elif [ ! -f "$CONFIG_SERVER_KEY_FILE" ]; then
		openssl rand -hex 16 > "$CONFIG_SERVER_KEY_FILE"
	fi
	local KEY DOMAIN
	KEY=$(cat "$CONFIG_SERVER_KEY_FILE")
	DOMAIN="${CODESPACE_NAME}-${CONFIG_SERVER_PORT}.app.github.dev"
	echo "https://${DOMAIN}/configs/${KEY}" > "$CONFIG_SERVER_URL_FILE"
	stop_config_server
	nohup python3 -c "
import http.server
KEY='${KEY}'; CF='${MOBILE_CONFIG_FILE}'; PORT=${CONFIG_SERVER_PORT}
class H(http.server.BaseHTTPRequestHandler):
 def log_message(self,*a): pass
 def do_GET(self):
  if self.path=='/configs/'+KEY:
   try: d=open(CF,'rb').read(); self.send_response(200); self.send_header('Content-Type','text/plain'); self.send_header('Content-Length',str(len(d))); self.end_headers(); self.wfile.write(d)
   except: self.send_response(404); self.end_headers()
  elif self.path=='/health': self.send_response(200); self.end_headers(); self.wfile.write(b'ok')
  else: self.send_response(403); self.end_headers()
http.server.HTTPServer(('0.0.0.0',PORT),H).serve_forever()
" > "$DATA_DIR/python_server.log" 2>&1 &
	echo $! > "$CONFIG_SERVER_PID"
	disown
}

stop_config_server() {
	[ -f "$CONFIG_SERVER_PID" ] && kill "$(cat "$CONFIG_SERVER_PID")" 2>/dev/null; rm -f "$CONFIG_SERVER_PID"
}
# ==================== PORT VISIBILITY CHECK ====================
check_port_visibility() {
	if ! is_port_open; then
		clear; draw_logo
		echo -e "  ${RED}[ ERROR ] Engine is not running locally!${NC}"
		echo -e "  ${YELLOW}Please start the engine first, then try again.${NC}\n"
		read -rp "  Press Enter to go back to main menu..."
		return 1
	fi
	ensure_all_ports_public
	return 0
}

# ==================== CONFIG GENERATION ====================
generate_config() {
	if ! command -v uuidgen >/dev/null 2>&1; then
		echo -e "${RED}Error: uuidgen not found.${NC}"; return 1
	fi
	uuidgen > "$UUID_FILE"
	local UUID PROTO WS_P WS_D
	UUID=$(cat "$UUID_FILE")
	PROTO=$(get_protocol)
	# WS uses port 443 when alone, 8080 when combined with XHTTP
	if [ "$PROTO" = "both" ]; then WS_P=$WS_PORT; WS_D=$WS_DOMAIN; else WS_P=$XRAY_PORT; WS_D=$PORT_DOMAIN; fi

	local XHTTP_BLOCK WS_BLOCK INBOUNDS
	XHTTP_BLOCK="{ \"tag\":\"vless-xhttp-in\", \"port\":${XRAY_PORT}, \"listen\":\"0.0.0.0\", \"protocol\":\"vless\", \"settings\":{ \"clients\":[{ \"id\":\"${UUID}\", \"flow\":\"\", \"level\":0, \"email\":\"user@gtunnel\" }], \"decryption\":\"none\" }, \"streamSettings\":{ \"network\":\"xhttp\", \"security\":\"none\", \"xhttpSettings\":{ \"mode\":\"packet-up\", \"path\":\"/\", \"maxUploadSize\":1000000, \"maxConcurrentUploads\":10 } }, \"sniffing\":{ \"enabled\":true, \"destOverride\":[\"http\",\"tls\",\"quic\"], \"routeOnly\":false } }"
	WS_BLOCK="{ \"tag\":\"vless-ws-in\", \"port\":${WS_P}, \"listen\":\"0.0.0.0\", \"protocol\":\"vless\", \"settings\":{ \"clients\":[{ \"id\":\"${UUID}\", \"flow\":\"\", \"level\":0, \"email\":\"user@gtunnel\" }], \"decryption\":\"none\" }, \"streamSettings\":{ \"network\":\"ws\", \"security\":\"none\", \"wsSettings\":{ \"path\":\"${WS_PATH}\" } }, \"sniffing\":{ \"enabled\":true, \"destOverride\":[\"http\",\"tls\",\"quic\"], \"routeOnly\":false } }"

	case "$PROTO" in
		ws)   INBOUNDS="$WS_BLOCK" ;;
		both) INBOUNDS="${XHTTP_BLOCK}, ${WS_BLOCK}" ;;
		*)    INBOUNDS="$XHTTP_BLOCK" ;;
	esac

	cat > "$CONFIG_FILE" <<JSONEOF
{
  "log": { "loglevel": "warning", "access": "none", "error": "${LOG_DIR}/xray-error.log" },
  "stats": {},
  "api": { "tag": "api", "services": [ "StatsService" ] },
  "policy": { "system": { "statsInboundDownlink": true, "statsInboundUplink": true }, "levels": { "0": { "statsUserUplink": true, "statsUserDownlink": true, "handshake": 4, "connIdle": 300, "uplinkOnly": 2, "downlinkOnly": 5, "bufferSize": 128 } } },
  "dns": { "hosts": { "dns.google": "8.8.8.8", "dns.cloudflare": "1.1.1.1" }, "servers": [ { "address": "https://1.1.1.1/dns-query", "domains": [ "geosite:geolocation-!cn" ], "queryStrategy": "UseIP" }, "8.8.4.4", "localhost" ], "queryStrategy": "UseIPv4" },
  "inbounds": [ ${INBOUNDS}, { "listen": "127.0.0.1", "port": 10085, "protocol": "dokodemo-door", "settings": { "address": "127.0.0.1" }, "tag": "api" } ],
  "outbounds": [ { "tag": "direct", "protocol": "freedom", "settings": { "domainStrategy": "UseIPv4" } }, { "tag": "block", "protocol": "blackhole", "settings": { "response": { "type": "http" } } } ],
  "routing": { "domainStrategy": "IPIfNonMatch", "rules": [ { "inboundTag": [ "api" ], "outboundTag": "api", "type": "field" }, { "type": "field", "ip": [ "geoip:private" ], "outboundTag": "block" }, { "type": "field", "protocol": [ "bittorrent" ], "outboundTag": "block" }, { "type": "field", "domain": [ "geosite:category-ads-all" ], "outboundTag": "block" } ] }
}
JSONEOF
	start_xray
	if wait_for_port >/dev/null 2>&1; then
		echo -e "${GREEN}Engine started on port ${XRAY_PORT}.${NC}"
	else
		echo -e "${YELLOW}[ WARN ] Engine may not have bound to port ${XRAY_PORT}.${NC}"
	fi
	ensure_all_ports_public
	# Validate generated JSON
	if command -v jq >/dev/null 2>&1; then
		if ! jq empty "$CONFIG_FILE" >/dev/null 2>&1; then
			echo -e "${RED}[ ERROR ] Generated config.json is invalid JSON! Check logs.${NC}"
			return 1
		fi
		local INBOUND_COUNT
		INBOUND_COUNT=$(jq '[.inbounds[] | select(.tag != "api")] | length' "$CONFIG_FILE" 2>/dev/null || echo 0)
		echo -e "  ${DIM}Active inbounds: ${INBOUND_COUNT} protocol(s) loaded.${NC}"
	fi
}

# ==================== LINK GENERATION ====================
# Resolves the real CDN IP for a given GitHub Codespace domain.
# Each port's subdomain (name-443, name-8443) may resolve to different IPs.
_resolve_domain_ip() {
	local domain="$1" fallback="$2" ip
	# Try getent first (fastest, uses system DNS)
	ip=$(getent hosts "$domain" 2>/dev/null | awk 'NR==1{print $1}')
	[ -z "$ip" ] && ip=$(curl -sf --max-time 4 "https://dns.google/resolve?name=${domain}&type=A" \
		| grep -oE '"data":"[0-9.]+"' | head -1 | grep -oE '[0-9.]+')
	echo "${ip:-$fallback}"
}
# Outputs lines in format: TYPE|VLESS_LINK
generate_links() {
	local UUID PROTO PUBLIC_IP WS_D XHTTP_IP WS_IP
	UUID=$(cat "$UUID_FILE" 2>/dev/null || echo "")
	[ -z "$UUID" ] && { return 1; }
	PROTO=$(get_protocol)
	# Fallback IP (custom or auto-detected outbound)
	if [ -n "$CUSTOM_IP" ]; then PUBLIC_IP="$CUSTOM_IP"
	else PUBLIC_IP=$(curl -s --max-time 4 https://api.ipify.org 2>/dev/null || echo "94.130.50.12"); fi
	# Resolve per-domain IPs (each GitHub subdomain may have its own CDN IP)
	XHTTP_IP=$(_resolve_domain_ip "$PORT_DOMAIN" "$PUBLIC_IP")
	if [ "$PROTO" = "both" ]; then
		WS_D=$WS_DOMAIN
		WS_IP=$(_resolve_domain_ip "$WS_D" "$PUBLIC_IP")
	else
		WS_D=$PORT_DOMAIN
		WS_IP=$XHTTP_IP
	fi
	local L_XHTTP="vless://${UUID}@${XHTTP_IP}:443?encryption=none&security=tls&sni=${PORT_DOMAIN}&fp=chrome&alpn=h2&insecure=1&allowInsecure=1&type=xhttp&host=${PORT_DOMAIN}&path=%2F&mode=packet-up#G-Tunnel-XHTTP"
	local L_WS="vless://${UUID}@${WS_IP}:443?encryption=none&security=tls&sni=${WS_D}&insecure=1&allowInsecure=1&type=ws&path=%2Fgtunnel-ws#G-Tunnel-WS"
	case "$PROTO" in
		xhttp) echo "XHTTP|${L_XHTTP}" ;;
		ws)    echo "WS|${L_WS}" ;;
		both)  echo "XHTTP|${L_XHTTP}"; echo "WS|${L_WS}" ;;
	esac
}

# ==================== FORMAT BYTES ====================
format_bytes() {
	local b="$1"
	awk -v b="$b" 'BEGIN {
		if (b < 1048576)         printf "%.2f KB", b / 1024
		else if (b < 1073741824) printf "%.2f MB", b / 1048576
		else                     printf "%.2f GB", b / 1073741824
	}'
}

# ==================== RESOURCE STATS ====================
show_resource_stats() {
	clear; draw_logo
	echo -e "  ${GREEN}📊 Resource Statistics${NC}"
	echo -e "  ${GREEN}──────────────────────────────────────────────${NC}"
	local XRAY_PID CPU MEM_KB MEM_MB
	XRAY_PID=$(pgrep -f "$XRAY_BIN run" | head -1)
	if [ -n "$XRAY_PID" ]; then
		read -r CPU MEM_KB <<< "$(ps -p "$XRAY_PID" -o %cpu,rss --no-headers 2>/dev/null || echo "0 0")"
		MEM_MB=$(awk "BEGIN {printf \"%.1f\", $MEM_KB / 1024}")
		echo -e "  Engine: ${GREEN}Active${NC} (PID $XRAY_PID)  CPU: ${WHITE}${CPU}%${NC}  MEM: ${WHITE}${MEM_MB} MB${NC}"
	else
		echo -e "  Engine: ${RED}Offline${NC}"
	fi
	echo -e "\n  Press Enter to return..."
	read -r
}

# ==================== MULTI IP MENU ====================
multi_ip_menu() {
	while true; do
		clear; draw_logo
		echo -e "  ${GREEN}🌍 Multi-IP & CDN Routing${NC}"
		echo -e "  ${GREEN}──────────────────────────────────────────────${NC}"
		if [ -n "$CUSTOM_IP" ]; then
			echo -e "  Current Route: ${GREEN}${CUSTOM_IP}${NC}\n"
		else
			echo -e "  Current Route: ${WHITE}Auto-detect Dynamic IP${NC}\n"
		fi
		echo -e "  ${GREEN}1)${NC} Set Auto-detect"
		echo -e "  ${WHITE}2)${NC} USA 50.7.5.83"
		echo -e "  ${WHITE}3)${NC} USA 63.141.252.203"
		echo -e "  ${WHITE}4)${NC} DE 94.130.50.12"
		echo -e "  ${WHITE}5)${NC} Enter Custom IP"
		echo -e "  ${WHITE}0)${NC} Go Back\n"
		read -rp "  Select: " mic
		case $mic in
			1) rm -f "$CUSTOM_IP_FILE"; CUSTOM_IP=""; echo -e "  ${GREEN}Switched to Auto-detect.${NC}"; sleep 1 ;;
			2) CUSTOM_IP="50.7.5.83"; echo "$CUSTOM_IP" > "$CUSTOM_IP_FILE"; echo -e "  ${GREEN}IP Updated.${NC}"; sleep 1 ;;
			3) CUSTOM_IP="63.141.252.203"; echo "$CUSTOM_IP" > "$CUSTOM_IP_FILE"; echo -e "  ${GREEN}IP Updated.${NC}"; sleep 1 ;;
			4) CUSTOM_IP="94.130.50.12"; echo "$CUSTOM_IP" > "$CUSTOM_IP_FILE"; echo -e "  ${GREEN}IP Updated.${NC}"; sleep 1 ;;
			5)
				read -rp "  IP Address: " _ip
				if [[ "$_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
					CUSTOM_IP="$_ip"
					echo "$_ip" > "$CUSTOM_IP_FILE"
					echo -e "  ${GREEN}Saved.${NC}"
				else
					echo -e "  ${RED}Invalid IP format.${NC}"
				fi
				sleep 1
				;;
			0) break ;;
		esac
	done
}

# ==================== KEEPALIVE MENU ====================
configure_keepalive_menu() {
	while true; do
		clear; draw_logo
		echo -e "  ${GREEN}⏳ Keepalive Control${NC}"
		echo -e "  ${GREEN}──────────────────────────────────────────────${NC}"
		echo -e "  Status: $(keepalive_status)"
		if [ -f "$KEEPALIVE_CONF" ]; then
			echo -e "  Current Interval: ${WHITE}$(( $(cat "$KEEPALIVE_CONF") / 60 )) min${NC}"
		fi
		echo ""
		echo -e "  ${WHITE}1)${NC} Set Custom Interval (minutes)"
		echo -e "  ${WHITE}2)${NC} Profile: Aggressive (30 sec)"
		echo -e "  ${GREEN}3)${NC} Profile: Normal (1 min) ${GREEN}[Recommended]${NC}"
		echo -e "  ${WHITE}4)${NC} Profile: Economy (3 min)"
		echo -e "  ${GREEN}5)${NC} Start Keepalive"
		echo -e "  ${RED}6)${NC} Stop Keepalive"
		echo -e "  ${WHITE}0)${NC} Go Back\n"
		read -rp "  Select: " kc
		case $kc in
			1)
				read -rp "  Minutes: " _mins
				if [[ "$_mins" =~ ^[0-9]+$ ]]; then
					start_keepalive $((_mins * 60))
					echo -e "  ${GREEN}Started.${NC}"
				else
					echo -e "  ${RED}Invalid input.${NC}"
				fi
				sleep 1
				;;
			2) start_keepalive 30;  echo -e "  ${GREEN}Started.${NC}"; sleep 1 ;;
			3) start_keepalive 60;  echo -e "  ${GREEN}Started.${NC}"; sleep 1 ;;
			4) start_keepalive 180; echo -e "  ${GREEN}Started.${NC}"; sleep 1 ;;
			5) start_keepalive "$(cat "$KEEPALIVE_CONF" 2>/dev/null || echo 60)"; echo -e "  ${GREEN}Started.${NC}"; sleep 1 ;;
			6) stop_keepalive ;;
			0) break ;;
		esac
	done
}

# ==================== PROTOCOL MENU ====================
select_protocol_menu() {
	while true; do
		clear; draw_logo
		local CUR; CUR=$(get_protocol)
		echo -e "  ${GREEN}🔌 Protocol Selection${NC}"
		echo -e "  ${GREEN}──────────────────────────────────────────────${NC}"
		echo -e "  Current: ${WHITE}${CUR}${NC}\n"
		echo -e "  ${GREEN}1)${NC} XHTTP (packet-up)   ${DIM}← High stealth, HTTP/2, anti-DPI${NC}"
		echo -e "  ${WHITE}2)${NC} WebSocket (WS)       ${DIM}← Low ping, universal app support${NC}"
		echo -e "  ${WHITE}3)${NC} Both (XHTTP+WS)      ${DIM}← XHTTP on :443 & WS on :8080${NC}"
		echo -e "  ${WHITE}0)${NC} Go Back\n"
		echo -e "  ${YELLOW}⚠  After changing, use option 2 (Generate New Config).${NC}\n"
		read -rp "  Select: " pc
		case $pc in
			1) echo "xhttp" > "$PROTOCOL_CONF"; echo -e "  ${GREEN}Set to XHTTP.${NC}"; sleep 1 ;;
			2) echo "ws"    > "$PROTOCOL_CONF"; echo -e "  ${GREEN}Set to WebSocket.${NC}"; sleep 1 ;;
			3) echo "both"  > "$PROTOCOL_CONF"; echo -e "  ${GREEN}Set to Both (XHTTP+WS).${NC}"; sleep 1 ;;
			0) break ;;
			*) echo -e "  ${RED}Invalid option.${NC}"; sleep 1 ;;
		esac
	done
}

# ==================== SILENT START ====================
if [ "${1:-}" = "--silent-start" ]; then
	# First run: no config exists — generate it automatically
	if [ ! -f "$CONFIG_FILE" ]; then
		echo "both" > "$PROTOCOL_CONF"
		generate_config
		start_xray
		wait_for_port > /dev/null 2>&1
		ensure_all_ports_public
		# Generate VLESS links and save to mobile file
		mapfile -t _AUTO_LINKS < <(generate_links 2>/dev/null)
		if [ ${#_AUTO_LINKS[@]} -gt 0 ]; then
			printf '%s\n' "${_AUTO_LINKS[@]#*|}" > "$MOBILE_CONFIG_FILE"
		fi
	else
		# Config exists — just restart xray
		start_xray
		wait_for_port > /dev/null 2>&1
		ensure_all_ports_public
	fi
	# Start config server for VPS orchestrator
	start_config_server
	# Start keepalive
	if ! kill -0 "$(cat "$KEEPALIVE_PID" 2>/dev/null)" 2>/dev/null; then
		_interval=$(cat "$KEEPALIVE_CONF" 2>/dev/null || echo 60)
		start_keepalive "$_interval"
	fi
	exit 0
fi

trap 'echo -e "\nGoodbye."; exit 0' EXIT INT TERM

if ! kill -0 "$(cat "$KEEPALIVE_PID" 2>/dev/null)" 2>/dev/null; then
	_interval=$(cat "$KEEPALIVE_CONF" 2>/dev/null || echo 60)
	start_keepalive "$_interval" >/dev/null
fi

if [ ! -f "$CONFIG_FILE" ]; then
	clear; draw_logo
	echo -e "  ${WHITE}Welcome to G-Tunnel Setup!${NC}"
	echo -e "  ${DIM}No configuration found — first run detected.${NC}\n"
	echo -e "  Protocol: ${GREEN}both${NC} ${DIM}(XHTTP + WebSocket — default)${NC}\n"
	echo -e "  ${GREEN}1)${NC} Generate Config & Start Engine"
	echo -e "  ${WHITE}2)${NC} Exit\n"
	read -rp "  Select: " _setup
	if [ "$_setup" = "1" ]; then
		echo "both" > "$PROTOCOL_CONF"
		generate_config
		echo -e "\n  ${GREEN}Setup complete!${NC}"
		sleep 1
	else
		exit 0
	fi
elif ! pgrep -f "$XRAY_BIN run" > /dev/null; then
	start_xray
	wait_for_port >/dev/null 2>&1
	ensure_all_ports_public
fi

# ==================== AUTO-SHOW LINKS ON ATTACH ====================
_auto_show_links() {
	clear; draw_logo
	echo -e "  ${GREEN}🔗 Active Connection Links${NC}"
	echo -e "  ${DIM}Protocol: $(get_protocol) | Engine: Running${NC}\n"
	mapfile -t _AL < <(generate_links 2>/dev/null)
	if [ ${#_AL[@]} -eq 0 ]; then
		echo -e "  ${YELLOW}No links available. Try Generate New Config (option 2).${NC}\n"
		return
	fi
	printf '%s\n' "${_AL[@]#*|}" > "$MOBILE_CONFIG_FILE"
	for _E in "${_AL[@]}"; do
		_T="${_E%%|*}"; _L="${_E#*|}"
		echo -e "  ${YELLOW}── ${_T} ──────────────────────────────────────────${NC}"
		if command -v qrencode >/dev/null 2>&1; then
			qrencode -t ANSIUTF8 "$_L" | sed 's/^/  /'
		fi
		echo -e "\n  ${WHITE}${_L}${NC}\n"
	done
	echo -e "  ${GREEN}📱 Saved to:${NC} ${DIM}${MOBILE_CONFIG_FILE}${NC}"
	echo -e "  ${GREEN}──────────────────────────────────────────────────────${NC}"
	# Start HTTP config server and show URL for VPS orchestrator
	start_config_server
	if [ -f "$CONFIG_SERVER_URL_FILE" ]; then
		echo -e "  ${GREEN}🌐 VPS Config URL:${NC}"
		echo -e "  ${YELLOW}$(cat "$CONFIG_SERVER_URL_FILE")${NC}"
		echo -e "  ${DIM}(Use this URL in the VPS orchestrator settings.json)${NC}"
	fi
	echo -e "  ${GREEN}──────────────────────────────────────────────────────${NC}"
	echo -e "  ${DIM}Press Enter to open main menu...${NC}"
	read -r
}
_auto_show_links

# ==================== MAIN LOOP ====================
while true; do
	clear
	draw_logo
	if pgrep -f "$XRAY_BIN run" > /dev/null; then
		_STATUS="${GREEN}▶ RUNNING${NC}"
	else
		_STATUS="${RED}■ STOPPED${NC}"
	fi
	_KA_STAT=$(keepalive_status)
	echo -e "${GREEN}┌────────────────────────────────────────────────────────┐${NC}"
	echo -e "${GREEN}│${NC} Engine: $_STATUS      ${GREEN}│${NC} Keepalive: $_KA_STAT             ${GREEN}│${NC}"
	echo -e "${GREEN}└────────────────────────────────────────────────────────┘${NC}"
	echo -e "${YELLOW}  🚀 Core Controls${NC}"
	echo -e "  ${GREEN}1)${NC} View Config & QR Code"
	echo -e "  ${WHITE}2)${NC} Generate New Config"
	echo -e "  ${WHITE}3)${NC} Start Engine"
	echo -e "  ${WHITE}4)${NC} Stop Engine"
	echo -e "  ${WHITE}5)${NC} Restart Engine"
	echo ""
	echo -e "${YELLOW}  ⚙️  Configuration${NC}"
	echo -e "  ${WHITE}6)${NC} Multi-IP / CDN Routing"
	echo -e "  ${WHITE}7)${NC} Keepalive Settings"
	echo -e "  ${WHITE}8)${NC} Protocol Selection  ${DIM}[$(get_protocol)]${NC}"
	echo ""
	echo -e "${YELLOW}  📊 Analytics & Tools${NC}"
	echo -e "  ${WHITE}9)${NC}  Data Usage"
	echo -e "  ${WHITE}10)${NC} Resource Stats"
	echo -e "  ${WHITE}11)${NC} Quota & Uptime"
	echo -e "  ${WHITE}12)${NC} Server Location"
	echo -e "  ${WHITE}13)${NC} View Engine Logs"
	echo ""
	echo -e "  ${RED}0)${NC} Exit Panel"
	echo -e "${GREEN}──────────────────────────────────────────────────────────${NC}"
	read -rp "  Select an option [0-13]: " _choice
	case $_choice in
		1)
			check_port_visibility || continue
			mapfile -t _LINKS < <(generate_links 2>/dev/null)
			[ ${#_LINKS[@]} -eq 0 ] && { echo -e "${RED}Error generating link${NC}"; sleep 2; continue; }
			# Save all links to mobile file
			printf '%s\n' "${_LINKS[@]#*|}" > "$MOBILE_CONFIG_FILE"
			clear; draw_logo
			echo -e "  ${GREEN}🔗 Your Connection Links${NC}\n"
			for _ENTRY in "${_LINKS[@]}"; do
				_TYPE="${_ENTRY%%|*}"
				_LINK="${_ENTRY#*|}"
				echo -e "  ${YELLOW}── ${_TYPE} ──────────────────────────────────${NC}"
				if command -v qrencode >/dev/null 2>&1; then
					qrencode -t ANSIUTF8 "$_LINK" | sed 's/^/  /'
				else
					echo -e "  ${DIM}(qrencode not installed)${NC}"
				fi
				echo -e "\n  ${GREEN}Link:${NC}"
				echo -e "  ${WHITE}${_LINK}${NC}\n"
			done
			echo -e "  ${YELLOW}──────────────────────────────────────────────${NC}"
			echo -e "  ${GREEN}📱 All links saved to:${NC} ${WHITE}${MOBILE_CONFIG_FILE}${NC}"
			echo -e "  ${YELLOW}──────────────────────────────────────────────${NC}\n"
			read -rp "  Press Enter to return..."
			;;
		2)
			clear; draw_logo
			echo -e "  ${WHITE}This will overwrite your current config and restart the engine.${NC}"
			read -rp "  Proceed? (y/n): " _confirm
			if [[ "$_confirm" =~ ^[Yy]$ ]]; then
				generate_config
				sleep 1
			fi
			;;
		3)
			clear; draw_logo
			if pgrep -f "$XRAY_BIN run" >/dev/null; then
				echo -e "  ${WHITE}Engine is already running.${NC}"
			else
				start_xray
				wait_for_port
				ensure_codespace_port_public
			fi
			sleep 1
			;;
		4)
			clear; draw_logo
			sudo pkill -f "$XRAY_BIN run" 2>/dev/null || true
			echo -e "  ${RED}Engine stopped.${NC}"
			sleep 1
			;;
		5)
			clear; draw_logo
			start_xray
			wait_for_port
			ensure_all_ports_public
			sleep 1
			;;
		6) multi_ip_menu ;;
		7) configure_keepalive_menu ;;
		8) select_protocol_menu ;;
		9)
			clear; draw_logo
			echo -e "${GREEN}📡 G-Tunnel Data Usage${NC}\n"
			if pgrep -f "$XRAY_BIN run" > /dev/null; then
				STATS=$(sudo "$XRAY_BIN" api statsquery -server=127.0.0.1:10085 2>/dev/null || echo "")
				if [ -n "$STATS" ]; then
					DOWN=$(echo "$STATS" | grep -A 1 'downlink' | grep 'value' | grep -oE '[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?' | awk '{s+=$1} END {printf "%.0f", s+0}')
					UP=$(echo "$STATS" | grep -A 1 'uplink' | grep 'value' | grep -oE '[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?' | awk '{s+=$1} END {printf "%.0f", s+0}')
					DOWN=${DOWN:-0}
					UP=${UP:-0}
					IS_ZERO=$(awk -v d="$DOWN" -v u="$UP" 'BEGIN {print (d==0 && u==0) ? "yes" : "no"}')
					if [ "$IS_ZERO" = "yes" ]; then
						echo -e "  ${DIM}No traffic data recorded yet. Browse the web to generate traffic.${NC}"
					else
						DOWN_FMT=$(format_bytes "$DOWN")
						UP_FMT=$(format_bytes "$UP")
						TOTAL=$(awk -v d="$DOWN" -v u="$UP" 'BEGIN {printf "%.0f", d+u}')
						TOTAL_FMT=$(format_bytes "$TOTAL")
						echo -e "  Traffic from Connected Clients:"
						echo -e "  ────────────────────────────────────────"
						echo -e "  Download (RX):  ${WHITE}${DOWN_FMT}${NC}"
						echo -e "  Upload (TX):    ${WHITE}${UP_FMT}${NC}"
						echo -e "  Total Traffic:  ${GREEN}${TOTAL_FMT}${NC}"
						echo -e "  ────────────────────────────────────────"
					fi
				else
					echo -e "  ${DIM}No traffic data recorded yet. Browse the web to generate traffic.${NC}"
				fi
			else
				echo -e "  ${RED}Engine is offline. Start the engine to view stats.${NC}"
			fi
			echo ""
			read -rp "  Press Enter to return..."
			;;
		10) show_resource_stats ;;
		11)
			clear; draw_logo
			echo -e "${GREEN}⏱️ Codespace Quota & Uptime${NC}\n"
			estimate_quota
			echo ""
			read -rp "  Press Enter to return..."
			;;
		12)
			clear; draw_logo
			echo -e "  ${DIM}Fetching server details...${NC}\n"
			if command -v jq >/dev/null 2>&1; then
				_RES=$(curl -s --max-time 5 https://ipinfo.io/json 2>/dev/null || echo "{}")
				_IP=$(echo "$_RES" | jq -r '.ip // empty')
				if [ -z "$_IP" ]; then
					echo -e "  ${RED}Could not fetch location.${NC}"
				else
					echo -e "  IP:       ${GREEN}$(echo "$_RES" | jq -r '.ip')${NC}"
					echo -e "  Location: ${WHITE}$(echo "$_RES" | jq -r '.city'), $(echo "$_RES" | jq -r '.country')${NC}"
					echo -e "  ISP/Host: ${WHITE}$(echo "$_RES" | jq -r '.org')${NC}"
				fi
			else
				echo -e "  ${RED}jq not installed - cannot parse location data${NC}"
			fi
			echo ""
			read -rp "  Press Enter to return..."
			;;
		13)
			clear; draw_logo
			echo -e "${GREEN}📜 Live Engine Logs (Last 15 Lines)${NC}"
			echo -e "${GREEN}──────────────────────────────────────────────${NC}"
			if [ -f "$LOG_DIR/xray.log" ]; then
				tail -n 15 "$LOG_DIR/xray.log" | sed 's/^/  /'
			else
				echo -e "  ${DIM}Log file is empty or missing.${NC}"
			fi
			echo -e "\n  ${WHITE}(Note: Log level is 'warning', so empty logs mean no errors!)${NC}"
			echo ""
			read -rp "  Press Enter to return..."
			;;
		0) echo -e "\n  Exiting G-Tunnel Panel..."; exit 0 ;;
		*) echo -e "  ${RED}Invalid option.${NC}"; sleep 1 ;;
	esac
done
