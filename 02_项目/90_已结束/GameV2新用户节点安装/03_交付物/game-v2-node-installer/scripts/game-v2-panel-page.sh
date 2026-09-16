#!/bin/sh
set -eu

VERSION='1.0.0'
ROLLBACK_SECONDS='900'

say() {
  printf '%s\n' "$*"
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  game-v2-panel-page.sh build CONFIG OUTPUT_HTML
  game-v2-panel-page.sh inspect CONFIG
  game-v2-panel-page.sh apply CONFIG
  game-v2-panel-page.sh verify CONFIG
  game-v2-panel-page.sh status CONFIG
  game-v2-panel-page.sh commit CONFIG
  game-v2-panel-page.sh rollback CONFIG

Environment:
  GAME_V2_SSH_IDENTITY=/path/to/id_ed25519

apply only replaces /www/wgpanel.html. It leaves a 15-minute rollback armed.
Run browser QA, then use commit to verify again and cancel the rollback.
EOF
}

need() {
  command -v "$1" >/dev/null 2>&1 || die "missing local command: $1"
}

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PACKAGE_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
SOURCE_PAGE="$PACKAGE_ROOT/assets/wgpanel-cy507.html"
SSH_IDENTITY=${GAME_V2_SSH_IDENTITY:-"$HOME/.ssh/id_ed25519"}
LOCAL_TMP=''
LOCAL_KNOWN_HOSTS=''
OPENWRT_SELECTED_HOST=''

cleanup() {
  [ -z "$LOCAL_TMP" ] || rm -rf "$LOCAL_TMP"
}
trap cleanup EXIT HUP INT TERM

load_config() {
  config_path="$1"
  [ -f "$config_path" ] || die "config not found: $config_path"
  need python3
  ensure_tmp
  config_vars="$LOCAL_TMP/config.sh"
  python3 - "$config_path" >"$config_vars" <<'PY'
from pathlib import Path
import shlex
import sys

allowed = {
    "client_id",
    "openwrt_host",
    "openwrt_fallback_host",
    "openwrt_ed25519_fp",
    "panel_node_id",
    "panel_node_label",
    "panel_expected_fec",
    "panel_require_network",
}
values = {
    "openwrt_fallback_host": "",
    "panel_expected_fec": "",
    "panel_require_network": "reachable",
}
seen = set()
for number, raw in enumerate(Path(sys.argv[1]).read_text().splitlines(), 1):
    line = raw.strip()
    if not line or line.startswith("#"):
        continue
    if "=" not in line:
        raise SystemExit(f"invalid config line {number}: missing =")
    key, value = line.split("=", 1)
    key = key.strip()
    value = value.strip()
    if key not in allowed:
        raise SystemExit(f"invalid config line {number}: unknown key {key}")
    if key in seen:
        raise SystemExit(f"invalid config line {number}: duplicate key {key}")
    seen.add(key)
    values[key] = value

names = {
    "client_id": "CLIENT_ID",
    "openwrt_host": "OPENWRT_HOST",
    "openwrt_fallback_host": "OPENWRT_FALLBACK_HOST",
    "openwrt_ed25519_fp": "OPENWRT_ED25519_FP",
    "panel_node_id": "PANEL_NODE_ID",
    "panel_node_label": "PANEL_NODE_LABEL",
    "panel_expected_fec": "PANEL_EXPECTED_FEC",
    "panel_require_network": "PANEL_REQUIRE_NETWORK",
}
for key, shell_name in names.items():
    print(f"{shell_name}={shlex.quote(values.get(key, ''))}")
PY
  . "$config_vars"

  case "$CLIENT_ID" in ''|*[!a-z0-9_-]*) die 'client_id must use lowercase letters, digits, _ or -' ;; esac
  case "$PANEL_NODE_ID" in ''|*[!A-Za-z0-9_-]*) die 'panel_node_id must use letters, digits, _ or -' ;; esac
  [ -n "$PANEL_NODE_LABEL" ] || die 'panel_node_label is required'
  case "$PANEL_EXPECTED_FEC" in ''|*[!A-Za-z0-9_-]*) [ -z "$PANEL_EXPECTED_FEC" ] || die 'invalid panel_expected_fec' ;; esac
  case "$PANEL_REQUIRE_NETWORK" in reachable|any) ;; *) die 'panel_require_network must be reachable or any' ;; esac
}

