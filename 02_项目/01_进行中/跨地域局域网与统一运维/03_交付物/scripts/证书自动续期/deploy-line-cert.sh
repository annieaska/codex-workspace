#!/usr/bin/env bash
set -Eeuo pipefail

# Kept as a compatibility entry point. All sites are now deployed and verified together.
exec /usr/local/bin/deploy-lovewhowho-wildcard-cert.sh --deploy
