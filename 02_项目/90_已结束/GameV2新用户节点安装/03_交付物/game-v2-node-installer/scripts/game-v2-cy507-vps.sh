#!/bin/sh
set -eu

# Game V2 cy507 VPS installer 1.3.0.
# Fresh/rebuild installs only. It deliberately refuses to modify an existing
# cy507 installation and never owns the host-wide firewall restore source.

VERSION="1.3.0"
CLIENT_ID="cy507"
SERVER_ENDPOINT="91.223.119.134"
WG_IF="gv2_cy507"
WG_PORT="51872"
SERVER_SPEEDERV2_PORT="40972"
PUBLIC_GAME_PORT="23074"
GAME_DEVICE_IP="192.168.50.126"
GAME_DEVICE_PORT="3074"
SERVER_WG_ADDR="10.77.2.1/30"
CLIENT_WG_ADDR="10.77.2.2/30"
CLIENT_WG_IP="10.77.2.2"
ROUTE_TABLE="51872"
VPS_WAN_IFACE="ens3"
ROLLBACK_SECONDS="900"

STATE_DIR="/var/lib/game-v2-cy507"
ACTIVE_TXN="$STATE_DIR/active-transaction"
INSTALL_DIR="/usr/local/lib/game-v2-cy507"
CLIENT_DIR="/etc/game-v2/clients/cy507"
WG_CONF="/etc/wireguard/${WG_IF}.conf"
UNBOUND_CONF="/etc/unbound/unbound-cy507.conf"
UNBOUND_STATE="/var/lib/unbound/cy507"
NAT_FILE="/etc/game-v2/cy507-fixed-nat.nft"
RECONCILE="/usr/local/sbin/game-v2-cy507-reconcile"
BACKUP_ROOT="/var/backups/game-v2-cy507"

WG_UNIT="game-v2-wg-cy507.service"
SPEED_UNIT="game-v2-speederv2-cy507.service"
FAKE_UNIT="game-v2-faketcp-cy507.service"
DNS_UNIT="unbound-cy507.service"
RECONCILE_UNIT="game-v2-cy507-reconcile.service"
RECONCILE_TIMER="game-v2-cy507-reconcile.timer"

say() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1"; }

usage() {
  cat <<'EOF'
Usage:
  game-v2-cy507-vps.sh preflight <speederv2-bin> <udp2raw-bin>
  game-v2-cy507-vps.sh install   <speederv2-bin> <udp2raw-bin> <openwrt-install.sh>
  game-v2-cy507-vps.sh package
  game-v2-cy507-vps.sh verify
  game-v2-cy507-vps.sh status
  game-v2-cy507-vps.sh commit
  game-v2-cy507-vps.sh rollback

The install command is for a fresh/rebuild installation only. It refuses when
any cy507-owned target already exists. A successful install leaves a 15-minute
server-local rollback armed. Verify from a new SSH session, finish the OpenWrt
side, then run commit before the deadline.
EOF
}

require_root() {
  [ "$(id -u)" -eq 0 ] || die "run as root"
}

require_exact_host() {
  [ -r /etc/os-release ] || die "unsupported host: /etc/os-release missing"
  [ "$(uname -m)" = "x86_64" ] || die "unsupported architecture: $(uname -m)"
  command -v systemctl >/dev/null 2>&1 || die "systemd is required"
}

require_dependencies() {
  for cmd in awk cp cut date flock grep id install ip nft openssl sed ss systemctl tr wg wg-quick; do
    need "$cmd"
  done
  [ -x /usr/sbin/unbound ] || die "missing /usr/sbin/unbound"
  [ -x /usr/sbin/unbound-checkconf ] || die "missing /usr/sbin/unbound-checkconf"
}