require_remote_config() {
  [ -n "$OPENWRT_HOST" ] || die 'openwrt_host is required for remote actions'
  case "$OPENWRT_HOST" in *[!A-Za-z0-9_.:-]*) die 'invalid openwrt_host' ;; esac
  case "$OPENWRT_FALLBACK_HOST" in *[!A-Za-z0-9_.:-]*) die 'invalid openwrt_fallback_host' ;; esac
  case "$OPENWRT_ED25519_FP" in SHA256:*) ;; *) die 'openwrt_ed25519_fp must be an SHA256 fingerprint' ;; esac
  [ -f "$SSH_IDENTITY" ] || die "SSH identity not found: $SSH_IDENTITY"
}

ensure_tmp() {
  if [ -z "$LOCAL_TMP" ]; then
    LOCAL_TMP=$(mktemp -d /tmp/game-v2-panel-page.XXXXXX)
    chmod 700 "$LOCAL_TMP"
    LOCAL_KNOWN_HOSTS="$LOCAL_TMP/known_hosts"
    : >"$LOCAL_KNOWN_HOSTS"
  fi
}

build_candidate() {
  output="$1"
  [ -s "$SOURCE_PAGE" ] || die "reviewed page source missing: $SOURCE_PAGE"
  mkdir -p "$(dirname -- "$output")"
  python3 - "$SOURCE_PAGE" "$output" "$PANEL_NODE_ID" "$PANEL_NODE_LABEL" <<'PY'
from pathlib import Path
import json
import sys

source, output, node_id, node_label = sys.argv[1:]
text = Path(source).read_text()

helper_anchor = """    function setSignal(latency) {
"""
mapping = json.dumps({node_id: node_label}, ensure_ascii=False, separators=(",", ":"))
helper = f"""    // GAME_V2_PANEL_PAGE_V1: display names only; backend identity stays unchanged.
    const PANEL_DISPLAY_LABELS = {mapping};

    function displayNodeLabel(nodeId, rawLabel) {{
      return Object.prototype.hasOwnProperty.call(PANEL_DISPLAY_LABELS, nodeId)
        ? PANEL_DISPLAY_LABELS[nodeId]
        : (rawLabel || nodeId || "—");
    }}

"""
if text.count(helper_anchor) != 1:
    raise SystemExit("display helper anchor is missing or ambiguous")
text = text.replace(helper_anchor, helper + helper_anchor, 1)

old_node_label = "        label: parts[1] || parts[0],\n"
new_node_label = "        label: displayNodeLabel(parts[0], parts[1] || parts[0]),\n"
if text.count(old_node_label) != 1:
    raise SystemExit("node list label assignment is missing or ambiguous")
text = text.replace(old_node_label, new_node_label, 1)

old_current_label = '      currentNodeLabel = status.WG_NODE_LABEL || currentNode || "—";\n'
new_current_label = '      currentNodeLabel = displayNodeLabel(currentNode, status.WG_NODE_LABEL || currentNode || "—");\n'
if text.count(old_current_label) != 1:
    raise SystemExit("current node label assignment is missing or ambiguous")
text = text.replace(old_current_label, new_current_label, 1)

Path(output).write_text(text)
PY
  validate_candidate "$output"
}

validate_candidate() {
  page="$1"
  [ -s "$page" ] || die 'panel candidate is empty'
  grep -Fq 'const API_ENDPOINT = "/cgi-bin/wg_api.sh";' "$page" || die 'panel API endpoint is missing'
  grep -Fq 'const NODES_ENDPOINT = "/cgi-bin/wg_nodes.sh";' "$page" || die 'panel node endpoint is missing'
  grep -Fq 'GAME_V2_PANEL_PAGE_V1' "$page" || die 'panel method marker is missing'
  grep -Fq 'function displayNodeLabel(nodeId, rawLabel)' "$page" || die 'display label helper is missing'
  grep -Fq "\"$PANEL_NODE_ID\"" "$page" || die 'configured node ID is missing from page mapping'
  grep -Fq "$PANEL_NODE_LABEL" "$page" || die 'configured display label is missing from page mapping'
  [ "$(grep -Fc 'function displayNodeLabel(nodeId, rawLabel)' "$page")" -eq 1 ] || die 'display label helper is duplicated'
}

pin_one_host() {
  host="$1"
  output="$2"
  scan="$LOCAL_TMP/keyscan"
  : >"$scan"
  ssh-keyscan -T 5 -t ed25519 "$host" >"$scan" 2>/dev/null || return 1
  [ -s "$scan" ] || return 1
  actual=$(ssh-keygen -lf "$scan" -E sha256 2>/dev/null | awk '{print $2}' | sort -u)
  [ "$actual" = "$OPENWRT_ED25519_FP" ] || die "OpenWrt host fingerprint mismatch for $host"
  cp "$scan" "$output"
}

