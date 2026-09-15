#!/bin/sh
set -eu

test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH= cd -- "$test_dir/.." && pwd)
vps="$root/scripts/game-v2-cy507-vps.sh"
openwrt="$root/bundles/cy507-openwrt/install.sh"
config="$root/config/fleet/cy507.conf"

fail() { printf 'FAIL cy507-v13: %s\n' "$*" >&2; exit 1; }
has() { grep -Fq -- "$2" "$1" || fail "missing '$2' in ${1#$root/}"; }
lacks() { ! grep -Fq -- "$2" "$1" || fail "forbidden '$2' in ${1#$root/}"; }

[ "$(cat "$root/VERSION")" = "1.3.0" ] || fail "VERSION is not 1.3.0"
sh -n "$vps"
sh -n "$openwrt"

for item in \
  'client_id=cy507' \
  'server_endpoint=91.223.119.134' \
  'wireguard_port=51872' \
  'server_speederv2_port=40972' \
  'client_speederv2_port=30972' \
  'faketcp_local_port=31972' \
  'game_device_ip=192.168.50.126' \
  'game_device_port=3074' \
  'public_game_port=23074' \
  'vps_wan_iface=ens3' \
  'managed_dns=1'; do
  has "$config" "$item"
done

has "$vps" 'netfilter-persistent.service must be enabled'
has "$vps" 'iptables.service ip6tables.service nftables.service'
has "$vps" 'game_v2_cy507_fixed_nat'
has "$vps" 'dnat to $GAME_DEVICE_IP:$GAME_DEVICE_PORT'
has "$vps" 'snat to $SERVER_ENDPOINT:$PUBLIC_GAME_PORT'
has "$vps" 'unbound-cy507.service'
has "$vps" 'access-control: 192.168.50.126/32 allow'
has "$vps" 'automatic rollback remains armed for 15 minutes'
has "$vps" 'assert_fresh'

has "$openwrt" '-r $SERVER_ENDPOINT:40972'
has "$openwrt" '-r127.0.0.1:31972'
has "$openwrt" 'endpoint_host='
has "$openwrt" 'endpoint_port='
has "$openwrt" "set firewall.lan_to_game_v2_cy507='forwarding'"
has "$openwrt" 'cy507-dns-v1'
has "$openwrt" 'game-v2:cy507-fixed-bridge:no-local-snat'
has "$openwrt" 'cy507-nat-inbound-v1'
has "$openwrt" 'automatic rollback remains armed for 15 minutes'
has "$openwrt" 'assert_fresh'

for file in "$vps" "$openwrt"; do
  lacks "$file" 'nft flush ruleset'
  lacks "$file" 'iptables-save'
  lacks "$file" 'systemctl restart netfilter-persistent'
  lacks "$file" 'wg-data'
  lacks "$file" 'wg-data-direct'
  lacks "$file" 'domestic-live-relay-mediamtx'
  lacks "$file" '1935'
  lacks "$file" '8554'
  lacks "$file" '8890'
  lacks "$file" '9998'
done

case "$(grep -E '^(SERVER_PUBLIC_KEY|CLIENT_PRIVATE_KEY|SPEEDERV2_KEY)=' "$config" 2>/dev/null || true)" in
  '') ;;
  *) fail "secret material found in committed cy507 config" ;;
esac

printf '%s\n' 'PASS cy507-v13-static-contracts'
