#!/usr/bin/env bash
set -Eeuo pipefail

DEPLOY_SCRIPT=/usr/local/bin/deploy-lovewhowho-wildcard-cert.sh

case "${1:-}" in
  --check-only)
    exec "$DEPLOY_SCRIPT" --check
    ;;
  --probe)
    exec "$DEPLOY_SCRIPT" --probe
    ;;
  '')
    ;;
  *)
    echo "usage: $0 [--check-only|--probe]" >&2
    exit 64
    ;;
esac

if "$DEPLOY_SCRIPT" --check; then
  exit 0
fi

printf '%s certificate drift detected; starting controlled redeployment\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >&2
"$DEPLOY_SCRIPT" --deploy
"$DEPLOY_SCRIPT" --check