prepare_ssh() {
  require_remote_config
  need ssh
  need scp
  need ssh-keyscan
  need ssh-keygen
  ensure_tmp
  host_keys="$LOCAL_TMP/openwrt.known_hosts"
  if pin_one_host "$OPENWRT_HOST" "$host_keys"; then
    OPENWRT_SELECTED_HOST="$OPENWRT_HOST"
  elif [ -n "$OPENWRT_FALLBACK_HOST" ] && pin_one_host "$OPENWRT_FALLBACK_HOST" "$host_keys"; then
    OPENWRT_SELECTED_HOST="$OPENWRT_FALLBACK_HOST"
  else
    die 'no configured OpenWrt management address is reachable with the pinned host key'
  fi
  cp "$host_keys" "$LOCAL_KNOWN_HOSTS"
}

ssh_openwrt() {
  ssh -i "$SSH_IDENTITY" -o BatchMode=yes -o ConnectTimeout=10 \
    -o ServerAliveInterval=5 -o ServerAliveCountMax=3 \
    -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$LOCAL_KNOWN_HOSTS" \
    "root@$OPENWRT_SELECTED_HOST" "$@"
}

scp_to_openwrt() {
  scp -O -q -i "$SSH_IDENTITY" -o BatchMode=yes -o ConnectTimeout=10 \
    -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$LOCAL_KNOWN_HOSTS" \
    "$1" "root@$OPENWRT_SELECTED_HOST:$2"
}

scp_from_openwrt() {
  scp -O -q -i "$SSH_IDENTITY" -o BatchMode=yes -o ConnectTimeout=10 \
    -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$LOCAL_KNOWN_HOSTS" \
    "root@$OPENWRT_SELECTED_HOST:$1" "$2"
}

remote_call() {
  action="$1"
  transaction=${2:-none}
  command="/bin/sh -s -- '$action' '$CLIENT_ID' '$PANEL_NODE_ID' '$PANEL_EXPECTED_FEC' '$PANEL_REQUIRE_NETWORK' '$transaction' '$ROLLBACK_SECONDS'"
  ssh_openwrt "$command" <<'REMOTE'
set -eu

action=$1
client_id=$2
node_id=$3
configured_fec=$4
require_network=$5
requested_txn=$6
rollback_seconds=$7

state="/etc/game-v2/panel-page-$client_id"
active="$state/active-transaction"
backup_root="/root/game-v2-panel-page-backups/$client_id"
page='/www/wgpanel.html'

say() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

read_status() {
  target="$1"
  wget -qO "$target" 'http://127.0.0.1/cgi-bin/wg_api.sh?action=status'
}

status_value() {
  key="$1"
  file="$2"
  sed -n "s/^$key=//p" "$file" | sed -n '1p'
}

assert_api_state() {
  status_file="$1"
  expected_fec="$2"
  [ "$(status_value WG_NODE "$status_file")" = "$node_id" ] || die 'panel API selected a different node'
  [ "$(status_value WG_FEC_EFFECTIVE "$status_file")" = "$expected_fec" ] || die 'panel API FEC changed'
  [ "$(status_value WG_TRANSPORT_STATE "$status_file")" = running ] || die 'panel transport is not running'
  if [ "$require_network" = reachable ]; then
    [ "$(status_value WG_NETWORK_STATE "$status_file")" = reachable ] || die 'panel network is not reachable'
    status_value WG_LATENCY_MS "$status_file" | grep -Eq '^[0-9]+([.][0-9]+)?$' || die 'panel latency is missing'
  fi
}

cancel_rollback() {
  dir="$1"
  pid=$(cat "$dir/timer.pid" 2>/dev/null || true)
  case "$pid" in ''|*[!0-9]*) ;; *)
    if [ -r "/proc/$pid/cmdline" ] && tr '\000' ' ' <"/proc/$pid/cmdline" | grep -F "$dir/timer.sh" >/dev/null; then
      kill "$pid" >/dev/null 2>&1 || true
    fi
    ;;
  esac
  rm -f "$dir/timer.pid" "$dir/rollback.pending"
}

