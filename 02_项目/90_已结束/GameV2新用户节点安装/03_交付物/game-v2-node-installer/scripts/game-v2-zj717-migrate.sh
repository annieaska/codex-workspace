#!/bin/sh
set -eu

# Zhao Jie zj717 controlled migration and panel repair, version 1.5.5.
# One controller contains local orchestration and both endpoint operations.
# Scope: zj717 only. It never owns the host-wide firewall restore source.

VERSION='1.5.5'
CLIENT_ID='zj717'
VPS_HOST='91.223.119.134'
OPENWRT_HOST='192.168.66.30'
OPENWRT_LAN_HOST='192.168.7.17'
CY507_HOST='192.168.50.7'
VPS_ED25519_FP='SHA256:j/Jq0yCEWnSG7xLSFERc6dm7f4nQB0l188r0CUQVOdc'
OPENWRT_ED25519_FP='SHA256:3Zx4lDEXzSYqSh1/+4IgZq9dJ7rqaHXJQY69sAcM26g'
SSH_IDENTITY="${HOME}/.ssh/id_ed25519"

WG_IF='gv2_zj717'
WG_PORT='51873'
SERVER_SPEED_PORT='40973'
CLIENT_SPEED_PORT='30973'
FAKETCP_LOCAL_PORT='31973'
SERVER_WG_IP='10.77.3.1'
SERVER_WG_ADDR='10.77.3.1/30'
CLIENT_WG_IP='10.77.3.2'
CLIENT_WG_ADDR='10.77.3.2/30'
ROUTE_CIDR='192.168.7.0/24'
ROUTE_TABLE='51873'
GAME_DEVICE_IP='192.168.7.108'
GAME_DEVICE_PORT='3074'
PUBLIC_GAME_PORT='23075'
VPS_WAN_IFACE='ens3'
ROLLBACK_SECONDS='1800'

REMOTE_SCRIPT='/tmp/game-v2-zj717-migrate.sh'
LOCAL_KNOWN_HOSTS=''
SELF_PATH=''
PANEL_LOCAL_TMP=''

say() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1"; }

usage() {
  cat <<'EOF'
Usage:
  game-v2-zj717-migrate.sh inspect
  game-v2-zj717-migrate.sh apply
  game-v2-zj717-migrate.sh verify
  game-v2-zj717-migrate.sh status
  game-v2-zj717-migrate.sh commit
  game-v2-zj717-migrate.sh rollback
  game-v2-zj717-migrate.sh repair-panel
  game-v2-zj717-migrate.sh repair-panel-status
  game-v2-zj717-migrate.sh repair-status-latency
  game-v2-zj717-migrate.sh reinstall-panel-page
  game-v2-zj717-migrate.sh commit-panel-page
  game-v2-zj717-migrate.sh rollback-panel-page

inspect is read-only. apply creates endpoint backups, arms independent 30-minute
rollback timers, then uploads this single script, migrates only zj717 and verifies the
technical path. A successful apply leaves both rollback timers armed for the
Xbox test. Run commit only after NAT is Open, DNS works and online play works.
repair-panel archives the existing zj717 page in its rollback backup, copies the
verified cy507 page, and installs zj717-only control hooks. It creates independent
endpoint rollback timers and cancels them only after the page, node and status
checks match the running zj717 profile.
repair-panel-status updates only the zj717 OpenWrt status hook and page verdict.
It preserves the active FEC preset and uses a 15-minute local rollback timer.
repair-status-latency updates only the zj717 OpenWrt FEC coordinator. It removes
the duplicate remote verification from routine page status reads while retaining
paired verification for apply and explicit verify commands. It uses a 15-minute
local rollback timer and performs no VPS write.
reinstall-panel-page replaces only /www/wgpanel.html with the current cy507 page
and maps the zj717 node name to 荷兰 in the browser. It does not modify any
profile, CGI, controller, status hook, service or VPS object. Its 15-minute
rollback remains armed for real browser QA; then use commit-panel-page.
EOF
}

# ---------- local controller ----------

cleanup_local() {
  if [ -n "$LOCAL_KNOWN_HOSTS" ]; then
    rm -f "$LOCAL_KNOWN_HOSTS" "${LOCAL_KNOWN_HOSTS}.vps" "${LOCAL_KNOWN_HOSTS}.ow"
  fi
  case "$PANEL_LOCAL_TMP" in
    /tmp/game-v2-zj717-panel-local.*) rm -rf "$PANEL_LOCAL_TMP" ;;
  esac
}

resolve_self_path() {
  SELF_PATH="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/$(basename -- "$0")"
  [ -r "$SELF_PATH" ] || die 'cannot locate controller script'
}

pin_one_host() {
  host="$1"
  expected="$2"
  scan="$3"
  ssh-keyscan -T 8 -t ed25519 "$host" >"$scan" 2>/dev/null || return 1
  actual="$(ssh-keygen -E sha256 -lf "$scan" | awk 'NR==1 {print $2}')"
  [ "$actual" = "$expected" ] || die "SSH host fingerprint mismatch for $host: $actual"
  cat "$scan" >>"$LOCAL_KNOWN_HOSTS"
}

prepare_ssh() {
  need ssh
  need scp
  need ssh-keyscan
  need ssh-keygen
  [ -r "$SSH_IDENTITY" ] || die "SSH identity missing: $SSH_IDENTITY"
  LOCAL_KNOWN_HOSTS="$(mktemp /tmp/game-v2-zj717-known-hosts.XXXXXX)"
  trap cleanup_local EXIT
  trap 'cleanup_local; exit 130' HUP INT TERM
  : >"$LOCAL_KNOWN_HOSTS"
  pin_one_host "$VPS_HOST" "$VPS_ED25519_FP" "${LOCAL_KNOWN_HOSTS}.vps" || die "cannot scan SSH key for $VPS_HOST"
  if ! pin_one_host "$OPENWRT_HOST" "$OPENWRT_ED25519_FP" "${LOCAL_KNOWN_HOSTS}.ow"; then
    OPENWRT_HOST="$OPENWRT_LAN_HOST"
    pin_one_host "$OPENWRT_HOST" "$OPENWRT_ED25519_FP" "${LOCAL_KNOWN_HOSTS}.ow" || die 'neither Zhao Nebula nor LAN SSH address is reachable'
  fi
  cat "${LOCAL_KNOWN_HOSTS}.vps" "${LOCAL_KNOWN_HOSTS}.ow" >"$LOCAL_KNOWN_HOSTS"
  rm -f "${LOCAL_KNOWN_HOSTS}.vps" "${LOCAL_KNOWN_HOSTS}.ow"
}

prepare_openwrt_ssh() {
  need ssh
  need scp
  need ssh-keyscan
  need ssh-keygen
  [ -r "$SSH_IDENTITY" ] || die "SSH identity missing: $SSH_IDENTITY"
  LOCAL_KNOWN_HOSTS="$(mktemp /tmp/game-v2-zj717-known-hosts.XXXXXX)"
  trap cleanup_local EXIT
  trap 'cleanup_local; exit 130' HUP INT TERM
  : >"$LOCAL_KNOWN_HOSTS"
  if ! pin_one_host "$OPENWRT_HOST" "$OPENWRT_ED25519_FP" "${LOCAL_KNOWN_HOSTS}.ow"; then
    OPENWRT_HOST="$OPENWRT_LAN_HOST"
    pin_one_host "$OPENWRT_HOST" "$OPENWRT_ED25519_FP" "${LOCAL_KNOWN_HOSTS}.ow" || \
      die 'neither Zhao Nebula nor LAN SSH address is reachable'
  fi
  cat "${LOCAL_KNOWN_HOSTS}.ow" >"$LOCAL_KNOWN_HOSTS"
  rm -f "${LOCAL_KNOWN_HOSTS}.ow"
}

ssh_vps() {
  ssh -i "$SSH_IDENTITY" -o BatchMode=yes -o ConnectTimeout=10 \
    -o ServerAliveInterval=5 -o ServerAliveCountMax=3 \
    -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$LOCAL_KNOWN_HOSTS" \
    "root@$VPS_HOST" "$@"
}

ssh_openwrt() {
  ssh -i "$SSH_IDENTITY" -o BatchMode=yes -o ConnectTimeout=10 \
    -o ServerAliveInterval=5 -o ServerAliveCountMax=3 \
    -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$LOCAL_KNOWN_HOSTS" \
    "root@$OPENWRT_HOST" "$@"
}

scp_to_vps() {
  scp -O -q -i "$SSH_IDENTITY" -o BatchMode=yes -o ConnectTimeout=10 \
    -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$LOCAL_KNOWN_HOSTS" \
    "$1" "root@$VPS_HOST:$2"
}

scp_to_openwrt() {
  scp -O -q -i "$SSH_IDENTITY" -o BatchMode=yes -o ConnectTimeout=10 \
    -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$LOCAL_KNOWN_HOSTS" \
    "$1" "root@$OPENWRT_HOST:$2"
}

scp_from_cy507() {
  scp -O -q -i "$SSH_IDENTITY" -o BatchMode=yes -o ConnectTimeout=10 \
    -o StrictHostKeyChecking=yes -o UserKnownHostsFile="${HOME}/.ssh/known_hosts" \
    "root@$CY507_HOST:$1" "$2"
}

scp_from_openwrt() {
  scp -O -q -i "$SSH_IDENTITY" -o BatchMode=yes -o ConnectTimeout=10 \
    -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$LOCAL_KNOWN_HOSTS" \
    "root@$OPENWRT_HOST:$1" "$2"
}

copy_package_vps_to_openwrt() {
  src="$1"
  dst="$2"
  ssh_openwrt "test ! -e '$dst' && mkdir -p '$dst' && chmod 700 '$dst'" || return 1
  if ! scp -O -3 -q -r -i "$SSH_IDENTITY" -o BatchMode=yes -o ConnectTimeout=10 \
    -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$LOCAL_KNOWN_HOSTS" \
    "root@$VPS_HOST:$src/"'*' "root@$OPENWRT_HOST:$dst/"; then
    ssh_openwrt "rm -rf '$dst'" || true
    return 1
  fi
}

local_readonly_gate() {
  prepare_ssh
  ssh_vps "
    set -eu
    test -r /etc/os-release
    test \"\$(uname -m)\" = x86_64
    systemctl is-active --quiet netfilter-persistent.service
    test \"\$(systemctl is-enabled iptables.service 2>/dev/null)\" = masked
    test \"\$(systemctl is-enabled ip6tables.service 2>/dev/null)\" = masked
    test \"\$(systemctl is-enabled nftables.service 2>/dev/null)\" = masked
    systemctl is-active --quiet game-v2-wg-zj717.service
    systemctl is-active --quiet game-v2-speed-zj717.service
    ip -4 addr show dev gv2_zj717 | grep -F '10.77.3.1/30' >/dev/null
    test \"\$(wg show gv2_zj717 peers | sed '/^\$/d' | wc -l | tr -d ' ')\" = 1
    test -s /etc/game-v2/clients/zj717/server.env
    test -s /var/lib/game-v2/server/clients/zj717/secrets/client-private.key
    test -x /usr/local/bin/game-v2-speederv2
    test -x /usr/local/lib/game-v2-cy507-faketcp/udp2raw
  "
  ssh_openwrt "
    set -eu
    test -r /etc/openwrt_release
    case \"\$(uname -m)\" in x86_64|amd64) ;; *) exit 21 ;; esac
    ip -4 addr show dev br-lan | grep -F '192.168.7.17/24' >/dev/null
    ip -4 addr show dev nebula19266 | grep -F '192.168.66.30/24' >/dev/null
    ip -4 route get 91.223.119.134 | grep -F 'dev br-lan' >/dev/null
    test -x /etc/init.d/wg-game-zhaojie-v2-transport
    test -d /usr/libexec/wg-game-zhaojie-v2
    uci -q get network.wg_zj >/dev/null
    uci -q get firewall.wg_zj_zone >/dev/null
  "
  say "read-only target gate passed: VPS $VPS_HOST and Zhao OpenWrt $OPENWRT_HOST (dual-address identity verified)"
}

remote_exec_vps() {
  ssh_vps "/bin/sh '$REMOTE_SCRIPT' '$1' ${2:-}"
}

remote_exec_openwrt() {
  ssh_openwrt "/bin/sh '$REMOTE_SCRIPT' '$1' ${2:-}"
}

remote_stdin_vps() {
  ssh_vps "/bin/sh -s -- '$1' ${2:-}" <"$SELF_PATH"
}

remote_stdin_openwrt() {
  ssh_openwrt "/bin/sh -s -- '$1' ${2:-}" <"$SELF_PATH"
}

local_inspect() {
  local_readonly_gate
  ssh_vps "
    printf 'VPS generic zj717: '; systemctl is-active game-v2-wg-zj717.service game-v2-speed-zj717.service | tr '\n' ' '; printf '\n'
    printf 'VPS overlay objects: '; test ! -e /var/lib/game-v2-zj717-fixed && echo absent || echo present
    printf 'VPS control plane: '; systemctl is-active netfilter-persistent.service
  "
  ssh_openwrt "
    printf 'OpenWrt legacy service: '; /etc/init.d/wg-game-zhaojie-v2-transport running && echo running || echo stopped
    printf 'OpenWrt legacy interface: '; ip -4 addr show dev wg_zj 2>/dev/null | sed -n 's/.*inet \\([^ ]*\\).*/\\1/p'
    printf 'OpenWrt new objects: '; test ! -e /etc/game-v2/zj717 && echo absent || echo present
  "
  say 'inspect passed; no remote files or runtime state were changed'
}

local_upload_controller() {
  txn="$1"
  [ -r "$SELF_PATH" ] || die 'controller script was not resolved before upload'
  scp_to_vps "$SELF_PATH" "$REMOTE_SCRIPT" || return 1
  scp_to_openwrt "$SELF_PATH" "$REMOTE_SCRIPT" || return 1
  ssh_vps "chmod 700 '$REMOTE_SCRIPT'" || return 1
  ssh_openwrt "chmod 700 '$REMOTE_SCRIPT'" || return 1
  say "controller uploaded for transaction $txn"
}

local_apply() {
  local_readonly_gate
  resolve_self_path
  txn="zj717-$(date -u +%Y%m%dT%H%M%SZ)-$$"
  vps_ready=no
  ow_ready=no
  if remote_stdin_vps _vps_prepare "$txn"; then vps_ready=yes; else
    remote_stdin_vps _vps_rollback "$txn" || true
    die 'VPS prepare failed; rollback was requested and endpoint status must be checked before retry'
  fi
  if remote_stdin_openwrt _ow_prepare "$txn"; then ow_ready=yes; else
    remote_stdin_openwrt _ow_rollback "$txn" || true
    [ "$vps_ready" = no ] || remote_stdin_vps _vps_rollback "$txn" || true
    die 'OpenWrt prepare failed; rollback was requested on prepared endpoints and status must be checked before retry'
  fi
  if ! local_upload_controller "$txn"; then
    remote_stdin_openwrt _ow_rollback "$txn" || true
    remote_stdin_vps _vps_rollback "$txn" || true
    die 'controller upload failed; rollback was requested on both endpoints and status must be checked before retry'
  fi
  if ! remote_exec_vps _vps_apply "$txn"; then
    remote_exec_openwrt _ow_rollback "$txn" || true
    remote_exec_vps _vps_rollback "$txn" || true
    die 'VPS apply failed; rollback was requested on both endpoints and status must be checked before retry'
  fi
  package="/var/backups/game-v2-zj717-migrate/$txn/package"
  remote_pkg="/tmp/game-v2-zj717-package-$txn"
  if ! copy_package_vps_to_openwrt "$package" "$remote_pkg"; then
    remote_exec_openwrt _ow_rollback "$txn" || true
    remote_exec_vps _vps_rollback "$txn" || true
    die 'secure package transfer failed; rollback was requested on both endpoints and status must be checked before retry'
  fi
  if ! ssh_openwrt "/bin/sh '$REMOTE_SCRIPT' _ow_apply '$txn' '$remote_pkg'"; then
    remote_exec_openwrt _ow_rollback "$txn" || true
    remote_exec_vps _vps_rollback "$txn" || true
    die 'OpenWrt apply failed; rollback was requested on both endpoints and status must be checked before retry'
  fi
  if ! remote_exec_vps _vps_verify '' || ! remote_exec_openwrt _ow_verify ''; then
    remote_exec_openwrt _ow_rollback "$txn" || true
    remote_exec_vps _vps_rollback "$txn" || true
    die 'technical verification failed; rollback was requested on both endpoints and status must be checked before retry'
  fi
  say "TECHNICAL_STAGE_PASS transaction=$txn"
  say 'Both 30-minute rollback timers remain ARMED.'
  say 'Test Xbox NAT, DNS and online play now. Run commit only after all three pass.'
}

local_verify() {
  prepare_ssh
  resolve_self_path
  remote_stdin_vps _vps_verify
  remote_stdin_openwrt _ow_verify
  say 'technical verification passed on both endpoints'
}

local_status() {
  prepare_ssh
  resolve_self_path
  remote_stdin_vps _vps_status
  remote_stdin_openwrt _ow_status
}

local_commit() {
  prepare_ssh
  resolve_self_path
  remote_stdin_vps _vps_verify
  remote_stdin_openwrt _ow_verify
  vps_state="$(remote_stdin_vps _vps_txn_state)"
  ow_state="$(remote_stdin_openwrt _ow_txn_state)"
  case "$vps_state" in pending:*|commit-claimed:*|committed:*) ;; *) die "invalid VPS transaction state: $vps_state" ;; esac
  case "$ow_state" in pending:*|commit-claimed:*|committed:*) ;; *) die "invalid OpenWrt transaction state: $ow_state" ;; esac
  txn="${vps_state#*:}"
  [ -n "$txn" ] || die 'empty VPS transaction id'
  [ "${ow_state#*:}" = "$txn" ] || die "endpoint transaction mismatch: VPS=$vps_state OpenWrt=$ow_state"
  if ! remote_stdin_vps _vps_commit "$txn"; then
    die 'VPS commit result is uncertain; OpenWrt rollback remains armed, so inspect status and rerun commit promptly'
  fi
  if ! remote_stdin_openwrt _ow_commit "$txn"; then
    die 'OpenWrt commit result is uncertain after VPS commit; inspect status immediately; if OpenWrt is still pending, rerun commit before its deadline; if it already rolled back, keep the legacy route online and handle the idle VPS overlay separately'
  fi
  vps_state="$(remote_stdin_vps _vps_txn_state)"
  ow_state="$(remote_stdin_openwrt _ow_txn_state)"
  [ "$vps_state" = "committed:$txn" ] || die "VPS final transaction state is not committed: $vps_state"
  [ "$ow_state" = "committed:$txn" ] || die "OpenWrt final transaction state is not committed: $ow_state"
  say "zj717 committed: transaction=$txn; both automatic rollback timers cancelled"
}

local_rollback() {
  prepare_ssh
  resolve_self_path
  remote_stdin_openwrt _ow_rollback || true
  remote_stdin_vps _vps_rollback || true
  say 'zj717 rollback requested on both endpoints; inspect status before any retry'
}

local_panel_rollback() {
  txn="$1"
  remote_stdin_openwrt _panel_ow_rollback "$txn" || true
  remote_stdin_vps _panel_vps_rollback "$txn" || true
}

local_patch_panel_assets() {
  page="$1"
  controller="$2"
  python3 - "$page" "$controller" <<'PY'
from pathlib import Path
import sys

page_path = Path(sys.argv[1])
controller_path = Path(sys.argv[2])

def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)

page = page_path.read_text()
page = replace_once(
    page,
    '    const STATUS_REFRESH_MS = 10000;\n',
    '    const STATUS_REFRESH_MS = 10000;\n'
    '    const NODES_TIMEOUT_MS = 15000;\n'
    '    const ACTION_TIMEOUT_MS = 120000;\n'
    '    const STATUS_TIMEOUT_MS = 30000;\n'
    '    const STATUS_RETRY_MS = 1500;\n'
    '    const STATUS_RETRY_COUNT = 3;\n',
    'panel timeout constants',
)
page = replace_once(page, 'fetchWithTimeout(NODES_ENDPOINT, 5000)',
                    'fetchWithTimeout(NODES_ENDPOINT, NODES_TIMEOUT_MS)', 'nodes timeout')
page = replace_once(page, 'fetchWithTimeout(API_ENDPOINT + "?" + query, 8000)',
                    'fetchWithTimeout(API_ENDPOINT + "?" + query, ACTION_TIMEOUT_MS)', 'action timeout')
page = replace_once(
    page,
    '    let dialogReturnFocus = null;\n',
    '    let dialogReturnFocus = null;\n'
    '    let actionInFlight = false;\n',
    'panel action busy state',
)

old_refresh = '''    async function refreshStatus(options) {
      const quiet = options && options.quiet;
      refreshBtn.disabled = true;
      try {
        const response = await fetchWithTimeout(API_ENDPOINT + "?action=status", 8000);
        const body = await response.text();
        if (!response.ok) throw new Error("状态读取失败（HTTP " + response.status + "）");
        applyStatus(parseFields(body));
        if (!quiet) appendLog("状态同步成功，已更新目标节点探测结果。", "success");
      } catch (error) {
        setLiveState("error", "读取失败");
        animateText(document.getElementById("connection-verdict"), "无法读取网络状态");
        document.getElementById("probe-result").textContent = "状态接口错误";
        setSignal(null);
        appendLog(error.message || String(error), "error");
      } finally {
        refreshBtn.disabled = false;
      }
    }
'''
new_refresh = '''    async function readStatusWithRetry() {
      let lastError = new Error("状态读取失败");
      for (let attempt = 1; attempt <= STATUS_RETRY_COUNT; attempt += 1) {
        try {
          const response = await fetchWithTimeout(API_ENDPOINT + "?action=status", STATUS_TIMEOUT_MS);
          const body = await response.text();
          if (!response.ok) throw new Error("状态读取失败（HTTP " + response.status + "）");
          return parseFields(body);
        } catch (error) {
          lastError = error;
          if (attempt < STATUS_RETRY_COUNT) {
            await new Promise((resolve) => window.setTimeout(resolve, STATUS_RETRY_MS));
          }
        }
      }
      throw lastError;
    }

    async function refreshStatus(options) {
      const quiet = options && options.quiet;
      const force = options && options.force;
      if (actionInFlight && !force) return;
      refreshBtn.disabled = true;
      try {
        applyStatus(await readStatusWithRetry());
        if (!quiet) appendLog("状态同步成功，已更新目标节点探测结果。", "success");
      } catch (error) {
        if (actionInFlight && !force) return;
        if (quiet && String(error.message || error).includes("HTTP 409")) return;
        setLiveState("error", "读取失败");
        animateText(document.getElementById("connection-verdict"), "无法读取网络状态");
        document.getElementById("probe-result").textContent = "状态接口错误";
        setSignal(null);
        appendLog(error.message || String(error), "error");
      } finally {
        if (!actionInFlight) refreshBtn.disabled = false;
      }
    }
'''
page = replace_once(page, old_refresh, new_refresh, 'status retry flow')
page = replace_once(
    page,
    '''    async function withBusy(button, task) {
      const buttons = [applyBtn, confirmBtn, rollbackBtn, refreshBtn, dialogConfirm, dialogCancel];
      buttons.forEach((item) => { item.disabled = true; });
      const original = button.textContent;
      button.textContent = "处理中…";
      try {
        await task();
      } finally {
        button.textContent = original;
        buttons.forEach((item) => { item.disabled = false; });
        updateApplyButtonState();
      }
    }
''',
    '''    async function withBusy(button, task) {
      const buttons = [applyBtn, confirmBtn, rollbackBtn, refreshBtn, dialogConfirm, dialogCancel];
      actionInFlight = true;
      buttons.forEach((item) => { item.disabled = true; });
      const original = button.textContent;
      button.textContent = "处理中…";
      try {
        await task();
      } finally {
        actionInFlight = false;
        button.textContent = original;
        buttons.forEach((item) => { item.disabled = false; });
        updateApplyButtonState();
      }
    }
''',
    'panel action busy guard',
)
status_refresh_calls = page.count('await refreshStatus({ quiet: true });')
if status_refresh_calls != 4:
    raise SystemExit(f'post-action status refresh: expected four matches, found {status_refresh_calls}')
page = page.replace('await refreshStatus({ quiet: true });',
                    'await refreshStatus({ quiet: true, force: true });')
page = replace_once(
    page,
    '          const query = new URLSearchParams({\n            action: "apply",',
    '          appendLog("正在切换线路，通常需要约一分钟，请保持页面打开。");\n'
    '          const query = new URLSearchParams({\n            action: "apply",',
    'apply progress message',
)

copy_changes = {
    '选择已加入的游戏节点并查看真实延迟。线路失败时停止游戏加速，不会回退旧线路。':
        '选择已加入的游戏节点并查看真实延迟。切换失败或确认超时会恢复变更前的线路。',
    '切换时会先核对配置；启动失败、主动停止或确认超时都会断开游戏线路。':
        '切换时会先核对配置；启动失败、主动回退或确认超时都会恢复变更前的线路。',
    '请先确认 Xbox 联机可用；停止后不会回退旧线路。':
        '请先确认 Xbox 联机可用；需要撤销时可恢复变更前的线路。',
    '>停止并断开<': '>回退本次更改<',
    '如果新节点启动失败，游戏线路会停止且不会回退旧线路。':
        '如果新线路启动失败，控制器会恢复变更前的线路。',
    '停止并断开游戏线路？': '恢复变更前的线路？',
    '控制器会停止当前游戏线路，不会恢复变更前的线路。':
        '控制器会撤销本次切换，并恢复变更前的运行方式。',
    '确认停止': '确认回退',
    '游戏线路已停止，不会回退旧线路。': '已恢复变更前的游戏线路。',
    '停止失败：': '回退失败：',
}
for old, new in copy_changes.items():
    page = replace_once(page, old, new, f'copy: {old}')
page_path.write_text(page)

