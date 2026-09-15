#!/bin/sh
set -eu

# Game V2 cy507 OpenWrt installer 1.3.0.
# Run from the generated package directory containing enrollment.env,
# speederv2 and udp2raw. Fresh/rebuild installs only.

VERSION="1.3.0"
CLIENT_ID="cy507"
SERVER_ENDPOINT="91.223.119.134"
SERVER_WG_IP="10.77.2.1"
CLIENT_WG_ADDR="10.77.2.2/30"
WG_IF="gv2_cy507"
SERVER_SPEEDERV2_PORT="40972"
CLIENT_SPEEDERV2_PORT="30972"
FAKETCP_LOCAL_PORT="31972"
GAME_DEVICE_IP="192.168.50.126"
GAME_DEVICE_PORT="3074"
ROUTE_CIDR="192.168.50.0/24"
ROUTE_TABLE="51872"
ROLLBACK_SECONDS="900"

SELF_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ENROLLMENT="$SELF_DIR/enrollment.env"
STATE_DIR="/etc/game-v2/cy507"
INSTALL_DIR="/usr/local/lib/game-v2-cy507"
BACKUP_ROOT="/root/game-v2-cy507-backups"
ACTIVE_TXN="$STATE_DIR/active-transaction"
PROFILE_INIT="/etc/init.d/game-v2-cy507"
FAKETCP_INIT="/etc/init.d/game-v2-cy507-faketcp"
DNS_RULE="/usr/share/nftables.d/chain-pre/dstnat/10-game-v2-cy507-dns.nft"
NO_SNAT_RULE="/usr/share/nftables.d/chain-pre/srcnat/10-game-v2-cy507-fixed-bridge.nft"
INBOUND_RULE="/usr/share/nftables.d/chain-pre/forward/10-game-v2-cy507-inbound-3074.nft"

say() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1"; }

usage() {
  cat <<'EOF'
Usage:
  ./install.sh preflight
  ./install.sh apply
  ./install.sh verify
  ./install.sh status
  ./install.sh commit
  ./install.sh rollback

apply is for a fresh/rebuild installation only and refuses an existing cy507
target. It backs up the two UCI config files, arms a detached 15-minute local
rollback, applies the package and verifies it. Validate from a new management
session and on Xbox, then run commit before the deadline.
EOF
}

require_root() {
  [ "$(id -u)" -eq 0 ] || die "run as root"
}

load_enrollment() {
  [ -s "$ENROLLMENT" ] || die "missing enrollment.env beside install.sh"
  # shellcheck disable=SC1090
  . "$ENROLLMENT"
  [ "${CLIENT_ID:-}" = "cy507" ] || die "enrollment client_id mismatch"
  [ "${SERVER_ENDPOINT:-}" = "91.223.119.134" ] || die "enrollment endpoint mismatch"
  [ -n "${SERVER_PUBLIC_KEY:-}" ] || die "SERVER_PUBLIC_KEY is missing"
  [ -n "${CLIENT_PRIVATE_KEY:-}" ] || die "CLIENT_PRIVATE_KEY is missing"
  [ -n "${SPEEDERV2_KEY:-}" ] || die "SPEEDERV2_KEY is missing"
}

require_dependencies() {
  for cmd in awk chmod cp date grep id ifdown ifup ip mkdir nft nslookup sed setsid ss ubus uci wg; do
    need "$cmd"
  done
  [ -x /etc/init.d/network ] || die "OpenWrt network service missing"
  [ -x /etc/init.d/firewall ] || die "OpenWrt firewall service missing"
  [ -x "$SELF_DIR/speederv2" ] || die "speederv2 missing or not executable"
  [ -x "$SELF_DIR/udp2raw" ] || die "udp2raw missing or not executable"
}

assert_platform() {
  [ -r /etc/openwrt_release ] || die "this package requires OpenWrt"
  case "$(uname -m)" in
    x86_64|amd64) ;;
    *) die "unsupported architecture: $(uname -m)" ;;
  esac
}