assert_control_plane() {
  systemctl is-enabled netfilter-persistent.service 2>/dev/null | grep -qx enabled || \
    die "netfilter-persistent.service must be enabled"
  systemctl is-active netfilter-persistent.service 2>/dev/null | grep -qx active || \
    die "netfilter-persistent.service must be active"
  for unit in iptables.service ip6tables.service nftables.service; do
    systemctl is-enabled "$unit" 2>/dev/null | grep -qx masked || die "$unit must remain masked"
    if systemctl is-active --quiet "$unit" 2>/dev/null; then
      die "$unit must remain inactive"
    fi
  done
}

port_is_free() {
  proto="$1"
  port="$2"
  if [ "$proto" = tcp ]; then
    ! ss -H -lnt "sport = :$port" 2>/dev/null | grep -q .
  else
    ! ss -H -lnu "sport = :$port" 2>/dev/null | grep -q .
  fi
}

assert_fresh() {
  [ ! -e "$STATE_DIR" ] || die "existing cy507 state found: $STATE_DIR"
  [ ! -e "$INSTALL_DIR" ] || die "existing cy507 install found: $INSTALL_DIR"
  [ ! -e "$CLIENT_DIR" ] || die "existing cy507 client state found: $CLIENT_DIR"
  [ ! -e "$WG_CONF" ] || die "existing cy507 WireGuard config found: $WG_CONF"
  [ ! -e "$UNBOUND_CONF" ] || die "existing cy507 DNS config found: $UNBOUND_CONF"
  [ ! -e "$UNBOUND_STATE" ] || die "existing cy507 DNS state found: $UNBOUND_STATE"
  [ ! -e "$NAT_FILE" ] || die "existing cy507 NAT file found: $NAT_FILE"
  [ ! -e "$RECONCILE" ] || die "existing cy507 reconcile found: $RECONCILE"
  for unit in "$WG_UNIT" "$SPEED_UNIT" "$FAKE_UNIT" "$DNS_UNIT" "$RECONCILE_UNIT" "$RECONCILE_TIMER"; do
    [ ! -e "/etc/systemd/system/$unit" ] || die "existing unit found: $unit"
  done
  ! ip link show "$WG_IF" >/dev/null 2>&1 || die "existing interface found: $WG_IF"
  ! nft list table ip game_v2_cy507_fixed_nat >/dev/null 2>&1 || \
    die "existing nft table found: ip game_v2_cy507_fixed_nat"
  port_is_free tcp "$SERVER_SPEEDERV2_PORT" || die "TCP $SERVER_SPEEDERV2_PORT is already in use"
  port_is_free udp "$SERVER_SPEEDERV2_PORT" || die "UDP $SERVER_SPEEDERV2_PORT is already in use"
  port_is_free udp "$WG_PORT" || die "UDP $WG_PORT is already in use"
  port_is_free udp 53 || die "UDP 53 is already in use; inspect before installing dedicated DNS"
  port_is_free tcp 53 || die "TCP 53 is already in use; inspect before installing dedicated DNS"
}

find_root_anchor() {
  for p in /var/lib/unbound/root.key /usr/share/dns/root.key /usr/share/dnssec-root/trusted-key.key; do
    if [ -s "$p" ]; then
      printf '%s\n' "$p"
      return 0
    fi
  done
  return 1
}

preflight() {
  require_root
  require_exact_host
  require_dependencies
  [ "$#" -eq 2 ] || die "preflight requires <speederv2-bin> <udp2raw-bin>"
  [ -x "$1" ] || die "speederv2 binary is not executable: $1"
  [ -x "$2" ] || die "udp2raw binary is not executable: $2"
  assert_control_plane
  assert_fresh
  find_root_anchor >/dev/null || die "DNSSEC root.key not found"
  [ -d /sys/class/net/"$VPS_WAN_IFACE" ] || die "expected VPS WAN interface missing: $VPS_WAN_IFACE"
  say "preflight passed: fresh cy507 VPS target"
  say "required existing firewall allowances: TCP $SERVER_SPEEDERV2_PORT and UDP $WG_PORT"
  say "protected services, containers, routes and ports are outside this installer's ownership"
}

