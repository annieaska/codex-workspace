#!/bin/sh
set -eu

# GAME_V2_RELEASE_BUILDER_V1

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
installer_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
version=$(sed -n '1p' "$installer_dir/VERSION")
case "$version" in ''|*[!0-9.]*|.*|*.) printf '%s\n' 'ERROR=INVALID_VERSION' >&2; exit 1 ;; esac

output_dir=${1:-"$installer_dir/dist"}
[ ! -L "$output_dir" ] || { printf '%s\n' 'ERROR=OUTPUT_DIR_NOT_SAFE' >&2; exit 1; }
mkdir -p "$output_dir"
[ -d "$output_dir" ] || { printf '%s\n' 'ERROR=OUTPUT_DIR_NOT_DIRECTORY' >&2; exit 1; }

umask 077
stage_dir=$(mktemp -d "${TMPDIR:-/tmp}/game-v2-release.XXXXXX")
trap 'rm -rf "$stage_dir"' EXIT INT TERM

package_name="game-v2-server-installer-$version"
package_root="$stage_dir/$package_name"
mkdir -p \
  "$package_root/scripts" \
  "$package_root/bundles/cy507-openwrt" \
  "$package_root/config/fleet" \
  "$package_root/docs"

# v1.3.0 is the fixed cy507 delivery. Non-cy507 parameter records stay in the
# repository for reference, but are never published as executable content.
cp "$installer_dir/VERSION" "$package_root/VERSION"
cp "$installer_dir/README.md" "$package_root/README.md"
cp "$installer_dir/scripts/game-v2-cy507-vps.sh" "$package_root/scripts/game-v2-cy507-vps.sh"
cp "$installer_dir/bundles/cy507-openwrt/install.sh" "$package_root/bundles/cy507-openwrt/install.sh"
cp "$installer_dir/config/fleet/cy507.conf" "$package_root/config/fleet/cy507.conf"
cp "$installer_dir/docs/cy507-complete-install.md" "$package_root/docs/cy507-complete-install.md"

archive_tmp="$output_dir/.$package_name.tar.gz.tmp.$$"
archive="$output_dir/$package_name.tar.gz"
checksum_tmp="$output_dir/.SHA256SUMS.tmp.$$"
checksum_file="$output_dir/SHA256SUMS"
tar -czf "$archive_tmp" -C "$stage_dir" "$package_name"
chmod 644 "$archive_tmp"

if command -v sha256sum >/dev/null 2>&1; then
  archive_sha256=$(sha256sum "$archive_tmp" | awk '{print $1}')
else
  archive_sha256=$(shasum -a 256 "$archive_tmp" | awk '{print $1}')
fi
printf '%s  %s\n' "$archive_sha256" "$package_name.tar.gz" > "$checksum_tmp"
chmod 644 "$checksum_tmp"
mv "$archive_tmp" "$archive"
mv "$checksum_tmp" "$checksum_file"

printf '%s\n' \
  'RELEASE_BUILD=PASS' \
  "VERSION=$version" \
  "SERVER_PACKAGE=$archive" \
  "CHECKSUMS=$checksum_file"
