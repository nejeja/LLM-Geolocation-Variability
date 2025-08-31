#!/usr/bin/env bash
# vpn_switch.sh — robust geolocation switcher for the LLM geo-variability study
# Supports ProtonVPN CLI (official 'protonvpn-cli' or pip 'protonvpn'),
# Surfshark OpenVPN configs, and WireGuard profiles.
# vpn_switch.sh — robustní přepínač geolokace pro studii geografické variability LLM
# Podporuje ProtonVPN CLI (oficiální „protonvpn-cli“ nebo pip „protonvpn“),
# konfigurace Surfshark OpenVPN a profily WireGuard.
# Usage: ./vpn_switch.sh <node-id>
# Nodes: vpn-eu-1 | vpn-us-1 | vpn-br-1 | vpn-cn-1 | vpn-ir-1 | vpn-ru-1
# Exit: prints "[VPN] <node> -> <IP> (<Country>) via <method>"

set -euo pipefail
[[ "${VPN_DEBUG:-0}" = "1" ]] && set -x

# --- Tunables (override via env) ---
CONNECT_SETTLE_S=${CONNECT_SETTLE_S:-4}
VERIFY_TRIES=${VERIFY_TRIES:-30}
VERIFY_INTERVAL_S=${VERIFY_INTERVAL_S:-2}
PROTON_WAIT_TRIES=${PROTON_WAIT_TRIES:-30}
PROTON_WAIT_INTERVAL_S=${PROTON_WAIT_INTERVAL_S:-1}
CURL_MAX_TIME=${CURL_MAX_TIME:-3}
CURL_RETRY=${CURL_RETRY:-2}
CURL_RETRY_DELAY=${CURL_RETRY_DELAY:-1}
VPN_CHECK_DNS=${VPN_CHECK_DNS:-0}

# --- RU "no-verify" režim (volitelný) ---
RU_SKIP_VERIFY=${RU_SKIP_VERIFY:-0}   # 1 = Do not verify geo at all for RU;u RU neověřovat geo vůbec
RU_WAIT_S=${RU_WAIT_S:-10}            # how many seconds to wait passively after connecting;kolik sekund jen pasivně čekat po connectu


# --- sudo keepalive ---
sudo -v || { echo "ERROR: sudo auth failed" >&2; exit 1; }
( set +x; while true; do sleep 50; sudo -n true >/dev/null 2>&1 || exit; done ) >/dev/null 2>&1 &
SUDO_KEEPALIVE_PID=$!
trap 'kill $SUDO_KEEPALIVE_PID 2>/dev/null || true' EXIT

NODE=${1:?node_id required}

# --- Proton CLI autodetekce ---
if command -v protonvpn-cli >/dev/null 2>&1; then
  PVN_BIN="protonvpn-cli"
  p_disconnect() { protonvpn-cli d >/dev/null 2>&1 || true; }
  p_connect_cc() { protonvpn-cli c --cc "$1" -p udp >/dev/null; }
elif command -v protonvpn >/dev/null 2>&1; then
  PVN_BIN="protonvpn"   # pip varianta
  p_disconnect() { protonvpn d >/dev/null 2>&1 || true; }
  p_connect_cc() { protonvpn c -f -p udp -c "$1" >/dev/null; }
else
  PVN_BIN=""
  p_disconnect() { true; }
  p_connect_cc() { echo "No Proton CLI installed" >&2; return 1; }
fi

# ---paths / settings; cesty / nastavení ---
CONF_DIR="/etc/openvpn/surfshark"
CREDS="$CONF_DIR/credentials"
WG_PREFIX=""
CURL_OPTS=( -fsS --max-time "$CURL_MAX_TIME" --retry "$CURL_RETRY" --retry-delay "$CURL_RETRY_DELAY" )

# --- helpers ---
have() { command -v "$1" >/dev/null 2>&1; }
say()  { printf "%s\n" "$*"; }
die()  { printf "ERROR: %s\n" "$*" >&2; exit 1; }

normalize_country() {
  case "${1^^}" in
    US) echo "United States" ;;
    BR) echo "Brazil" ;;
    CZ|CZE) echo "Czechia" ;;
    DE|DEU) echo "Germany" ;;
    RU|RUS) echo "Russian Federation" ;;
    HK|HKG) echo "Hong Kong" ;;
    SG|SGP) echo "Singapore" ;;
    AE|ARE) echo "United Arab Emirates" ;;
    IR|IRN) echo "Iran" ;;
    CN|CHN) echo "China" ;;
    *) echo "$1" ;;
  esac
}