write_rollback_script() {
  backup_dir="$1"
  mkdir -p "$backup_dir"
  cat >"$backup_dir/rollback.sh" <<'EOF'
#!/bin/sh
set -u
UNITS="game-v2-cy507-reconcile.timer game-v2-cy507-reconcile.service unbound-cy507.service game-v2-faketcp-cy507.service game-v2-speederv2-cy507.service game-v2-wg-cy507.service"
for unit in $UNITS; do
  systemctl disable --now "$unit" >/dev/null 2>&1 || true
done
nft delete table ip game_v2_cy507_fixed_nat >/dev/null 2>&1 || true
ip route del 192.168.50.126/32 dev gv2_cy507 >/dev/null 2>&1 || true
wg-quick down gv2_cy507 >/dev/null 2>&1 || true
rm -f /etc/systemd/system/game-v2-wg-cy507.service
rm -f /etc/systemd/system/game-v2-speederv2-cy507.service
rm -f /etc/systemd/system/game-v2-faketcp-cy507.service
rm -f /etc/systemd/system/unbound-cy507.service
rm -f /etc/systemd/system/game-v2-cy507-reconcile.service
rm -f /etc/systemd/system/game-v2-cy507-reconcile.timer
rm -f /etc/wireguard/gv2_cy507.conf
rm -f /etc/unbound/unbound-cy507.conf
rm -f /etc/game-v2/cy507-fixed-nat.nft
rm -f /usr/local/sbin/game-v2-cy507-reconcile
rm -rf /etc/game-v2/clients/cy507
rm -rf /usr/local/lib/game-v2-cy507
rm -rf /var/lib/unbound/cy507
rm -rf /var/lib/game-v2-cy507
systemctl daemon-reload >/dev/null 2>&1 || true
exit 0
EOF
  chmod 700 "$backup_dir/rollback.sh"
}

arm_rollback() {
  txn="$1"
  backup_dir="$2"
  rollback_unit="game-v2-cy507-rollback-$txn"
  systemd-run --quiet --unit="$rollback_unit" --on-active="${ROLLBACK_SECONDS}s" \
    /bin/sh "$backup_dir/rollback.sh"
  printf '%s\n' "$rollback_unit"
}