assert_fresh() {
  [ ! -e "$STATE_DIR" ] || die "existing cy507 state found: $STATE_DIR"
  [ ! -e "$INSTALL_DIR" ] || die "existing cy507 install found: $INSTALL_DIR"
  [ ! -e "$PROFILE_INIT" ] || die "existing cy507 profile service found"
  [ ! -e "$FAKETCP_INIT" ] || die "existing cy507 FakeTCP service found"
  [ ! -e "$DNS_RULE" ] || die "existing cy507 DNS rule found"
  [ ! -e "$NO_SNAT_RULE" ] || die "existing cy507 NAT rule found"
  [ ! -e "$INBOUND_RULE" ] || die "existing cy507 inbound rule found"
  ! uci -q get network.gv2_cy507 >/dev/null 2>&1 || die "existing network.gv2_cy507 found"
  ! uci -q get network.gv2p_cy507 >/dev/null 2>&1 || die "existing network.gv2p_cy507 found"
  ! uci -q get firewall.game_v2_cy507 >/dev/null 2>&1 || die "existing firewall.game_v2_cy507 found"
  ! uci -q get firewall.lan_to_game_v2_cy507 >/dev/null 2>&1 || die "existing cy507 outbound forwarding found"
  ! uci -q get firewall.game_v2_cy507_to_lan >/dev/null 2>&1 || die "existing cy507 forwarding found"
  ! ip link show "$WG_IF" >/dev/null 2>&1 || die "existing interface found: $WG_IF"
  ! ip rule show | grep -Eq '^(9999|10000):' || die "policy rule priority 9999 or 10000 is already in use"
  ! ip route show table "$ROUTE_TABLE" 2>/dev/null | grep -q . || die "route table $ROUTE_TABLE is already in use"
  ! ss -H -lnu "sport = :$CLIENT_SPEEDERV2_PORT" 2>/dev/null | grep -q . || die "UDP $CLIENT_SPEEDERV2_PORT is already in use"
  ! ss -H -lnt "sport = :$FAKETCP_LOCAL_PORT" 2>/dev/null | grep -q . || die "TCP $FAKETCP_LOCAL_PORT is already in use"
}

preflight() {
  require_root
  assert_platform
  load_enrollment
  require_dependencies
  assert_fresh
  ip route get "$SERVER_ENDPOINT" | grep -q . || die "no route to VPS endpoint"
  say "preflight passed: fresh cy507 OpenWrt target"
}

write_rollback_script() {
  backup_dir="$1"
  cat >"$backup_dir/rollback.sh" <<EOF
#!/bin/sh
set -u
/etc/init.d/game-v2-cy507 stop >/dev/null 2>&1 || true
/etc/init.d/game-v2-cy507 disable >/dev/null 2>&1 || true
/etc/init.d/game-v2-cy507-faketcp stop >/dev/null 2>&1 || true
/etc/init.d/game-v2-cy507-faketcp disable >/dev/null 2>&1 || true
rm -f '$PROFILE_INIT' '$FAKETCP_INIT'
rm -f '$DNS_RULE' '$NO_SNAT_RULE' '$INBOUND_RULE'
rm -rf '$INSTALL_DIR'
if [ -f '$backup_dir/network' ]; then cp '$backup_dir/network' /etc/config/network; fi
if [ -f '$backup_dir/firewall' ]; then cp '$backup_dir/firewall' /etc/config/firewall; fi
/etc/init.d/network reload >/dev/null 2>&1 || true
/etc/init.d/firewall reload >/dev/null 2>&1 || true
rm -rf '$STATE_DIR'
exit 0
EOF
  chmod 700 "$backup_dir/rollback.sh"
  cat >"$backup_dir/timer.sh" <<EOF
#!/bin/sh
sleep $ROLLBACK_SECONDS
[ ! -e '$backup_dir/rollback.pending' ] || exec /bin/sh '$backup_dir/rollback.sh'
EOF
  chmod 700 "$backup_dir/timer.sh"
}

arm_rollback() {
  backup_dir="$1"
  : >"$backup_dir/rollback.pending"
  setsid "$backup_dir/timer.sh" >"$backup_dir/timer.log" 2>&1 </dev/null &
  printf '%s\n' "$!" >"$backup_dir/timer.pid"
}