disconnect_all() {
  p_disconnect
  sudo killall -q openvpn  >/dev/null 2>&1 || true
  for IF in wg-eu-1 wg-us-1 wg-br-1 wg-hk-1 wg-ae-1 wg-ru-1; do
    sudo wg-quick down "$IF" >/dev/null 2>&1 || true
  done
}

ip_country() {
  local ip="" ct="" raw=""
  ip=$(curl "${CURL_OPTS[@]}" https://ifconfig.co/ip 2>/dev/null || true)
  ct=$(curl "${CURL_OPTS[@]}" https://ifconfig.co/country 2>/dev/null || true)
  if [[ -n "$ip" && -n "$ct" ]]; then printf "%s|%s" "$ip" "$ct"; return 0; fi

  ip=$(curl "${CURL_OPTS[@]}" https://ipapi.co/ip 2>/dev/null || true)
  ct=$(curl "${CURL_OPTS[@]}" https://ipapi.co/country_name 2>/dev/null || true)
  if [[ -n "$ip" && -n "$ct" ]]; then printf "%s|%s" "$ip" "$ct"; return 0; fi

  ip=$(curl "${CURL_OPTS[@]}" https://ipinfo.io/ip 2>/dev/null || true)
  raw=$(curl "${CURL_OPTS[@]}" https://ipinfo.io/country 2>/dev/null || true)
  ct=$(normalize_country "$raw")
  if [[ -n "$ip" && -n "$ct" ]]; then printf "%s|%s" "$ip" "$ct"; return 0; fi

  ip=$(curl "${CURL_OPTS[@]}" https://ident.me 2>/dev/null || true)
  ct=$(curl "${CURL_OPTS[@]}" https://ipapi.co/country_name 2>/dev/null || true)
  if [[ -n "$ip" && -n "$ct" ]]; then printf "%s|%s" "$ip" "$ct"; return 0; fi

  printf "|"
  return 1
}

dns_leak_check() {
  local stub ok1 ok2 dnsline domline
  stub=$(grep -Ec '^\s*nameserver 127\.0\.0\.53\s*$' /etc/resolv.conf || true)
  dnsline=$(resolvectl dns 2>/dev/null | sed -n 's/.*proton0: *//p' | head -n1)
  domline=$(resolvectl domain 2>/dev/null | sed -n 's/.*proton0: *//p' | head -n1)
  [[ "$stub" = "1" ]] && ok1="yes" || ok1="no"
  [[ -n "$dnsline" ]] && ok2="yes" || ok2="no"

  if [[ "$ok1" = "yes" && "$ok2" = "yes" && "$domline" = "~." ]]; then
    echo "[DNS] OK (stub=127.0.0.53, proton0 DNS=$dnsline, domain=$domline)"
    return 0
  else
    echo "[DNS] WARN (stub_ok=$ok1, proton_dns='${dnsline:-}', domain='${domline:-}')"
    return 1
  fi
}

wait_for_change_and_verify() {
  local prev_ip="$1"; shift
  local -a allow_countries=( "$@" )
  local tries=${VERIFY_TRIES}
  local ip ct
  while (( tries-- > 0 )); do
    IFS="|" read -r ip ct < <(ip_country)
    if [[ -n "$ip" && "$ip" != "$prev_ip" ]]; then
      if [[ ${#allow_countries[@]} -eq 0 ]]; then
        echo "$ip|$ct"; return 0
      fi
      for a in "${allow_countries[@]}"; do
        [[ "$ct" == "$a" ]] && { echo "$ip|$ct"; return 0; }
      done
    fi
    sleep "${VERIFY_INTERVAL_S}"
  done
  IFS="|" read -r ip ct < <(ip_country)
  echo "$ip|$ct"
  return 1
}

wait_proton_connected() {
  local tries=${PROTON_WAIT_TRIES}
  local s
  while (( tries-- > 0 )); do
    s=$(protonvpn-cli s 2>/dev/null || true)
    if echo "$s" | grep -qi 'Proton VPN Connection Status' && echo "$s" | grep -qi 'Protocol'; then
      for expect in "$@"; do
        if echo "$s" | grep -qi "Country: *$expect"; then
          return 0
        fi
      done
    fi
    sleep "${PROTON_WAIT_INTERVAL_S}"
  done
  return 1
}

connect_proton_cc() {
  local cc="$1"
  [[ -n "$PVN_BIN" ]] || die "Proton CLI not installed"
  p_connect_cc "$cc"
}

connect_openvpn_conf() {
  local ovpn="$1"
  [[ -r "$ovpn" ]] || die "OpenVPN config not found: $ovpn"
  sudo test -r "$CREDS" || die "OpenVPN credentials not found: $CREDS"
  say "[VPN] dialing OpenVPN: ${ovpn##*/}"
  sudo openvpn --config "$ovpn" --auth-user-pass "$CREDS" --daemon
}

connect_wg_iface() {
  local iface="$1"
  [[ -n "$iface" ]] || die "WireGuard iface missing"
  sudo wg-quick up "$iface"
}

# --- node mapping;mapování uzlů ---
method=""
target=""
expected=()   # array

case "$NODE" in
  vpn-eu-1) method="openvpn"; target="$CONF_DIR/de-fra.prod.surfshark.com_udp.ovpn"; expected=("Germany" "Czechia");; 
  vpn-us-1) method="openvpn"; target="$CONF_DIR/us-nyc.prod.surfshark.com_udp.ovpn";  expected=("United States");;  
  vpn-br-1) method="openvpn"; target="$CONF_DIR/br-sao.prod.surfshark.com_udp.ovpn"; expected=("Brazil");;    
  vpn-cn-1) method="openvpn"; target="$CONF_DIR/hk-hkg.prod.surfshark.com_udp.ovpn"; expected=("Hong Kong" "China");; 
  vpn-ir-1) method="openvpn"; target="$CONF_DIR/ae-dub.prod.surfshark.com_udp.ovpn"; expected=("United Arab Emirates" "Iran");; 
  vpn-ru-1) method="proton";  target="RU"; expected=("Russia" "Russian Federation" "RU");;  # jediný Proton
  *) die "unknown node '$NODE'";;
esac

# ---------- run;běh ----------
prev_ip=$(curl "${CURL_OPTS[@]}" https://ifconfig.co/ip || true)
disconnect_all
sleep 1

ok=0
used=""

if [[ "$method" == "proton" ]]; then
    if [[ -n "$PVN_BIN" ]]; then
      #optional RU mode without verification (only waits for RU_WAIT_S);volitelný RU režim bez ověřování (jen čeká RU_WAIT_S)
      if connect_proton_cc "$target"; then
        used="proton:$target"; ok=1
        if [[ "$NODE" == "vpn-ru-1" && "$RU_SKIP_VERIFY" = "1" ]]; then
          sleep "$RU_WAIT_S"
        else
          if ! wait_proton_connected "${expected[@]}"; then
            say "[VPN] WARN: Proton not yet reporting expected country; continuing anyway"
          fi
        fi
      fi
    fi

elif [[ "$method" == "openvpn" ]]; then
  #  Always OpenVPN for everyone else;Vždy OpenVPN pro všechny ostatní
  if [[ -f "$target" ]]; then
    connect_openvpn_conf "$target"; used="openvpn:${target##*/}"; ok=1
  fi
fi

# ---------- Final verification ----------
if [[ "$NODE" == "vpn-ru-1" && "$RU_SKIP_VERIFY" = "1" ]]; then
  out="$(ip_country || true)"
  IFS="|" read -r new_ip new_ct <<< "${out:-|}"
  [[ -z "${new_ip:-}" ]] && new_ip="?"
  [[ -z "${new_ct:-}" ]] && new_ct="unknown"
  [[ "${VPN_CHECK_DNS}" = "1" ]] && dns_leak_check || true
  say "[VPN] $NODE -> $new_ip (${new_ct}) via ${used:-unknown}"
else
  # standard authentication for all other nodes;standardní ověřování pro všechny ostatní uzly
  set +e
  out=$(wait_for_change_and_verify "$prev_ip" "${expected[@]}")
  set -e
  IFS="|" read -r new_ip new_ct <<< "${out:-|}"
  if [[ -z "${new_ip:-}" ]]; then
    die "could not obtain public IP"
  fi
  if [[ "${VPN_CHECK_DNS}" = "1" ]]; then
    dns_leak_check || true
  fi
  match=0
  for a in "${expected[@]:-}"; do
    [[ "$new_ct" == "$a" ]] && match=1 && break
  done
  if [[ $match -eq 0 ]]; then
    say "[VPN] WARN: expected one of: ${expected[*]:-(any)}, got: '${new_ct:-}'"
  fi
  say "[VPN] $NODE -> $new_ip (${new_ct:-unknown}) via ${used:-unknown}"
fi