controller = controller_path.read_text()
old_lock = '''panel_acquire_lock() {
  mkdir -p "$PANEL_STATE_ROOT"
  if ! mkdir "$PANEL_LOCK_DIR" 2>/dev/null; then
    panel_die 'CONTROL_BUSY'
  fi
  trap 'rmdir "$PANEL_LOCK_DIR" 2>/dev/null || true' EXIT HUP INT TERM
}
'''
new_lock = '''panel_release_lock() {
  [ -d "$PANEL_LOCK_DIR" ] || return 0
  panel_lock_owner="$(sed -n '1p' "$PANEL_LOCK_DIR/pid" 2>/dev/null || true)"
  if [ -z "$panel_lock_owner" ] || [ "$panel_lock_owner" = "$$" ]; then
    rm -f "$PANEL_LOCK_DIR/pid"
    rmdir "$PANEL_LOCK_DIR" 2>/dev/null || true
  fi
}

panel_acquire_lock() {
  mkdir -p "$PANEL_STATE_ROOT"
  panel_lock_attempt=0
  while ! mkdir "$PANEL_LOCK_DIR" 2>/dev/null; do
    panel_lock_owner="$(sed -n '1p' "$PANEL_LOCK_DIR/pid" 2>/dev/null || true)"
    case "$panel_lock_owner" in
      ''|*[!0-9]*)
        if [ "$panel_lock_attempt" -ge 5 ]; then
          rmdir "$PANEL_LOCK_DIR" 2>/dev/null || true
        fi
        ;;
      *)
        if ! kill -0 "$panel_lock_owner" 2>/dev/null; then
          rm -f "$PANEL_LOCK_DIR/pid"
          rmdir "$PANEL_LOCK_DIR" 2>/dev/null || true
        fi
        ;;
    esac
    panel_lock_attempt=$((panel_lock_attempt + 1))
    [ "$panel_lock_attempt" -lt 60 ] || panel_die 'CONTROL_BUSY'
    sleep 1
  done
  printf '%s\\n' "$$" >"$PANEL_LOCK_DIR/pid"
  trap 'panel_release_lock' EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
}
'''
if old_lock in controller:
    controller = replace_once(controller, old_lock, new_lock, 'controller lock')
elif (controller.count('panel_release_lock() {') == 1
      and '"$PANEL_LOCK_DIR/pid"' in controller):
    pass
else:
    raise SystemExit('controller lock: neither original nor repaired implementation found')
controller_path.write_text(controller)
PY

  local_patch_panel_status_page "$page"
}

local_patch_panel_status_page() {
  page="$1"
  python3 - "$page" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
old = '''    function setNetworkVerdict(status, latency, hasLatencyTelemetry) {
      const verdict = document.getElementById("connection-verdict");
      const probe = document.getElementById("probe-result");
      if (status.WG_ENABLED !== "1") {
        animateText(verdict, "服务未运行");
        probe.textContent = "未执行目标探测";
        setLiveState("warning", "未运行");
        return;
      }
      if (status.WG_FEC_PAIR_STATE === "degraded") {
        animateText(verdict, "通道运行中，FEC 配对校验暂不可用");
        probe.textContent = "远端校验瞬时失败，可刷新重试";
        setLiveState("warning", "配对待复核");
        return;
      }
      if (!hasLatencyTelemetry) {
        animateText(verdict, "通道已启动，延时数据未配置");
        probe.textContent = "控制端未提供探测数据";
        setLiveState("warning", "延时未配置");
        return;
      }
      if (latency != null) {
        animateText(verdict, "已连接 " + currentNodeLabel);
        probe.textContent = "目标已响应 · 单个探测包";
        setLiveState("online", "目标已响应");
        return;
      }
      animateText(verdict, "通道已启动，目标未响应");
      probe.textContent = "单个探测包无响应";
      setLiveState("error", "探测失败");
    }
'''
new = '''    function setNetworkVerdict(status, latency, hasLatencyTelemetry) {
      const verdict = document.getElementById("connection-verdict");
      const probe = document.getElementById("probe-result");
      if (status.WG_ENABLED !== "1") {
        animateText(verdict, "服务未运行");
        probe.textContent = "未执行公网探测";
        setLiveState("warning", "未运行");
        return;
      }
      if (status.WG_FEC_PAIR_STATE === "degraded") {
        animateText(verdict, "通道运行中，FEC 配对校验暂不可用");
        probe.textContent = "远端校验瞬时失败，可刷新重试";
        setLiveState("warning", "配对待复核");
        return;
      }
      const transportRunning = status.WG_TRANSPORT_STATE === "running";
      const networkReachable = status.WG_NETWORK_STATE === "reachable" || latency != null;
      if (!transportRunning) {
        animateText(verdict, "通道未运行");
        probe.textContent = "请检查线路服务状态";
        setLiveState("error", "通道异常");
        return;
      }
      if (networkReachable) {
        animateText(verdict, "通道运行正常 · " + currentNodeLabel);
        probe.textContent = "公网已响应 · 经游戏隧道探测";
        setLiveState("online", "线路正常");
        return;
      }
      if (!hasLatencyTelemetry) {
        animateText(verdict, "通道运行中，延迟探针未配置");
        probe.textContent = "线路状态正常，暂无延迟数据";
        setLiveState("warning", "延迟未配置");
        return;
      }
      animateText(verdict, "通道运行中，公网延迟暂未取得");
      probe.textContent = "线路切换已生效，请刷新复核延迟";
      setLiveState("warning", "等待探测");
    }
'''
if old in text:
    text = text.replace(old, new, 1)
elif text.count('const networkReachable = status.WG_NETWORK_STATE === "reachable" || latency != null;') == 1:
    pass
else:
    raise SystemExit('panel network verdict: expected original or repaired implementation')
path.write_text(text)
PY
}

local_validate_panel_status_candidate() {
  page="$1"
  hook="$2"
  [ -s "$page" ] && [ -s "$hook" ] || die 'panel status candidate is empty'
  sh -n "$hook" || die 'panel status hook syntax check failed'
  grep -Fq 'const networkReachable = status.WG_NETWORK_STATE === "reachable" || latency != null;' "$page" || \
    die 'panel status verdict repair is missing'
  grep -Fq '通道运行中，公网延迟暂未取得' "$page" || die 'panel probe warning copy is missing'
  grep -Fq 'WG_NETWORK_STATE=%s' "$hook" || die 'panel network state output is missing'
  grep -Fq 'ping -I "$tunnel_if"' "$hook" || die 'tunnel-bound public probe is missing'
}

local_repair_panel_status() {
  resolve_self_path
  need python3
  txn="zj717-panel-status-$(date -u +%Y%m%dT%H%M%SZ)-$$"
  PANEL_LOCAL_TMP="$(mktemp -d /tmp/game-v2-zj717-panel-local.XXXXXX)"
  chmod 700 "$PANEL_LOCAL_TMP"
  trap cleanup_local EXIT
  trap 'exit 130' HUP INT TERM
  source_page="${ZJ717_PANEL_CANDIDATE_SOURCE:-}"
  dry_run_dir="${ZJ717_PANEL_CANDIDATE_DIR:-}"
  if [ -n "$source_page" ]; then
    [ -n "$dry_run_dir" ] || die 'ZJ717_PANEL_CANDIDATE_SOURCE is only allowed with ZJ717_PANEL_CANDIDATE_DIR'
    [ -s "$source_page" ] || die "candidate source page missing: $source_page"
    cp "$source_page" "$PANEL_LOCAL_TMP/wgpanel.html"
  else
    prepare_openwrt_ssh
    scp_from_openwrt /www/wgpanel.html "$PANEL_LOCAL_TMP/wgpanel.html" || \
      die 'cannot read the current zj717 panel page'
  fi
  local_patch_panel_status_page "$PANEL_LOCAL_TMP/wgpanel.html"
  panel_write_status_hook "$PANEL_LOCAL_TMP/status.sh"
  local_validate_panel_status_candidate "$PANEL_LOCAL_TMP/wgpanel.html" "$PANEL_LOCAL_TMP/status.sh"

  if [ -n "$dry_run_dir" ]; then
    mkdir -p "$dry_run_dir"
    cp "$PANEL_LOCAL_TMP/wgpanel.html" "$dry_run_dir/wgpanel.html"
    cp "$PANEL_LOCAL_TMP/status.sh" "$dry_run_dir/status.sh"
    say "ZJ717_PANEL_STATUS_CANDIDATE_PASS output=$dry_run_dir production_write=no"
    return 0
  fi

  expected_fec="$(ssh_openwrt "sed -n 's/^preset=//p' '$PANEL_OW_FEC_STATE' | sed -n '1p'")"
  panel_validate_preset "$expected_fec" || die "invalid active zj717 FEC preset: $expected_fec"
  if ! remote_stdin_openwrt _panel_status_prepare "$txn"; then
    remote_stdin_openwrt _panel_status_rollback "$txn" || true
    die 'zj717 panel status prepare failed; rollback was requested'
  fi
  if ! scp_to_openwrt "$PANEL_LOCAL_TMP/wgpanel.html" "/tmp/game-v2-zj717-panel-status-$txn.wgpanel.html" || \
     ! scp_to_openwrt "$PANEL_LOCAL_TMP/status.sh" "/tmp/game-v2-zj717-panel-status-$txn.status.sh"; then
    remote_stdin_openwrt _panel_status_rollback "$txn" || true
    die 'zj717 panel status staging failed; rollback was requested'
  fi
  if ! remote_stdin_openwrt _panel_status_apply "$txn"; then
    remote_stdin_openwrt _panel_status_rollback "$txn" || true
    die 'zj717 panel status apply failed; backup was restored'
  fi
  if ! remote_stdin_openwrt _panel_status_verify "$expected_fec"; then
    remote_stdin_openwrt _panel_status_rollback "$txn" || true
    die 'zj717 panel status verification failed; backup was restored'
  fi
  remote_stdin_openwrt _panel_status_commit "$txn" || \
    die 'zj717 panel status commit is uncertain; inspect the OpenWrt rollback timer immediately'
  say "ZJ717_PANEL_STATUS_REPAIR_PASS transaction=$txn fec=$expected_fec rollback=cancelled"
}

# Build the Zhao page from the current cy507 production page. The only change is
# a browser-side display alias; the APIs and every backend object remain intact.
local_patch_panel_page_display() {
  page="$1"
  python3 - "$page" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()

display_helper = '''    function displayNodeLabel(nodeId, rawLabel) {
      return nodeId === "nl-zhaojie-v2" ? "荷兰" : (rawLabel || nodeId || "—");
    }

'''
helper_anchor = '''    function setSignal(latency) {
'''
if 'function displayNodeLabel(nodeId, rawLabel)' not in text:
    if text.count(helper_anchor) != 1:
        raise SystemExit('display label helper anchor is missing or ambiguous')
    text = text.replace(helper_anchor, display_helper + helper_anchor, 1)

old_node_label = '''        label: parts[1] || parts[0],
'''
new_node_label = '''        label: displayNodeLabel(parts[0], parts[1] || parts[0]),
'''
if old_node_label in text:
    text = text.replace(old_node_label, new_node_label, 1)
elif text.count(new_node_label) != 1:
    raise SystemExit('node list display label assignment is missing or ambiguous')

old_current_label = '''      currentNodeLabel = status.WG_NODE_LABEL || currentNode || "—";
'''
new_current_label = '''      currentNodeLabel = displayNodeLabel(currentNode, status.WG_NODE_LABEL || currentNode || "—");
'''
if old_current_label in text:
    text = text.replace(old_current_label, new_current_label, 1)
elif text.count(new_current_label) != 1:
    raise SystemExit('current node display label assignment is missing or ambiguous')

path.write_text(text)
PY
}

local_validate_panel_page_candidate() {
  page="$1"
  [ -s "$page" ] || die 'panel page candidate is empty'
  grep -Fq 'const API_ENDPOINT = "/cgi-bin/wg_api.sh";' "$page" || die 'cy507 API endpoint is missing'
  grep -Fq 'const NODES_ENDPOINT = "/cgi-bin/wg_nodes.sh";' "$page" || die 'cy507 node endpoint is missing'
  grep -Fq 'function displayNodeLabel(nodeId, rawLabel)' "$page" || die 'frontend label helper is missing'
  grep -Fq 'return nodeId === "nl-zhaojie-v2" ? "荷兰"' "$page" || die 'frontend 荷兰 alias is missing'
  grep -Fq 'label: displayNodeLabel(parts[0], parts[1] || parts[0]),' "$page" || die 'node list alias is missing'
  grep -Fq 'currentNodeLabel = displayNodeLabel(currentNode, status.WG_NODE_LABEL || currentNode || "—");' "$page" || \
    die 'current node alias is missing'
  [ "$(grep -Fc 'function displayNodeLabel(nodeId, rawLabel)' "$page")" -eq 1 ] || \
    die 'frontend label helper is duplicated'
}

local_validate_status_latency_candidate() {
  coordinator="$1"
  [ -s "$coordinator" ] || die 'status latency coordinator candidate is empty'
  sh -n "$coordinator" || die 'status latency coordinator syntax check failed'
  status_block="$(sed -n '/^  status)/,/^  stop)/p' "$coordinator")"
  printf '%s\n' "$status_block" | grep -Fq 'remote_current="$(read_remote)"' || \
    die 'status latency candidate does not read the remote preset once'
  printf '%s\n' "$status_block" | grep -Fq 'validate_preset "$current" && validate_preset "$remote_current"' || \
    die 'status latency candidate does not validate both presets'
  printf '%s\n' "$status_block" | grep -Fq '"$local_ep" verify "$current"' || \
    die 'status latency candidate omits the local health check'
  if printf '%s\n' "$status_block" | grep -Fq 'pair_verify "$current"'; then
    die 'status latency candidate still performs duplicate remote verification'
  fi
  grep -Fq 'pair_verify() {' "$coordinator" || die 'paired verification helper was removed'
  grep -Fq 'pair_verify "$4"' "$coordinator" || die 'explicit paired verification was removed'
  grep -Fq 'pair_verify "$target"' "$coordinator" || die 'apply paired verification was removed'
}

local_verify_status_latency_http() {
  need curl
  browser_host='192.168.66.30'
  curl --max-time 7 -fsS -o /dev/null "http://$browser_host/wgpanel.html" || return 1
  started="$(date +%s)"
  api_output="$(curl --max-time 7 -fsS "http://$browser_host/cgi-bin/wg_api.sh?action=status")" || return 1
  api_elapsed=$(( $(date +%s) - started ))
  [ "$api_elapsed" -lt 7 ] || return 1
  printf '%s\n' "$api_output" | grep -Fqx 'WG_NETWORK_STATE=reachable' || return 1
  printf '%s\n' "$api_output" | grep -Fqx "WG_FEC_EFFECTIVE=$1" || return 1
  printf '%s\n' "$api_output" | grep -Eq '^WG_LATENCY_MS=[0-9]+([.][0-9]+)?$' || return 1
  nodes_output="$(curl --max-time 7 -fsS "http://$browser_host/cgi-bin/wg_nodes.sh")" || return 1
  printf '%s\n' "$nodes_output" | grep -Fq 'nl-zhaojie-v2' || return 1
  say "ZJ717_EXTERNAL_HTTP_QA_PASS host=$browser_host api=${api_elapsed}s rollback=armed"
}

local_repair_status_latency() {
  resolve_self_path
  PANEL_LOCAL_TMP="$(mktemp -d /tmp/game-v2-zj717-panel-local.XXXXXX)"
  chmod 700 "$PANEL_LOCAL_TMP"
  trap cleanup_local EXIT
  trap 'exit 130' HUP INT TERM

  panel_ow_write_coordinator "$PANEL_LOCAL_TMP/fec-coordinator.sh"
  local_validate_status_latency_candidate "$PANEL_LOCAL_TMP/fec-coordinator.sh"

  dry_run_dir="${ZJ717_STATUS_LATENCY_CANDIDATE_DIR:-}"
  if [ -n "$dry_run_dir" ]; then
    mkdir -p "$dry_run_dir"
    cp "$PANEL_LOCAL_TMP/fec-coordinator.sh" "$dry_run_dir/fec-coordinator.sh"
    chmod 755 "$dry_run_dir/fec-coordinator.sh"
    say "ZJ717_STATUS_LATENCY_CANDIDATE_PASS output=$dry_run_dir/fec-coordinator.sh production_write=no"
    return 0
  fi

  prepare_openwrt_ssh
  expected_fec="$(ssh_openwrt "sed -n 's/^preset=//p' '$PANEL_OW_FEC_STATE' | sed -n '1p'")"
  panel_validate_preset "$expected_fec" || die "invalid active zj717 FEC preset: $expected_fec"
  txn="zj717-panel-status-latency-$(date -u +%Y%m%dT%H%M%SZ)-$$"
  if ! remote_stdin_openwrt _panel_latency_prepare "$txn"; then
    remote_stdin_openwrt _panel_latency_rollback "$txn" || true
    die 'zj717 status latency prepare failed; rollback was requested'
  fi
  if ! scp_to_openwrt "$PANEL_LOCAL_TMP/fec-coordinator.sh" \
      "/tmp/game-v2-zj717-panel-status-latency-$txn.coordinator.sh"; then
    remote_stdin_openwrt _panel_latency_rollback "$txn" || true
    die 'zj717 status latency staging failed; backup was restored'
  fi
  if ! remote_stdin_openwrt _panel_latency_apply "$txn"; then
    remote_stdin_openwrt _panel_latency_rollback "$txn" || true
    die 'zj717 status latency apply failed; backup was restored'
  fi
  if ! remote_stdin_openwrt _panel_latency_verify "$expected_fec"; then
    remote_stdin_openwrt _panel_latency_rollback "$txn" || true
    die 'zj717 status latency verification failed; backup was restored'
  fi
  if ! local_verify_status_latency_http "$expected_fec"; then
    remote_stdin_openwrt _panel_latency_rollback "$txn" || true
    die 'zj717 browser-route HTTP QA failed; backup was restored'
  fi
  if ! remote_stdin_openwrt _panel_latency_commit "$txn"; then
    die 'zj717 status latency commit is uncertain; inspect the OpenWrt rollback timer immediately'
  fi
  say "ZJ717_STATUS_LATENCY_REPAIR_PASS transaction=$txn fec=$expected_fec rollback=cancelled"
}

local_reinstall_panel_page() {
  resolve_self_path
  need python3
  PANEL_LOCAL_TMP="$(mktemp -d /tmp/game-v2-zj717-panel-local.XXXXXX)"
  chmod 700 "$PANEL_LOCAL_TMP"
  trap cleanup_local EXIT
  trap 'exit 130' HUP INT TERM

  source_page="${ZJ717_PANEL_PAGE_SOURCE:-}"
  dry_run_dir="${ZJ717_PANEL_PAGE_CANDIDATE_DIR:-}"
  if [ -n "$dry_run_dir" ]; then
    [ -s "$source_page" ] || die 'ZJ717_PANEL_PAGE_SOURCE is required for candidate-only build'
    cp "$source_page" "$PANEL_LOCAL_TMP/wgpanel.html"
  else
    [ -z "$source_page" ] || die 'ZJ717_PANEL_PAGE_SOURCE is only allowed with candidate-only build'
    prepare_openwrt_ssh
    scp_from_cy507 /www/wgpanel.html "$PANEL_LOCAL_TMP/wgpanel.html" || \
      die 'cannot read the current cy507 production page'
  fi

  local_patch_panel_page_display "$PANEL_LOCAL_TMP/wgpanel.html"
  local_validate_panel_page_candidate "$PANEL_LOCAL_TMP/wgpanel.html"

  if [ -n "$dry_run_dir" ]; then
    mkdir -p "$dry_run_dir"
    cp "$PANEL_LOCAL_TMP/wgpanel.html" "$dry_run_dir/wgpanel.html"
    say "ZJ717_PANEL_PAGE_CANDIDATE_PASS output=$dry_run_dir/wgpanel.html production_write=no"
    return 0
  fi

  expected_fec="$(ssh_openwrt "sed -n 's/^preset=//p' '$PANEL_OW_FEC_STATE' | sed -n '1p'")"
  [ "$expected_fec" = extreme ] || die "zj717 active FEC is $expected_fec, expected extreme; no write performed"
  txn="zj717-panel-page-$(date -u +%Y%m%dT%H%M%SZ)-$$"
  if ! remote_stdin_openwrt _panel_page_prepare "$txn"; then
    remote_stdin_openwrt _panel_page_rollback "$txn" || true
    die 'zj717 frontend prepare failed; rollback was requested'
  fi
  if ! scp_to_openwrt "$PANEL_LOCAL_TMP/wgpanel.html" "/tmp/game-v2-zj717-panel-page-$txn.wgpanel.html"; then
    remote_stdin_openwrt _panel_page_rollback "$txn" || true
    die 'zj717 frontend staging failed; backup was restored'
  fi
  if ! remote_stdin_openwrt _panel_page_apply "$txn"; then
    remote_stdin_openwrt _panel_page_rollback "$txn" || true
    die 'zj717 frontend apply failed; backup was restored'
  fi
  if ! remote_stdin_openwrt _panel_page_verify "$txn"; then
    remote_stdin_openwrt _panel_page_rollback "$txn" || true
    die 'zj717 frontend technical verification failed; backup was restored'
  fi
  say "ZJ717_PANEL_PAGE_APPLY_PASS transaction=$txn fec=$expected_fec rollback=armed-${PANEL_PAGE_ROLLBACK_SECONDS}s next=browser-QA"
}

local_commit_panel_page() {
  resolve_self_path
  prepare_openwrt_ssh
  remote_stdin_openwrt _panel_page_commit
  say 'ZJ717_PANEL_PAGE_COMMIT_PASS rollback=cancelled'
}

local_rollback_panel_page() {
  resolve_self_path
  prepare_openwrt_ssh
  remote_stdin_openwrt _panel_page_rollback
  say 'ZJ717_PANEL_PAGE_ROLLBACK_PASS'
}

local_panel_api_qa() {
  api_url="$1"
  action_output="$(curl --max-time 150 -fsS "$api_url?action=apply&node=nl-zhaojie-v2&mode=faketcp&fec=light&confirm=yes")" || return 1
  action_txn="$(printf '%s\n' "$action_output" | sed -n 's/^WG_TRANSACTION=//p' | sed -n '1p')"
  [ -n "$action_txn" ] || return 1
  curl --max-time 150 -fsS "$api_url?action=confirm&transaction=$action_txn&confirm=yes" >/dev/null || return 1
  status_output="$(curl --max-time 150 -fsS "$api_url?action=status")" || return 1
  printf '%s\n' "$status_output" | grep -Fqx 'WG_FEC_EFFECTIVE=light' || return 1
  printf '%s\n' "$status_output" | grep -Fqx 'WG_TRANSACTION_STATE=confirmed' || return 1

  action_output="$(curl --max-time 150 -fsS "$api_url?action=apply&node=nl-zhaojie-v2&mode=faketcp&fec=original&confirm=yes")" || return 1
  action_txn="$(printf '%s\n' "$action_output" | sed -n 's/^WG_TRANSACTION=//p' | sed -n '1p')"
  [ -n "$action_txn" ] || return 1
  curl --max-time 150 -fsS "$api_url?action=confirm&transaction=$action_txn&confirm=yes" >/dev/null || return 1
  status_output="$(curl --max-time 150 -fsS "$api_url?action=status")" || return 1
  printf '%s\n' "$status_output" | grep -Fqx 'WG_FEC_EFFECTIVE=original' || return 1
  printf '%s\n' "$status_output" | grep -Fqx 'WG_TRANSACTION_STATE=confirmed' || return 1
}