write_runtime_files() {
  mkdir -p "$STATE_DIR" "$INSTALL_DIR"
  chmod 700 "$STATE_DIR"
  chmod 755 "$INSTALL_DIR"
  cp "$SELF_DIR/speederv2" "$INSTALL_DIR/speederv2"
  cp "$SELF_DIR/udp2raw" "$INSTALL_DIR/udp2raw"
  chmod 755 "$INSTALL_DIR/speederv2" "$INSTALL_DIR/udp2raw"
  umask 077
  cat >"$STATE_DIR/profile.env" <<EOF
SERVER_ENDPOINT='$SERVER_ENDPOINT'
SPEEDERV2_KEY='$SPEEDERV2_KEY'
EOF
  chmod 600 "$STATE_DIR/profile.env"
  umask 022

  cat >"$INSTALL_DIR/run-faketcp.sh" <<'EOF'
#!/bin/sh
set -eu
. /etc/game-v2/cy507/profile.env
runtime=/var/run/game-v2-cy507-faketcp
mkdir -p "$runtime"
umask 077
cat >"$runtime/udp2raw.conf" <<CFG
-c
-l 127.0.0.1:31972
-r $SERVER_ENDPOINT:40972
--raw-mode easyfaketcp
--cipher-mode aes128cbc
--auth-mode hmac_sha1
--log-level 3
--disable-color
-k $SPEEDERV2_KEY
CFG
exec /usr/local/lib/game-v2-cy507/udp2raw --conf-file "$runtime/udp2raw.conf"
EOF
  cat >"$INSTALL_DIR/run-profile.sh" <<'EOF'
#!/bin/sh
set -eu
. /etc/game-v2/cy507/profile.env
case "${1:-}" in
  start)
    ifup gv2_cy507
    sleep 1
    main_route="$(ip -4 route get "$SERVER_ENDPOINT" | sed -n '1p')"
    main_gw="$(printf '%s\n' "$main_route" | awk '{for (i=1;i<=NF;i++) if ($i=="via") print $(i+1)}')"
    main_dev="$(printf '%s\n' "$main_route" | awk '{for (i=1;i<=NF;i++) if ($i=="dev") print $(i+1)}')"
    [ -n "$main_dev" ]
    if [ -n "$main_gw" ]; then
      ip route replace "$SERVER_ENDPOINT/32" via "$main_gw" dev "$main_dev" table 51872
    else
      ip route replace "$SERVER_ENDPOINT/32" dev "$main_dev" table 51872
    fi
    ip route replace 10.77.2.1/32 dev gv2_cy507 table 51872
    ip route replace default dev gv2_cy507 table 51872
    ip rule add priority 9999 from 192.168.50.0/24 to 192.168.50.0/24 lookup main 2>/dev/null || true
    ip rule add priority 10000 from 192.168.50.0/24 lookup 51872 2>/dev/null || true
    exec /usr/local/lib/game-v2-cy507/speederv2 -c -l127.0.0.1:30972 -r127.0.0.1:31972 --mode 0 -k "$SPEEDERV2_KEY"
    ;;
  stop)
    ip rule del priority 10000 2>/dev/null || true
    ip rule del priority 9999 2>/dev/null || true
    ip route flush table 51872 2>/dev/null || true
    ifdown gv2_cy507 >/dev/null 2>&1 || true
    ;;
  *) exit 2 ;;
esac
EOF
  chmod 700 "$INSTALL_DIR/run-faketcp.sh" "$INSTALL_DIR/run-profile.sh"

  cat >"$FAKETCP_INIT" <<'EOF'
#!/bin/sh /etc/rc.common
USE_PROCD=1
START=90
STOP=10
start_service() {
  procd_open_instance
  procd_set_param command /usr/local/lib/game-v2-cy507/run-faketcp.sh
  procd_set_param respawn 3600 5 5
  procd_set_param stdout 1
  procd_set_param stderr 1
  procd_close_instance
}
EOF
  cat >"$PROFILE_INIT" <<'EOF'
