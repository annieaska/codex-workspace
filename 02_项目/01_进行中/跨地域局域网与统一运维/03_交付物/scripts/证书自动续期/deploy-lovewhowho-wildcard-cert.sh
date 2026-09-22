#!/usr/bin/env bash
set -Eeuo pipefail

SRC_DIR=/root/.acme.sh/lovewhowho.net_ecc
SRC_CERT="$SRC_DIR/fullchain.cer"
SRC_KEY="$SRC_DIR/lovewhowho.net.key"
OPENRESTY_ROOT=/opt/1panel/apps/openresty/openresty
CONF_DIR="$OPENRESTY_ROOT/conf/conf.d"
RESOURCE_CERT=/opt/1panel/resource/ssl/lovewhowho_cert/fullchain.pem
RESOURCE_KEY=/opt/1panel/resource/ssl/lovewhowho_cert/privkey.pem
BACKUP_ROOT=/var/backups/lovewhowho-cert
LOCK_FILE=/run/lock/lovewhowho-cert.lock
FRESHNESS_SECONDS=$((21 * 24 * 60 * 60))

MODE=deploy
case "${1:-}" in
  '') ;;
  --deploy) MODE=deploy ;;
  --check) MODE=check ;;
  --probe) MODE=probe ;;
  *) echo "usage: $0 [--deploy|--check|--probe]" >&2; exit 64 ;;
esac

log() {
  printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*"
}

die() {
  log "ERROR $*" >&2
  exit 1
}

cert_fingerprint() {
  openssl x509 -in "$1" -outform DER 2>/dev/null | sha256sum | awk '{print $1}'
}

cert_pubkey_fingerprint() {
  openssl x509 -in "$1" -pubkey -noout 2>/dev/null \
    | openssl pkey -pubin -outform DER 2>/dev/null \
    | sha256sum | awk '{print $1}'
}

key_pubkey_fingerprint() {
  openssl pkey -in "$1" -pubout -outform DER 2>/dev/null \
    | sha256sum | awk '{print $1}'
}

validate_source() {
  [[ -r "$SRC_CERT" ]] || die "source certificate is not readable: $SRC_CERT"
  [[ -r "$SRC_KEY" ]] || die "source private key is not readable: $SRC_KEY"
  openssl x509 -in "$SRC_CERT" -noout >/dev/null 2>&1 \
    || die "source certificate cannot be parsed"
  openssl pkey -in "$SRC_KEY" -noout >/dev/null 2>&1 \
    || die "source private key cannot be parsed"
  openssl x509 -in "$SRC_CERT" -checkend 3600 -noout >/dev/null 2>&1 \
    || die "source certificate is expired or expires within one hour"

  local san cert_pub key_pub
  san=$(openssl x509 -in "$SRC_CERT" -noout -ext subjectAltName 2>/dev/null)
  grep -Fq 'DNS:*.lovewhowho.net' <<<"$san" \
    || die "source certificate is missing wildcard SAN"
  grep -Eq 'DNS:lovewhowho\.net([,[:space:]]|$)' <<<"$san" \
    || die "source certificate is missing apex SAN"

  cert_pub=$(cert_pubkey_fingerprint "$SRC_CERT")
  key_pub=$(key_pubkey_fingerprint "$SRC_KEY")
  [[ -n "$cert_pub" && "$cert_pub" == "$key_pub" ]] \
    || die "source certificate and private key do not match"
}

check_source_freshness() {
  openssl x509 -in "$SRC_CERT" -checkend "$FRESHNESS_SECONDS" -noout >/dev/null 2>&1 \
    || die "source certificate expires within 21 days; ACME renewal needs attention"
}