local_panel_rollback_protection_qa() {
  ssh_openwrt "
    set -eu
    test ! -s '$PANEL_CONTROL_STATE/active-transaction'
    rm -rf '$PANEL_CONTROL_STATE/control.lock'
    mkdir -p '$PANEL_CONTROL_STATE/control.lock'
    WG_GAME_PANEL_CONFIRM_SECONDS=8 '$PANEL_CONTROL_SCRIPT' apply nl-zhaojie-v2 faketcp light >/tmp/zj717-panel-rollback-qa.out
    wait_count=0
    while [ -s '$PANEL_CONTROL_STATE/active-transaction' ] && [ \"\$wait_count\" -lt 60 ]; do
      wait_count=\$((wait_count + 1))
      sleep 1
    done
    test ! -s '$PANEL_CONTROL_STATE/active-transaction'
    test ! -d '$PANEL_CONTROL_STATE/control.lock'
    '$PANEL_CONTROL_SCRIPT' status | grep -Fqx 'WG_FEC_EFFECTIVE=original'
    grep -Fqx 'WG_TRANSACTION_STATE=prepared' /tmp/zj717-panel-rollback-qa.out
    rm -f /tmp/zj717-panel-rollback-qa.out
  "
}

local_repair_panel() {
  prepare_ssh
  resolve_self_path
  need curl
  need python3
  txn="zj717-panel-$(date -u +%Y%m%dT%H%M%SZ)-$$"
  PANEL_LOCAL_TMP="$(mktemp -d /tmp/game-v2-zj717-panel-local.XXXXXX)"
  chmod 700 "$PANEL_LOCAL_TMP"
  scp_from_cy507 /www/wgpanel.html "$PANEL_LOCAL_TMP/wgpanel.html" || \
    die 'cannot read the verified cy507 panel page'
  scp_from_openwrt "$PANEL_CONTROL_SCRIPT" "$PANEL_LOCAL_TMP/panel-control.sh" || \
    die 'cannot read the current OpenWrt panel controller'
  [ -s "$PANEL_LOCAL_TMP/wgpanel.html" ] || die 'the verified cy507 panel page is empty'
  [ -s "$PANEL_LOCAL_TMP/panel-control.sh" ] || die 'the OpenWrt panel controller is empty'
  local_patch_panel_assets "$PANEL_LOCAL_TMP/wgpanel.html" "$PANEL_LOCAL_TMP/panel-control.sh"
  ssh-keygen -q -t ed25519 -N '' -C game-v2-zj717-panel -f "$PANEL_LOCAL_TMP/id_ed25519"
  awk -v host="$VPS_HOST" '$1 == host || $1 == "[" host "]:22" { print; found=1 } END { exit !found }' \
    "$LOCAL_KNOWN_HOSTS" >"$PANEL_LOCAL_TMP/known_hosts"

  if ! remote_stdin_vps _panel_vps_prepare "$txn"; then
    remote_stdin_vps _panel_vps_rollback "$txn" || true
    die 'zj717 panel VPS prepare failed; rollback was requested'
  fi
  if ! remote_stdin_openwrt _panel_ow_prepare "$txn"; then
    local_panel_rollback "$txn"
    die 'zj717 panel OpenWrt prepare failed; rollback was requested on both endpoints'
  fi
  if ! local_upload_controller "$txn"; then
    local_panel_rollback "$txn"
    die 'zj717 panel controller upload failed; rollback was requested on both endpoints'
  fi

  if ! scp_to_vps "$PANEL_LOCAL_TMP/id_ed25519.pub" "/tmp/game-v2-zj717-panel-$txn.pub" || \
     ! scp_to_openwrt "$PANEL_LOCAL_TMP/id_ed25519" "/tmp/game-v2-zj717-panel-$txn.key" || \
     ! scp_to_openwrt "$PANEL_LOCAL_TMP/id_ed25519.pub" "/tmp/game-v2-zj717-panel-$txn.pub" || \
     ! scp_to_openwrt "$PANEL_LOCAL_TMP/known_hosts" "/tmp/game-v2-zj717-panel-$txn.known_hosts" || \
     ! scp_to_openwrt "$PANEL_LOCAL_TMP/panel-control.sh" "/tmp/game-v2-zj717-panel-$txn.panel-control.sh" || \
     ! scp_to_openwrt "$PANEL_LOCAL_TMP/wgpanel.html" "/tmp/game-v2-zj717-panel-$txn.wgpanel.html"; then
    local_panel_rollback "$txn"
    die 'zj717 panel key staging failed; rollback was requested on both endpoints'
  fi

  if ! remote_exec_vps _panel_vps_apply "$txn"; then
    local_panel_rollback "$txn"
    die 'zj717 panel VPS apply failed; rollback was requested on both endpoints'
  fi
  if ! remote_exec_openwrt _panel_ow_apply "$txn"; then
    local_panel_rollback "$txn"
    die 'zj717 panel OpenWrt apply failed; rollback was requested on both endpoints'
  fi
  if ! remote_exec_openwrt _panel_ow_activate original; then
    local_panel_rollback "$txn"
    die 'zj717 panel active state update failed; rollback was requested on both endpoints'
  fi
  if ! remote_exec_vps _panel_vps_verify original || \
     ! remote_exec_openwrt _panel_ow_verify original; then
    local_panel_rollback "$txn"
    die 'zj717 panel endpoint verification failed; rollback was requested on both endpoints'
  fi

  page_url="http://$OPENWRT_HOST/wgpanel.html"
  api_url="http://$OPENWRT_HOST/cgi-bin/wg_api.sh"
  nodes_url="http://$OPENWRT_HOST/cgi-bin/wg_nodes.sh"
  curl --max-time 10 -fsS -o /dev/null "$page_url" || {
    local_panel_rollback "$txn"
    die 'zj717 panel HTML probe failed; rollback was requested on both endpoints'
  }
  status_output="$(curl --max-time 15 -fsS "$api_url?action=status")" || {
    local_panel_rollback "$txn"
    die 'zj717 panel status API probe failed; rollback was requested on both endpoints'
  }
  printf '%s\n' "$status_output" | grep -Fqx 'WG_NODE=nl-zhaojie-v2' || {
    local_panel_rollback "$txn"
    die 'zj717 panel status API returned the wrong node; rollback was requested on both endpoints'
  }
  printf '%s\n' "$status_output" | grep -Fqx 'WG_FEC_EFFECTIVE=original' || {
    local_panel_rollback "$txn"
    die 'zj717 panel status API returned the wrong FEC mode; rollback was requested on both endpoints'
  }
  nodes_output="$(curl --max-time 15 -fsS "$nodes_url")" || {
    local_panel_rollback "$txn"
    die 'zj717 panel nodes API probe failed; rollback was requested on both endpoints'
  }
  printf '%s\n' "$nodes_output" | grep -F 'nl-zhaojie-v2' >/dev/null || {
    local_panel_rollback "$txn"
    die 'zj717 panel nodes API omitted the zj717 node; rollback was requested on both endpoints'
  }
  if printf '%s\n' "$nodes_output" | grep -F 'cy507' >/dev/null; then
    local_panel_rollback "$txn"
    die 'zj717 panel nodes API exposed the cy507 profile; rollback was requested on both endpoints'
  fi

  if ! local_panel_rollback_protection_qa; then
    local_panel_rollback "$txn"
    die 'zj717 panel automatic rollback QA failed; repair backup was restored'
  fi
  if ! local_panel_api_qa "$api_url"; then
    local_panel_rollback "$txn"
    die 'zj717 panel apply/confirm API QA failed; repair backup was restored'
  fi
  remote_exec_vps _panel_vps_verify original || {
    local_panel_rollback "$txn"
    die 'zj717 panel final VPS verification failed after QA; repair backup was restored'
  }
  remote_exec_openwrt _panel_ow_verify original || {
    local_panel_rollback "$txn"
    die 'zj717 panel final OpenWrt verification failed after QA; repair backup was restored'
  }

  remote_exec_vps _panel_vps_commit "$txn" || die 'VPS panel commit is uncertain; inspect immediately'
  remote_exec_openwrt _panel_ow_commit "$txn" || die 'OpenWrt panel commit is uncertain after VPS commit; inspect immediately'
  say "ZJ717_PANEL_REPAIR_PASS transaction=$txn page=cy507-copy profile=zj717 fec=original rollback=cancelled"
}

# ---------- Dutch VPS endpoint ----------

VPS_STATE='/var/lib/game-v2-zj717-fixed'
VPS_ACTIVE="$VPS_STATE/active-transaction"
VPS_COMMITTED="$VPS_STATE/committed-transaction"
VPS_BACKUP_ROOT='/var/backups/game-v2-zj717-migrate'
VPS_INSTALL='/usr/local/lib/game-v2-zj717-fixed'
VPS_ENV='/etc/game-v2/clients/zj717/server.env'
VPS_ENROLLMENT='/var/lib/game-v2/server/clients/zj717/enrollment.env'
VPS_CLIENT_KEY='/var/lib/game-v2/server/clients/zj717/secrets/client-private.key'
VPS_NAT_FILE='/etc/game-v2/zj717-fixed-nat.nft'
VPS_RECONCILE='/usr/local/sbin/game-v2-zj717-fixed-reconcile'
VPS_UNBOUND_CONF='/etc/unbound/unbound-zj717.conf'
VPS_UNBOUND_STATE='/var/lib/unbound/zj717'
VPS_FAKE_UNIT='game-v2-faketcp-zj717.service'
VPS_DNS_UNIT='unbound-zj717.service'
VPS_RECONCILE_DROPIN='/etc/systemd/system/game-v2-firewall-reconcile.service.d/70-zj717-fixed.conf'
PROTECTED_CONTAINER='domestic-live-relay-mediamtx'

vps_require_root() { [ "$(id -u)" -eq 0 ] || die 'VPS endpoint requires root'; }

vps_assert_control_plane() {
  systemctl is-enabled netfilter-persistent.service 2>/dev/null | grep -qx enabled || die 'netfilter-persistent must be enabled'
  systemctl is-active netfilter-persistent.service 2>/dev/null | grep -qx active || die 'netfilter-persistent must be active'
  for unit in iptables.service ip6tables.service nftables.service; do
    systemctl is-enabled "$unit" 2>/dev/null | grep -qx masked || die "$unit must remain masked"
    ! systemctl is-active --quiet "$unit" 2>/dev/null || die "$unit must remain inactive"
  done
}

vps_assert_protected_live() {
  for unit in docker.service wg-quick@wg-data.service wg-quick@wg-data-direct.service; do
    systemctl is-active --quiet "$unit" || die "protected service is not active: $unit"
  done
  [ "$(docker inspect -f '{{.State.Running}}' "$PROTECTED_CONTAINER" 2>/dev/null)" = true ] || die 'protected relay container is not running'
  ip -4 addr show dev wg-data | grep -F '10.10.14.1/24' >/dev/null || die 'protected wg-data address missing'
  ip -4 addr show dev wg-data-direct | grep -F '10.10.15.1/32' >/dev/null || die 'protected wg-data-direct address missing'
  ss -H -lnt | grep -F '10.10.14.1:1935 ' >/dev/null || die 'protected TCP 1935 listener missing'
  ss -H -lnt | grep -F '10.10.14.1:8554 ' >/dev/null || die 'protected TCP 8554 listener missing'
  ss -H -lnu | grep -F '10.10.15.1:8890 ' >/dev/null || die 'protected UDP 8890 listener missing'
  ss -H -lnt | grep -F '127.0.0.1:9998 ' >/dev/null || die 'protected TCP 9998 listener missing'
  ss -H -lnu | grep -F '192.168.88.131:1053 ' >/dev/null || die 'protected UDP DNS relay missing'
  ss -H -lnt | grep -F '192.168.88.131:1053 ' >/dev/null || die 'protected TCP DNS relay missing'
}

vps_find_root_anchor() {
  for p in /var/lib/unbound/root.key /usr/share/dns/root.key /usr/share/dnssec-root/trusted-key.key; do
    [ ! -s "$p" ] || { printf '%s\n' "$p"; return 0; }
  done
  return 1
}

vps_allowed_ips() {
  wg show "$WG_IF" allowed-ips | awk 'NR == 1 { $1 = ""; sub(/^[[:space:]]+/, ""); print; exit }'
}

vps_assert_base() {
  vps_require_root
  for cmd in awk cp cut date docker flock grep install ip iptables mv nft sed ss systemctl systemd-run tar tr wc wg; do need "$cmd"; done
  [ -x /usr/sbin/unbound ] || die 'unbound binary missing'
  [ -x /usr/sbin/unbound-checkconf ] || die 'unbound-checkconf missing'
  [ -d "/sys/class/net/$VPS_WAN_IFACE" ] || die 'VPS WAN interface missing'
  vps_assert_control_plane
  vps_assert_protected_live
  systemctl is-active --quiet game-v2-wg-zj717.service || die 'generic zj717 WireGuard service not active'
  systemctl is-active --quiet game-v2-speed-zj717.service || die 'generic zj717 speed service not active'
  systemctl is-active --quiet game-v2-firewall-reconcile.timer || die 'generic Game V2 reconcile timer not active'
  generic_forward="$(nft list table inet game_v2 2>/dev/null)" || die 'generic Game V2 forward table missing'
  printf '%s\n' "$generic_forward" | grep -F 'iifname "gv2_zj717" accept comment "game-v2:zj717"' >/dev/null || die 'generic zj717 outbound forward rule missing'
  printf '%s\n' "$generic_forward" | grep -F 'oifname "gv2_zj717"' | grep -F 'accept comment "game-v2:zj717"' >/dev/null || die 'generic zj717 return forward rule missing'
  generic_nat="$(nft list table ip game_v2_nat 2>/dev/null)" || die 'generic Game V2 NAT table missing'
  printf '%s\n' "$generic_nat" | grep -F 'iifname "gv2_zj717" ip saddr 10.77.3.2 masquerade comment "game-v2:zj717"' >/dev/null || die 'generic zj717 client NAT rule missing'
  ip -4 addr show dev "$WG_IF" | grep -F "$SERVER_WG_ADDR" >/dev/null || die 'generic zj717 address mismatch'
  [ "$(wg show "$WG_IF" peers | sed '/^$/d' | wc -l | tr -d ' ')" = 1 ] || die 'generic zj717 peer count mismatch'
  allowed="$(vps_allowed_ips)"
  case "$allowed" in
    "$CLIENT_WG_IP/32"|"$CLIENT_WG_IP/32 $GAME_DEVICE_IP/32"|"$GAME_DEVICE_IP/32 $CLIENT_WG_IP/32") ;;
    *) die "unexpected zj717 AllowedIPs: $allowed" ;;
  esac
  [ -s "$VPS_ENV" ] || die 'generic zj717 server.env missing'
  [ -s "$VPS_ENROLLMENT" ] || die 'generic zj717 enrollment missing'
  [ -s "$VPS_CLIENT_KEY" ] || die 'generic zj717 client private key missing'
  [ -x /usr/local/bin/game-v2-speederv2 ] || die 'generic speederv2 binary missing'
  [ -x /usr/local/lib/game-v2-cy507-faketcp/udp2raw ] || die 'approved local udp2raw source missing'
  vps_find_root_anchor >/dev/null || die 'DNSSEC root anchor missing'
}

vps_assert_overlay_absent() {
  allowed="$(vps_allowed_ips)"
  [ "$allowed" = "$CLIENT_WG_IP/32" ] || die "zj717 generic baseline AllowedIPs already changed: $allowed"
  [ ! -e "$VPS_STATE" ] || die "existing zj717 fixed state: $VPS_STATE"
  [ ! -e "$VPS_INSTALL" ] || die "existing zj717 fixed install: $VPS_INSTALL"
  [ ! -e "$VPS_NAT_FILE" ] || die "existing zj717 NAT file: $VPS_NAT_FILE"
  [ ! -e "$VPS_RECONCILE" ] || die "existing zj717 reconcile: $VPS_RECONCILE"
  [ ! -e "$VPS_UNBOUND_CONF" ] || die "existing zj717 dedicated DNS config: $VPS_UNBOUND_CONF"
  for unit in "$VPS_FAKE_UNIT" "$VPS_DNS_UNIT"; do
    [ ! -e "/etc/systemd/system/$unit" ] || die "existing target unit: $unit"
  done
  [ ! -e "$VPS_RECONCILE_DROPIN" ] || die "existing target drop-in: $VPS_RECONCILE_DROPIN"
  ! nft list table ip game_v2_zj717_fixed_nat >/dev/null 2>&1 || die 'existing zj717 fixed NAT table'
  ! iptables -S GAME_V2_ZJ717_INPUT >/dev/null 2>&1 || die 'existing zj717 INPUT chain'
  ! iptables -S GAME_V2_ZJ717_FORWARD >/dev/null 2>&1 || die 'existing zj717 FORWARD chain'
  ! ip route show "$GAME_DEVICE_IP/32" | grep -q . || die 'existing Xbox host route'
  ! ss -H -lnt "sport = :$SERVER_SPEED_PORT" 2>/dev/null | grep -q . || die "TCP $SERVER_SPEED_PORT already in use"
  ! ss -H -lnut 2>/dev/null | grep -F "$SERVER_WG_IP:53 " >/dev/null || die 'zj717 DNS address already in use'
}

vps_backup_dir() { printf '%s/%s\n' "$VPS_BACKUP_ROOT" "$1"; }