#!/bin/sh /etc/rc.common
USE_PROCD=1
START=91
STOP=9
start_service() {
  procd_open_instance
  procd_set_param command /usr/local/lib/game-v2-cy507/run-profile.sh start
  procd_set_param respawn 3600 5 5
  procd_set_param stdout 1
  procd_set_param stderr 1
  procd_close_instance
}
stop_service() {
  /usr/local/lib/game-v2-cy507/run-profile.sh stop
}
EOF
  chmod 755 "$FAKETCP_INIT" "$PROFILE_INIT"
}

write_uci_config() {
  uci batch <<EOF
set network.gv2_cy507='interface'
set network.gv2_cy507.proto='wireguard'
set network.gv2_cy507.private_key='$CLIENT_PRIVATE_KEY'
add_list network.gv2_cy507.addresses='$CLIENT_WG_ADDR'
set network.gv2_cy507.mtu='1500'
set network.gv2_cy507.auto='0'
set network.gv2p_cy507='wireguard_gv2_cy507'
set network.gv2p_cy507.public_key='$SERVER_PUBLIC_KEY'
set network.gv2p_cy507.endpoint_host='127.0.0.1'
set network.gv2p_cy507.endpoint_port='$CLIENT_SPEEDERV2_PORT'
add_list network.gv2p_cy507.allowed_ips='0.0.0.0/0'
set network.gv2p_cy507.route_allowed_ips='0'
set network.gv2p_cy507.persistent_keepalive='25'
set firewall.game_v2_cy507='zone'
set firewall.game_v2_cy507.name='game_v2_cy507'
add_list firewall.game_v2_cy507.network='gv2_cy507'
set firewall.game_v2_cy507.input='REJECT'
set firewall.game_v2_cy507.output='ACCEPT'
set firewall.game_v2_cy507.forward='REJECT'
set firewall.game_v2_cy507.masq='1'
set firewall.game_v2_cy507.mtu_fix='1'
set firewall.lan_to_game_v2_cy507='forwarding'
set firewall.lan_to_game_v2_cy507.src='lan'
set firewall.lan_to_game_v2_cy507.dest='game_v2_cy507'
set firewall.game_v2_cy507_to_lan='forwarding'
set firewall.game_v2_cy507_to_lan.src='game_v2_cy507'
set firewall.game_v2_cy507_to_lan.dest='lan'
EOF
  uci commit network
  uci commit firewall
}

write_firewall_fragments() {
  mkdir -p "$(dirname "$DNS_RULE")" "$(dirname "$NO_SNAT_RULE")" "$(dirname "$INBOUND_RULE")"
  cat >"$DNS_RULE" <<EOF
ip saddr $GAME_DEVICE_IP meta l4proto { tcp, udp } th dport 53 counter dnat to $SERVER_WG_IP:53 comment "cy507-dns-v1"
EOF
  cat >"$NO_SNAT_RULE" <<EOF
oifname "$WG_IF" ip saddr $GAME_DEVICE_IP counter return comment "game-v2:cy507-fixed-bridge:no-local-snat"
EOF
  cat >"$INBOUND_RULE" <<EOF
iifname "$WG_IF" oifname "br-lan" ip daddr $GAME_DEVICE_IP udp dport $GAME_DEVICE_PORT counter accept comment "cy507-nat-inbound-v1"
EOF
}

start_client() {
  /etc/init.d/network reload
  /etc/init.d/firewall reload
  "$FAKETCP_INIT" enable
  "$FAKETCP_INIT" start
  sleep 1
  "$PROFILE_INIT" enable
  "$PROFILE_INIT" start
}