write_server_files() {
  speed_src="$1"
  udp2raw_src="$2"
  client_installer="$3"
  root_anchor="$4"

  install -d -m 700 "$STATE_DIR/secrets"
  install -d -m 755 "$STATE_DIR/package" "$INSTALL_DIR" "$CLIENT_DIR" /etc/game-v2 /etc/wireguard /etc/unbound
  install -d -m 755 "$UNBOUND_STATE"
  install -m 755 "$speed_src" "$INSTALL_DIR/speederv2"
  install -m 755 "$udp2raw_src" "$INSTALL_DIR/udp2raw"

  server_private="$(wg genkey)"
  server_public="$(printf '%s' "$server_private" | wg pubkey)"
  client_private="$(wg genkey)"
  client_public="$(printf '%s' "$client_private" | wg pubkey)"
  speed_key="$(openssl rand -base64 32 | tr -d '\n')"

  umask 077
  printf '%s\n' "$client_private" >"$STATE_DIR/secrets/client.key"
  printf '%s\n' "$client_public" >"$STATE_DIR/secrets/client.pub"
  printf '%s\n' "$server_public" >"$STATE_DIR/server.pub"
  cat >"$CLIENT_DIR/server.env" <<EOF
SPEEDERV2_KEY='$speed_key'
EOF

  cat >"$WG_CONF" <<EOF
[Interface]
Address = $SERVER_WG_ADDR
ListenPort = $WG_PORT
PrivateKey = $server_private
MTU = 1500

[Peer]
PublicKey = $client_public
AllowedIPs = $CLIENT_WG_IP/32,$GAME_DEVICE_IP/32
EOF
  chmod 600 "$WG_CONF" "$CLIENT_DIR/server.env"

  cat >"$INSTALL_DIR/run-speederv2.sh" <<'EOF'
#!/bin/sh
set -eu
. /etc/game-v2/clients/cy507/server.env
exec /usr/local/lib/game-v2-cy507/speederv2 -s -l0.0.0.0:40972 -r127.0.0.1:51872 --mode 0 -k "$SPEEDERV2_KEY"
EOF
  cat >"$INSTALL_DIR/run-faketcp.sh" <<'EOF'
#!/bin/sh
set -eu
. /etc/game-v2/clients/cy507/server.env
runtime=/run/game-v2-cy507-faketcp
mkdir -p "$runtime"
umask 077
cat >"$runtime/udp2raw.conf" <<CFG
-s
-l 0.0.0.0:40972
-r 127.0.0.1:40972
--raw-mode easyfaketcp
--cipher-mode aes128cbc
--auth-mode hmac_sha1
--log-level 3
--disable-color
-k $SPEEDERV2_KEY
CFG
exec /usr/local/lib/game-v2-cy507/udp2raw --conf-file "$runtime/udp2raw.conf"
EOF
  chmod 700 "$INSTALL_DIR/run-speederv2.sh" "$INSTALL_DIR/run-faketcp.sh"

  cat >"$NAT_FILE" <<EOF
table ip game_v2_cy507_fixed_nat {
  chain prerouting {
    type nat hook prerouting priority -101; policy accept;
    iifname "$VPS_WAN_IFACE" ip daddr $SERVER_ENDPOINT udp dport $PUBLIC_GAME_PORT counter dnat to $GAME_DEVICE_IP:$GAME_DEVICE_PORT comment "game-v2:cy507-fixed-bridge:dnat"
  }
  chain postrouting {
    type nat hook postrouting priority 99; policy accept;
    iifname "$WG_IF" oifname "$VPS_WAN_IFACE" ip saddr $GAME_DEVICE_IP udp sport $GAME_DEVICE_PORT counter snat to $SERVER_ENDPOINT:$PUBLIC_GAME_PORT comment "game-v2:cy507-fixed-bridge:port-snat"
    iifname "$WG_IF" oifname "$VPS_WAN_IFACE" ip saddr $GAME_DEVICE_IP counter snat to $SERVER_ENDPOINT comment "game-v2:cy507-fixed-bridge:fallback-snat"
  }
}
EOF

  cat >"$RECONCILE" <<'EOF'
#!/bin/sh
set -eu
exec 9>/run/game-v2-cy507-reconcile.lock
flock -n 9 || exit 0
[ -d /sys/class/net/gv2_cy507 ] || exit 1
txn_file=/run/game-v2-cy507-reconcile.nft
if nft list table ip game_v2_cy507_fixed_nat >/dev/null 2>&1; then
  {
    printf '%s\n' 'delete table ip game_v2_cy507_fixed_nat'
    cat /etc/game-v2/cy507-fixed-nat.nft
  } >"$txn_file"
else
  cp /etc/game-v2/cy507-fixed-nat.nft "$txn_file"
fi
nft -c -f "$txn_file"
nft -f "$txn_file"
rm -f "$txn_file"
ip route replace 192.168.50.126/32 dev gv2_cy507
peer="$(wg show gv2_cy507 peers)"
[ "$(printf '%s\n' "$peer" | sed '/^$/d' | wc -l | tr -d ' ')" = 1 ]
wg set gv2_cy507 peer "$peer" allowed-ips 10.77.2.2/32,192.168.50.126/32
EOF
  chmod 700 "$RECONCILE"

  cp "$root_anchor" "$UNBOUND_STATE/root.key"
  chown -R unbound:unbound "$UNBOUND_STATE"
  chmod 700 "$UNBOUND_STATE"
  chmod 600 "$UNBOUND_STATE/root.key"
  cat >"$UNBOUND_CONF" <<'EOF'
server:
    interface: 10.77.2.1
    port: 53
    do-ip4: yes
    do-ip6: no
    do-udp: yes
    do-tcp: yes
    access-control: 0.0.0.0/0 refuse
    access-control: 192.168.50.126/32 allow
    access-control: 10.77.2.2/32 allow
    username: "unbound"
    chroot: ""
    directory: "/var/lib/unbound/cy507"
    pidfile: "/var/lib/unbound/cy507/unbound.pid"
    auto-trust-anchor-file: "/var/lib/unbound/cy507/root.key"
    module-config: "validator iterator"
    use-syslog: yes
    verbosity: 1
    hide-identity: yes
    hide-version: yes
    harden-glue: yes
    harden-dnssec-stripped: yes
    qname-minimisation: yes
    prefetch: yes
    edns-buffer-size: 1232
remote-control:
    control-enable: no
EOF

  cat >/etc/systemd/system/"$WG_UNIT" <<'EOF'
[Unit]
Description=Game V2 cy507 WireGuard
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/wg-quick up gv2_cy507
ExecStop=/usr/bin/wg-quick down gv2_cy507

[Install]
WantedBy=multi-user.target
EOF
  cat >/etc/systemd/system/"$SPEED_UNIT" <<'EOF'
[Unit]
Description=Game V2 cy507 speederv2 server
After=game-v2-wg-cy507.service
Requires=game-v2-wg-cy507.service

[Service]
Type=simple
ExecStart=/usr/local/lib/game-v2-cy507/run-speederv2.sh
Restart=on-failure
RestartSec=3
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF
  cat >/etc/systemd/system/"$FAKE_UNIT" <<'EOF'
[Unit]
Description=Game V2 cy507 FakeTCP server
After=network-online.target game-v2-speederv2-cy507.service
Wants=network-online.target
Requires=game-v2-speederv2-cy507.service

[Service]
Type=simple
ExecStart=/usr/local/lib/game-v2-cy507/run-faketcp.sh
Restart=on-failure
RestartSec=3
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF
  cat >/etc/systemd/system/"$DNS_UNIT" <<'EOF'
[Unit]
Description=cy507 dedicated validating DNS resolver
After=network-online.target game-v2-wg-cy507.service
Wants=network-online.target

[Service]
Type=simple
ExecStartPre=/usr/sbin/unbound-checkconf /etc/unbound/unbound-cy507.conf
ExecStart=/usr/sbin/unbound -d -p -c /etc/unbound/unbound-cy507.conf
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=3s
NoNewPrivileges=true
PrivateTmp=true
PrivateDevices=true
ProtectSystem=strict
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
ReadWritePaths=/var/lib/unbound/cy507
RestrictAddressFamilies=AF_UNIX AF_INET AF_NETLINK
CapabilityBoundingSet=CAP_NET_BIND_SERVICE CAP_SETGID CAP_SETUID

[Install]
WantedBy=multi-user.target
EOF
  cat >/etc/systemd/system/"$RECONCILE_UNIT" <<'EOF'
[Unit]
Description=Reconcile only cy507 Game V2 route and NAT table
After=netfilter-persistent.service game-v2-wg-cy507.service
Requires=game-v2-wg-cy507.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/game-v2-cy507-reconcile
EOF
  cat >/etc/systemd/system/"$RECONCILE_TIMER" <<'EOF'
[Unit]
Description=Periodic cy507 Game V2 reconcile

[Timer]
OnBootSec=45s
OnUnitActiveSec=60s
AccuracySec=5s
Unit=game-v2-cy507-reconcile.service

[Install]
WantedBy=timers.target
EOF

  install -m 700 "$client_installer" "$STATE_DIR/package/install.sh"
  install -m 755 "$speed_src" "$STATE_DIR/package/speederv2"
  install -m 755 "$udp2raw_src" "$STATE_DIR/package/udp2raw"
  cat >"$STATE_DIR/package/enrollment.env" <<EOF
CLIENT_ID='$CLIENT_ID'
SERVER_ENDPOINT='$SERVER_ENDPOINT'
SERVER_PUBLIC_KEY='$server_public'
CLIENT_PRIVATE_KEY='$client_private'
SPEEDERV2_KEY='$speed_key'
EOF
  chmod 600 "$STATE_DIR/package/enrollment.env"
  umask 022
}

