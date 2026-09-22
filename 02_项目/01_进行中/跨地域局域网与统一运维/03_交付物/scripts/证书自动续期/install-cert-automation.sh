#!/usr/bin/env bash
set -Eeuo pipefail

[[ $# -eq 1 ]] || { echo "usage: $0 STAGE_DIR" >&2; exit 64; }
STAGE_DIR=$1
BACKUP_ROOT=/var/backups/lovewhowho-cert-automation
STAMP=$(date -u '+%Y%m%dT%H%M%SZ')
BACKUP_DIR="$BACKUP_ROOT/$STAMP"
SUCCESS=0

declare -a MANAGED_FILES=(
  /usr/local/bin/deploy-lovewhowho-wildcard-cert.sh
  /usr/local/bin/check-lovewhowho-wildcard-cert.sh
  /usr/local/bin/deploy-line-cert.sh
  /opt/ops-monitor/bin/extra_probe.py
  /opt/ops-monitor/conf/extra_targets.json
  /etc/logrotate.d/lovewhowho-cert
)

log() {
  printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*"
}

check_expected_hash() {
  local expected=$1 path=$2 actual
  actual=$(sha256sum "$path" | awk '{print $1}')
  [[ "$actual" == "$expected" ]] || {
    log "ERROR source changed since audit: $path" >&2
    exit 1
  }
}

backup_path() {
  local path=$1 backup="$BACKUP_DIR/files/${path#/}" marker="$BACKUP_DIR/missing/${path#/}"
  if [[ -e "$path" || -L "$path" ]]; then
    install -d -m 700 "$(dirname "$backup")"
    cp -a -- "$path" "$backup"
  else
    install -d -m 700 "$(dirname "$marker")"
    : >"$marker"
  fi
}

restore_path() {
  local path=$1 backup="$BACKUP_DIR/files/${path#/}" marker="$BACKUP_DIR/missing/${path#/}"
  if [[ -e "$backup" || -L "$backup" ]]; then
    install -d "$(dirname "$path")"
    cp -a -- "$backup" "$path"
  elif [[ -e "$marker" ]]; then
    rm -f -- "$path"
  fi
}

rollback_automation() {
  local path
  log "ROLLBACK restoring automation files and crontab from $BACKUP_DIR" >&2
  set +e
  for path in "${MANAGED_FILES[@]}"; do
    restore_path "$path"
  done
  crontab "$BACKUP_DIR/root.crontab"
  set -e
}

on_exit() {
  local rc=$?
  trap - EXIT
  if ((SUCCESS == 0)) && [[ -n "${BACKUP_DIR:-}" && -f "$BACKUP_DIR/root.crontab" ]]; then
    rollback_automation
  fi
  exit "$rc"
}
trap on_exit EXIT

for file in \
  deploy-lovewhowho-wildcard-cert.sh \
  check-lovewhowho-wildcard-cert.sh \
  deploy-line-cert.sh \
  extra_probe.py \
  extra_targets.json \
  lovewhowho-cert-logrotate; do
  [[ -f "$STAGE_DIR/$file" ]] || { log "ERROR missing staged file: $file" >&2; exit 1; }
done

bash -n \
  "$STAGE_DIR/deploy-lovewhowho-wildcard-cert.sh" \
  "$STAGE_DIR/check-lovewhowho-wildcard-cert.sh" \
  "$STAGE_DIR/deploy-line-cert.sh"
python3 -m py_compile "$STAGE_DIR/extra_probe.py"
python3 -m json.tool "$STAGE_DIR/extra_targets.json" >/dev/null

check_expected_hash 54858f26469fc1132fdf2f64df636363bc083f6c82cec0d0a00363bcbba2d221 /usr/local/bin/deploy-lovewhowho-wildcard-cert.sh
check_expected_hash e960c4355cba98ead0d4355d0951613632ba46879743e9f6265433e341f921f8 /usr/local/bin/check-lovewhowho-wildcard-cert.sh
check_expected_hash 9054d3f0e9639471d09aeaa9288dc4397ab1ee77a33028fc13eade78664f00b0 /usr/local/bin/deploy-line-cert.sh
check_expected_hash 602a5818fd3b8c0779d4a2db0582b2548619a82249329afe525ae282416477b6 /opt/ops-monitor/bin/extra_probe.py
check_expected_hash ae3323a37d75fc5b343b9cd674475563b44ec881f39d685128c4c76fdef0b0b1 /opt/ops-monitor/conf/extra_targets.json

install -d -m 700 "$BACKUP_DIR/files" "$BACKUP_DIR/missing"
crontab -l >"$BACKUP_DIR/root.crontab"
for path in "${MANAGED_FILES[@]}"; do
  backup_path "$path"
done

install -m 755 "$STAGE_DIR/deploy-lovewhowho-wildcard-cert.sh" /usr/local/bin/deploy-lovewhowho-wildcard-cert.sh
install -m 755 "$STAGE_DIR/check-lovewhowho-wildcard-cert.sh" /usr/local/bin/check-lovewhowho-wildcard-cert.sh
install -m 755 "$STAGE_DIR/deploy-line-cert.sh" /usr/local/bin/deploy-line-cert.sh
install -m 755 "$STAGE_DIR/extra_probe.py" /opt/ops-monitor/bin/extra_probe.py
install -m 640 "$STAGE_DIR/extra_targets.json" /opt/ops-monitor/conf/extra_targets.json
install -m 644 "$STAGE_DIR/lovewhowho-cert-logrotate" /etc/logrotate.d/lovewhowho-cert

CURRENT_CRON=$(mktemp)
NEW_CRON=$(mktemp)
trap 'rm -f "$CURRENT_CRON" "$NEW_CRON"' RETURN
crontab -l >"$CURRENT_CRON"
python3 - "$CURRENT_CRON" "$NEW_CRON" <<'PY'
import sys
from pathlib import Path

source = Path(sys.argv[1]).read_text(encoding='utf-8')
replacements = {
    '40 6 * * * "/root/.acme.sh"/acme.sh --cron --home "/root/.acme.sh" > /dev/null':
        '40 6,18 * * * "/root/.acme.sh"/acme.sh --cron --home "/root/.acme.sh" >> /var/log/lovewhowho-acme.log 2>&1',
    '50 6 * * * /usr/local/bin/check-lovewhowho-wildcard-cert.sh >> /var/log/lovewhowho-cert-check.log 2>&1':
        '50 6,18 * * * /usr/local/bin/check-lovewhowho-wildcard-cert.sh >> /var/log/lovewhowho-cert-check.log 2>&1',
}
for old, new in replacements.items():
    if source.count(old) != 1:
        raise SystemExit(f'expected exactly one crontab line, found {source.count(old)}: {old}')
    source = source.replace(old, new)
Path(sys.argv[2]).write_text(source, encoding='utf-8')
PY
crontab "$NEW_CRON"
rm -f "$CURRENT_CRON" "$NEW_CRON"
trap - RETURN

for log_file in /var/log/lovewhowho-acme.log /var/log/lovewhowho-cert-check.log; do
  if [[ ! -e "$log_file" ]]; then
    install -m 600 /dev/null "$log_file"
  else
    chmod 600 "$log_file"
  fi
done

/usr/local/bin/deploy-lovewhowho-wildcard-cert.sh --deploy
/usr/local/bin/check-lovewhowho-wildcard-cert.sh --check-only
/opt/ops-monitor/bin/extra_probe.py \
  | grep -Fx 'extra:lovewhowho_certificate|UP|certificate_check_rc=0' >/dev/null
logrotate -d /etc/logrotate.d/lovewhowho-cert >/dev/null 2>&1

SUCCESS=1
log "INSTALL_OK automation_backup=$BACKUP_DIR"