vps_write_rollback() {
  txn="$1"
  dir="$(vps_backup_dir "$txn")"
cat >"$dir/rollback.sh" <<'EOF'
#!/bin/sh
set -u
WG_IF='gv2_zj717'
ACTIVE='/var/lib/game-v2-zj717-fixed/active-transaction'
COMMITTED='/var/lib/game-v2-zj717-fixed/committed-transaction'
ROLLBACK_DIR="${1:-}"
case "$ROLLBACK_DIR" in /var/backups/game-v2-zj717-migrate/*) ;; *) exit 0 ;; esac
exec 8>"$ROLLBACK_DIR/finalize.lock"
flock 8 || exit 1
[ -s "$ACTIVE" ] || exit 0
. "$ACTIVE"
[ "$BACKUP_DIR" = "$ROLLBACK_DIR" ] || exit 0
if mv "$ROLLBACK_DIR/rollback.pending" "$ROLLBACK_DIR/rollback.claimed" 2>/dev/null; then
  :
elif [ -e "$ROLLBACK_DIR/rollback.claimed" ]; then
  :
elif [ -e "$ROLLBACK_DIR/commit.claimed" ]; then
  if [ -s "$COMMITTED" ] && [ "$(cat "$COMMITTED")" = "$TXN" ]; then
    exit 0
  fi
  mv "$ROLLBACK_DIR/commit.claimed" "$ROLLBACK_DIR/rollback.claimed" 2>/dev/null || exit 1
else
  exit 0
fi
rm -f /var/lib/game-v2-zj717-fixed/enabled
rm -f /etc/systemd/system/game-v2-firewall-reconcile.service.d/70-zj717-fixed.conf
systemctl daemon-reload >/dev/null 2>&1 || true
exec 9>/run/game-v2-zj717-fixed-reconcile.lock
flock 9 || exit 1
for unit in unbound-zj717.service game-v2-faketcp-zj717.service; do
  systemctl disable --now "$unit" >/dev/null 2>&1 || true
done
nft delete table ip game_v2_zj717_fixed_nat >/dev/null 2>&1 || true
while iptables -D INPUT -j GAME_V2_ZJ717_INPUT >/dev/null 2>&1; do :; done
iptables -F GAME_V2_ZJ717_INPUT >/dev/null 2>&1 || true
iptables -X GAME_V2_ZJ717_INPUT >/dev/null 2>&1 || true
while iptables -D FORWARD -j GAME_V2_ZJ717_FORWARD >/dev/null 2>&1; do :; done
iptables -F GAME_V2_ZJ717_FORWARD >/dev/null 2>&1 || true
iptables -X GAME_V2_ZJ717_FORWARD >/dev/null 2>&1 || true
ip route del 192.168.7.108/32 dev gv2_zj717 >/dev/null 2>&1 || true
peer="$(wg show "$WG_IF" peers 2>/dev/null | sed -n '1p')"
[ -z "$peer" ] || wg set "$WG_IF" peer "$peer" allowed-ips 10.77.3.2/32 >/dev/null 2>&1 || true
rm -f /etc/systemd/system/game-v2-faketcp-zj717.service
rm -f /etc/systemd/system/unbound-zj717.service
rm -f /etc/game-v2/zj717-fixed-nat.nft
rm -f /etc/unbound/unbound-zj717.conf
rm -f /usr/local/sbin/game-v2-zj717-fixed-reconcile
case "$BACKUP_DIR" in /var/backups/game-v2-zj717-migrate/*) rm -rf "$BACKUP_DIR/package" ;; esac
rm -rf /usr/local/lib/game-v2-zj717-fixed /var/lib/unbound/zj717 /run/game-v2-zj717-faketcp
systemctl daemon-reload >/dev/null 2>&1 || true
rollback_ok=yes
systemctl is-active --quiet game-v2-wg-zj717.service || rollback_ok=no
systemctl is-active --quiet game-v2-speed-zj717.service || rollback_ok=no
systemctl is-enabled netfilter-persistent.service 2>/dev/null | grep -qx enabled || rollback_ok=no
systemctl is-active --quiet netfilter-persistent.service || rollback_ok=no
for unit in iptables.service ip6tables.service nftables.service; do
  systemctl is-enabled "$unit" 2>/dev/null | grep -qx masked || rollback_ok=no
  ! systemctl is-active --quiet "$unit" || rollback_ok=no
done
for unit in docker.service wg-quick@wg-data.service wg-quick@wg-data-direct.service; do
  systemctl is-active --quiet "$unit" || rollback_ok=no
done
[ "$(docker inspect -f '{{.State.Running}}' domestic-live-relay-mediamtx 2>/dev/null)" = true ] || rollback_ok=no
[ "$(docker inspect -f '{{.State.StartedAt}}' domestic-live-relay-mediamtx 2>/dev/null)" = "$(cat "$ROLLBACK_DIR/protected-container-started.before" 2>/dev/null)" ] || rollback_ok=no
ip -4 addr show dev wg-data | grep -F '10.10.14.1/24' >/dev/null || rollback_ok=no
ip -4 addr show dev wg-data-direct | grep -F '10.10.15.1/32' >/dev/null || rollback_ok=no
ss -H -lnt | grep -F '10.10.14.1:1935 ' >/dev/null || rollback_ok=no
ss -H -lnt | grep -F '10.10.14.1:8554 ' >/dev/null || rollback_ok=no
ss -H -lnu | grep -F '10.10.15.1:8890 ' >/dev/null || rollback_ok=no
ss -H -lnt | grep -F '127.0.0.1:9998 ' >/dev/null || rollback_ok=no
ss -H -lnu | grep -F '192.168.88.131:1053 ' >/dev/null || rollback_ok=no
ss -H -lnt | grep -F '192.168.88.131:1053 ' >/dev/null || rollback_ok=no
for unit in unbound-zj717.service game-v2-faketcp-zj717.service; do
  ! systemctl is-active --quiet "$unit" || rollback_ok=no
  ! systemctl is-enabled --quiet "$unit" 2>/dev/null || rollback_ok=no
done
for path in \
  /etc/systemd/system/game-v2-faketcp-zj717.service \
  /etc/systemd/system/unbound-zj717.service \
  /etc/systemd/system/game-v2-firewall-reconcile.service.d/70-zj717-fixed.conf \
  /etc/game-v2/zj717-fixed-nat.nft \
  /etc/unbound/unbound-zj717.conf \
  /usr/local/sbin/game-v2-zj717-fixed-reconcile \
  /usr/local/lib/game-v2-zj717-fixed \
  /var/lib/unbound/zj717 \
  /run/game-v2-zj717-faketcp; do
  [ ! -e "$path" ] || rollback_ok=no
done
! nft list table ip game_v2_zj717_fixed_nat >/dev/null 2>&1 || rollback_ok=no
! iptables -S GAME_V2_ZJ717_INPUT >/dev/null 2>&1 || rollback_ok=no
! iptables -S GAME_V2_ZJ717_FORWARD >/dev/null 2>&1 || rollback_ok=no
! ip route show 192.168.7.108/32 | grep -q . || rollback_ok=no
allowed="$(wg show "$WG_IF" allowed-ips 2>/dev/null | awk 'NR == 1 { $1 = ""; sub(/^[[:space:]]+/, ""); print; exit }')"
[ "$(wg show "$WG_IF" peers 2>/dev/null | sed '/^$/d' | wc -l | tr -d ' ')" = 1 ] || rollback_ok=no
[ "$allowed" = '10.77.3.2/32' ] || rollback_ok=no
[ "$rollback_ok" = yes ] || exit 1
rm -rf /var/lib/game-v2-zj717-fixed
rm -f "$ROLLBACK_DIR/rollback.claimed"
exit 0
EOF
  chmod 700 "$dir/rollback.sh"
}

vps_arm_rollback() {
  txn="$1"
  dir="$(vps_backup_dir "$txn")"
  unit="game-v2-zj717-rollback-$txn"
  : >"$dir/rollback.pending" || return 1
  systemd-run --quiet --unit="$unit" --on-active="${ROLLBACK_SECONDS}s" /bin/sh "$dir/rollback.sh" "$dir" || return 1
  printf '%s\n' "$unit" >"$dir/rollback-unit" || return 1
  systemctl is-active --quiet "$unit.timer" || return 1
}

vps_write_files() {
  txn="$1"
  dir="$(vps_backup_dir "$txn")"
  root_anchor="$(vps_find_root_anchor)"
  install -d -m 700 "$VPS_STATE" "$VPS_STATE/secrets" "$dir/package"
  install -d -m 755 "$VPS_INSTALL" /etc/game-v2 /etc/unbound "$VPS_UNBOUND_STATE" /etc/systemd/system/game-v2-firewall-reconcile.service.d
  install -m 755 /usr/local/lib/game-v2-cy507-faketcp/udp2raw "$VPS_INSTALL/udp2raw"
  cp "$root_anchor" "$VPS_UNBOUND_STATE/root.key"
  chown -R unbound:unbound "$VPS_UNBOUND_STATE"
  # ExecStartPre runs as root with CAP_DAC_OVERRIDE removed.  Match the
  # distribution Unbound state permissions so it can traverse and read the
  # public DNSSEC trust anchor before the daemon drops to the unbound user.
  chmod 755 "$VPS_UNBOUND_STATE"
  chmod 644 "$VPS_UNBOUND_STATE/root.key"

  cat >"$VPS_INSTALL/run-faketcp.sh" <<'EOF'
#!/bin/sh
set -eu
. /etc/game-v2/clients/zj717/server.env
runtime=/run/game-v2-zj717-faketcp
mkdir -p "$runtime"
umask 077
cat >"$runtime/udp2raw.conf" <<CFG
-s
-l 0.0.0.0:40973
-r 127.0.0.1:40973
--raw-mode easyfaketcp
--cipher-mode aes128cbc
--auth-mode hmac_sha1
--log-level 3
--disable-color
-k $SPEEDERV2_KEY
CFG
exec /usr/local/lib/game-v2-zj717-fixed/udp2raw --conf-file "$runtime/udp2raw.conf"
EOF
  chmod 700 "$VPS_INSTALL/run-faketcp.sh"

  cat >"$VPS_NAT_FILE" <<EOF
table ip game_v2_zj717_fixed_nat {
  chain prerouting {
    type nat hook prerouting priority -101; policy accept;
    iifname "$VPS_WAN_IFACE" ip daddr $VPS_HOST udp dport $PUBLIC_GAME_PORT counter dnat to $GAME_DEVICE_IP:$GAME_DEVICE_PORT comment "game-v2:zj717-fixed:dnat"
  }
  chain postrouting {
    type nat hook postrouting priority 99; policy accept;
    iifname "$WG_IF" oifname "$VPS_WAN_IFACE" ip saddr $GAME_DEVICE_IP udp sport $GAME_DEVICE_PORT counter snat to $VPS_HOST:$PUBLIC_GAME_PORT comment "game-v2:zj717-fixed:port-snat"
    iifname "$WG_IF" oifname "$VPS_WAN_IFACE" ip saddr $GAME_DEVICE_IP counter snat to $VPS_HOST comment "game-v2:zj717-fixed:fallback-snat"
  }
}
EOF

  cat >"$VPS_RECONCILE" <<'EOF'
#!/bin/sh
set -eu
[ -e /var/lib/game-v2-zj717-fixed/enabled ] || exit 0
exec 9>/run/game-v2-zj717-fixed-reconcile.lock
flock -w 15 9 || { printf '%s\n' 'zj717 reconcile lock timeout' >&2; exit 1; }
[ -e /var/lib/game-v2-zj717-fixed/enabled ] || exit 0
WG_IF='gv2_zj717'
[ -d "/sys/class/net/$WG_IF" ]
peer="$(wg show "$WG_IF" peers)"
[ "$(printf '%s\n' "$peer" | sed '/^$/d' | wc -l | tr -d ' ')" = 1 ]
wg set "$WG_IF" peer "$peer" allowed-ips 10.77.3.2/32,192.168.7.108/32
ip route replace 192.168.7.108/32 dev "$WG_IF"
tmp=/run/game-v2-zj717-fixed-reconcile.nft
if nft list table ip game_v2_zj717_fixed_nat >/dev/null 2>&1; then
  { printf '%s\n' 'delete table ip game_v2_zj717_fixed_nat'; cat /etc/game-v2/zj717-fixed-nat.nft; } >"$tmp"
else
  cp /etc/game-v2/zj717-fixed-nat.nft "$tmp"
fi
nft -c -f "$tmp"
nft -f "$tmp"
rm -f "$tmp"
iptables -N GAME_V2_ZJ717_INPUT >/dev/null 2>&1 || true
iptables -F GAME_V2_ZJ717_INPUT
iptables -A GAME_V2_ZJ717_INPUT -p tcp --dport 40973 -j ACCEPT
iptables -A GAME_V2_ZJ717_INPUT -i "$WG_IF" -p udp --dport 53 -j ACCEPT
iptables -A GAME_V2_ZJ717_INPUT -i "$WG_IF" -p tcp --dport 53 -j ACCEPT
iptables -A GAME_V2_ZJ717_INPUT -j RETURN
while iptables -D INPUT -j GAME_V2_ZJ717_INPUT >/dev/null 2>&1; do :; done
iptables -I INPUT 1 -j GAME_V2_ZJ717_INPUT
iptables -N GAME_V2_ZJ717_FORWARD >/dev/null 2>&1 || true
iptables -F GAME_V2_ZJ717_FORWARD
iptables -A GAME_V2_ZJ717_FORWARD -i ens3 -o "$WG_IF" -d 192.168.7.108/32 -p udp --dport 3074 -j ACCEPT
iptables -A GAME_V2_ZJ717_FORWARD -i "$WG_IF" -o ens3 -s 192.168.7.108/32 -j ACCEPT
iptables -A GAME_V2_ZJ717_FORWARD -j RETURN
while iptables -D FORWARD -j GAME_V2_ZJ717_FORWARD >/dev/null 2>&1; do :; done
iptables -I FORWARD 1 -j GAME_V2_ZJ717_FORWARD
EOF
  chmod 700 "$VPS_RECONCILE"

  cat >"$VPS_UNBOUND_CONF" <<EOF
server:
    interface: $SERVER_WG_IP
    port: 53
    do-ip4: yes
    do-ip6: no
    do-udp: yes
    do-tcp: yes
    access-control: 0.0.0.0/0 refuse
    access-control: $GAME_DEVICE_IP/32 allow
    access-control: $CLIENT_WG_IP/32 allow
    username: "unbound"
    chroot: ""
    directory: "$VPS_UNBOUND_STATE"
    pidfile: "$VPS_UNBOUND_STATE/unbound.pid"
    auto-trust-anchor-file: "$VPS_UNBOUND_STATE/root.key"
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

  cat >/etc/systemd/system/"$VPS_FAKE_UNIT" <<'EOF'
[Unit]
Description=Game V2 zj717 FakeTCP server
After=network-online.target game-v2-speed-zj717.service
Wants=network-online.target
Requires=game-v2-speed-zj717.service

[Service]
Type=simple
ExecStart=/usr/local/lib/game-v2-zj717-fixed/run-faketcp.sh
Restart=on-failure
RestartSec=3
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF
  cat >/etc/systemd/system/"$VPS_DNS_UNIT" <<'EOF'
[Unit]
Description=zj717 dedicated validating DNS resolver
After=network-online.target game-v2-wg-zj717.service
Wants=network-online.target

[Service]
Type=simple
ExecStartPre=/usr/sbin/unbound-checkconf /etc/unbound/unbound-zj717.conf
ExecStart=/usr/sbin/unbound -d -p -c /etc/unbound/unbound-zj717.conf
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
ReadWritePaths=/var/lib/unbound/zj717
RestrictAddressFamilies=AF_UNIX AF_INET AF_NETLINK
CapabilityBoundingSet=CAP_NET_BIND_SERVICE CAP_SETGID CAP_SETUID

[Install]
WantedBy=multi-user.target
EOF
  cat >"$VPS_RECONCILE_DROPIN" <<'EOF'
[Service]
ExecStartPost=/usr/local/sbin/game-v2-zj717-fixed-reconcile
EOF

  # Build a short-lived client package from the existing generic enrollment.
  # Values are never written to stdout and the package stays mode 0700/0600.
  set -a
  . "$VPS_ENV"
  set +a
  server_public="$(wg show "$WG_IF" public-key)"
  client_private="$(cat "$VPS_CLIENT_KEY")"
  [ -n "$server_public" ] && [ -n "$client_private" ] && [ -n "${SPEEDERV2_KEY:-}" ] || die 'generic enrollment material incomplete'
  umask 077
  cat >"$dir/package/enrollment.env" <<EOF
CLIENT_ID='$CLIENT_ID'
SERVER_ENDPOINT='$VPS_HOST'
SERVER_PUBLIC_KEY='$server_public'
CLIENT_PRIVATE_KEY='$client_private'
SPEEDERV2_KEY='$SPEEDERV2_KEY'
EOF
  install -m 755 /usr/local/bin/game-v2-speederv2 "$dir/package/speederv2"
  install -m 755 "$VPS_INSTALL/udp2raw" "$dir/package/udp2raw"
  chmod 600 "$dir/package/enrollment.env"
  : >"$VPS_STATE/enabled"
  umask 022
}

vps_verify() {
  vps_assert_base
  for unit in "$VPS_FAKE_UNIT" "$VPS_DNS_UNIT"; do
    systemctl is-active --quiet "$unit" || die "$unit is not active"
    systemctl is-enabled "$unit" 2>/dev/null | grep -qx enabled || die "$unit is not enabled"
  done
  systemctl is-active --quiet game-v2-firewall-reconcile.timer || die 'generic Game V2 reconcile timer is not active'
  [ -e "$VPS_STATE/enabled" ] || die 'zj717 reconcile enable marker missing'
  grep -Fqx 'ExecStartPost=/usr/local/sbin/game-v2-zj717-fixed-reconcile' "$VPS_RECONCILE_DROPIN" || die 'zj717 reconcile drop-in missing'
  allowed="$(vps_allowed_ips)"
  case "$allowed" in
    "$CLIENT_WG_IP/32 $GAME_DEVICE_IP/32"|"$GAME_DEVICE_IP/32 $CLIENT_WG_IP/32") ;;
    *) die "zj717 AllowedIPs mismatch: $allowed" ;;
  esac
  ip route show "$GAME_DEVICE_IP/32" | grep -F "dev $WG_IF" >/dev/null || die 'Xbox host route missing'
  nft list table ip game_v2_zj717_fixed_nat | grep -F "dnat to $GAME_DEVICE_IP:$GAME_DEVICE_PORT" >/dev/null || die 'zj717 DNAT missing'
  nft list table ip game_v2_zj717_fixed_nat | grep -F "snat to $VPS_HOST:$PUBLIC_GAME_PORT" >/dev/null || die 'zj717 fixed port SNAT missing'
  iptables -C INPUT -j GAME_V2_ZJ717_INPUT >/dev/null 2>&1 || die 'zj717 INPUT jump missing'
  iptables -C FORWARD -j GAME_V2_ZJ717_FORWARD >/dev/null 2>&1 || die 'zj717 FORWARD jump missing'
  ss -H -lnt "sport = :$SERVER_SPEED_PORT" | grep -q . || die 'zj717 FakeTCP listener missing'
  ss -H -lnu "sport = :$SERVER_SPEED_PORT" | grep -q . || die 'zj717 UDPspeeder listener missing'
  ss -H -lnu "sport = :$WG_PORT" | grep -q . || die 'zj717 WireGuard listener missing'
  ss -H -lnu "sport = :53" | grep -F "$SERVER_WG_IP:53" >/dev/null || die 'zj717 UDP DNS listener missing'
  ss -H -lnt "sport = :53" | grep -F "$SERVER_WG_IP:53" >/dev/null || die 'zj717 TCP DNS listener missing'
  vps_assert_protected_live
  if [ -s "$VPS_ACTIVE" ]; then
    . "$VPS_ACTIVE"
    current_started="$(docker inspect -f '{{.State.StartedAt}}' "$PROTECTED_CONTAINER")"
    [ "$current_started" = "$(cat "$BACKUP_DIR/protected-container-started.before")" ] || die 'protected relay container restarted during zj717 change'
  fi
  say 'VPS_VERIFY_PASS'
}

vps_prepare() {
  txn="$1"
  [ -n "$txn" ] || die 'missing transaction id'
  vps_assert_base
  vps_assert_overlay_absent
  dir="$(vps_backup_dir "$txn")"
  [ ! -e "$dir" ] || die "transaction already exists: $txn"
  mkdir -p "$dir"
  chmod 700 "$dir"
  wg show "$WG_IF" allowed-ips >"$dir/wg-allowed-before.txt"
  ip route show >"$dir/routes-before.txt"
  iptables -S >"$dir/iptables-before.txt"
  nft list ruleset >"$dir/nft-before.txt"
  ss -H -lntup >"$dir/listeners-before.txt" 2>/dev/null || true
  docker inspect -f '{{.State.StartedAt}}' "$PROTECTED_CONTAINER" >"$dir/protected-container-started.before"
  vps_write_rollback "$txn"
  mkdir -p "$VPS_STATE"
  chmod 700 "$VPS_STATE"
  cat >"$VPS_ACTIVE" <<EOF
TXN='$txn'
BACKUP_DIR='$dir'
EOF
  chmod 600 "$VPS_ACTIVE"
  if ! vps_arm_rollback "$txn"; then
    /bin/sh "$dir/rollback.sh" "$dir"
    die 'failed to arm VPS rollback; prepared state was restored'
  fi
  say "VPS_PREPARE_PASS transaction=$txn rollback=armed-${ROLLBACK_SECONDS}s"
}

vps_apply() {
  txn="$1"
  [ -s "$VPS_ACTIVE" ] || die 'no prepared VPS transaction'
  . "$VPS_ACTIVE"
  [ "$TXN" = "$txn" ] || die 'VPS transaction mismatch'
  vps_assert_base
  vps_write_files "$txn"
  /usr/sbin/unbound-checkconf "$VPS_UNBOUND_CONF"
  nft -c -f "$VPS_NAT_FILE"
  systemctl daemon-reload
  systemctl enable --now "$VPS_FAKE_UNIT"
  systemctl enable --now "$VPS_DNS_UNIT"
  "$VPS_RECONCILE"
  vps_verify
  say "VPS_APPLY_PASS transaction=$txn"
}

vps_txn_state() {
  if [ -s "$VPS_ACTIVE" ]; then
    . "$VPS_ACTIVE"
    if [ -e "$BACKUP_DIR/commit.claimed" ]; then
      printf 'commit-claimed:%s\n' "$TXN"
    elif [ -e "$BACKUP_DIR/rollback.claimed" ]; then
      printf 'rollback-claimed:%s\n' "$TXN"
    elif [ -e "$BACKUP_DIR/rollback.pending" ]; then
      printf 'pending:%s\n' "$TXN"
    else
      printf 'unarmed:%s\n' "$TXN"
    fi
  elif [ -s "$VPS_COMMITTED" ]; then
    printf 'committed:%s\n' "$(cat "$VPS_COMMITTED")"
  else
    die 'no VPS transaction state'
  fi
}

vps_commit() {
  expected="$1"
  [ -n "$expected" ] || die 'missing expected VPS transaction'
  if [ ! -s "$VPS_ACTIVE" ]; then
    [ -s "$VPS_COMMITTED" ] && [ "$(cat "$VPS_COMMITTED")" = "$expected" ] || die 'no matching pending or committed VPS transaction'
    vps_verify
    say "VPS_COMMIT_ALREADY_PASS transaction=$expected"
    return 0
  fi
  . "$VPS_ACTIVE"
  [ "$TXN" = "$expected" ] || die 'VPS commit transaction mismatch'
  prepared_backup="$BACKUP_DIR"
  exec 8>"$BACKUP_DIR/finalize.lock"
  flock 8
  [ -s "$VPS_ACTIVE" ] || die 'VPS rollback completed before commit acquired the transaction'
  . "$VPS_ACTIVE"
  [ "$TXN" = "$expected" ] && [ "$BACKUP_DIR" = "$prepared_backup" ] || die 'VPS active transaction changed while commit waited for the lock'
  vps_verify
  if mv "$BACKUP_DIR/rollback.pending" "$BACKUP_DIR/commit.claimed" 2>/dev/null; then
    :
  elif [ -e "$BACKUP_DIR/commit.claimed" ]; then
    :
  else
    die 'VPS rollback already started or is no longer armed'
  fi
  umask 077
  committed_tmp="$VPS_STATE/.committed.$$"
  printf '%s\n' "$TXN" >"$committed_tmp"
  mv "$committed_tmp" "$VPS_COMMITTED"
  rm -f "$VPS_ACTIVE"
  unit="$(cat "$BACKUP_DIR/rollback-unit")"
  systemctl stop "$unit.timer" "$unit.service" >/dev/null 2>&1 || true
  systemctl reset-failed "$unit.service" >/dev/null 2>&1 || true
  rm -rf "$BACKUP_DIR/package" || true
  rm -f "$BACKUP_DIR/commit.claimed"
  say "VPS_COMMIT_PASS transaction=$TXN"
}

vps_rollback() {
  requested="${1:-}"
  [ -s "$VPS_ACTIVE" ] || { say 'VPS_ROLLBACK_NO_PENDING_TRANSACTION'; return 0; }
  . "$VPS_ACTIVE"
  [ -z "$requested" ] || [ "$TXN" = "$requested" ] || die 'VPS rollback transaction mismatch'
  unit="$(cat "$BACKUP_DIR/rollback-unit" 2>/dev/null || true)"
  /bin/sh "$BACKUP_DIR/rollback.sh" "$BACKUP_DIR"
  [ ! -s "$VPS_ACTIVE" ] || die 'VPS rollback could not claim the pending transaction'
  if [ -n "$unit" ]; then
    systemctl stop "$unit.timer" "$unit.service" >/dev/null 2>&1 || true
    systemctl reset-failed "$unit.service" >/dev/null 2>&1 || true
  fi
  say "VPS_ROLLBACK_PASS transaction=$TXN"
}

vps_status() {
  printf 'VPS generic WG=%s speed=%s\n' "$(systemctl is-active game-v2-wg-zj717.service 2>/dev/null || true)" "$(systemctl is-active game-v2-speed-zj717.service 2>/dev/null || true)"
  printf 'VPS zj717 FakeTCP=%s DNS=%s global-reconcile=%s\n' "$(systemctl is-active "$VPS_FAKE_UNIT" 2>/dev/null || true)" "$(systemctl is-active "$VPS_DNS_UNIT" 2>/dev/null || true)" "$(systemctl is-active game-v2-firewall-reconcile.timer 2>/dev/null || true)"
  if [ -s "$VPS_ACTIVE" ]; then
    . "$VPS_ACTIVE"
    if [ -e "$BACKUP_DIR/commit.claimed" ]; then
      say "VPS transaction=COMMIT_CLAIMED transaction=$TXN"
    elif [ -e "$BACKUP_DIR/rollback.claimed" ]; then
      say "VPS transaction=ROLLBACK_CLAIMED transaction=$TXN"
    elif [ -e "$BACKUP_DIR/rollback.pending" ]; then
      say "VPS rollback=ARMED transaction=$TXN"
    else
      say "VPS transaction=UNARMED transaction=$TXN"
    fi
  elif [ -s "$VPS_COMMITTED" ]; then
    say "VPS transaction=COMMITTED transaction=$(cat "$VPS_COMMITTED")"
  else
    say 'VPS rollback=not-pending'
  fi
  wg show "$WG_IF" latest-handshakes 2>/dev/null || true
}

# ---------- Zhao Jie OpenWrt endpoint ----------

OW_STATE='/etc/game-v2/zj717'
OW_ACTIVE="$OW_STATE/active-transaction"
OW_COMMITTED="$OW_STATE/committed-transaction"
OW_BACKUP_ROOT='/root/game-v2-zj717-backups'
OW_INSTALL='/usr/local/lib/game-v2-zj717'
OW_PROFILE_INIT='/etc/init.d/game-v2-zj717'
OW_FAKE_INIT='/etc/init.d/game-v2-zj717-faketcp'
OW_DNS_RULE='/usr/share/nftables.d/chain-pre/dstnat/10-game-v2-zj717-dns.nft'
OW_NO_SNAT_RULE='/usr/share/nftables.d/chain-pre/srcnat/10-game-v2-zj717-fixed-bridge.nft'
OW_INBOUND_RULE='/usr/share/nftables.d/chain-pre/forward/10-game-v2-zj717-inbound-3074.nft'
OW_LEGACY_INIT='/etc/init.d/wg-game-zhaojie-v2-transport'
OW_LEGACY_DIR='/usr/libexec/wg-game-zhaojie-v2'
OW_LEGACY_DNS='/usr/share/nftables.d/chain-pre/dstnat/50-wg-game-zhaojie-v2-dns.nft'
OW_LEGACY_FORWARD='/usr/share/nftables.d/chain-pre/forward/wg-game-xbox-xbox-zhao.nft'

ow_require_root() { [ "$(id -u)" -eq 0 ] || die 'OpenWrt endpoint requires root'; }

ow_assert_platform() {
  ow_require_root
  [ -r /etc/openwrt_release ] || die 'target is not OpenWrt'
  case "$(uname -m)" in x86_64|amd64) ;; *) die "unsupported OpenWrt architecture: $(uname -m)" ;; esac
  for cmd in awk cat chmod cmp cp date grep id ifdown ifup ip kill ln mkdir mv nc netstat nft nslookup rm sed setsid sleep tar tr ubus uci wc wg; do need "$cmd"; done
  [ -x /etc/init.d/network ] || die 'OpenWrt network service missing'
  [ -x /etc/init.d/firewall ] || die 'OpenWrt firewall service missing'
  ip -4 addr show dev br-lan | grep -F '192.168.7.17/24' >/dev/null || die 'Zhao LAN identity mismatch'
  ip -4 addr show dev nebula19266 | grep -F '192.168.66.30/24' >/dev/null || die 'Zhao Nebula identity mismatch'
  ip -4 route get "$VPS_HOST" | grep -F 'dev br-lan' >/dev/null || die 'VPS physical route must use br-lan'
}

ow_port_in_use() {
  proto="$1"
  port="$2"
  netstat -ln 2>/dev/null | awk -v proto="$proto" -v suffix=":$port" '
    $1 ~ ("^" proto) && length($4) >= length(suffix) && substr($4, length($4) - length(suffix) + 1) == suffix { found = 1 }
    END { exit !found }
  '
}

ow_assert_legacy() {
  [ -x "$OW_LEGACY_INIT" ] || die 'legacy Zhao service missing'
  [ -d "$OW_LEGACY_DIR" ] || die 'legacy Zhao runtime missing'
  [ -f "$OW_LEGACY_DNS" ] || die 'legacy Zhao DNS rule missing'
  [ -f "$OW_LEGACY_FORWARD" ] || die 'legacy Zhao forward rule missing'
  "$OW_LEGACY_INIT" running >/dev/null 2>&1 || die 'legacy Zhao service is not running'
  for obj in network.wg_zj network.wg_zj_peer network.wg_game_xbox_xbox_zhao_route network.wg_game_xbox_xbox_zhao_rule firewall.wg_zj_zone; do
    uci -q get "$obj" >/dev/null || die "legacy UCI object missing: $obj"
  done
  grep -F "$GAME_DEVICE_IP" "$OW_LEGACY_DNS" >/dev/null || die 'legacy Zhao DNS file does not identify the expected Xbox'
  grep -F "$GAME_DEVICE_IP" "$OW_LEGACY_FORWARD" >/dev/null || die 'legacy Zhao forward file does not identify the expected Xbox'
}

ow_assert_new_absent() {
  for path in "$OW_STATE" "$OW_INSTALL" "$OW_PROFILE_INIT" "$OW_FAKE_INIT" "$OW_DNS_RULE" "$OW_NO_SNAT_RULE" "$OW_INBOUND_RULE"; do
    [ ! -e "$path" ] || die "existing zj717 target object: $path"
  done
  for obj in network.gv2_zj717 network.gv2p_zj717 firewall.game_v2_zj717 firewall.lan_to_game_v2_zj717 firewall.game_v2_zj717_to_lan; do
    ! uci -q get "$obj" >/dev/null 2>&1 || die "existing UCI target object: $obj"
  done
  ! ip link show "$WG_IF" >/dev/null 2>&1 || die "existing interface: $WG_IF"
  ! ip rule show | grep -Eq '^(9999|10000):' || die 'policy rule priority 9999 or 10000 is already in use'
  ! ip route show table "$ROUTE_TABLE" 2>/dev/null | grep -q . || die "route table $ROUTE_TABLE is already in use"
  ! ow_port_in_use udp "$CLIENT_SPEED_PORT" || die "UDP $CLIENT_SPEED_PORT is already in use"
  ! ow_port_in_use udp "$FAKETCP_LOCAL_PORT" || die "UDP $FAKETCP_LOCAL_PORT is already in use"
}

ow_backup_dir() { printf '%s/%s\n' "$OW_BACKUP_ROOT" "$1"; }

ow_write_rollback() {
  txn="$1"
  dir="$(ow_backup_dir "$txn")"
  cat >"$dir/rollback.sh" <<EOF
#!/bin/sh
set -u
ACTIVE='$OW_ACTIVE'
COMMITTED='$OW_COMMITTED'
PACKAGE_DIR=''
FINALIZE_LOCK='$dir/finalize.lock'
LOCK_CANDIDATE="\${FINALIZE_LOCK}.\$\$"
cleanup_finalize_lock() {
  rm -f "\$LOCK_CANDIDATE"
  if [ "\$(cat "\$FINALIZE_LOCK" 2>/dev/null || true)" = "\$\$" ]; then
    rm -f "\$FINALIZE_LOCK"
  fi
}
trap cleanup_finalize_lock 0
trap 'exit 130' 1 2 15
umask 077
printf '%s\n' "\$\$" >"\$LOCK_CANDIDATE" || exit 1
lock_tries=0
while ! ln "\$LOCK_CANDIDATE" "\$FINALIZE_LOCK" 2>/dev/null; do
  lock_pid="\$(cat "\$FINALIZE_LOCK" 2>/dev/null || true)"
  case "\$lock_pid" in
    ''|*[!0-9]*) ;;
    *)
      if ! kill -0 "\$lock_pid" 2>/dev/null; then
        if [ "\$(cat "\$FINALIZE_LOCK" 2>/dev/null || true)" = "\$lock_pid" ] && ! kill -0 "\$lock_pid" 2>/dev/null; then
          rm -f "\$FINALIZE_LOCK"
        fi
        continue
      fi
      ;;
  esac
  lock_tries=\$((lock_tries + 1))
  [ "\$lock_tries" -lt 30 ] || exit 1
  sleep 1
done
rm -f "\$LOCK_CANDIDATE"
[ -s "\$ACTIVE" ] || exit 0
. "\$ACTIVE"
[ "\$BACKUP_DIR" = '$dir' ] || exit 0
if mv '$dir/rollback.pending' '$dir/rollback.claimed' 2>/dev/null; then
  :
elif [ -e '$dir/rollback.claimed' ]; then
  :
elif [ -e '$dir/commit.claimed' ]; then
  if [ -s "\$COMMITTED" ] && [ "\$(cat "\$COMMITTED")" = "\$TXN" ]; then
    exit 0
  fi
  mv '$dir/commit.claimed' '$dir/rollback.claimed' 2>/dev/null || exit 1
else
  exit 0
fi
/etc/init.d/game-v2-zj717 stop >/dev/null 2>&1 || true
/etc/init.d/game-v2-zj717 disable >/dev/null 2>&1 || true
/etc/init.d/game-v2-zj717-faketcp stop >/dev/null 2>&1 || true
/etc/init.d/game-v2-zj717-faketcp disable >/dev/null 2>&1 || true
while ip rule del priority 10000 >/dev/null 2>&1; do :; done
while ip rule del priority 9999 >/dev/null 2>&1; do :; done
ip route flush table 51873 >/dev/null 2>&1 || true
ifdown gv2_zj717 >/dev/null 2>&1 || true
rm -f '$OW_PROFILE_INIT' '$OW_FAKE_INIT' '$OW_DNS_RULE' '$OW_NO_SNAT_RULE' '$OW_INBOUND_RULE'
rm -rf '$OW_INSTALL' /var/run/game-v2-zj717-faketcp
if [ -f '$dir/network' ]; then cp '$dir/network' /etc/config/network; fi
if [ -f '$dir/firewall' ]; then cp '$dir/firewall' /etc/config/firewall; fi
if [ -f '$dir/legacy.tar.gz' ]; then tar -xzf '$dir/legacy.tar.gz' -C /; fi
/etc/init.d/network reload >/dev/null 2>&1 || true
/etc/init.d/firewall reload >/dev/null 2>&1 || true
if [ -f '$dir/legacy-enabled' ]; then '$OW_LEGACY_INIT' enable >/dev/null 2>&1 || true; fi
if [ -f '$dir/legacy-running' ]; then '$OW_LEGACY_INIT' restart >/dev/null 2>&1 || '$OW_LEGACY_INIT' start >/dev/null 2>&1 || true; fi
case "\${PACKAGE_DIR:-}" in /tmp/game-v2-zj717-package-*) rm -rf "\$PACKAGE_DIR" ;; esac
rollback_ok=yes
[ -x '$OW_LEGACY_INIT' ] || rollback_ok=no
[ -d '$OW_LEGACY_DIR' ] || rollback_ok=no
[ -f '$OW_LEGACY_DNS' ] || rollback_ok=no
[ -f '$OW_LEGACY_FORWARD' ] || rollback_ok=no
cmp '$dir/network' /etc/config/network >/dev/null 2>&1 || rollback_ok=no
cmp '$dir/firewall' /etc/config/firewall >/dev/null 2>&1 || rollback_ok=no
grep -F '$GAME_DEVICE_IP' '$OW_LEGACY_DNS' >/dev/null 2>&1 || rollback_ok=no
grep -F '$GAME_DEVICE_IP' '$OW_LEGACY_FORWARD' >/dev/null 2>&1 || rollback_ok=no
'$OW_LEGACY_INIT' running >/dev/null 2>&1 || rollback_ok=no
if [ -f '$dir/legacy-enabled' ]; then
  '$OW_LEGACY_INIT' enabled >/dev/null 2>&1 || rollback_ok=no
else
  ! '$OW_LEGACY_INIT' enabled >/dev/null 2>&1 || rollback_ok=no
fi
for obj in network.wg_zj network.wg_zj_peer network.wg_game_xbox_xbox_zhao_route network.wg_game_xbox_xbox_zhao_rule firewall.wg_zj_zone; do
  uci -q get "\$obj" >/dev/null 2>&1 || rollback_ok=no
done
for obj in network.gv2_zj717 network.gv2p_zj717 firewall.game_v2_zj717 firewall.lan_to_game_v2_zj717 firewall.game_v2_zj717_to_lan; do
  ! uci -q get "\$obj" >/dev/null 2>&1 || rollback_ok=no
done
[ ! -e '$OW_PROFILE_INIT' ] || rollback_ok=no
[ ! -e '$OW_FAKE_INIT' ] || rollback_ok=no
[ ! -e '$OW_DNS_RULE' ] || rollback_ok=no
[ ! -e '$OW_NO_SNAT_RULE' ] || rollback_ok=no
[ ! -e '$OW_INBOUND_RULE' ] || rollback_ok=no
[ ! -e '$OW_INSTALL' ] || rollback_ok=no
[ ! -e /var/run/game-v2-zj717-faketcp ] || rollback_ok=no
! ip link show gv2_zj717 >/dev/null 2>&1 || rollback_ok=no
! ip rule show | grep -Eq '^(9999|10000):' || rollback_ok=no
! ip route show table 51873 2>/dev/null | grep -q . || rollback_ok=no
[ "\$rollback_ok" = yes ] || exit 1
timer_pid="\$(cat '$dir/timer.pid' 2>/dev/null || true)"
[ "\$timer_pid" != "\$\$" ] || rm -f '$dir/timer.pid'
rm -rf '$OW_STATE'
rm -f '$dir/rollback.claimed'
exit 0
EOF
  chmod 700 "$dir/rollback.sh"
  cat >"$dir/timer.sh" <<EOF
#!/bin/sh
sleep $ROLLBACK_SECONDS
exec /bin/sh '$dir/rollback.sh'
EOF
  chmod 700 "$dir/timer.sh"
}

ow_arm_rollback() {
  dir="$1"
  : >"$dir/rollback.pending" || return 1
  setsid "$dir/timer.sh" >"$dir/timer.log" 2>&1 </dev/null &
  printf '%s\n' "$!" >"$dir/timer.pid" || return 1
  kill -0 "$(cat "$dir/timer.pid")" 2>/dev/null || return 1
}

ow_cancel_timer() {
  dir="$1"
  [ -s "$dir/timer.pid" ] || return 0
  timer_pid="$(cat "$dir/timer.pid" 2>/dev/null || true)"
  case "$timer_pid" in ''|*[!0-9]*) rm -f "$dir/timer.pid"; return 0 ;; esac
  if [ -r "/proc/$timer_pid/cmdline" ] && tr '\000' ' ' <"/proc/$timer_pid/cmdline" | grep -F "$dir/timer.sh" >/dev/null; then
    kill "$timer_pid" >/dev/null 2>&1 || true
  fi
  rm -f "$dir/timer.pid"
}

ow_prepare() {
  txn="$1"
  [ -n "$txn" ] || die 'missing transaction id'
  ow_assert_platform
  ow_assert_legacy
  ow_assert_new_absent
  dir="$(ow_backup_dir "$txn")"
  [ ! -e "$dir" ] || die "transaction already exists: $txn"
  mkdir -p "$dir"
  chmod 700 "$dir"
  cp /etc/config/network "$dir/network"
  cp /etc/config/firewall "$dir/firewall"
  tar -C / -czf "$dir/legacy.tar.gz" \
    "${OW_LEGACY_INIT#/}" "${OW_LEGACY_DIR#/}" "${OW_LEGACY_DNS#/}" "${OW_LEGACY_FORWARD#/}"
  "$OW_LEGACY_INIT" enabled >/dev/null 2>&1 && : >"$dir/legacy-enabled" || true
  "$OW_LEGACY_INIT" running >/dev/null 2>&1 && : >"$dir/legacy-running" || true
  ip rule show >"$dir/rules-before.txt"
  ip route show table all >"$dir/routes-before.txt"
  nft list ruleset >"$dir/nft-before.txt"
  ow_write_rollback "$txn"
  mkdir -p "$OW_STATE"
  chmod 700 "$OW_STATE"
  cat >"$OW_ACTIVE" <<EOF
TXN='$txn'
BACKUP_DIR='$dir'
PACKAGE_DIR='/tmp/game-v2-zj717-package-$txn'
EOF
  chmod 600 "$OW_ACTIVE"
  if ! ow_arm_rollback "$dir"; then
    /bin/sh "$dir/rollback.sh"
    die 'failed to arm OpenWrt rollback; prepared state was restored'
  fi
  say "OPENWRT_PREPARE_PASS transaction=$txn rollback=armed-${ROLLBACK_SECONDS}s"
}

ow_load_package() {
  package="$1"
  [ -s "$package/enrollment.env" ] || die 'client package enrollment missing'
  [ -x "$package/speederv2" ] || die 'client package speederv2 missing'
  [ -x "$package/udp2raw" ] || die 'client package udp2raw missing'
  . "$package/enrollment.env"
  [ "${CLIENT_ID:-}" = zj717 ] || die 'client package identity mismatch'
  [ "${SERVER_ENDPOINT:-}" = "$VPS_HOST" ] || die 'client package endpoint mismatch'
  [ -n "${SERVER_PUBLIC_KEY:-}" ] || die 'client package server public key missing'
  [ -n "${CLIENT_PRIVATE_KEY:-}" ] || die 'client package private key missing'
  [ -n "${SPEEDERV2_KEY:-}" ] || die 'client package speed key missing'
}

ow_remove_legacy() {
  "$OW_LEGACY_INIT" stop >/dev/null 2>&1 || true
  "$OW_LEGACY_INIT" disable >/dev/null 2>&1 || true
  for obj in \
    network.wg_zj network.wg_zj_peer network.wg_game_xbox_xbox_zhao_route network.wg_game_xbox_xbox_zhao_rule \
    firewall.wg_zj_zone; do
    uci -q delete "$obj" || true
  done
  uci commit network
  uci commit firewall
  rm -f "$OW_LEGACY_INIT" "$OW_LEGACY_DNS" "$OW_LEGACY_FORWARD"
  rm -rf "$OW_LEGACY_DIR"
}

ow_write_runtime() {
  package="$1"
  mkdir -p "$OW_STATE" "$OW_INSTALL"
  chmod 700 "$OW_STATE"
  chmod 755 "$OW_INSTALL"
  cp "$package/speederv2" "$OW_INSTALL/speederv2"
  cp "$package/udp2raw" "$OW_INSTALL/udp2raw"
  chmod 755 "$OW_INSTALL/speederv2" "$OW_INSTALL/udp2raw"
  umask 077
  cat >"$OW_STATE/profile.env" <<EOF
SERVER_ENDPOINT='$SERVER_ENDPOINT'
SPEEDERV2_KEY='$SPEEDERV2_KEY'
EOF
  chmod 600 "$OW_STATE/profile.env"
  cat >"$OW_STATE/fec.state" <<'EOF'
# game-v2 zj717 FEC state
preset=original
EOF
  chmod 600 "$OW_STATE/fec.state"
  umask 022

  cat >"$OW_INSTALL/run-faketcp.sh" <<'EOF'
#!/bin/sh
set -eu
. /etc/game-v2/zj717/profile.env
runtime=/var/run/game-v2-zj717-faketcp
mkdir -p "$runtime"
umask 077
cat >"$runtime/udp2raw.conf" <<CFG
-c
-l 127.0.0.1:31973
-r $SERVER_ENDPOINT:40973
--raw-mode easyfaketcp
--cipher-mode aes128cbc
--auth-mode hmac_sha1
--log-level 3
--disable-color
-k $SPEEDERV2_KEY
CFG
exec /usr/local/lib/game-v2-zj717/udp2raw --conf-file "$runtime/udp2raw.conf"
EOF

  cat >"$OW_INSTALL/run-profile.sh" <<'EOF'
#!/bin/sh
set -eu
. /etc/game-v2/zj717/profile.env
case "${1:-}" in
  start)
    ifup gv2_zj717
    ready=0
    while [ "$ready" -lt 20 ]; do
      ip -4 addr show dev gv2_zj717 2>/dev/null | grep -F '10.77.3.2/30' >/dev/null && break
      ready=$((ready + 1))
      sleep 1
    done
    [ "$ready" -lt 20 ]
    main_route="$(ip -4 route get "$SERVER_ENDPOINT" | sed -n '1p')"
    main_gw="$(printf '%s\n' "$main_route" | awk '{for (i=1;i<=NF;i++) if ($i=="via") print $(i+1)}')"
    main_dev="$(printf '%s\n' "$main_route" | awk '{for (i=1;i<=NF;i++) if ($i=="dev") print $(i+1)}')"
    [ -n "$main_dev" ]
    if [ -n "$main_gw" ]; then
      ip route replace "$SERVER_ENDPOINT/32" via "$main_gw" dev "$main_dev" table 51873
    else
      ip route replace "$SERVER_ENDPOINT/32" dev "$main_dev" table 51873
    fi
    ip route replace 10.77.3.1/32 dev gv2_zj717 table 51873
    ip route replace default dev gv2_zj717 table 51873
    while ip rule del priority 10000 2>/dev/null; do :; done
    while ip rule del priority 9999 2>/dev/null; do :; done
    ip rule add priority 9999 from 192.168.7.0/24 to 192.168.7.0/24 lookup main
    ip rule add priority 10000 from 192.168.7.0/24 lookup 51873
    preset="$(sed -n 's/^preset=//p' /etc/game-v2/zj717/fec.state | sed -n '1p')"
    case "$preset" in
      auto) set -- '-f1:3,2:4,8:6,20:10' '--timeout' '8' ;;
      original) set -- ;;
      light) set -- '-f2:2' '--timeout' '1' ;;
      balanced) set -- '-f2:4' '--timeout' '1' ;;
      strong) set -- '-f2:6' '--timeout' '1' ;;
      extreme) set -- '-f2:4' '--timeout' '0' ;;
      *) exit 2 ;;
    esac
    exec /usr/local/lib/game-v2-zj717/speederv2 -c -l127.0.0.1:30973 -r127.0.0.1:31973 --mode 0 -k "$SPEEDERV2_KEY" "$@"
    ;;
  stop)
    while ip rule del priority 10000 2>/dev/null; do :; done
    while ip rule del priority 9999 2>/dev/null; do :; done
    ip route flush table 51873 2>/dev/null || true
    ifdown gv2_zj717 >/dev/null 2>&1 || true
    ;;
  *) exit 2 ;;
esac
EOF
  chmod 700 "$OW_INSTALL/run-faketcp.sh" "$OW_INSTALL/run-profile.sh"

  cat >"$OW_FAKE_INIT" <<'EOF'
#!/bin/sh /etc/rc.common
USE_PROCD=1
START=90
STOP=10
start_service() {
  procd_open_instance
  procd_set_param command /usr/local/lib/game-v2-zj717/run-faketcp.sh
  procd_set_param respawn 3600 5 5
  procd_set_param stdout 1
  procd_set_param stderr 1
  procd_close_instance
}
EOF
  cat >"$OW_PROFILE_INIT" <<'EOF'
#!/bin/sh /etc/rc.common
USE_PROCD=1
START=91
STOP=9
start_service() {
  procd_open_instance
  procd_set_param command /usr/local/lib/game-v2-zj717/run-profile.sh start
  procd_set_param respawn 3600 5 5
  procd_set_param stdout 1
  procd_set_param stderr 1
  procd_close_instance
}
stop_service() {
  /usr/local/lib/game-v2-zj717/run-profile.sh stop
}
EOF
  chmod 755 "$OW_FAKE_INIT" "$OW_PROFILE_INIT"
}

ow_write_uci() {
  uci batch <<EOF
set network.gv2_zj717='interface'
set network.gv2_zj717.proto='wireguard'
set network.gv2_zj717.private_key='$CLIENT_PRIVATE_KEY'
add_list network.gv2_zj717.addresses='$CLIENT_WG_ADDR'
set network.gv2_zj717.mtu='1500'
set network.gv2_zj717.auto='0'
set network.gv2p_zj717='wireguard_gv2_zj717'
set network.gv2p_zj717.public_key='$SERVER_PUBLIC_KEY'
set network.gv2p_zj717.endpoint_host='127.0.0.1'
set network.gv2p_zj717.endpoint_port='$CLIENT_SPEED_PORT'
add_list network.gv2p_zj717.allowed_ips='0.0.0.0/0'
set network.gv2p_zj717.route_allowed_ips='0'
set network.gv2p_zj717.persistent_keepalive='25'
set firewall.game_v2_zj717='zone'
set firewall.game_v2_zj717.name='game_v2_zj717'
add_list firewall.game_v2_zj717.network='gv2_zj717'
set firewall.game_v2_zj717.input='REJECT'
set firewall.game_v2_zj717.output='ACCEPT'
set firewall.game_v2_zj717.forward='REJECT'
set firewall.game_v2_zj717.masq='1'
set firewall.game_v2_zj717.mtu_fix='1'
set firewall.lan_to_game_v2_zj717='forwarding'
set firewall.lan_to_game_v2_zj717.src='lan'
set firewall.lan_to_game_v2_zj717.dest='game_v2_zj717'
set firewall.game_v2_zj717_to_lan='forwarding'
set firewall.game_v2_zj717_to_lan.src='game_v2_zj717'
set firewall.game_v2_zj717_to_lan.dest='lan'
EOF
  uci commit network
  uci commit firewall
}

ow_write_firewall_fragments() {
  mkdir -p "$(dirname "$OW_DNS_RULE")" "$(dirname "$OW_NO_SNAT_RULE")" "$(dirname "$OW_INBOUND_RULE")"
  cat >"$OW_DNS_RULE" <<EOF
ip saddr $GAME_DEVICE_IP meta l4proto { tcp, udp } th dport 53 counter dnat to $SERVER_WG_IP:53 comment "zj717-dns-v1"
EOF
  cat >"$OW_NO_SNAT_RULE" <<EOF
oifname "$WG_IF" ip saddr $GAME_DEVICE_IP counter return comment "game-v2:zj717-fixed-bridge:no-local-snat"
EOF
  cat >"$OW_INBOUND_RULE" <<EOF
iifname "$WG_IF" oifname "br-lan" ip daddr $GAME_DEVICE_IP udp dport $GAME_DEVICE_PORT counter accept comment "zj717-nat-inbound-v1"
EOF
}

ow_start_new() {
  /etc/init.d/network reload
  /etc/init.d/firewall reload
  "$OW_FAKE_INIT" enable
  "$OW_FAKE_INIT" start
  sleep 1
  "$OW_PROFILE_INIT" enable
  "$OW_PROFILE_INIT" start
}

ow_service_running() {
  ubus call service list "{\"name\":\"$1\"}" 2>/dev/null | grep -q '"running": true'
}

ow_dns_tcp_probe() {
  request="/tmp/game-v2-zj717-dns-request.$$"
  response="/tmp/game-v2-zj717-dns-response.$$"
  probe_ok=no
  printf '\000\035\000\001\001\000\000\001\000\000\000\000\000\000\007example\003com\000\000\001\000\001' >"$request" || return 1
  : >"$response" || { rm -f "$request"; return 1; }
  setsid nc "$SERVER_WG_IP" 53 <"$request" >"$response" 2>/dev/null &
  probe_pid=$!
  i=0
  while [ "$i" -lt 5 ]; do
    bytes="$(wc -c <"$response" | tr -d ' ')"
    if [ "${bytes:-0}" -gt 2 ]; then
      probe_ok=yes
      break
    fi
    if ! kill -0 "$probe_pid" 2>/dev/null; then
      break
    fi
    sleep 1
    i=$((i + 1))
  done
  kill "$probe_pid" 2>/dev/null || true
  wait "$probe_pid" 2>/dev/null || true
  bytes="$(wc -c <"$response" | tr -d ' ')"
  rm -f "$request" "$response"
  [ "$probe_ok" = yes ] && [ "${bytes:-0}" -gt 2 ]
}

ow_verify() {
  ow_assert_platform
  [ -s "$OW_STATE/profile.env" ] || die 'zj717 profile state missing'
  ow_service_running game-v2-zj717-faketcp || die 'zj717 FakeTCP service is not running'
  ow_service_running game-v2-zj717 || die 'zj717 profile service is not running'
  ip -4 addr show dev "$WG_IF" | grep -F "$CLIENT_WG_ADDR" >/dev/null || die 'zj717 WireGuard address mismatch'
  ip rule show | grep -Eq '^9999:.*from 192\.168\.7\.0/24 to 192\.168\.7\.0/24 lookup main' || die 'zj717 LAN bypass rule missing'
  ip rule show | grep -Eq '^10000:.*from 192\.168\.7\.0/24 lookup 51873' || die 'zj717 policy rule missing'
  ip route show table "$ROUTE_TABLE" | grep -F "default dev $WG_IF" >/dev/null || die 'zj717 policy default route missing'
  wg show "$WG_IF" endpoints | grep -F '127.0.0.1:30973' >/dev/null || die 'zj717 WireGuard endpoint mismatch'
  handshake="$(wg show "$WG_IF" latest-handshakes | awk 'NR==1 {print $2}')"
  [ "${handshake:-0}" -gt 0 ] || die 'zj717 WireGuard has no handshake'
  nft list ruleset | grep -F 'zj717-dns-v1' >/dev/null || die 'zj717 DNS DNAT missing'
  nft list ruleset | grep -F 'game-v2:zj717-fixed-bridge:no-local-snat' >/dev/null || die 'zj717 no-SNAT rule missing'
  nft list ruleset | grep -F 'zj717-nat-inbound-v1' >/dev/null || die 'zj717 inbound rule missing'
  ip -4 route get "$VPS_HOST" | grep -F 'dev br-lan' >/dev/null || die 'VPS endpoint route is looping into the tunnel'
  nslookup example.com "$SERVER_WG_IP" >/dev/null 2>&1 || die 'zj717 UDP DNS probe failed'
  ow_dns_tcp_probe || die 'zj717 TCP DNS probe failed'
  [ ! -e "$OW_LEGACY_INIT" ] || die 'legacy Zhao service still exists'
  [ ! -e "$OW_LEGACY_DIR" ] || die 'legacy Zhao runtime still exists'
  [ ! -e "$OW_LEGACY_DNS" ] || die 'legacy Zhao DNS rule still exists'
  [ ! -e "$OW_LEGACY_FORWARD" ] || die 'legacy Zhao forward rule still exists'
  for obj in network.wg_zj network.wg_zj_peer network.wg_game_xbox_xbox_zhao_route network.wg_game_xbox_xbox_zhao_rule firewall.wg_zj_zone; do
    ! uci -q get "$obj" >/dev/null 2>&1 || die "legacy UCI object still exists: $obj"
  done
  say 'OPENWRT_VERIFY_PASS'
}

ow_apply() {
  txn="$1"
  package="$2"
  [ -s "$OW_ACTIVE" ] || die 'no prepared OpenWrt transaction'
  . "$OW_ACTIVE"
  [ "$TXN" = "$txn" ] || die 'OpenWrt transaction mismatch'
  case "$package" in /tmp/game-v2-zj717-package-"$txn") ;; *) die 'unsafe client package path' ;; esac
  ow_assert_platform
  ow_load_package "$package"
  cat >"$OW_ACTIVE" <<EOF
TXN='$txn'
BACKUP_DIR='$BACKUP_DIR'
PACKAGE_DIR='$package'
EOF
  chmod 600 "$OW_ACTIVE"
  ow_remove_legacy
  ow_write_runtime "$package"
  ow_write_uci
  ow_write_firewall_fragments
  ow_start_new
  wait_count=0
  while [ "$wait_count" -lt 30 ]; do
    handshake="$(wg show "$WG_IF" latest-handshakes 2>/dev/null | awk 'NR==1 {print $2}')"
    [ "${handshake:-0}" -gt 0 ] && break
    wait_count=$((wait_count + 1))
    sleep 1
  done
  ow_verify
  say "OPENWRT_APPLY_PASS transaction=$txn"
}

ow_txn_state() {
  if [ -s "$OW_ACTIVE" ]; then
    . "$OW_ACTIVE"
    if [ -e "$BACKUP_DIR/commit.claimed" ]; then
      printf 'commit-claimed:%s\n' "$TXN"
    elif [ -e "$BACKUP_DIR/rollback.claimed" ]; then
      printf 'rollback-claimed:%s\n' "$TXN"
    elif [ -e "$BACKUP_DIR/rollback.pending" ]; then
      printf 'pending:%s\n' "$TXN"
    else
      printf 'unarmed:%s\n' "$TXN"
    fi
  elif [ -s "$OW_COMMITTED" ]; then
    printf 'committed:%s\n' "$(cat "$OW_COMMITTED")"
  else
    die 'no OpenWrt transaction state'
  fi
}

ow_commit() {
  expected="$1"
  [ -n "$expected" ] || die 'missing expected OpenWrt transaction'
  if [ ! -s "$OW_ACTIVE" ]; then
    [ -s "$OW_COMMITTED" ] && [ "$(cat "$OW_COMMITTED")" = "$expected" ] || die 'no matching pending or committed OpenWrt transaction'
    ow_verify
    say "OPENWRT_COMMIT_ALREADY_PASS transaction=$expected"
    return 0
  fi
  . "$OW_ACTIVE"
  [ "$TXN" = "$expected" ] || die 'OpenWrt commit transaction mismatch'
  prepared_backup="$BACKUP_DIR"
  FINALIZE_LOCK="$BACKUP_DIR/finalize.lock"
  LOCK_CANDIDATE="${FINALIZE_LOCK}.$$"
  cleanup_finalize_lock() {
    rm -f "$LOCK_CANDIDATE"
    if [ "$(cat "$FINALIZE_LOCK" 2>/dev/null || true)" = "$$" ]; then
      rm -f "$FINALIZE_LOCK"
    fi
  }
  trap cleanup_finalize_lock 0
  trap 'exit 130' 1 2 15
  umask 077
  printf '%s\n' "$$" >"$LOCK_CANDIDATE" || die 'cannot prepare OpenWrt finalize lock'
  lock_tries=0
  while ! ln "$LOCK_CANDIDATE" "$FINALIZE_LOCK" 2>/dev/null; do
    lock_pid="$(cat "$FINALIZE_LOCK" 2>/dev/null || true)"
    case "$lock_pid" in
      ''|*[!0-9]*) ;;
      *)
        if ! kill -0 "$lock_pid" 2>/dev/null; then
          if [ "$(cat "$FINALIZE_LOCK" 2>/dev/null || true)" = "$lock_pid" ] && ! kill -0 "$lock_pid" 2>/dev/null; then
            rm -f "$FINALIZE_LOCK"
          fi
          continue
        fi
        ;;
    esac
    lock_tries=$((lock_tries + 1))
    [ "$lock_tries" -lt 30 ] || die 'OpenWrt finalize lock timeout'
    sleep 1
  done
  rm -f "$LOCK_CANDIDATE"
  [ -s "$OW_ACTIVE" ] || die 'OpenWrt rollback completed before commit acquired the transaction'
  . "$OW_ACTIVE"
  [ "$TXN" = "$expected" ] && [ "$BACKUP_DIR" = "$prepared_backup" ] || die 'OpenWrt active transaction changed while commit waited for the lock'
  ow_verify
  if mv "$BACKUP_DIR/rollback.pending" "$BACKUP_DIR/commit.claimed" 2>/dev/null; then
    :
  elif [ -e "$BACKUP_DIR/commit.claimed" ]; then
    :
  else
    die 'OpenWrt rollback already started or is no longer armed'
  fi
  umask 077
  committed_tmp="$OW_STATE/.committed.$$"
  printf '%s\n' "$TXN" >"$committed_tmp"
  mv "$committed_tmp" "$OW_COMMITTED"
  rm -f "$OW_ACTIVE"
  ow_cancel_timer "$BACKUP_DIR"
  case "${PACKAGE_DIR:-}" in /tmp/game-v2-zj717-package-*) rm -rf "$PACKAGE_DIR" || true ;; esac
  rm -f "$BACKUP_DIR/commit.claimed"
  say "OPENWRT_COMMIT_PASS transaction=$TXN"
}

ow_rollback() {
  requested="${1:-}"
  [ -s "$OW_ACTIVE" ] || { say 'OPENWRT_ROLLBACK_NO_PENDING_TRANSACTION'; return 0; }
  . "$OW_ACTIVE"
  [ -z "$requested" ] || [ "$TXN" = "$requested" ] || die 'OpenWrt rollback transaction mismatch'
  /bin/sh "$BACKUP_DIR/rollback.sh"
  [ ! -s "$OW_ACTIVE" ] || die 'OpenWrt rollback could not claim the pending transaction'
  ow_cancel_timer "$BACKUP_DIR"
  say "OPENWRT_ROLLBACK_PASS transaction=$TXN"
}

ow_status() {
  printf 'OpenWrt zj717 FakeTCP=%s profile=%s\n' \
    "$(ow_service_running game-v2-zj717-faketcp && printf active || printf inactive)" \
    "$(ow_service_running game-v2-zj717 && printf active || printf inactive)"
  if [ -s "$OW_ACTIVE" ]; then
    . "$OW_ACTIVE"
    if [ -e "$BACKUP_DIR/commit.claimed" ]; then
      say "OpenWrt transaction=COMMIT_CLAIMED transaction=$TXN"
    elif [ -e "$BACKUP_DIR/rollback.claimed" ]; then
      say "OpenWrt transaction=ROLLBACK_CLAIMED transaction=$TXN"
    elif [ -e "$BACKUP_DIR/rollback.pending" ]; then
      say "OpenWrt rollback=ARMED transaction=$TXN"
    else
      say "OpenWrt transaction=UNARMED transaction=$TXN"
    fi
  elif [ -s "$OW_COMMITTED" ]; then
    say "OpenWrt transaction=COMMITTED transaction=$(cat "$OW_COMMITTED")"
  else
    say 'OpenWrt rollback=not-pending'
  fi
  wg show "$WG_IF" latest-handshakes 2>/dev/null || true
}

# ---------- zj717 web panel repair ----------

PANEL_VPS_STATE='/var/lib/game-v2-zj717-panel'
PANEL_VPS_ACTIVE="$PANEL_VPS_STATE/active-transaction"
PANEL_VPS_BACKUP_ROOT='/var/backups/game-v2-zj717-panel'
PANEL_VPS_INSTALL='/usr/local/lib/game-v2-zj717-panel'
PANEL_VPS_RUNNER='/usr/local/lib/game-v2/clients/zj717/run-speederv2'
PANEL_VPS_FEC_STATE='/var/lib/game-v2/server/clients/zj717/fec.state'
PANEL_VPS_AUTHORIZED='/root/.ssh/authorized_keys'

PANEL_OW_STATE='/etc/game-v2/zj717-panel'
PANEL_OW_ACTIVE="$PANEL_OW_STATE/active-transaction"
PANEL_OW_BACKUP_ROOT='/root/game-v2-zj717-panel-backups'
PANEL_OW_INSTALL='/usr/local/lib/game-v2-zj717-panel'
PANEL_OW_FEC_STATE='/etc/game-v2/zj717/fec.state'
PANEL_OW_KEY_DIR='/etc/wg-game-v2/panel/ssh/nl-zhaojie-v2'
PANEL_OW_PROFILE='/etc/wg-game-v2/panel/profiles/nl-zhaojie-v2/faketcp'
PANEL_OW_ROOT='/etc/wg-game-v2/panel'
PANEL_CONTROL_SCRIPT='/usr/libexec/wg-game/panel-control.sh'
PANEL_CONTROL_STATE='/var/lib/wg-game-v2/panel'
PANEL_STATUS_STATE='/etc/game-v2/zj717-panel-status'
PANEL_STATUS_ACTIVE="$PANEL_STATUS_STATE/active-transaction"
PANEL_STATUS_BACKUP_ROOT='/root/game-v2-zj717-panel-status-backups'
PANEL_STATUS_ROLLBACK_SECONDS='900'
PANEL_PAGE_STATE='/etc/game-v2/zj717-panel-page-reinstall'
PANEL_PAGE_ACTIVE="$PANEL_PAGE_STATE/active-transaction"
PANEL_PAGE_BACKUP_ROOT='/root/game-v2-zj717-panel-page-backups'
PANEL_PAGE_ROLLBACK_SECONDS='900'
PANEL_LATENCY_STATE='/etc/game-v2/zj717-panel-status-latency'
PANEL_LATENCY_ACTIVE="$PANEL_LATENCY_STATE/active-transaction"
PANEL_LATENCY_BACKUP_ROOT='/root/game-v2-zj717-panel-status-latency-backups'
PANEL_LATENCY_ROLLBACK_SECONDS='900'

panel_validate_preset() {
  case "$1" in auto|original|light|balanced|strong|extreme) return 0 ;; *) return 1 ;; esac
}

panel_read_preset() {
  state_file="$1"
  preset="$(sed -n 's/^preset=//p' "$state_file" 2>/dev/null | sed -n '1p')"
  panel_validate_preset "$preset" || return 1
  printf '%s\n' "$preset"
}

panel_write_status_hook() {
  target="$1"
  cat >"$target" <<'EOF'
#!/bin/sh
set -u

coordinator='/usr/local/lib/game-v2-zj717-panel/fec-coordinator.sh'
tunnel_if='gv2_zj717'
probe_target='1.1.1.1'

status_output="$("$coordinator" status --node-id nl-zhaojie-v2)" || exit 1
latency_ms=''
network_state='unavailable'
if ip link show dev "$tunnel_if" >/dev/null 2>&1; then
  probe_output="$(ping -I "$tunnel_if" -c 1 -W 2 "$probe_target" 2>/dev/null || true)"
  latency_ms="$(printf '%s\n' "$probe_output" | sed -n 's/.*time[=<]\([0-9][0-9.]*\)[[:space:]]*ms.*/\1/p' | sed -n '1p')"
  case "$latency_ms" in
    ''|*[!0-9.]*) latency_ms='' ;;
    *) network_state='reachable' ;;
  esac