write_rollback() {
  dir="$1"
  txn="$2"
  cat >"$dir/rollback.sh" <<EOF
#!/bin/sh
set -u
dir='$dir'
page='$page'
[ -e "\$dir/rollback.pending" ] || exit 0
mv "\$dir/rollback.pending" "\$dir/rollback.claimed" 2>/dev/null || exit 0
case "\$(cat "\$dir/page-state")" in
  present)
    cp "\$dir/wgpanel.html" "\$page.rollback"
    chmod 644 "\$page.rollback"
    mv "\$page.rollback" "\$page"
    ;;
  absent) rm -f "\$page" "\$page.rollback" ;;
  *) exit 1 ;;
esac
rm -f '$active' '/tmp/game-v2-panel-page-$client_id-$txn.html' "\$dir/rollback.claimed"
printf '%s\n' rolled-back >"\$dir/final-state"
EOF
  chmod 700 "$dir/rollback.sh"
  cat >"$dir/timer.sh" <<EOF
#!/bin/sh
sleep $rollback_seconds
exec /bin/sh '$dir/rollback.sh'
EOF
  chmod 700 "$dir/timer.sh"
}

arm_rollback() {
  dir="$1"
  : >"$dir/rollback.pending"
  setsid "$dir/timer.sh" >"$dir/timer.log" 2>&1 </dev/null &
  printf '%s\n' "$!" >"$dir/timer.pid"
  kill -0 "$(cat "$dir/timer.pid")" 2>/dev/null
}

verify_pending() {
  expected_txn=${1:-}
  [ -s "$active" ] || die 'no pending panel page transaction'
  . "$active"
  [ -z "$expected_txn" ] || [ "$TXN" = "$expected_txn" ] || die 'panel page transaction mismatch'
  [ -e "$BACKUP_DIR/rollback.pending" ] || die 'panel page rollback is no longer armed'
  [ ! -e "$BACKUP_DIR/rollback.claimed" ] || die 'panel page rollback is already running'
  cmp -s "$page" "$BACKUP_DIR/candidate.html" || die 'served page differs from the reviewed candidate'
  grep -Fq 'GAME_V2_PANEL_PAGE_V1' "$page" || die 'served page method marker is missing'
  grep -Fq "\"$node_id\"" "$page" || die 'served page node mapping is missing'
  wget -qO "$BACKUP_DIR/nodes.current" 'http://127.0.0.1/cgi-bin/wg_nodes.sh' || die 'node API failed'
  cmp -s "$BACKUP_DIR/nodes.before" "$BACKUP_DIR/nodes.current" || die 'backend node API changed during page deployment'
  grep -q "^$node_id|" "$BACKUP_DIR/nodes.current" || die 'configured backend node is missing'
  read_status "$BACKUP_DIR/status.current" || die 'status API failed'
  assert_api_state "$BACKUP_DIR/status.current" "$EXPECTED_FEC"
  say "PANEL_PAGE_VERIFY_PASS transaction=$TXN node=$node_id fec=$EXPECTED_FEC backend=unchanged rollback=armed"
}

inspect() {
  grep -Fq 'OpenWrt' /etc/openwrt_release || die 'target is not OpenWrt'
  command -v wget >/dev/null 2>&1 || die 'wget is missing'
  command -v setsid >/dev/null 2>&1 || die 'setsid is missing'
  nodes="/tmp/game-v2-panel-nodes-$$"
  status="/tmp/game-v2-panel-status-$$"
  trap 'rm -f "$nodes" "$status"' EXIT HUP INT TERM
  wget -qO "$nodes" 'http://127.0.0.1/cgi-bin/wg_nodes.sh' || die 'node API failed'
  grep -q "^$node_id|" "$nodes" || die 'configured backend node is missing'
  read_status "$status" || die 'status API failed'
  observed_fec=$(status_value WG_FEC_EFFECTIVE "$status")
  [ -n "$observed_fec" ] || die 'status API returned no effective FEC'
  [ -z "$configured_fec" ] || [ "$configured_fec" = "$observed_fec" ] || die 'configured FEC differs from the active backend'
  assert_api_state "$status" "$observed_fec"
  page_state=absent
  [ ! -s "$page" ] || page_state=present
  pending=no
  [ ! -s "$active" ] || pending=yes
  say "PANEL_PAGE_INSPECT_PASS client=$client_id host=$(uci -q get system.@system[0].hostname || printf unknown) node=$node_id fec=$observed_fec network=$require_network page=$page_state pending=$pending"
}

