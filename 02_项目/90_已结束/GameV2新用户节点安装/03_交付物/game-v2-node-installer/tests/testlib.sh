#!/bin/sh

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
assert_file() { [ -f "$1" ] || fail "missing file: $1"; }
assert_no_file() { [ ! -e "$1" ] || fail "unexpected path: $1"; }
assert_contains() { grep -Fq -- "$2" "$1" || fail "missing '$2' in $1"; }
assert_not_contains() { ! grep -Fq -- "$2" "$1" || fail "unexpected '$2' in $1"; }
assert_mode() {
  actual=$(stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1")
  [ "$actual" = "$2" ] || fail "mode $actual != $2: $1"
}