fi

printf '%s\n' "$status_output" | sed '/^WG_LATENCY_MS=/d; /^WG_NETWORK_STATE=/d'
printf 'WG_NETWORK_STATE=%s\nWG_LATENCY_MS=%s\n' "$network_state" "$latency_ms"
EOF
  chmod 755 "$target"
}

panel_vps_write_rollback() {
  dir="$1"
  cat >"$dir/rollback.sh" <<EOF
#!/bin/sh
set -u
dir='$dir'
active='$PANEL_VPS_ACTIVE'
state='$PANEL_VPS_FEC_STATE'
authorized='$PANEL_VPS_AUTHORIZED'
install_dir='$PANEL_VPS_INSTALL'
[ -e "\$dir/rollback.pending" ] || exit 0
mv "\$dir/rollback.pending" "\$dir/rollback.claimed" 2>/dev/null || exit 0
if [ -f "\$dir/fec.state" ]; then
  cp "\$dir/fec.state" "\$state"
else
  rm -f "\$state"
fi
if [ -f "\$dir/authorized_keys" ]; then
  cp "\$dir/authorized_keys" "\$authorized"
  chmod 600 "\$authorized"
else
  rm -f "\$authorized"
fi
rm -rf "\$install_dir"
if [ -f "\$dir/install.tar.gz" ]; then tar -xzf "\$dir/install.tar.gz" -C /; fi
systemctl restart game-v2-speed-zj717.service >/dev/null 2>&1 || exit 1
systemctl is-active --quiet game-v2-speed-zj717.service || exit 1
current_started="\$(docker inspect -f '{{.State.StartedAt}}' '$PROTECTED_CONTAINER' 2>/dev/null)"
[ "\$current_started" = "\$(cat "\$dir/protected-container-started.before")" ] || exit 1
rm -f "\$active" "\$dir/rollback.claimed"
exit 0
EOF
  chmod 700 "$dir/rollback.sh"
}