start_server() {
  /usr/sbin/unbound-checkconf "$UNBOUND_CONF"
  nft -c -f "$NAT_FILE"
  systemctl daemon-reload
  systemctl enable --now "$WG_UNIT"
  systemctl enable --now "$SPEED_UNIT"
  systemctl enable --now "$FAKE_UNIT"
  systemctl enable --now "$DNS_UNIT"
  systemctl start "$RECONCILE_UNIT"
  systemctl enable --now "$RECONCILE_TIMER"
}

verify_server() {
  require_root
  assert_control_plane
  for unit in "$WG_UNIT" "$SPEED_UNIT" "$FAKE_UNIT" "$DNS_UNIT" "$RECONCILE_TIMER"; do
    systemctl is-active --quiet "$unit" || die "$unit is not active"
  done
  ip -4 addr show dev "$WG_IF" | grep -q '10\.77\.2\.1/30' || die "WireGuard address mismatch"
  [ "$(wg show "$WG_IF" peers | sed '/^$/d' | wc -l | tr -d ' ')" = 1 ] || die "WireGuard peer count mismatch"
  allowed="$(wg show "$WG_IF" allowed-ips | awk '{print $2}')"
  [ "$allowed" = '10.77.2.2/32,192.168.50.126/32' ] || die "WireGuard AllowedIPs mismatch: $allowed"
  ip route show "$GAME_DEVICE_IP/32" | grep -q "dev $WG_IF" || die "Xbox host route missing"
  nft list table ip game_v2_cy507_fixed_nat | grep -q "udp dport $PUBLIC_GAME_PORT.*dnat to $GAME_DEVICE_IP:$GAME_DEVICE_PORT" || die "DNAT rule missing"
  nft list table ip game_v2_cy507_fixed_nat | grep -q "udp sport $GAME_DEVICE_PORT.*snat to $SERVER_ENDPOINT:$PUBLIC_GAME_PORT" || die "port-SNAT rule missing"
  ss -H -lnt "sport = :$SERVER_SPEEDERV2_PORT" | grep -q . || die "FakeTCP listener missing"
  ss -H -lnu "sport = :$SERVER_SPEEDERV2_PORT" | grep -q . || die "speederv2 listener missing"
  ss -H -lnu "sport = :$WG_PORT" | grep -q . || die "WireGuard listener missing"
  ss -H -lnu "sport = :53" | grep -q '10\.77\.2\.1:53' || die "cy507 UDP DNS listener missing"
  ss -H -lnt "sport = :53" | grep -q '10\.77\.2\.1:53' || die "cy507 TCP DNS listener missing"
  say "VPS technical verification passed"
}