prepare() {
  txn="$requested_txn"
  case "$txn" in none|'') die 'missing panel page transaction' ;; esac
  inspect >/dev/null
  [ ! -s "$active" ] || die 'another panel page transaction is pending'
  dir="$backup_root/$txn"
  [ ! -e "$dir" ] || die 'panel page transaction already exists'
  mkdir -p "$state" "$dir"
  chmod 700 "$state" "$dir"
  if [ -e "$page" ]; then
    cp "$page" "$dir/wgpanel.html"
    chmod 600 "$dir/wgpanel.html"
    printf '%s\n' present >"$dir/page-state"
  else
    printf '%s\n' absent >"$dir/page-state"
  fi
  wget -qO "$dir/nodes.before" 'http://127.0.0.1/cgi-bin/wg_nodes.sh' || die 'cannot snapshot node API'
  read_status "$dir/status.before" || die 'cannot snapshot status API'
  observed_fec=$(status_value WG_FEC_EFFECTIVE "$dir/status.before")
  [ -n "$observed_fec" ] || die 'cannot read active FEC'
  [ -z "$configured_fec" ] || [ "$configured_fec" = "$observed_fec" ] || die 'configured FEC differs from active backend'
  assert_api_state "$dir/status.before" "$observed_fec"
  chmod 600 "$dir/page-state" "$dir/nodes.before" "$dir/status.before"
  write_rollback "$dir" "$txn"
  cat >"$active" <<EOF
TXN='$txn'
BACKUP_DIR='$dir'
EXPECTED_FEC='$observed_fec'
EOF
  chmod 600 "$active"
  if ! arm_rollback "$dir"; then
    /bin/sh "$dir/rollback.sh" || true
    die 'failed to arm panel page rollback'
  fi
  say "PANEL_PAGE_PREPARE_PASS transaction=$txn backup=$dir rollback=armed-${rollback_seconds}s scope=/www/wgpanel.html-only"
}

apply() {
  txn="$requested_txn"
  [ -s "$active" ] || die 'no prepared panel page transaction'
  . "$active"
  [ "$TXN" = "$txn" ] || die 'panel page transaction mismatch'
  staged="/tmp/game-v2-panel-page-$client_id-$txn.html"
  [ -s "$staged" ] || die 'staged panel page is missing'
  grep -Fq 'const API_ENDPOINT = "/cgi-bin/wg_api.sh";' "$staged" || die 'staged API endpoint is missing'
  grep -Fq 'const NODES_ENDPOINT = "/cgi-bin/wg_nodes.sh";' "$staged" || die 'staged node endpoint is missing'
  grep -Fq 'GAME_V2_PANEL_PAGE_V1' "$staged" || die 'staged method marker is missing'
  grep -Fq "\"$node_id\"" "$staged" || die 'staged node mapping is missing'
  cp "$staged" "$BACKUP_DIR/candidate.html"
  chmod 600 "$BACKUP_DIR/candidate.html"
  cp "$staged" "$page.new"
  chmod 644 "$page.new"
  mv "$page.new" "$page"
  rm -f "$staged"
  verify_pending "$txn"
  say "PANEL_PAGE_APPLY_PASS transaction=$txn scope=/www/wgpanel.html-only next=browser-QA"
}

verify_current() {
  inspect
  [ -s "$page" ] || die 'panel page is missing'
  grep -Fq 'GAME_V2_PANEL_PAGE_V1' "$page" || die 'installed page method marker is missing'
  grep -Fq "\"$node_id\"" "$page" || die 'installed page node mapping is missing'
  if [ -s "$active" ]; then
    verify_pending
  else
    say "PANEL_PAGE_CURRENT_PASS client=$client_id node=$node_id transaction=committed-or-external"
  fi
}

commit() {
  [ -s "$active" ] || die 'no pending panel page transaction'
  . "$active"
  verify_pending "$TXN"
  cancel_rollback "$BACKUP_DIR"
  [ ! -e "$BACKUP_DIR/rollback.claimed" ] || die 'automatic rollback already claimed the transaction'
  cmp -s "$page" "$BACKUP_DIR/candidate.html" || die 'page changed while cancelling rollback'
  printf '%s\n' committed >"$BACKUP_DIR/final-state"
  rm -f "$active"
  say "PANEL_PAGE_COMMIT_PASS transaction=$TXN backup=$BACKUP_DIR rollback=cancelled"
}