panel_vps_arm_rollback() {
  txn="$1"
  dir="$2"
  unit="game-v2-zj717-panel-rollback-$(printf '%s' "$txn" | tr -c 'A-Za-z0-9_.-' '-')"
  : >"$dir/rollback.pending"
  systemd-run --quiet --unit="$unit" --on-active="${ROLLBACK_SECONDS}s" /bin/sh "$dir/rollback.sh"
  printf '%s\n' "$unit" >"$dir/rollback-unit"
  systemctl is-active --quiet "$unit.timer"
}

panel_vps_cancel_rollback() {
  dir="$1"
  unit="$(cat "$dir/rollback-unit" 2>/dev/null || true)"
  if [ -n "$unit" ]; then
    systemctl stop "$unit.timer" "$unit.service" >/dev/null 2>&1 || true
    systemctl reset-failed "$unit.service" >/dev/null 2>&1 || true
  fi
  rm -f "$dir/rollback.pending"
}

panel_vps_prepare() {
  txn="$1"
  [ -n "$txn" ] || die 'missing panel VPS transaction'
  vps_assert_base
  [ -x "$PANEL_VPS_RUNNER" ] || die 'zj717 VPS speed runner missing'
  grep -F "$PANEL_VPS_FEC_STATE" "$PANEL_VPS_RUNNER" >/dev/null || die 'zj717 VPS speed runner is not FEC aware'
  [ ! -s "$PANEL_VPS_ACTIVE" ] || die 'another zj717 VPS panel repair is pending'
  dir="$PANEL_VPS_BACKUP_ROOT/$txn"
  [ ! -e "$dir" ] || die 'panel VPS transaction already exists'
  mkdir -p "$dir" "$PANEL_VPS_STATE"
  chmod 700 "$dir" "$PANEL_VPS_STATE"
  [ ! -f "$PANEL_VPS_FEC_STATE" ] || cp "$PANEL_VPS_FEC_STATE" "$dir/fec.state"
  [ ! -f "$PANEL_VPS_AUTHORIZED" ] || cp "$PANEL_VPS_AUTHORIZED" "$dir/authorized_keys"
  [ ! -d "$PANEL_VPS_INSTALL" ] || tar -C / -czf "$dir/install.tar.gz" "${PANEL_VPS_INSTALL#/}"
  docker inspect -f '{{.State.StartedAt}}' "$PROTECTED_CONTAINER" >"$dir/protected-container-started.before"
  panel_vps_write_rollback "$dir"
  cat >"$PANEL_VPS_ACTIVE" <<EOF
TXN='$txn'
BACKUP_DIR='$dir'
EOF
  chmod 600 "$PANEL_VPS_ACTIVE"
  if ! panel_vps_arm_rollback "$txn" "$dir"; then
    /bin/sh "$dir/rollback.sh" || true
    die 'failed to arm VPS panel rollback'
  fi
  say "PANEL_VPS_PREPARE_PASS transaction=$txn rollback=armed-${ROLLBACK_SECONDS}s"
}

panel_vps_write_endpoint() {
  mkdir -p "$PANEL_VPS_INSTALL" "$(dirname "$PANEL_VPS_FEC_STATE")"
  chmod 755 "$PANEL_VPS_INSTALL"
  cat >"$PANEL_VPS_INSTALL/fec-endpoint.sh" <<'EOF'
#!/bin/sh
set -eu
state=/var/lib/game-v2/server/clients/zj717/fec.state
unit=game-v2-speed-zj717.service
validate() { case "$1" in auto|original|light|balanced|strong|extreme) return 0 ;; *) return 1 ;; esac; }
read_preset() {
  value="$(sed -n 's/^preset=//p' "$state" 2>/dev/null | sed -n '1p')"
  validate "$value" || return 1
  printf '%s\n' "$value"
}
verify() {
  expected="$1"
  validate "$expected" || return 1
  [ "$(read_preset)" = "$expected" ] || return 1
  systemctl is-active --quiet "$unit" || return 1
  pid="$(systemctl show -p MainPID --value "$unit")"
  case "$pid" in ''|0|*[!0-9]*) return 1 ;; esac
  [ -r "/proc/$pid/cmdline" ] || return 1
  args="$(tr '\000' ' ' <"/proc/$pid/cmdline")"
  case "$expected" in
    auto) printf '%s\n' "$args" | grep -F -- '-f1:3,2:4,8:6,20:10' >/dev/null && printf '%s\n' "$args" | grep -F -- '--timeout 8' >/dev/null ;;
    original) ! printf '%s\n' "$args" | grep -Eq '(^|[[:space:]])-f[^[:space:]]*' ;;
    light) printf '%s\n' "$args" | grep -F -- '-f2:2' >/dev/null && printf '%s\n' "$args" | grep -F -- '--timeout 1' >/dev/null ;;
    balanced) printf '%s\n' "$args" | grep -F -- '-f2:4' >/dev/null && printf '%s\n' "$args" | grep -F -- '--timeout 1' >/dev/null ;;
    strong) printf '%s\n' "$args" | grep -F -- '-f2:6' >/dev/null && printf '%s\n' "$args" | grep -F -- '--timeout 1' >/dev/null ;;
    extreme) printf '%s\n' "$args" | grep -F -- '-f2:4' >/dev/null && printf '%s\n' "$args" | grep -F -- '--timeout 0' >/dev/null ;;
  esac
}
apply() {
  target="$1"
  validate "$target" || return 2
  old="$(read_preset)"
  tmp="$state.$$"
  umask 077
  printf '# game-v2 zj717 FEC state\npreset=%s\n' "$target" >"$tmp"
  mv "$tmp" "$state"
  if systemctl restart "$unit" && verify "$target"; then return 0; fi
  printf '# game-v2 zj717 FEC state\npreset=%s\n' "$old" >"$tmp"
  mv "$tmp" "$state"
  systemctl restart "$unit" >/dev/null 2>&1 || true
  return 1
}
cmd="${1:-}"
case "$cmd" in
  status) [ "$#" -eq 1 ]; printf 'FEC_PRESET=%s\n' "$(read_preset)" ;;
  apply) [ "$#" -eq 2 ]; apply "$2" ;;
  verify) [ "$#" -eq 2 ]; verify "$2" ;;
  *) exit 2 ;;
esac
EOF
  cat >"$PANEL_VPS_INSTALL/forced-command.sh" <<'EOF'
#!/bin/sh
set -eu
case "${SSH_ORIGINAL_COMMAND:-}" in
  status) exec /usr/local/lib/game-v2-zj717-panel/fec-endpoint.sh status ;;
  'apply auto'|'apply original'|'apply light'|'apply balanced'|'apply strong'|'apply extreme')
    exec /usr/local/lib/game-v2-zj717-panel/fec-endpoint.sh ${SSH_ORIGINAL_COMMAND} ;;
  'verify auto'|'verify original'|'verify light'|'verify balanced'|'verify strong'|'verify extreme')
    exec /usr/local/lib/game-v2-zj717-panel/fec-endpoint.sh ${SSH_ORIGINAL_COMMAND} ;;
  *) exit 2 ;;
esac
EOF
  chmod 755 "$PANEL_VPS_INSTALL/fec-endpoint.sh" "$PANEL_VPS_INSTALL/forced-command.sh"
}

panel_vps_apply() {
  txn="$1"
  [ -s "$PANEL_VPS_ACTIVE" ] || die 'no prepared VPS panel transaction'
  . "$PANEL_VPS_ACTIVE"
  [ "$TXN" = "$txn" ] || die 'VPS panel transaction mismatch'
  pub="/tmp/game-v2-zj717-panel-$txn.pub"
  [ -s "$pub" ] || die 'staged zj717 panel public key missing'
  key_line="$(sed -n '1p' "$pub")"
  case "$key_line" in ssh-ed25519\ *) ;; *) die 'invalid zj717 panel public key' ;; esac
  panel_vps_write_endpoint
  [ -f "$PANEL_VPS_FEC_STATE" ] || { umask 077; printf '# game-v2 zj717 FEC state\npreset=original\n' >"$PANEL_VPS_FEC_STATE"; }
  mkdir -p /root/.ssh
  chmod 700 /root/.ssh
  auth_tmp="$PANEL_VPS_AUTHORIZED.$$"
  if [ -f "$PANEL_VPS_AUTHORIZED" ]; then
    awk '$NF != "game-v2-zj717-panel"' "$PANEL_VPS_AUTHORIZED" >"$auth_tmp"
  else
    : >"$auth_tmp"
  fi
  printf '%s %s\n' 'no-agent-forwarding,no-port-forwarding,no-pty,no-user-rc,no-X11-forwarding,command="/usr/local/lib/game-v2-zj717-panel/forced-command.sh"' "$key_line" >>"$auth_tmp"
  chmod 600 "$auth_tmp"
  mv "$auth_tmp" "$PANEL_VPS_AUTHORIZED"
  rm -f "$pub"
  "$PANEL_VPS_INSTALL/fec-endpoint.sh" verify "$(panel_read_preset "$PANEL_VPS_FEC_STATE")"
  vps_assert_protected_live
  say "PANEL_VPS_APPLY_PASS transaction=$txn"
}

panel_vps_verify() {
  expected="$1"
  panel_validate_preset "$expected" || die 'invalid VPS panel verification preset'
  [ -x "$PANEL_VPS_INSTALL/fec-endpoint.sh" ] || die 'VPS panel endpoint missing'
  "$PANEL_VPS_INSTALL/fec-endpoint.sh" verify "$expected" || die 'VPS FEC verification failed'
  grep -F 'game-v2-zj717-panel' "$PANEL_VPS_AUTHORIZED" >/dev/null || die 'VPS restricted panel key missing'
  vps_assert_control_plane
  vps_assert_protected_live
  if [ -s "$PANEL_VPS_ACTIVE" ]; then
    . "$PANEL_VPS_ACTIVE"
    [ "$(docker inspect -f '{{.State.StartedAt}}' "$PROTECTED_CONTAINER")" = "$(cat "$BACKUP_DIR/protected-container-started.before")" ] || die 'protected relay container restarted during panel repair'
  fi
  say "PANEL_VPS_VERIFY_PASS fec=$expected"
}

panel_vps_commit() {
  txn="$1"
  [ -s "$PANEL_VPS_ACTIVE" ] || die 'no pending VPS panel transaction'
  . "$PANEL_VPS_ACTIVE"
  [ "$TXN" = "$txn" ] || die 'VPS panel commit mismatch'
  panel_vps_cancel_rollback "$BACKUP_DIR"
  rm -f "$PANEL_VPS_ACTIVE"
  say "PANEL_VPS_COMMIT_PASS transaction=$txn"
}

panel_vps_rollback() {
  requested="${1:-}"
  [ -s "$PANEL_VPS_ACTIVE" ] || { say 'PANEL_VPS_ROLLBACK_NO_PENDING'; return 0; }
  . "$PANEL_VPS_ACTIVE"
  [ -z "$requested" ] || [ "$TXN" = "$requested" ] || die 'VPS panel rollback mismatch'
  /bin/sh "$BACKUP_DIR/rollback.sh"
  panel_vps_cancel_rollback "$BACKUP_DIR"
  [ ! -s "$PANEL_VPS_ACTIVE" ] || die 'VPS panel rollback did not clear transaction'
  vps_assert_control_plane
  vps_assert_protected_live
  say "PANEL_VPS_ROLLBACK_PASS transaction=$TXN"
}

panel_ow_write_rollback() {
  dir="$1"
  cat >"$dir/rollback.sh" <<EOF
#!/bin/sh
set -u
dir='$dir'
active='$PANEL_OW_ACTIVE'
[ -e "\$dir/rollback.pending" ] || exit 0
mv "\$dir/rollback.pending" "\$dir/rollback.claimed" 2>/dev/null || exit 0
/etc/init.d/game-v2-zj717 stop >/dev/null 2>&1 || true
rm -rf '$OW_INSTALL' '$OW_STATE' '$PANEL_OW_INSTALL' '$PANEL_OW_KEY_DIR' '$PANEL_OW_PROFILE' '$PANEL_CONTROL_STATE'
rm -f '$PANEL_OW_ROOT/stop.sh' '$PANEL_OW_ROOT/verify-stop.sh' '$PANEL_OW_ROOT/active.env'
rm -f '$PANEL_CONTROL_SCRIPT'
tar -xzf "\$dir/backup.tar.gz" -C / || exit 1
/etc/init.d/game-v2-zj717 restart >/dev/null 2>&1 || exit 1
sleep 3
ubus call service list '{"name":"game-v2-zj717"}' 2>/dev/null | grep -q '"running": true' || exit 1
rm -f "\$active" "\$dir/rollback.claimed"
exit 0
EOF
  chmod 700 "$dir/rollback.sh"
  cat >"$dir/timer.sh" <<EOF
#!/bin/sh
sleep $ROLLBACK_SECONDS
exec /bin/sh '$dir/rollback.sh'
EOF
  chmod 700 "$dir/timer.sh"
}

panel_ow_arm_rollback() {
  dir="$1"
  : >"$dir/rollback.pending"
  setsid "$dir/timer.sh" >"$dir/timer.log" 2>&1 </dev/null &
  printf '%s\n' "$!" >"$dir/timer.pid"
  kill -0 "$(cat "$dir/timer.pid")" 2>/dev/null
}

panel_ow_cancel_rollback() {
  dir="$1"
  pid="$(cat "$dir/timer.pid" 2>/dev/null || true)"
  case "$pid" in ''|*[!0-9]*) ;; *)
    if [ -r "/proc/$pid/cmdline" ] && tr '\000' ' ' <"/proc/$pid/cmdline" | grep -F "$dir/timer.sh" >/dev/null; then
      kill "$pid" >/dev/null 2>&1 || true
    fi
    ;;
  esac
  rm -f "$dir/timer.pid" "$dir/rollback.pending"
}

panel_ow_prepare() {
  txn="$1"
  [ -n "$txn" ] || die 'missing OpenWrt panel transaction'
  ow_assert_platform
  ow_service_running game-v2-zj717 || die 'zj717 OpenWrt service is not running'
  [ -x "$OW_INSTALL/run-profile.sh" ] || die 'zj717 OpenWrt runner missing'
  [ -s "$OW_STATE/profile.env" ] || die 'zj717 OpenWrt profile missing'
  [ -s /www/wgpanel.html ] || die 'existing zj717 panel page missing'
  [ -x "$PANEL_CONTROL_SCRIPT" ] || die 'existing zj717 panel controller missing'
  [ ! -s "$PANEL_OW_ACTIVE" ] || die 'another OpenWrt panel repair is pending'
  [ ! -s /var/lib/wg-game-v2/panel/active-transaction ] || die 'web panel has a pending user transaction'
  [ -d "$PANEL_OW_PROFILE" ] || die 'zj717 web panel profile missing'
  dir="$PANEL_OW_BACKUP_ROOT/$txn"
  [ ! -e "$dir" ] || die 'OpenWrt panel transaction already exists'
  mkdir -p "$dir" "$PANEL_OW_STATE"
  chmod 700 "$dir" "$PANEL_OW_STATE"
  set -- "${OW_INSTALL#/}" "${OW_STATE#/}" "${PANEL_OW_PROFILE#/}" \
    "${PANEL_OW_ROOT#/}/stop.sh" "${PANEL_OW_ROOT#/}/verify-stop.sh" "${PANEL_OW_ROOT#/}/active.env" \
    'www/wgpanel.html' "${PANEL_CONTROL_SCRIPT#/}"
  [ ! -d "$PANEL_OW_KEY_DIR" ] || set -- "$@" "${PANEL_OW_KEY_DIR#/}"
  [ ! -d "$PANEL_OW_INSTALL" ] || set -- "$@" "${PANEL_OW_INSTALL#/}"
  [ ! -d "$PANEL_CONTROL_STATE" ] || set -- "$@" "${PANEL_CONTROL_STATE#/}"
  tar -C / -czf "$dir/backup.tar.gz" "$@"
  panel_ow_write_rollback "$dir"
  cat >"$PANEL_OW_ACTIVE" <<EOF
TXN='$txn'
BACKUP_DIR='$dir'
EOF
  chmod 600 "$PANEL_OW_ACTIVE"
  if ! panel_ow_arm_rollback "$dir"; then
    /bin/sh "$dir/rollback.sh" || true
    die 'failed to arm OpenWrt panel rollback'
  fi
  say "PANEL_OPENWRT_PREPARE_PASS transaction=$txn rollback=armed-${ROLLBACK_SECONDS}s"
}

panel_ow_write_runner() {
  cat >"$OW_INSTALL/run-profile.sh" <<'EOF'
#!/bin/sh
set -eu
. /etc/game-v2/zj717/profile.env
case "${1:-}" in
  start)
    ifup gv2_zj717
    ready=0
    while [ "$ready" -lt 20 ]; do
      ip -4 addr show dev gv2_zj717 2>/dev/null | grep -F '10.77.3.2/30' >/dev/null && break
      ready=$((ready + 1)); sleep 1
    done
    [ "$ready" -lt 20 ]
    main_route="$(ip -4 route get "$SERVER_ENDPOINT" | sed -n '1p')"
    main_gw="$(printf '%s\n' "$main_route" | awk '{for (i=1;i<=NF;i++) if ($i=="via") print $(i+1)}')"
    main_dev="$(printf '%s\n' "$main_route" | awk '{for (i=1;i<=NF;i++) if ($i=="dev") print $(i+1)}')"
    [ -n "$main_dev" ]
    if [ -n "$main_gw" ]; then ip route replace "$SERVER_ENDPOINT/32" via "$main_gw" dev "$main_dev" table 51873
    else ip route replace "$SERVER_ENDPOINT/32" dev "$main_dev" table 51873; fi
    ip route replace 10.77.3.1/32 dev gv2_zj717 table 51873
    ip route replace default dev gv2_zj717 table 51873
    while ip rule del priority 10000 2>/dev/null; do :; done
    while ip rule del priority 9999 2>/dev/null; do :; done
    ip rule add priority 9999 from 192.168.7.0/24 to 192.168.7.0/24 lookup main
    ip rule add priority 10000 from 192.168.7.0/24 lookup 51873
    preset="$(sed -n 's/^preset=//p' /etc/game-v2/zj717/fec.state | sed -n '1p')"
    case "$preset" in
      auto) set -- '-f1:3,2:4,8:6,20:10' '--timeout' '8' ;;
      original) set -- ;;
      light) set -- '-f2:2' '--timeout' '1' ;;
      balanced) set -- '-f2:4' '--timeout' '1' ;;
      strong) set -- '-f2:6' '--timeout' '1' ;;
      extreme) set -- '-f2:4' '--timeout' '0' ;;
      *) exit 2 ;;
    esac
    exec /usr/local/lib/game-v2-zj717/speederv2 -c -l127.0.0.1:30973 -r127.0.0.1:31973 --mode 0 -k "$SPEEDERV2_KEY" "$@"
    ;;
  stop)
    while ip rule del priority 10000 2>/dev/null; do :; done
    while ip rule del priority 9999 2>/dev/null; do :; done
    ip route flush table 51873 2>/dev/null || true
    ifdown gv2_zj717 >/dev/null 2>&1 || true
    ;;
  *) exit 2 ;;
esac
EOF
  chmod 700 "$OW_INSTALL/run-profile.sh"
}

panel_ow_write_endpoint() {
  mkdir -p "$PANEL_OW_INSTALL"
  cat >"$PANEL_OW_INSTALL/fec-endpoint.sh" <<'EOF'
#!/bin/sh
set -eu
state=/etc/game-v2/zj717/fec.state
validate() { case "$1" in auto|original|light|balanced|strong|extreme) return 0 ;; *) return 1 ;; esac; }
read_preset() {
  value="$(sed -n 's/^preset=//p' "$state" 2>/dev/null | sed -n '1p')"
  validate "$value" || return 1
  printf '%s\n' "$value"
}
running() { ubus call service list '{"name":"game-v2-zj717"}' 2>/dev/null | grep -q '"running": true'; }
verify() {
  expected="$1"
  validate "$expected" || return 1
  [ "$(read_preset)" = "$expected" ] || return 1
  running || return 1
  pid="$(pgrep -f '^/usr/local/lib/game-v2-zj717/speederv2 ' | sed -n '1p')"
  case "$pid" in ''|*[!0-9]*) return 1 ;; esac
  [ -r "/proc/$pid/cmdline" ] || return 1
  args="$(tr '\000' ' ' <"/proc/$pid/cmdline")"
  case "$expected" in
    auto) printf '%s\n' "$args" | grep -F -- '-f1:3,2:4,8:6,20:10' >/dev/null && printf '%s\n' "$args" | grep -F -- '--timeout 8' >/dev/null ;;
    original) ! printf '%s\n' "$args" | grep -Eq '(^|[[:space:]])-f[^[:space:]]*' ;;
    light) printf '%s\n' "$args" | grep -F -- '-f2:2' >/dev/null && printf '%s\n' "$args" | grep -F -- '--timeout 1' >/dev/null ;;
    balanced) printf '%s\n' "$args" | grep -F -- '-f2:4' >/dev/null && printf '%s\n' "$args" | grep -F -- '--timeout 1' >/dev/null ;;
    strong) printf '%s\n' "$args" | grep -F -- '-f2:6' >/dev/null && printf '%s\n' "$args" | grep -F -- '--timeout 1' >/dev/null ;;
    extreme) printf '%s\n' "$args" | grep -F -- '-f2:4' >/dev/null && printf '%s\n' "$args" | grep -F -- '--timeout 0' >/dev/null ;;
  esac
  now="$(date +%s)"
  hs="$(wg show gv2_zj717 latest-handshakes | awk 'NR==1 {print $2}')"
  [ "${hs:-0}" -gt 0 ] && [ $((now - hs)) -le 180 ]
}
apply() {
  target="$1"
  validate "$target" || return 2
  old="$(read_preset)"
  tmp="$state.$$"
  umask 077
  printf '# game-v2 zj717 FEC state\npreset=%s\n' "$target" >"$tmp"
  mv "$tmp" "$state"
  if /etc/init.d/game-v2-zj717 restart >/dev/null 2>&1; then
    count=0
    while [ "$count" -lt 30 ]; do verify "$target" && return 0; count=$((count + 1)); sleep 1; done
  fi
  printf '# game-v2 zj717 FEC state\npreset=%s\n' "$old" >"$tmp"
  mv "$tmp" "$state"
  /etc/init.d/game-v2-zj717 restart >/dev/null 2>&1 || true
  return 1
}
case "${1:-}" in
  status) [ "$#" -eq 1 ]; printf 'FEC_PRESET=%s\n' "$(read_preset)" ;;
  apply) [ "$#" -eq 2 ]; apply "$2" ;;
  verify) [ "$#" -eq 2 ]; verify "$2" ;;
  *) exit 2 ;;
esac
EOF
  chmod 755 "$PANEL_OW_INSTALL/fec-endpoint.sh"
}