verify_client() {
  require_root
  load_enrollment
  ubus call service list '{"name":"game-v2-cy507-faketcp"}' | grep -q '"running": true' || die "FakeTCP service is not running"
  ubus call service list '{"name":"game-v2-cy507"}' | grep -q '"running": true' || die "profile service is not running"
  ip -4 addr show dev "$WG_IF" | grep -q '10\.77\.2\.2/30' || die "WireGuard address mismatch"
  ip rule show | grep -q '^9999:.*from 192\.168\.50\.0/24 to 192\.168\.50\.0/24 lookup main' || die "LAN bypass rule missing"
  ip rule show | grep -q '^10000:.*from 192\.168\.50\.0/24 lookup 51872' || die "policy routing rule missing"
  ip route show table "$ROUTE_TABLE" | grep -q '^default dev gv2_cy507' || die "policy default route missing"
  wg show "$WG_IF" endpoints | grep -q '127\.0\.0\.1:30972' || die "WireGuard endpoint mismatch"
  nft list ruleset | grep -q 'cy507-dns-v1' || die "cy507 DNS DNAT is not active"
  nft list ruleset | grep -q 'game-v2:cy507-fixed-bridge:no-local-snat' || die "cy507 no-SNAT rule is not active"
  nft list ruleset | grep -q 'cy507-nat-inbound-v1' || die "cy507 inbound rule is not active"
  ip -4 route get "$SERVER_ENDPOINT" | grep -qv 'dev gv2_cy507' || die "VPS endpoint route is looping into the tunnel"
  nslookup example.com "$SERVER_WG_IP" >/dev/null 2>&1 || die "dedicated DNS probe failed"
  say "OpenWrt technical verification passed"
}

apply_client() {
  preflight
  txn="$(date -u +%Y%m%dT%H%M%SZ)-$$"
  backup_dir="$BACKUP_ROOT/$txn"
  mkdir -p "$backup_dir"
  cp /etc/config/network "$backup_dir/network"
  cp /etc/config/firewall "$backup_dir/firewall"
  ip rule show >"$backup_dir/rules-before.txt"
  ip route show table all >"$backup_dir/routes-before.txt"
  write_rollback_script "$backup_dir"
  arm_rollback "$backup_dir"

  if ! write_runtime_files || ! write_uci_config || ! write_firewall_fragments || \
     ! start_client || ! verify_client; then
    /bin/sh "$backup_dir/rollback.sh"
    rm -f "$backup_dir/rollback.pending"
    die "installation failed and cy507-owned OpenWrt changes were rolled back"
  fi
  cat >"$ACTIVE_TXN" <<EOF
BACKUP_DIR='$backup_dir'
EOF
  chmod 600 "$ACTIVE_TXN"
  say "OpenWrt install staged successfully; automatic rollback remains armed for 15 minutes"
  say "Validate from a new management session and on Xbox, then run ./install.sh commit"
}

commit_client() {
  require_root
  [ -s "$ACTIVE_TXN" ] || die "no pending cy507 transaction"
  verify_client
  # shellcheck disable=SC1090
  . "$ACTIVE_TXN"
  rm -f "$BACKUP_DIR/rollback.pending"
  rm -f "$ACTIVE_TXN"
  say "OpenWrt rollback cancelled; cy507 install committed"
}

rollback_client() {
  require_root
  [ -s "$ACTIVE_TXN" ] || die "no pending cy507 transaction"
  # shellcheck disable=SC1090
  . "$ACTIVE_TXN"
  /bin/sh "$BACKUP_DIR/rollback.sh"
  rm -f "$BACKUP_DIR/rollback.pending"
  say "cy507-owned OpenWrt changes rolled back"
}

status_client() {
  require_root
  for service in game-v2-cy507-faketcp game-v2-cy507; do
    printf '%-28s ' "$service"
    ubus call service list "{\"name\":\"$service\"}" 2>/dev/null | grep -q '"running": true' && say active || say inactive
  done
  if [ -s "$ACTIVE_TXN" ]; then say "rollback: ARMED"; else say "rollback: not pending"; fi
  wg show "$WG_IF" latest-handshakes 2>/dev/null || true
}

cmd="${1:-}"
[ -n "$cmd" ] || { usage; exit 1; }
shift
case "$cmd" in
  preflight) [ "$#" -eq 0 ] || die "preflight takes no arguments"; preflight ;;
  apply) [ "$#" -eq 0 ] || die "apply takes no arguments"; apply_client ;;
  verify) [ "$#" -eq 0 ] || die "verify takes no arguments"; verify_client ;;
  status) [ "$#" -eq 0 ] || die "status takes no arguments"; status_client ;;
  commit) [ "$#" -eq 0 ] || die "commit takes no arguments"; commit_client ;;
  rollback) [ "$#" -eq 0 ] || die "rollback takes no arguments"; rollback_client ;;
  -h|--help|help) usage ;;
  *) usage; die "unknown command: $cmd" ;;
esac