rollback() {
  if [ ! -s "$active" ]; then
    say 'PANEL_PAGE_ROLLBACK_NO_PENDING'
    return 0
  fi
  . "$active"
  [ "$requested_txn" = none ] || [ "$TXN" = "$requested_txn" ] || die 'panel page rollback transaction mismatch'
  backup_dir="$BACKUP_DIR"
  transaction="$TXN"
  /bin/sh "$backup_dir/rollback.sh"
  cancel_rollback "$backup_dir"
  [ ! -s "$active" ] || die 'panel page rollback did not clear active transaction'
  case "$(cat "$backup_dir/page-state")" in
    present) cmp -s "$page" "$backup_dir/wgpanel.html" || die 'restored page differs from backup' ;;
    absent) [ ! -e "$page" ] || die 'rollback did not remove newly installed page' ;;
  esac
  say "PANEL_PAGE_ROLLBACK_PASS transaction=$transaction backup=$backup_dir"
}

status() {
  if [ -s "$active" ]; then
    . "$active"
    timer=missing
    [ ! -e "$BACKUP_DIR/rollback.pending" ] || timer=armed
    [ ! -e "$BACKUP_DIR/rollback.claimed" ] || timer=claimed
    say "PANEL_PAGE_STATUS client=$client_id transaction=$TXN rollback=$timer backup=$BACKUP_DIR"
  else
    say "PANEL_PAGE_STATUS client=$client_id transaction=none"
  fi
  inspect
}

case "$action" in
  inspect) inspect ;;
  prepare) prepare ;;
  apply) apply ;;
  verify) verify_current ;;
  commit) commit ;;
  rollback) rollback ;;
  status) status ;;
  *) die "unknown remote action: $action" ;;
esac
REMOTE
}

cmd=${1:-}
[ -n "$cmd" ] || { usage; exit 1; }
case "$cmd" in
  -h|--help|help) usage; exit 0 ;;
  --version) say "$VERSION"; exit 0 ;;
esac
[ "$#" -ge 2 ] || { usage; exit 1; }
config=$2
load_config "$config"

case "$cmd" in
  build)
    [ "$#" -eq 3 ] || die 'build requires CONFIG and OUTPUT_HTML'
    build_candidate "$3"
    say "PANEL_PAGE_BUILD_PASS client=$CLIENT_ID node=$PANEL_NODE_ID output=$3 production_write=no"
    ;;
  inspect)
    [ "$#" -eq 2 ] || die 'inspect requires only CONFIG'
    prepare_ssh
    remote_call inspect
    ;;
  apply)
    [ "$#" -eq 2 ] || die 'apply requires only CONFIG'
    ensure_tmp
    candidate="$LOCAL_TMP/wgpanel.html"
    build_candidate "$candidate"
    prepare_ssh
    remote_call inspect
    txn="panel-$CLIENT_ID-$(date -u +%Y%m%dT%H%M%SZ)-$$"
    if ! remote_call prepare "$txn"; then
      remote_call rollback "$txn" || true
      die 'panel page prepare failed; rollback was requested'
    fi
    if ! scp_to_openwrt "$candidate" "/tmp/game-v2-panel-page-$CLIENT_ID-$txn.html"; then
      remote_call rollback "$txn" || true
      die 'panel page upload failed; backup was restored'
    fi
    if ! remote_call apply "$txn"; then
      remote_call rollback "$txn" || true
      die 'panel page apply or technical verification failed; backup was restored'
    fi
    say "PANEL_PAGE_DEPLOY_PASS transaction=$txn rollback=armed-${ROLLBACK_SECONDS}s next=browser-QA-then-commit"
    ;;
  verify)
    [ "$#" -eq 2 ] || die 'verify requires only CONFIG'
    ensure_tmp
    expected="$LOCAL_TMP/wgpanel.expected.html"
    installed="$LOCAL_TMP/wgpanel.installed.html"
    build_candidate "$expected"
    prepare_ssh
    scp_from_openwrt /www/wgpanel.html "$installed" || die 'cannot read installed panel page'
    cmp -s "$expected" "$installed" || die 'installed page differs from the generated reviewed candidate'
    remote_call verify
    say "PANEL_PAGE_VERIFY_EXACT_PASS client=$CLIENT_ID node=$PANEL_NODE_ID"
    ;;
  status)
    [ "$#" -eq 2 ] || die 'status requires only CONFIG'
    prepare_ssh
    remote_call status
    ;;
  commit)
    [ "$#" -eq 2 ] || die 'commit requires only CONFIG'
    prepare_ssh
    remote_call commit
    ;;
  rollback)
    [ "$#" -eq 2 ] || die 'rollback requires only CONFIG'
    prepare_ssh
    remote_call rollback
    ;;
  *) usage; die "unknown command: $cmd" ;;
esac