panel_ow_write_coordinator() {
  target="${1:-$PANEL_OW_INSTALL/fec-coordinator.sh}"
  cat >"$target" <<'EOF'
#!/bin/sh
set -eu
local_ep=/usr/local/lib/game-v2-zj717-panel/fec-endpoint.sh
key=/etc/wg-game-v2/panel/ssh/nl-zhaojie-v2/id_ed25519
known=/etc/wg-game-v2/panel/ssh/nl-zhaojie-v2/known_hosts
remote() { ssh -i "$key" -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=5 -o ServerAliveCountMax=2 -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$known" root@91.223.119.134 "$@"; }
validate_node() { [ "${1:-}" = '--node-id' ] && [ "${2:-}" = 'nl-zhaojie-v2' ]; }
validate_preset() { case "$1" in auto|original|light|balanced|strong|extreme) return 0 ;; *) return 1 ;; esac; }
read_local() { "$local_ep" status | sed -n 's/^FEC_PRESET=//p'; }
read_remote() { remote status | sed -n 's/^FEC_PRESET=//p'; }
pair_verify() { validate_preset "$1" && "$local_ep" verify "$1" && remote verify "$1"; }
pair_apply() {
  target="$1"
  validate_preset "$target" || return 2
  old_local="$(read_local)"; old_remote="$(read_remote)"
  validate_preset "$old_local" && validate_preset "$old_remote" || return 1
  remote apply "$target" || return 1
  if "$local_ep" apply "$target" && pair_verify "$target"; then return 0; fi
  "$local_ep" apply "$old_local" >/dev/null 2>&1 || true
  remote apply "$old_remote" >/dev/null 2>&1 || true
  return 1
}
acquire_lock() {
  tries=0
  while ! mkdir /var/run/game-v2-zj717-panel.lock 2>/dev/null; do
    tries=$((tries + 1)); [ "$tries" -lt 30 ] || return 1; sleep 1
  done
  trap 'rmdir /var/run/game-v2-zj717-panel.lock 2>/dev/null || true' EXIT HUP INT TERM
}
cmd="${1:-}"; shift || true
case "$cmd" in
  apply)
    validate_node "${1:-}" "${2:-}" || exit 2
    [ "${3:-}" = '--preset' ] || exit 2
    [ "$#" -eq 4 ] || exit 2
    acquire_lock; pair_apply "$4"
    ;;
  verify)
    validate_node "${1:-}" "${2:-}" || exit 2
    [ "${3:-}" = '--preset' ] || exit 2
    [ "$#" -eq 4 ] || exit 2
    pair_verify "$4"
    ;;
  verify-transport)
    validate_node "${1:-}" "${2:-}" || exit 2
    [ "$#" -eq 2 ] || exit 2
    current="$(read_local)"; [ "$current" = "$(read_remote)" ] && pair_verify "$current"
    ;;
  status)
    validate_node "${1:-}" "${2:-}" || exit 2
    [ "$#" -eq 2 ] || exit 2
    current="$(read_local)"; remote_current="$(read_remote)"
    validate_preset "$current" && validate_preset "$remote_current"
    [ "$current" = "$remote_current" ]
    "$local_ep" verify "$current"
    printf '%s\n' 'WG_TRANSPORT_STATE=running' "WG_FEC_EFFECTIVE=$current" 'WG_FEC_RECOMMENDED=light' \
      'WG_RECOMMENDED_MODE=faketcp' 'WG_PROBE_FAKETCP=reachable' 'WG_PROBE_DIRECT_UDP=unavailable' 'WG_LATENCY_MS='
    ;;
  stop)
    validate_node "${1:-}" "${2:-}" || exit 2
    [ "$#" -eq 2 ] || exit 2
    /etc/init.d/game-v2-zj717 stop >/dev/null 2>&1
    ;;
  verify-stop)
    validate_node "${1:-}" "${2:-}" || exit 2
    [ "$#" -eq 2 ] || exit 2
    ! ubus call service list '{"name":"game-v2-zj717"}' 2>/dev/null | grep -q '"running": true'
    ;;
  *) exit 2 ;;
esac
EOF
  chmod 755 "$target"
}

panel_ow_write_hooks() {
  mkdir -p "$PANEL_OW_PROFILE"
  cat >"$PANEL_OW_PROFILE/apply.sh" <<'EOF'
#!/bin/sh
exec /usr/local/lib/game-v2-zj717-panel/fec-coordinator.sh apply --node-id nl-zhaojie-v2 --preset original
EOF
  cat >"$PANEL_OW_PROFILE/verify.sh" <<'EOF'
#!/bin/sh
exec /usr/local/lib/game-v2-zj717-panel/fec-coordinator.sh verify-transport --node-id nl-zhaojie-v2
EOF
  panel_write_status_hook "$PANEL_OW_PROFILE/status.sh"
  printf '%s\n' light >"$PANEL_OW_PROFILE/baseline-fec"
  printf '%s\n' ready >"$PANEL_OW_PROFILE/ready"
  for preset in auto original light balanced strong extreme; do
    fec_dir="$PANEL_OW_PROFILE/fec/$preset"
    mkdir -p "$fec_dir"
    cat >"$fec_dir/apply.sh" <<EOF
#!/bin/sh
exec /usr/local/lib/game-v2-zj717-panel/fec-coordinator.sh apply --node-id nl-zhaojie-v2 --preset $preset
EOF
    cat >"$fec_dir/verify.sh" <<EOF
#!/bin/sh
exec /usr/local/lib/game-v2-zj717-panel/fec-coordinator.sh verify --node-id nl-zhaojie-v2 --preset $preset
EOF
    printf '%s\n' ready >"$fec_dir/ready"
    chmod 755 "$fec_dir/apply.sh" "$fec_dir/verify.sh"
  done
  cat >"$PANEL_OW_ROOT/stop.sh" <<'EOF'
#!/bin/sh
exec /usr/local/lib/game-v2-zj717-panel/fec-coordinator.sh stop --node-id nl-zhaojie-v2
EOF
  cat >"$PANEL_OW_ROOT/verify-stop.sh" <<'EOF'
#!/bin/sh
exec /usr/local/lib/game-v2-zj717-panel/fec-coordinator.sh verify-stop --node-id nl-zhaojie-v2
EOF
  chmod 755 "$PANEL_OW_PROFILE/apply.sh" "$PANEL_OW_PROFILE/verify.sh" "$PANEL_OW_PROFILE/status.sh" \
    "$PANEL_OW_ROOT/stop.sh" "$PANEL_OW_ROOT/verify-stop.sh"
}

panel_ow_apply() {
  txn="$1"
  [ -s "$PANEL_OW_ACTIVE" ] || die 'no prepared OpenWrt panel transaction'
  . "$PANEL_OW_ACTIVE"
  [ "$TXN" = "$txn" ] || die 'OpenWrt panel transaction mismatch'
  staged="/tmp/game-v2-zj717-panel-$txn"
  [ -s "$staged.key" ] && [ -s "$staged.pub" ] && [ -s "$staged.known_hosts" ] && \
    [ -s "$staged.panel-control.sh" ] && [ -s "$staged.wgpanel.html" ] || die 'staged panel files missing'
  mkdir -p "$PANEL_OW_KEY_DIR"
  chmod 700 "$PANEL_OW_KEY_DIR"
  cp "$staged.key" "$PANEL_OW_KEY_DIR/id_ed25519"
  cp "$staged.pub" "$PANEL_OW_KEY_DIR/id_ed25519.pub"
  cp "$staged.known_hosts" "$PANEL_OW_KEY_DIR/known_hosts"
  chmod 600 "$PANEL_OW_KEY_DIR/id_ed25519" "$PANEL_OW_KEY_DIR/known_hosts"
  chmod 644 "$PANEL_OW_KEY_DIR/id_ed25519.pub"
  cp "$staged.wgpanel.html" /www/wgpanel.html.new
  chmod 644 /www/wgpanel.html.new
  mv /www/wgpanel.html.new /www/wgpanel.html
  cp "$staged.panel-control.sh" "$PANEL_CONTROL_SCRIPT.new"
  chmod 755 "$PANEL_CONTROL_SCRIPT.new"
  mv "$PANEL_CONTROL_SCRIPT.new" "$PANEL_CONTROL_SCRIPT"
  rm -f "$staged.key" "$staged.pub" "$staged.known_hosts" "$staged.panel-control.sh" "$staged.wgpanel.html"
  [ -f "$PANEL_OW_FEC_STATE" ] || { umask 077; printf '# game-v2 zj717 FEC state\npreset=original\n' >"$PANEL_OW_FEC_STATE"; }
  panel_ow_write_runner
  panel_ow_write_endpoint
  panel_ow_write_coordinator
  panel_ow_write_hooks
  "$PANEL_OW_INSTALL/fec-coordinator.sh" verify-transport --node-id nl-zhaojie-v2
  say "PANEL_OPENWRT_APPLY_PASS transaction=$txn"
}

panel_ow_activate() {
  preset="$1"
  panel_validate_preset "$preset" || die 'invalid OpenWrt active panel preset'
  tmp="$PANEL_OW_ROOT/active.env.$$"
  cat >"$tmp" <<EOF
WG_ENABLED=1
WG_NODE=nl-zhaojie-v2
WG_MODE=faketcp
WG_FEC_MODE=$preset
WG_FEC_EFFECTIVE=$preset
EOF
  chmod 600 "$tmp"
  mv "$tmp" "$PANEL_OW_ROOT/active.env"
  say "PANEL_OPENWRT_ACTIVE_PASS fec=$preset"
}

panel_ow_verify() {
  expected="$1"
  panel_validate_preset "$expected" || die 'invalid OpenWrt panel verification preset'
  [ -x "$PANEL_OW_INSTALL/fec-coordinator.sh" ] || die 'OpenWrt panel coordinator missing'
  "$PANEL_OW_INSTALL/fec-coordinator.sh" verify --node-id nl-zhaojie-v2 --preset "$expected" || die 'paired FEC verification failed'
  for preset in auto original light balanced strong extreme; do
    [ "$(sed -n '1p' "$PANEL_OW_PROFILE/fec/$preset/ready")" = ready ] || die "panel FEC profile not ready: $preset"
    [ -x "$PANEL_OW_PROFILE/fec/$preset/apply.sh" ] && [ -x "$PANEL_OW_PROFILE/fec/$preset/verify.sh" ] || die "panel FEC hooks missing: $preset"
  done
  grep -Fqx 'WG_NODE=nl-zhaojie-v2' "$PANEL_OW_ROOT/active.env" || die 'panel active node mismatch'
  grep -Fqx "WG_FEC_EFFECTIVE=$expected" "$PANEL_OW_ROOT/active.env" || die 'panel active FEC mismatch'
  [ -s /www/wgpanel.html ] || die 'OpenWrt panel page missing'
  grep -Fq 'const ACTION_TIMEOUT_MS = 120000;' /www/wgpanel.html || die 'panel action timeout fix missing'
  grep -Fq 'const STATUS_RETRY_COUNT = 3;' /www/wgpanel.html || die 'panel status retry fix missing'
  grep -Fq 'let actionInFlight = false;' /www/wgpanel.html || die 'panel action busy guard missing'
  grep -Fq 'includes("HTTP 409")' /www/wgpanel.html || die 'panel transient 409 suppression missing'
  grep -Fq 'panel_release_lock()' "$PANEL_CONTROL_SCRIPT" || die 'panel controller lock release fix missing'
  grep -Fq '"$PANEL_LOCK_DIR/pid"' "$PANEL_CONTROL_SCRIPT" || die 'panel controller lock owner fix missing'
  say "PANEL_OPENWRT_VERIFY_PASS fec=$expected"
}

panel_ow_commit() {
  txn="$1"
  [ -s "$PANEL_OW_ACTIVE" ] || die 'no pending OpenWrt panel transaction'
  . "$PANEL_OW_ACTIVE"
  [ "$TXN" = "$txn" ] || die 'OpenWrt panel commit mismatch'
  panel_ow_cancel_rollback "$BACKUP_DIR"
  rm -f "$PANEL_OW_ACTIVE"
  say "PANEL_OPENWRT_COMMIT_PASS transaction=$txn"
}

panel_ow_rollback() {
  requested="${1:-}"
  [ -s "$PANEL_OW_ACTIVE" ] || { say 'PANEL_OPENWRT_ROLLBACK_NO_PENDING'; return 0; }
  . "$PANEL_OW_ACTIVE"
  [ -z "$requested" ] || [ "$TXN" = "$requested" ] || die 'OpenWrt panel rollback mismatch'
  /bin/sh "$BACKUP_DIR/rollback.sh"
  panel_ow_cancel_rollback "$BACKUP_DIR"
  [ ! -s "$PANEL_OW_ACTIVE" ] || die 'OpenWrt panel rollback did not clear transaction'
  ow_verify
  say "PANEL_OPENWRT_ROLLBACK_PASS transaction=$TXN"
}

# ---------- zj717 panel status-only repair ----------

panel_status_write_rollback() {
  dir="$1"
  txn="$2"
  cat >"$dir/rollback.sh" <<EOF
#!/bin/sh
set -u
dir='$dir'
active='$PANEL_STATUS_ACTIVE'
page='/www/wgpanel.html'
hook='$PANEL_OW_PROFILE/status.sh'
[ -e "\$dir/rollback.pending" ] || exit 0
mv "\$dir/rollback.pending" "\$dir/rollback.claimed" 2>/dev/null || exit 0
cp "\$dir/wgpanel.html" "\$page.rollback"
chmod 644 "\$page.rollback"
mv "\$page.rollback" "\$page"
cp "\$dir/status.sh" "\$hook.rollback"
chmod 755 "\$hook.rollback"
mv "\$hook.rollback" "\$hook"
rm -f '$PANEL_STATUS_ACTIVE' '/tmp/game-v2-zj717-panel-status-$txn.wgpanel.html' \
  '/tmp/game-v2-zj717-panel-status-$txn.status.sh' "\$dir/rollback.claimed"
EOF
  chmod 700 "$dir/rollback.sh"
  cat >"$dir/timer.sh" <<EOF
#!/bin/sh
sleep $PANEL_STATUS_ROLLBACK_SECONDS
exec /bin/sh '$dir/rollback.sh'
EOF
  chmod 700 "$dir/timer.sh"
}

panel_status_arm_rollback() {
  dir="$1"
  : >"$dir/rollback.pending"
  setsid "$dir/timer.sh" >"$dir/timer.log" 2>&1 </dev/null &
  printf '%s\n' "$!" >"$dir/timer.pid"
  kill -0 "$(cat "$dir/timer.pid")" 2>/dev/null
}

panel_status_cancel_rollback() {
  dir="$1"
  pid="$(cat "$dir/timer.pid" 2>/dev/null || true)"
  case "$pid" in ''|*[!0-9]*) ;; *)
    if [ -r "/proc/$pid/cmdline" ] && tr '\000' ' ' <"/proc/$pid/cmdline" | grep -F "$dir/timer.sh" >/dev/null; then
      kill "$pid" >/dev/null 2>&1 || true
    fi
    ;;
  esac
  rm -f "$dir/timer.pid" "$dir/rollback.pending"
}

panel_status_prepare() {
  txn="$1"
  [ -n "$txn" ] || die 'missing zj717 panel status transaction'
  ow_assert_platform
  ow_service_running game-v2-zj717 || die 'zj717 OpenWrt service is not running'
  [ -s /www/wgpanel.html ] || die 'current zj717 panel page missing'
  [ -x "$PANEL_OW_PROFILE/status.sh" ] || die 'current zj717 status hook missing'
  [ -x "$PANEL_OW_INSTALL/fec-coordinator.sh" ] || die 'zj717 coordinator missing'
  [ ! -s "$PANEL_STATUS_ACTIVE" ] || die 'another zj717 panel status repair is pending'
  [ ! -s "$PANEL_OW_ACTIVE" ] || die 'a full zj717 panel repair is pending'
  [ ! -s "$PANEL_CONTROL_STATE/active-transaction" ] || die 'the panel has a pending user transaction'
  expected_fec="$(panel_read_preset "$PANEL_OW_FEC_STATE")" || die 'cannot read active zj717 FEC preset'
  dir="$PANEL_STATUS_BACKUP_ROOT/$txn"
  [ ! -e "$dir" ] || die 'zj717 panel status transaction already exists'
  mkdir -p "$dir" "$PANEL_STATUS_STATE"
  chmod 700 "$dir" "$PANEL_STATUS_STATE"
  cp /www/wgpanel.html "$dir/wgpanel.html"
  cp "$PANEL_OW_PROFILE/status.sh" "$dir/status.sh"
  printf '%s\n' "$expected_fec" >"$dir/expected-fec"
  chmod 600 "$dir/expected-fec"
  panel_status_write_rollback "$dir" "$txn"
  cat >"$PANEL_STATUS_ACTIVE" <<EOF
TXN='$txn'
BACKUP_DIR='$dir'
EXPECTED_FEC='$expected_fec'
EOF
  chmod 600 "$PANEL_STATUS_ACTIVE"
  if ! panel_status_arm_rollback "$dir"; then
    /bin/sh "$dir/rollback.sh" || true
    die 'failed to arm zj717 panel status rollback'
  fi
  say "PANEL_STATUS_PREPARE_PASS transaction=$txn fec=$expected_fec rollback=armed-${PANEL_STATUS_ROLLBACK_SECONDS}s"
}

panel_status_apply() {
  txn="$1"
  [ -s "$PANEL_STATUS_ACTIVE" ] || die 'no prepared zj717 panel status transaction'
  . "$PANEL_STATUS_ACTIVE"
  [ "$TXN" = "$txn" ] || die 'zj717 panel status transaction mismatch'
  [ "$(panel_read_preset "$PANEL_OW_FEC_STATE")" = "$EXPECTED_FEC" ] || die 'active FEC changed before panel status apply'
  staged="/tmp/game-v2-zj717-panel-status-$txn"
  [ -s "$staged.wgpanel.html" ] && [ -s "$staged.status.sh" ] || die 'staged panel status files missing'
  sh -n "$staged.status.sh" || die 'staged status hook syntax is invalid'
  grep -Fq 'const networkReachable = status.WG_NETWORK_STATE === "reachable" || latency != null;' \
    "$staged.wgpanel.html" || die 'staged page verdict repair missing'
  cp "$staged.wgpanel.html" /www/wgpanel.html.new
  chmod 644 /www/wgpanel.html.new
  mv /www/wgpanel.html.new /www/wgpanel.html
  cp "$staged.status.sh" "$PANEL_OW_PROFILE/status.sh.new"
  chmod 755 "$PANEL_OW_PROFILE/status.sh.new"
  mv "$PANEL_OW_PROFILE/status.sh.new" "$PANEL_OW_PROFILE/status.sh"
  rm -f "$staged.wgpanel.html" "$staged.status.sh"
  say "PANEL_STATUS_APPLY_PASS transaction=$txn fec=$EXPECTED_FEC"
}

panel_status_verify() {
  expected="$1"
  panel_validate_preset "$expected" || die 'invalid expected zj717 FEC preset'
  [ "$(panel_read_preset "$PANEL_OW_FEC_STATE")" = "$expected" ] || die 'active FEC preset changed'
  grep -Fqx "WG_FEC_EFFECTIVE=$expected" "$PANEL_OW_ROOT/active.env" || die 'panel active FEC changed'
  ow_service_running game-v2-zj717 || die 'zj717 service stopped'
  grep -Fq 'const networkReachable = status.WG_NETWORK_STATE === "reachable" || latency != null;' \
    /www/wgpanel.html || die 'page network verdict repair missing'
  grep -Fq '通道运行中，公网延迟暂未取得' /www/wgpanel.html || die 'page transient probe warning missing'
  grep -Fq 'ping -I "$tunnel_if"' "$PANEL_OW_PROFILE/status.sh" || die 'tunnel-bound public probe missing'
  attempt=0
  status_output=''
  while [ "$attempt" -lt 3 ]; do
    attempt=$((attempt + 1))
    status_output="$("$PANEL_OW_PROFILE/status.sh")" || status_output=''
    printf '%s\n' "$status_output" | grep -Fqx 'WG_TRANSPORT_STATE=running' && \
      printf '%s\n' "$status_output" | grep -Fqx 'WG_NETWORK_STATE=reachable' && \
      printf '%s\n' "$status_output" | grep -Eq '^WG_LATENCY_MS=[0-9]+([.][0-9]+)?$' && break
    status_output=''
    sleep 1
  done
  [ -n "$status_output" ] || die 'the zj717 tunnel public probe did not return a latency sample'
  printf '%s\n' "$status_output" | grep -Fqx "WG_FEC_EFFECTIVE=$expected" || die 'status hook returned the wrong FEC preset'
  api_output="$(wget -qO- 'http://127.0.0.1/cgi-bin/wg_api.sh?action=status')" || die 'local panel status API failed'
  printf '%s\n' "$api_output" | grep -Fqx 'WG_NETWORK_STATE=reachable' || die 'panel API omitted reachable network state'
  printf '%s\n' "$api_output" | grep -Eq '^WG_LATENCY_MS=[0-9]+([.][0-9]+)?$' || die 'panel API omitted tunnel latency'
  wget -qO- 'http://127.0.0.1/wgpanel.html' | \
    grep -Fq 'const networkReachable = status.WG_NETWORK_STATE === "reachable" || latency != null;' || \
    die 'served panel page is not the repaired version'
  [ ! -s "$PANEL_CONTROL_STATE/active-transaction" ] || die 'panel user transaction changed during status repair'
  say "PANEL_STATUS_VERIFY_PASS fec=$expected network=reachable rollback=armed"
}

panel_status_commit() {
  txn="$1"
  [ -s "$PANEL_STATUS_ACTIVE" ] || die 'no pending zj717 panel status transaction'
  . "$PANEL_STATUS_ACTIVE"
  [ "$TXN" = "$txn" ] || die 'zj717 panel status commit mismatch'
  panel_status_cancel_rollback "$BACKUP_DIR"
  rm -f "$PANEL_STATUS_ACTIVE"
  say "PANEL_STATUS_COMMIT_PASS transaction=$txn backup=$BACKUP_DIR"
}

panel_status_rollback() {
  requested="${1:-}"
  [ -s "$PANEL_STATUS_ACTIVE" ] || { say 'PANEL_STATUS_ROLLBACK_NO_PENDING'; return 0; }
  . "$PANEL_STATUS_ACTIVE"
  [ -z "$requested" ] || [ "$TXN" = "$requested" ] || die 'zj717 panel status rollback mismatch'
  /bin/sh "$BACKUP_DIR/rollback.sh"
  panel_status_cancel_rollback "$BACKUP_DIR"
  [ ! -s "$PANEL_STATUS_ACTIVE" ] || die 'zj717 panel status rollback did not clear transaction'
  cmp -s /www/wgpanel.html "$BACKUP_DIR/wgpanel.html" || die 'zj717 panel page rollback mismatch'
  cmp -s "$PANEL_OW_PROFILE/status.sh" "$BACKUP_DIR/status.sh" || die 'zj717 status hook rollback mismatch'
  ow_service_running game-v2-zj717 || die 'zj717 service stopped after panel status rollback'
  say "PANEL_STATUS_ROLLBACK_PASS transaction=$TXN"
}

# ---------- zj717 routine status latency repair ----------

panel_latency_write_rollback() {
  dir="$1"
  txn="$2"
  cat >"$dir/rollback.sh" <<EOF
#!/bin/sh
set -u
dir='$dir'
active='$PANEL_LATENCY_ACTIVE'
coordinator='$PANEL_OW_INSTALL/fec-coordinator.sh'
[ -e "\$dir/rollback.pending" ] || exit 0
mv "\$dir/rollback.pending" "\$dir/rollback.claimed" 2>/dev/null || exit 0
cp "\$dir/fec-coordinator.sh" "\$coordinator.rollback"
chmod 755 "\$coordinator.rollback"
mv "\$coordinator.rollback" "\$coordinator"
rm -f "\$active" '/tmp/game-v2-zj717-panel-status-latency-$txn.coordinator.sh' \
  "\$dir/rollback.claimed"
EOF
  chmod 700 "$dir/rollback.sh"
  cat >"$dir/timer.sh" <<EOF
#!/bin/sh
sleep $PANEL_LATENCY_ROLLBACK_SECONDS
exec /bin/sh '$dir/rollback.sh'
EOF
  chmod 700 "$dir/timer.sh"
}

panel_latency_arm_rollback() {
  dir="$1"
  : >"$dir/rollback.pending"
  setsid "$dir/timer.sh" >"$dir/timer.log" 2>&1 </dev/null &
  printf '%s\n' "$!" >"$dir/timer.pid"
  kill -0 "$(cat "$dir/timer.pid")" 2>/dev/null
}

panel_latency_cancel_rollback() {
  dir="$1"
  pid="$(cat "$dir/timer.pid" 2>/dev/null || true)"
  case "$pid" in ''|*[!0-9]*) ;; *)
    if [ -r "/proc/$pid/cmdline" ] && tr '\000' ' ' <"/proc/$pid/cmdline" | grep -F "$dir/timer.sh" >/dev/null; then
      kill "$pid" >/dev/null 2>&1 || true
    fi
    ;;
  esac
  rm -f "$dir/timer.pid" "$dir/rollback.pending"
}

panel_latency_prepare() {
  txn="$1"
  [ -n "$txn" ] || die 'missing zj717 status latency transaction'
  ow_assert_platform
  ow_service_running game-v2-zj717 || die 'zj717 OpenWrt service is not running'
  [ -x "$PANEL_OW_INSTALL/fec-coordinator.sh" ] || die 'zj717 coordinator missing'
  [ -x "$PANEL_OW_PROFILE/status.sh" ] || die 'zj717 status hook missing'
  [ -s /www/wgpanel.html ] || die 'zj717 panel page missing'
  [ -x /www/cgi-bin/wg_api.sh ] || die 'zj717 panel API missing'
  [ -x /www/cgi-bin/wg_nodes.sh ] || die 'zj717 node API missing'
  [ ! -s "$PANEL_LATENCY_ACTIVE" ] || die 'another zj717 status latency repair is pending'
  [ ! -s "$PANEL_STATUS_ACTIVE" ] || die 'a zj717 panel status repair is pending'
  [ ! -s "$PANEL_PAGE_ACTIVE" ] || die 'a zj717 frontend reinstall is pending'
  [ ! -s "$PANEL_OW_ACTIVE" ] || die 'a full zj717 panel repair is pending'
  [ ! -s "$PANEL_CONTROL_STATE/active-transaction" ] || die 'the panel has a pending user transaction'
  expected_fec="$(panel_read_preset "$PANEL_OW_FEC_STATE")" || die 'cannot read active zj717 FEC preset'
  panel_validate_preset "$expected_fec" || die 'invalid active zj717 FEC preset'
  dir="$PANEL_LATENCY_BACKUP_ROOT/$txn"
  [ ! -e "$dir" ] || die 'zj717 status latency transaction already exists'
  mkdir -p "$dir" "$PANEL_LATENCY_STATE"
  chmod 700 "$dir" "$PANEL_LATENCY_STATE"
  cp "$PANEL_OW_INSTALL/fec-coordinator.sh" "$dir/fec-coordinator.sh"
  cp /www/wgpanel.html "$dir/wgpanel.html"
  cp "$PANEL_OW_PROFILE/status.sh" "$dir/status.sh"
  cp /www/cgi-bin/wg_api.sh "$dir/wg_api.sh"
  cp /www/cgi-bin/wg_nodes.sh "$dir/wg_nodes.sh"
  printf '%s\n' "$expected_fec" >"$dir/expected-fec"
  chmod 600 "$dir/fec-coordinator.sh" "$dir/wgpanel.html" "$dir/status.sh" \
    "$dir/wg_api.sh" "$dir/wg_nodes.sh" "$dir/expected-fec"
  panel_latency_write_rollback "$dir" "$txn"
  cat >"$PANEL_LATENCY_ACTIVE" <<EOF
TXN='$txn'
BACKUP_DIR='$dir'
EXPECTED_FEC='$expected_fec'
EOF
  chmod 600 "$PANEL_LATENCY_ACTIVE"
  if ! panel_latency_arm_rollback "$dir"; then
    /bin/sh "$dir/rollback.sh" || true
    die 'failed to arm zj717 status latency rollback'
  fi
  say "PANEL_LATENCY_PREPARE_PASS transaction=$txn fec=$expected_fec rollback=armed-${PANEL_LATENCY_ROLLBACK_SECONDS}s"
}

