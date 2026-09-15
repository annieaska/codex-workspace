#!/bin/sh
set -eu

test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
installer_dir=$(CDPATH= cd -- "$test_dir/.." && pwd)
. "$test_dir/testlib.sh"

test_root=$(mktemp -d "${TMPDIR:-/tmp}/game-v2-release-test.XXXXXX")
trap 'rm -rf "$test_root"' EXIT INT TERM
dist_dir="$test_root/dist"
extract_dir="$test_root/extract"
mkdir -p "$extract_dir"

release_output=$(sh "$installer_dir/scripts/build-release.sh" "$dist_dir")
printf '%s\n' "$release_output" > "$test_root/release.out"
assert_contains "$test_root/release.out" 'RELEASE_BUILD=PASS'

version=$(sed -n '1p' "$installer_dir/VERSION")
package_name="game-v2-server-installer-$version"
archive="$dist_dir/$package_name.tar.gz"
assert_file "$archive"
assert_file "$dist_dir/SHA256SUMS"

if command -v sha256sum >/dev/null 2>&1; then
  (cd "$dist_dir" && sha256sum -c SHA256SUMS)
else
  (cd "$dist_dir" && shasum -a 256 -c SHA256SUMS)
fi

tar -tzf "$archive" > "$test_root/archive.list"
assert_contains "$test_root/archive.list" "$package_name/scripts/game-v2-cy507-vps.sh"
assert_contains "$test_root/archive.list" "$package_name/bundles/cy507-openwrt/install.sh"
assert_contains "$test_root/archive.list" "$package_name/config/fleet/cy507.conf"
assert_contains "$test_root/archive.list" "$package_name/docs/cy507-complete-install.md"
assert_not_contains "$test_root/archive.list" "$package_name/scripts/game-v2-server.sh"
assert_not_contains "$test_root/archive.list" "$package_name/scripts/game-v2-client.sh"
assert_not_contains "$test_root/archive.list" "$package_name/bundles/openwrt-apk-x86_64/"
assert_not_contains "$test_root/archive.list" "$package_name/config/fleet/jzg37.conf"
assert_not_contains "$test_root/archive.list" "$package_name/config/fleet/yhz187.conf"
assert_not_contains "$test_root/archive.list" "$package_name/config/fleet/zj717.conf"
assert_not_contains "$test_root/archive.list" "$package_name/docs/new-node-sop.md"
assert_not_contains "$test_root/archive.list" "$package_name/tests/"
assert_not_contains "$test_root/archive.list" '.DS_Store'
assert_not_contains "$test_root/archive.list" '/dist/'

tar -xzf "$archive" -C "$extract_dir"
find "$extract_dir/$package_name/scripts" "$extract_dir/$package_name/bundles" -type f -name '*.sh' -exec sh -n {} \;

printf '%s\n' 'PASS test-release-package'