install_server() {
  require_root
  [ "$#" -eq 3 ] || die "install requires <speederv2-bin> <udp2raw-bin> <openwrt-install.sh>"
  speed_src="$1"
  udp2raw_src="$2"
  client_installer="$3"
  [ -f "$client_installer" ] || die "OpenWrt installer missing: $client_installer"
  preflight "$speed_src" "$udp2raw_src"
  root_anchor="$(find_root_anchor)"
  txn="$(date -u +%Y%m%dT%H%M%SZ)-$$"
  backup_dir="$BACKUP_ROOT/$txn"
  mkdir -p "$backup_dir"
  {
    for unit in netfilter-persistent.service iptables.service ip6tables.service nftables.service; do
      printf '%s enabled=%s active=%s\n' "$unit" \
        "$(systemctl is-enabled "$unit" 2>/dev/null || true)" \
        "$(systemctl is-active "$unit" 2>/dev/null || true)"
    done
  } >"$backup_dir/control-plane.txt"
  ss -H -lntup >"$backup_dir/listeners-before.txt" 2>/dev/null || true
  ip route show >"$backup_dir/routes-before.txt"
  write_rollback_script "$backup_dir"
  rollback_unit="$(arm_rollback "$txn" "$backup_dir")"

  if ! write_server_files "$speed_src" "$udp2raw_src" "$client_installer" "$root_anchor" || \
     ! start_server || ! verify_server; then
    /bin/sh "$backup_dir/rollback.sh"
    systemctl stop "$rollback_unit.timer" >/dev/null 2>&1 || true
    die "installation failed and cy507-owned changes were rolled back"
  fi

  mkdir -p "$STATE_DIR"
  cat >"$ACTIVE_TXN" <<EOF
TXN='$txn'
BACKUP_DIR='$backup_dir'
ROLLBACK_UNIT='$rollback_unit'
EOF
  chmod 600 "$ACTIVE_TXN"
  say "VPS install staged successfully; automatic rollback remains armed for 15 minutes"
  say "OpenWrt package: $STATE_DIR/package"
  say "Next: copy that directory to 192.168.50.7, run ./install.sh apply, validate, then commit both endpoints"
}