panel_latency_apply() {
  txn="$1"
  [ -s "$PANEL_LATENCY_ACTIVE" ] || die 'no prepared zj717 status latency transaction'
  . "$PANEL_LATENCY_ACTIVE"
  [ "$TXN" = "$txn" ] || die 'zj717 status latency transaction mismatch'
  [ "$(panel_read_preset "$PANEL_OW_FEC_STATE")" = "$EXPECTED_FEC" ] || \
    die 'active FEC changed before status latency apply'
  staged="/tmp/game-v2-zj717-panel-status-latency-$txn.coordinator.sh"
  [ -s "$staged" ] || die 'staged zj717 coordinator missing'
  sh -n "$staged" || die 'staged zj717 coordinator syntax is invalid'
  status_block="$(sed -n '/^  status)/,/^  stop)/p' "$staged")"
  printf '%s\n' "$status_block" | grep -Fq 'remote_current="$(read_remote)"' || \
    die 'staged coordinator does not read the remote preset once'
  printf '%s\n' "$status_block" | grep -Fq '"$local_ep" verify "$current"' || \
    die 'staged coordinator omits local health verification'
  if printf '%s\n' "$status_block" | grep -Fq 'pair_verify "$current"'; then
    die 'staged coordinator still duplicates remote verification in routine status'
  fi
  grep -Fq 'pair_verify "$4"' "$staged" || die 'explicit paired verification is missing'
  grep -Fq 'pair_verify "$target"' "$staged" || die 'apply paired verification is missing'
  cp "$staged" "$BACKUP_DIR/fec-coordinator.candidate.sh"
  chmod 600 "$BACKUP_DIR/fec-coordinator.candidate.sh"
  cp "$staged" "$PANEL_OW_INSTALL/fec-coordinator.sh.new"
  chmod 755 "$PANEL_OW_INSTALL/fec-coordinator.sh.new"
  mv "$PANEL_OW_INSTALL/fec-coordinator.sh.new" "$PANEL_OW_INSTALL/fec-coordinator.sh"
  rm -f "$staged"
  say "PANEL_LATENCY_APPLY_PASS transaction=$txn fec=$EXPECTED_FEC"
}

panel_latency_verify() {
  expected="$1"
  panel_validate_preset "$expected" || die 'invalid expected zj717 FEC preset'
  [ -s "$PANEL_LATENCY_ACTIVE" ] || die 'no pending zj717 status latency transaction'
  . "$PANEL_LATENCY_ACTIVE"
  [ "$EXPECTED_FEC" = "$expected" ] || die 'zj717 status latency FEC mismatch'
  [ "$(panel_read_preset "$PANEL_OW_FEC_STATE")" = "$expected" ] || die 'active FEC preset changed'
  grep -Fqx "WG_FEC_EFFECTIVE=$expected" "$PANEL_OW_ROOT/active.env" || die 'panel active FEC changed'
  ow_service_running game-v2-zj717 || die 'zj717 service stopped'
  [ ! -s "$PANEL_CONTROL_STATE/active-transaction" ] || die 'panel user transaction changed'
  cmp -s /www/wgpanel.html "$BACKUP_DIR/wgpanel.html" || die 'frontend changed during status latency repair'
  cmp -s "$PANEL_OW_PROFILE/status.sh" "$BACKUP_DIR/status.sh" || die 'status hook changed during status latency repair'
  cmp -s /www/cgi-bin/wg_api.sh "$BACKUP_DIR/wg_api.sh" || die 'panel API changed during status latency repair'
  cmp -s /www/cgi-bin/wg_nodes.sh "$BACKUP_DIR/wg_nodes.sh" || die 'node API changed during status latency repair'
  cmp -s "$PANEL_OW_INSTALL/fec-coordinator.sh" "$BACKUP_DIR/fec-coordinator.candidate.sh" || \
    die 'installed coordinator does not match the reviewed candidate'
  "$PANEL_OW_INSTALL/fec-coordinator.sh" verify --node-id nl-zhaojie-v2 --preset "$expected" || \
    die 'explicit paired FEC verification failed'

  started="$(date +%s)"
  status_output="$("$PANEL_OW_PROFILE/status.sh")" || die 'zj717 status hook failed'
  status_elapsed=$(( $(date +%s) - started ))
  [ "$status_elapsed" -lt 7 ] || die "zj717 status hook exceeded browser safety margin: ${status_elapsed}s"
  printf '%s\n' "$status_output" | grep -Fqx 'WG_TRANSPORT_STATE=running' || die 'status hook omitted running transport state'
  printf '%s\n' "$status_output" | grep -Fqx 'WG_NETWORK_STATE=reachable' || die 'status hook did not prove tunnel reachability'
  printf '%s\n' "$status_output" | grep -Fqx "WG_FEC_EFFECTIVE=$expected" || die 'status hook returned the wrong FEC preset'
  printf '%s\n' "$status_output" | grep -Eq '^WG_LATENCY_MS=[0-9]+([.][0-9]+)?$' || die 'status hook omitted tunnel latency'

  started="$(date +%s)"
  api_output="$(wget -qO- 'http://127.0.0.1/cgi-bin/wg_api.sh?action=status')" || die 'local panel status API failed'
  api_elapsed=$(( $(date +%s) - started ))
  [ "$api_elapsed" -lt 7 ] || die "zj717 panel status API exceeded browser safety margin: ${api_elapsed}s"
  printf '%s\n' "$api_output" | grep -Fqx 'WG_NETWORK_STATE=reachable' || die 'panel API omitted reachable network state'
  printf '%s\n' "$api_output" | grep -Fqx "WG_FEC_EFFECTIVE=$expected" || die 'panel API returned the wrong FEC preset'
  printf '%s\n' "$api_output" | grep -Eq '^WG_LATENCY_MS=[0-9]+([.][0-9]+)?$' || die 'panel API omitted tunnel latency'
  wget -qO- 'http://127.0.0.1/cgi-bin/wg_nodes.sh' | grep -Fq 'nl-zhaojie-v2' || die 'node API omitted the zj717 profile'
  say "PANEL_LATENCY_VERIFY_PASS fec=$expected status=${status_elapsed}s api=${api_elapsed}s rollback=armed"
}

panel_latency_commit() {
  txn="$1"
  [ -s "$PANEL_LATENCY_ACTIVE" ] || die 'no pending zj717 status latency transaction'
  . "$PANEL_LATENCY_ACTIVE"
  [ "$TXN" = "$txn" ] || die 'zj717 status latency commit mismatch'
  if ! mv "$BACKUP_DIR/rollback.pending" "$BACKUP_DIR/commit.claimed" 2>/dev/null; then
    die 'zj717 status latency rollback already started or is no longer armed'
  fi
  panel_latency_cancel_rollback "$BACKUP_DIR"
  rm -f "$PANEL_LATENCY_ACTIVE" "$BACKUP_DIR/commit.claimed"
  say "PANEL_LATENCY_COMMIT_PASS transaction=$txn backup=$BACKUP_DIR"
}

panel_latency_rollback() {
  requested="${1:-}"
  [ -s "$PANEL_LATENCY_ACTIVE" ] || { say 'PANEL_LATENCY_ROLLBACK_NO_PENDING'; return 0; }
  . "$PANEL_LATENCY_ACTIVE"
  [ -z "$requested" ] || [ "$TXN" = "$requested" ] || die 'zj717 status latency rollback mismatch'
  expected_fec="$EXPECTED_FEC"
  backup_dir="$BACKUP_DIR"
  /bin/sh "$backup_dir/rollback.sh"
  panel_latency_cancel_rollback "$backup_dir"
  [ ! -s "$PANEL_LATENCY_ACTIVE" ] || die 'zj717 status latency rollback did not clear transaction'
  cmp -s "$PANEL_OW_INSTALL/fec-coordinator.sh" "$backup_dir/fec-coordinator.sh" || \
    die 'zj717 coordinator rollback mismatch'
  [ "$(panel_read_preset "$PANEL_OW_FEC_STATE")" = "$expected_fec" ] || die 'active FEC changed during rollback'
  ow_service_running game-v2-zj717 || die 'zj717 service stopped after rollback'
  say "PANEL_LATENCY_ROLLBACK_PASS transaction=$TXN"
}

# ---------- zj717 frontend-only clean page reinstall ----------

panel_page_write_rollback() {
  dir="$1"
  txn="$2"
  cat >"$dir/rollback.sh" <<EOF
#!/bin/sh
set -u
dir='$dir'
page='/www/wgpanel.html'
[ -e "\$dir/rollback.pending" ] || exit 0
mv "\$dir/rollback.pending" "\$dir/rollback.claimed" 2>/dev/null || exit 0
cp "\$dir/wgpanel.html" "\$page.rollback"
chmod 644 "\$page.rollback"
mv "\$page.rollback" "\$page"
rm -f '$PANEL_PAGE_ACTIVE' '/tmp/game-v2-zj717-panel-page-$txn.wgpanel.html' "\$dir/rollback.claimed"
EOF
  chmod 700 "$dir/rollback.sh"
  cat >"$dir/timer.sh" <<EOF
#!/bin/sh
sleep $PANEL_PAGE_ROLLBACK_SECONDS
exec /bin/sh '$dir/rollback.sh'
EOF
  chmod 700 "$dir/timer.sh"
}

panel_page_arm_rollback() {
  dir="$1"
  : >"$dir/rollback.pending"
  setsid "$dir/timer.sh" >"$dir/timer.log" 2>&1 </dev/null &
  printf '%s\n' "$!" >"$dir/timer.pid"
  kill -0 "$(cat "$dir/timer.pid")" 2>/dev/null
}

panel_page_cancel_rollback() {
  dir="$1"
  pid="$(cat "$dir/timer.pid" 2>/dev/null || true)"
  case "$pid" in ''|*[!0-9]*) ;; *)
    if [ -r "/proc/$pid/cmdline" ] && tr '\000' ' ' <"/proc/$pid/cmdline" | grep -F "$dir/timer.sh" >/dev/null; then
      kill "$pid" >/dev/null 2>&1 || true
    fi
    ;;
  esac
  rm -f "$dir/timer.pid" "$dir/rollback.pending"
}

panel_page_prepare() {
  txn="$1"
  [ -n "$txn" ] || die 'missing zj717 frontend transaction'
  ow_assert_platform
  ow_service_running game-v2-zj717 || die 'zj717 OpenWrt service is not running'
  [ -s /www/wgpanel.html ] || die 'current zj717 panel page missing'
  [ ! -s "$PANEL_PAGE_ACTIVE" ] || die 'another zj717 frontend reinstall is pending'
  [ ! -s "$PANEL_STATUS_ACTIVE" ] || die 'a zj717 panel status repair is pending'
  [ ! -s "$PANEL_OW_ACTIVE" ] || die 'a full zj717 panel repair is pending'
  [ ! -s "$PANEL_CONTROL_STATE/active-transaction" ] || die 'the panel has a pending user transaction'
  expected_fec="$(panel_read_preset "$PANEL_OW_FEC_STATE")" || die 'cannot read active zj717 FEC preset'
  [ "$expected_fec" = extreme ] || die "active zj717 FEC is $expected_fec, expected extreme"
  dir="$PANEL_PAGE_BACKUP_ROOT/$txn"
  [ ! -e "$dir" ] || die 'zj717 frontend transaction already exists'
  mkdir -p "$dir" "$PANEL_PAGE_STATE"
  chmod 700 "$dir" "$PANEL_PAGE_STATE"
  cp /www/wgpanel.html "$dir/wgpanel.html"
  chmod 600 "$dir/wgpanel.html"
  wget -qO "$dir/nodes.before" 'http://127.0.0.1/cgi-bin/wg_nodes.sh' || die 'cannot snapshot the unchanged node API'
  printf '%s\n' "$expected_fec" >"$dir/expected-fec"
  chmod 600 "$dir/nodes.before" "$dir/expected-fec"
  panel_page_write_rollback "$dir" "$txn"
  cat >"$PANEL_PAGE_ACTIVE" <<EOF
TXN='$txn'
BACKUP_DIR='$dir'
EXPECTED_FEC='$expected_fec'
EOF
  chmod 600 "$PANEL_PAGE_ACTIVE"
  if ! panel_page_arm_rollback "$dir"; then
    /bin/sh "$dir/rollback.sh" || true
    die 'failed to arm zj717 frontend rollback'
  fi
  say "PANEL_PAGE_PREPARE_PASS transaction=$txn fec=$expected_fec rollback=armed-${PANEL_PAGE_ROLLBACK_SECONDS}s scope=/www/wgpanel.html-only"
}

panel_page_apply() {
  txn="$1"
  [ -s "$PANEL_PAGE_ACTIVE" ] || die 'no prepared zj717 frontend transaction'
  . "$PANEL_PAGE_ACTIVE"
  [ "$TXN" = "$txn" ] || die 'zj717 frontend transaction mismatch'
  [ "$(panel_read_preset "$PANEL_OW_FEC_STATE")" = "$EXPECTED_FEC" ] || die 'active FEC changed before frontend apply'
  staged="/tmp/game-v2-zj717-panel-page-$txn.wgpanel.html"
  [ -s "$staged" ] || die 'staged zj717 frontend page missing'
  grep -Fq 'const API_ENDPOINT = "/cgi-bin/wg_api.sh";' "$staged" || die 'staged page API endpoint missing'
  grep -Fq 'const NODES_ENDPOINT = "/cgi-bin/wg_nodes.sh";' "$staged" || die 'staged page node endpoint missing'
  grep -Fq 'return nodeId === "nl-zhaojie-v2" ? "荷兰"' "$staged" || die 'staged frontend 荷兰 alias missing'
  grep -Fq 'label: displayNodeLabel(parts[0], parts[1] || parts[0]),' "$staged" || die 'staged node list alias missing'
  grep -Fq 'currentNodeLabel = displayNodeLabel(currentNode, status.WG_NODE_LABEL || currentNode || "—");' "$staged" || \
    die 'staged current node alias missing'
  cp "$staged" "$BACKUP_DIR/candidate.html"
  chmod 600 "$BACKUP_DIR/candidate.html"
  cp "$staged" /www/wgpanel.html.new
  chmod 644 /www/wgpanel.html.new
  mv /www/wgpanel.html.new /www/wgpanel.html
  rm -f "$staged"
  say "PANEL_PAGE_APPLY_PASS transaction=$txn scope=/www/wgpanel.html-only"
}

panel_page_verify() {
  requested="${1:-}"
  [ -s "$PANEL_PAGE_ACTIVE" ] || die 'no pending zj717 frontend transaction'
  . "$PANEL_PAGE_ACTIVE"
  [ -z "$requested" ] || [ "$TXN" = "$requested" ] || die 'zj717 frontend verification mismatch'
  [ "$(panel_read_preset "$PANEL_OW_FEC_STATE")" = "$EXPECTED_FEC" ] || die 'active FEC preset changed'
  grep -Fqx "WG_FEC_EFFECTIVE=$EXPECTED_FEC" "$PANEL_OW_ROOT/active.env" || die 'panel active FEC changed'
  ow_service_running game-v2-zj717 || die 'zj717 service stopped'
  [ ! -s "$PANEL_CONTROL_STATE/active-transaction" ] || die 'panel user transaction changed during frontend reinstall'
  cmp -s /www/wgpanel.html "$BACKUP_DIR/candidate.html" || die 'served frontend differs from the reviewed candidate'
  grep -Fq 'return nodeId === "nl-zhaojie-v2" ? "荷兰"' /www/wgpanel.html || die 'served frontend 荷兰 alias missing'
  nodes_output="$(wget -qO- 'http://127.0.0.1/cgi-bin/wg_nodes.sh')" || die 'node API failed'
  printf '%s\n' "$nodes_output" | cmp -s - "$BACKUP_DIR/nodes.before" || die 'backend node API changed during frontend reinstall'
  printf '%s\n' "$nodes_output" | grep -Eq '^nl-zhaojie-v2\|' || die 'zj717 backend node is missing'
  attempt=0
  api_output=''
  while [ "$attempt" -lt 3 ]; do
    attempt=$((attempt + 1))
    api_output="$(wget -qO- 'http://127.0.0.1/cgi-bin/wg_api.sh?action=status')" || api_output=''
    printf '%s\n' "$api_output" | grep -Fqx 'WG_NODE=nl-zhaojie-v2' && \
      printf '%s\n' "$api_output" | grep -Fqx 'WG_TRANSPORT_STATE=running' && \
      printf '%s\n' "$api_output" | grep -Fqx 'WG_NETWORK_STATE=reachable' && \
      printf '%s\n' "$api_output" | grep -Eq '^WG_LATENCY_MS=[0-9]+([.][0-9]+)?$' && break
    api_output=''
    sleep 1
  done
  [ -n "$api_output" ] || die 'zj717 frontend API did not return a healthy live state'
  printf '%s\n' "$api_output" | grep -Fqx "WG_FEC_EFFECTIVE=$EXPECTED_FEC" || die 'frontend API returned the wrong FEC preset'
  say "PANEL_PAGE_VERIFY_PASS transaction=$TXN fec=$EXPECTED_FEC network=reachable backend=unchanged rollback=armed"
}

panel_page_commit() {
  [ -s "$PANEL_PAGE_ACTIVE" ] || die 'no pending zj717 frontend transaction'
  . "$PANEL_PAGE_ACTIVE"
  panel_page_verify "$TXN"
  panel_page_cancel_rollback "$BACKUP_DIR"
  rm -f "$PANEL_PAGE_ACTIVE"
  say "PANEL_PAGE_COMMIT_PASS transaction=$TXN backup=$BACKUP_DIR rollback=cancelled"
}

panel_page_rollback() {
  requested="${1:-}"
  [ -s "$PANEL_PAGE_ACTIVE" ] || { say 'PANEL_PAGE_ROLLBACK_NO_PENDING'; return 0; }
  . "$PANEL_PAGE_ACTIVE"
  [ -z "$requested" ] || [ "$TXN" = "$requested" ] || die 'zj717 frontend rollback mismatch'
  expected_fec="$EXPECTED_FEC"
  backup_dir="$BACKUP_DIR"
  /bin/sh "$backup_dir/rollback.sh"
  panel_page_cancel_rollback "$backup_dir"
  [ ! -s "$PANEL_PAGE_ACTIVE" ] || die 'zj717 frontend rollback did not clear transaction'
  cmp -s /www/wgpanel.html "$backup_dir/wgpanel.html" || die 'zj717 frontend rollback mismatch'
  [ "$(panel_read_preset "$PANEL_OW_FEC_STATE")" = "$expected_fec" ] || die 'active FEC changed during frontend rollback'
  ow_service_running game-v2-zj717 || die 'zj717 service stopped after frontend rollback'
  say "PANEL_PAGE_ROLLBACK_PASS transaction=$TXN"
}

# ---------- command dispatch ----------

cmd="${1:-}"
[ -n "$cmd" ] || { usage; exit 1; }
shift
case "$cmd" in
  inspect) [ "$#" -eq 0 ] || die 'inspect takes no arguments'; local_inspect ;;
  apply) [ "$#" -eq 0 ] || die 'apply takes no arguments'; local_apply ;;
  verify) [ "$#" -eq 0 ] || die 'verify takes no arguments'; local_verify ;;
  status) [ "$#" -eq 0 ] || die 'status takes no arguments'; local_status ;;
  commit) [ "$#" -eq 0 ] || die 'commit takes no arguments'; local_commit ;;
  rollback) [ "$#" -eq 0 ] || die 'rollback takes no arguments'; local_rollback ;;
  repair-panel) [ "$#" -eq 0 ] || die 'repair-panel takes no arguments'; local_repair_panel ;;
  repair-panel-status) [ "$#" -eq 0 ] || die 'repair-panel-status takes no arguments'; local_repair_panel_status ;;
  repair-status-latency) [ "$#" -eq 0 ] || die 'repair-status-latency takes no arguments'; local_repair_status_latency ;;
  reinstall-panel-page) [ "$#" -eq 0 ] || die 'reinstall-panel-page takes no arguments'; local_reinstall_panel_page ;;
  commit-panel-page) [ "$#" -eq 0 ] || die 'commit-panel-page takes no arguments'; local_commit_panel_page ;;
  rollback-panel-page) [ "$#" -eq 0 ] || die 'rollback-panel-page takes no arguments'; local_rollback_panel_page ;;
  _vps_prepare) [ "$#" -eq 1 ] || die '_vps_prepare requires transaction'; vps_prepare "$1" ;;
  _vps_apply) [ "$#" -eq 1 ] || die '_vps_apply requires transaction'; vps_apply "$1" ;;
  _vps_verify) [ "$#" -eq 0 ] || die '_vps_verify takes no arguments'; vps_verify ;;
  _vps_txn_state) [ "$#" -eq 0 ] || die '_vps_txn_state takes no arguments'; vps_txn_state ;;
  _vps_commit) [ "$#" -eq 1 ] || die '_vps_commit requires transaction'; vps_commit "$1" ;;
  _vps_rollback) [ "$#" -le 1 ] || die '_vps_rollback takes at most one argument'; vps_rollback "${1:-}" ;;
  _vps_status) [ "$#" -eq 0 ] || die '_vps_status takes no arguments'; vps_status ;;
  _ow_prepare) [ "$#" -eq 1 ] || die '_ow_prepare requires transaction'; ow_prepare "$1" ;;
  _ow_apply) [ "$#" -eq 2 ] || die '_ow_apply requires transaction and package'; ow_apply "$1" "$2" ;;
  _ow_verify) [ "$#" -eq 0 ] || die '_ow_verify takes no arguments'; ow_verify ;;
  _ow_txn_state) [ "$#" -eq 0 ] || die '_ow_txn_state takes no arguments'; ow_txn_state ;;
  _ow_commit) [ "$#" -eq 1 ] || die '_ow_commit requires transaction'; ow_commit "$1" ;;
  _ow_rollback) [ "$#" -le 1 ] || die '_ow_rollback takes at most one argument'; ow_rollback "${1:-}" ;;
  _ow_status) [ "$#" -eq 0 ] || die '_ow_status takes no arguments'; ow_status ;;
  _panel_vps_prepare) [ "$#" -eq 1 ] || die '_panel_vps_prepare requires transaction'; panel_vps_prepare "$1" ;;
  _panel_vps_apply) [ "$#" -eq 1 ] || die '_panel_vps_apply requires transaction'; panel_vps_apply "$1" ;;
  _panel_vps_verify) [ "$#" -eq 1 ] || die '_panel_vps_verify requires preset'; panel_vps_verify "$1" ;;
  _panel_vps_commit) [ "$#" -eq 1 ] || die '_panel_vps_commit requires transaction'; panel_vps_commit "$1" ;;
  _panel_vps_rollback) [ "$#" -le 1 ] || die '_panel_vps_rollback takes at most one argument'; panel_vps_rollback "${1:-}" ;;
  _panel_ow_prepare) [ "$#" -eq 1 ] || die '_panel_ow_prepare requires transaction'; panel_ow_prepare "$1" ;;
  _panel_ow_apply) [ "$#" -eq 1 ] || die '_panel_ow_apply requires transaction'; panel_ow_apply "$1" ;;
  _panel_ow_activate) [ "$#" -eq 1 ] || die '_panel_ow_activate requires preset'; panel_ow_activate "$1" ;;
  _panel_ow_verify) [ "$#" -eq 1 ] || die '_panel_ow_verify requires preset'; panel_ow_verify "$1" ;;
  _panel_ow_commit) [ "$#" -eq 1 ] || die '_panel_ow_commit requires transaction'; panel_ow_commit "$1" ;;
  _panel_ow_rollback) [ "$#" -le 1 ] || die '_panel_ow_rollback takes at most one argument'; panel_ow_rollback "${1:-}" ;;
  _panel_status_prepare) [ "$#" -eq 1 ] || die '_panel_status_prepare requires transaction'; panel_status_prepare "$1" ;;
  _panel_status_apply) [ "$#" -eq 1 ] || die '_panel_status_apply requires transaction'; panel_status_apply "$1" ;;
  _panel_status_verify) [ "$#" -eq 1 ] || die '_panel_status_verify requires preset'; panel_status_verify "$1" ;;
  _panel_status_commit) [ "$#" -eq 1 ] || die '_panel_status_commit requires transaction'; panel_status_commit "$1" ;;
  _panel_status_rollback) [ "$#" -le 1 ] || die '_panel_status_rollback takes at most one argument'; panel_status_rollback "${1:-}" ;;
  _panel_latency_prepare) [ "$#" -eq 1 ] || die '_panel_latency_prepare requires transaction'; panel_latency_prepare "$1" ;;
  _panel_latency_apply) [ "$#" -eq 1 ] || die '_panel_latency_apply requires transaction'; panel_latency_apply "$1" ;;
  _panel_latency_verify) [ "$#" -eq 1 ] || die '_panel_latency_verify requires preset'; panel_latency_verify "$1" ;;
  _panel_latency_commit) [ "$#" -eq 1 ] || die '_panel_latency_commit requires transaction'; panel_latency_commit "$1" ;;
  _panel_latency_rollback) [ "$#" -le 1 ] || die '_panel_latency_rollback takes at most one argument'; panel_latency_rollback "${1:-}" ;;
  _panel_page_prepare) [ "$#" -eq 1 ] || die '_panel_page_prepare requires transaction'; panel_page_prepare "$1" ;;
  _panel_page_apply) [ "$#" -eq 1 ] || die '_panel_page_apply requires transaction'; panel_page_apply "$1" ;;
  _panel_page_verify) [ "$#" -le 1 ] || die '_panel_page_verify takes at most one argument'; panel_page_verify "${1:-}" ;;
  _panel_page_commit) [ "$#" -eq 0 ] || die '_panel_page_commit takes no arguments'; panel_page_commit ;;
  _panel_page_rollback) [ "$#" -le 1 ] || die '_panel_page_rollback takes at most one argument'; panel_page_rollback "${1:-}" ;;
  -h|--help|help) usage ;;
  *) usage; die "unknown command: $cmd" ;;
esac