find_openresty_container() {
  mapfile -t OPENRESTY_CONTAINERS < <(
    docker ps --format '{{.Names}} {{.Image}}' \
      | awk 'tolower($1) ~ /openresty/ && $2 ~ /1panel\/openresty/ {print $1}'
  )
  ((${#OPENRESTY_CONTAINERS[@]} == 1)) \
    || die "expected exactly one running 1Panel OpenResty container, found ${#OPENRESTY_CONTAINERS[@]}"
  OPENRESTY_CONTAINER=${OPENRESTY_CONTAINERS[0]}
}

resolve_container_path() {
  local container_path=$1 current link loops=0
  [[ "$container_path" == /www/* ]] \
    || die "unsupported certificate path outside /www: $container_path"
  current="$OPENRESTY_ROOT$container_path"

  while [[ -L "$current" ]]; do
    loops=$((loops + 1))
    ((loops <= 12)) || die "too many symlink levels: $container_path"
    link=$(readlink "$current")
    if [[ "$link" == /www/* ]]; then
      current="$OPENRESTY_ROOT$link"
    elif [[ "$link" == /* ]]; then
      die "unsupported absolute symlink target: $link"
    else
      current=$(realpath -m "$(dirname "$current")/$link")
    fi
  done

  current=$(realpath -m "$current")
  [[ "$current" == "$OPENRESTY_ROOT/www/sites/"* ]] \
    || die "resolved path escaped the OpenResty sites directory: $current"
  printf '%s\n' "$current"
}

declare -A TARGET_KEY_BY_CERT=()
declare -A DOMAIN_SET=()
declare -a ACTIVE_CERTS=()
declare -a ACTIVE_DOMAINS=()

add_target() {
  local cert=$1 key=$2 existing
  existing=${TARGET_KEY_BY_CERT[$cert]:-}
  if [[ -n "$existing" && "$existing" != "$key" ]]; then
    die "certificate target maps to conflicting keys: $cert"
  fi
  TARGET_KEY_BY_CERT[$cert]=$key
}

discover_active_targets() {
  local conf name relevant cert_container key_container cert_host key_host
  local -a names=() cert_paths=() key_paths=()

  shopt -s nullglob
  for conf in "$CONF_DIR"/*.conf; do
    mapfile -t names < <(
      awk '{sub(/#.*/, "")} $1 == "server_name" {for (i=2; i<=NF; i++) {gsub(/;/, "", $i); print $i}}' "$conf" \
        | sort -u
    )
    relevant=0
    for name in "${names[@]}"; do
      if [[ "$name" == lovewhowho.net || "$name" == *.lovewhowho.net ]]; then
        relevant=1
        break
      fi
    done
    ((relevant == 1)) || continue

    mapfile -t cert_paths < <(
      awk '{sub(/#.*/, "")} $1 == "ssl_certificate" {gsub(/;/, "", $2); print $2}' "$conf" \
        | sort -u
    )
    mapfile -t key_paths < <(
      awk '{sub(/#.*/, "")} $1 == "ssl_certificate_key" {gsub(/;/, "", $2); print $2}' "$conf" \
        | sort -u
    )

    if ((${#cert_paths[@]} == 0 && ${#key_paths[@]} == 0)); then
      continue
    fi
    ((${#cert_paths[@]} == 1 && ${#key_paths[@]} == 1)) \
      || die "ambiguous certificate directives in $conf"

    cert_container=${cert_paths[0]}
    key_container=${key_paths[0]}
    cert_host=$(resolve_container_path "$cert_container")
    key_host=$(resolve_container_path "$key_container")
    [[ "$(basename "$cert_host")" == fullchain.pem ]] \
      || die "unexpected certificate filename in $conf: $cert_host"
    [[ "$(basename "$key_host")" == privkey.pem ]] \
      || die "unexpected private-key filename in $conf: $key_host"
    [[ "$(dirname "$cert_host")" == "$(dirname "$key_host")" ]] \
      || die "certificate and key directories differ in $conf"
    add_target "$cert_host" "$key_host"

    for name in "${names[@]}"; do
      if [[ "$name" == lovewhowho.net || "$name" == *.lovewhowho.net ]]; then
        [[ "$name" == \*.* ]] && continue
        [[ "$name" =~ ^[A-Za-z0-9.-]+$ ]] || continue
        DOMAIN_SET[$name]=1
      fi
    done
  done
  shopt -u nullglob

  add_target "$RESOURCE_CERT" "$RESOURCE_KEY"
  mapfile -t ACTIVE_CERTS < <(printf '%s\n' "${!TARGET_KEY_BY_CERT[@]}" | sort)
  mapfile -t ACTIVE_DOMAINS < <(printf '%s\n' "${!DOMAIN_SET[@]}" | sort)
  ((${#ACTIVE_CERTS[@]} > 1)) || die "no active lovewhowho.net certificate targets were discovered"
  ((${#ACTIVE_DOMAINS[@]} > 0)) || die "no active lovewhowho.net TLS domains were discovered"
  [[ -n "${DOMAIN_SET[ops.lovewhowho.net]:-}" ]] \
    || die "critical TLS domain is missing from active configuration: ops.lovewhowho.net"
}

audit_files() {
  local source_fp cert key target_fp failures=0 mode
  source_fp=$(cert_fingerprint "$SRC_CERT")
  for cert in "${ACTIVE_CERTS[@]}"; do
    key=${TARGET_KEY_BY_CERT[$cert]}
    if [[ ! -r "$cert" ]]; then
      log "ERROR missing deployed certificate: $cert" >&2
      failures=$((failures + 1))
    elif ! target_fp=$(cert_fingerprint "$cert"); then
      log "ERROR invalid deployed certificate: $cert" >&2
      failures=$((failures + 1))
    elif [[ "$target_fp" != "$source_fp" ]]; then
      log "ERROR certificate drift: $cert" >&2
      failures=$((failures + 1))
    fi

    if [[ ! -r "$key" ]]; then
      log "ERROR missing deployed private key: $key" >&2
      failures=$((failures + 1))
    elif ! cmp -s "$SRC_KEY" "$key"; then
      log "ERROR private-key drift: $key" >&2
      failures=$((failures + 1))
    else
      mode=$(stat -c '%a' "$key" 2>/dev/null || true)
      if [[ "$mode" != 600 ]]; then
        log "ERROR unsafe private-key mode $mode: $key" >&2
        failures=$((failures + 1))
      fi
    fi
  done
  ((failures == 0))
}

live_fingerprint() {
  local domain=$1
  timeout 8 openssl s_client -connect 127.0.0.1:443 -servername "$domain" </dev/null 2>/dev/null \
    | openssl x509 -outform DER 2>/dev/null \
    | sha256sum | awk '{print $1}'
}

audit_live_domains() {
  local source_fp domain live_fp failures=0
  source_fp=$(cert_fingerprint "$SRC_CERT")
  for domain in "$@"; do
    if ! live_fp=$(live_fingerprint "$domain") || [[ -z "$live_fp" ]]; then
      log "ERROR cannot read live certificate: $domain" >&2
      failures=$((failures + 1))
    elif [[ "$live_fp" != "$source_fp" ]]; then
      log "ERROR live certificate drift: $domain" >&2
      failures=$((failures + 1))
    fi
  done
  ((failures == 0))
}

openresty_test() {
  docker exec "$OPENRESTY_CONTAINER" openresty -t
}

reload_openresty() {
  docker exec "$OPENRESTY_CONTAINER" openresty -s reload
}

declare -A BACKUP_EXISTS=()
BACKUP_DIR=
DEPLOY_STARTED=0
DEPLOY_SUCCEEDED=0

backup_file() {
  local src=$1 dst
  dst="$BACKUP_DIR/files/${src#/}"
  install -d -m 700 "$(dirname "$dst")"
  if [[ -e "$src" ]]; then
    cp -aL -- "$src" "$dst"
    BACKUP_EXISTS[$src]=1
  else
    BACKUP_EXISTS[$src]=0
  fi
}

restore_file() {
  local dst=$1 mode=$2 src
  src="$BACKUP_DIR/files/${dst#/}"
  if [[ "${BACKUP_EXISTS[$dst]:-0}" == 1 ]]; then
    install -d -m 700 "$(dirname "$dst")"
    install -m "$mode" "$src" "$dst"
  else
    rm -f -- "$dst"
  fi
}

rollback_deployment() {
  local cert key
  log "ROLLBACK restoring certificate files from $BACKUP_DIR" >&2
  set +e
  for cert in "${ACTIVE_CERTS[@]}"; do
    key=${TARGET_KEY_BY_CERT[$cert]}
    restore_file "$cert" 644
    restore_file "$key" 600
  done
  openresty_test >/dev/null 2>&1 && reload_openresty >/dev/null 2>&1
  set -e
}

on_exit() {
  local rc=$?
  trap - EXIT
  if ((DEPLOY_STARTED == 1 && DEPLOY_SUCCEEDED == 0)); then
    rollback_deployment
  fi
  exit "$rc"
}
trap on_exit EXIT

atomic_install() {
  local src=$1 dst=$2 mode=$3 tmp
  install -d -m 700 "$(dirname "$dst")"
  tmp="${dst}.new.$$"
  install -m "$mode" "$src" "$tmp"
  mv -f -- "$tmp" "$dst"
}

deploy() {
  local cert key stamp expiry source_fp
  openresty_test >/dev/null
  stamp=$(date -u '+%Y%m%dT%H%M%SZ')
  BACKUP_DIR="$BACKUP_ROOT/$stamp"
  install -d -m 700 "$BACKUP_DIR/files"

  for cert in "${ACTIVE_CERTS[@]}"; do
    key=${TARGET_KEY_BY_CERT[$cert]}
    backup_file "$cert"
    backup_file "$key"
  done

  DEPLOY_STARTED=1
  for cert in "${ACTIVE_CERTS[@]}"; do
    key=${TARGET_KEY_BY_CERT[$cert]}
    atomic_install "$SRC_CERT" "$cert" 644
    atomic_install "$SRC_KEY" "$key" 600
  done

  audit_files
  openresty_test >/dev/null
  reload_openresty >/dev/null
  sleep 1
  audit_live_domains "${ACTIVE_DOMAINS[@]}"

  DEPLOY_SUCCEEDED=1
  source_fp=$(cert_fingerprint "$SRC_CERT")
  expiry=$(openssl x509 -in "$SRC_CERT" -noout -enddate | cut -d= -f2-)
  log "DEPLOY_OK targets=${#ACTIVE_CERTS[@]} domains=${#ACTIVE_DOMAINS[@]} fingerprint=$source_fp expires='$expiry' backup=$BACKUP_DIR"
}

exec 9>"$LOCK_FILE"
flock -n 9 || die "another certificate deployment or check is already running"

validate_source
find_openresty_container
discover_active_targets

case "$MODE" in
  deploy)
    deploy
    ;;
  check)
    check_source_freshness
    audit_files
    audit_live_domains "${ACTIVE_DOMAINS[@]}"
    log "CHECK_OK targets=${#ACTIVE_CERTS[@]} domains=${#ACTIVE_DOMAINS[@]}"
    ;;
  probe)
    check_source_freshness
    audit_files
    audit_live_domains ops.lovewhowho.net auth.lovewhowho.net panel.lovewhowho.net
    log "PROBE_OK targets=${#ACTIVE_CERTS[@]} critical_domains=3"
    ;;
esac

DEPLOY_SUCCEEDED=1
