#!/bin/sh
set -eu

test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
sh "$test_dir/test-release-package.sh"
sh "$test_dir/test-cy507-v13.sh"

printf '%s\n' 'PASS game-v2-offline-tests (2/2)'