package_info() {
  require_root
  [ -s "$STATE_DIR/package/enrollment.env" ] || die "package is not available"
  say "$STATE_DIR/package"
  say "Contains private enrollment material; transfer securely and do not commit it to source control."
}

commit_install() {
  require_root
  [ -s "$ACTIVE_TXN" ] || die "no pending cy507 transaction"
  verify_server
  # shellcheck disable=SC1090
  . "$ACTIVE_TXN"
  systemctl stop "$ROLLBACK_UNIT.timer" >/dev/null 2>&1 || true
  systemctl reset-failed "$ROLLBACK_UNIT.service" >/dev/null 2>&1 || true
  rm -f "$ACTIVE_TXN"
  say "VPS rollback cancelled; cy507 install committed"
}

rollback_install() {
  require_root
  [ -s "$ACTIVE_TXN" ] || die "no pending cy507 transaction"
  # shellcheck disable=SC1090
  . "$ACTIVE_TXN"
  /bin/sh "$BACKUP_DIR/rollback.sh"
  systemctl stop "$ROLLBACK_UNIT.timer" >/dev/null 2>&1 || true
  say "cy507-owned VPS changes rolled back"
}

status_server() {
  require_root
  for unit in "$WG_UNIT" "$SPEED_UNIT" "$FAKE_UNIT" "$DNS_UNIT" "$RECONCILE_TIMER"; do
    printf '%-42s %s\n' "$unit" "$(systemctl is-active "$unit" 2>/dev/null || true)"
  done
  if [ -s "$ACTIVE_TXN" ]; then
    say "rollback: ARMED"
  else
    say "rollback: not pending"
  fi
  wg show "$WG_IF" latest-handshakes 2>/dev/null || true
}

cmd="${1:-}"
[ -n "$cmd" ] || { usage; exit 1; }
shift
case "$cmd" in
  preflight) preflight "$@" ;;
  install) install_server "$@" ;;
  package) [ "$#" -eq 0 ] || die "package takes no arguments"; package_info ;;
  verify) [ "$#" -eq 0 ] || die "verify takes no arguments"; verify_server ;;
  status) [ "$#" -eq 0 ] || die "status takes no arguments"; status_server ;;
  commit) [ "$#" -eq 0 ] || die "commit takes no arguments"; commit_install ;;
  rollback) [ "$#" -eq 0 ] || die "rollback takes no arguments"; rollback_install ;;
  -h|--help|help) usage ;;
  *) usage; die "unknown command: $cmd" ;;
esac
