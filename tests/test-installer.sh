#!/bin/sh

set -u

SCRIPT=${SYSINFO_INSTALLER:-./install-system-info.sh}
out_file=""
err_file=""
test_home=""

cleanup() {
    [ -n "$out_file" ] && rm -f "$out_file"
    [ -n "$err_file" ] && rm -f "$err_file"
    [ -n "$test_home" ] && rm -rf "$test_home"
}

fail() {
    printf 'test-installer: %s\n' "$1" >&2
    exit 1
}

assert_contains() {
    haystack=$1
    needle=$2

    printf '%s\n' "$haystack" | grep -F -- "$needle" >/dev/null 2>&1 || {
        printf 'Expected to find: %s\n' "$needle" >&2
        printf '%s\n' "$haystack" >&2
        fail "missing expected output"
    }
}

trap cleanup EXIT HUP INT TERM

version=$(sh "$SCRIPT" --version) || fail "version command failed"
[ "$version" = "1.5.1" ] || fail "unexpected version: $version"

help_output=$(sh "$SCRIPT" --help) || fail "help command failed"
assert_contains "$help_output" "--command-tool"
assert_contains "$help_output" "--auto-start"
assert_contains "$help_output" "--uninstall"

out_file=$(mktemp "${TMPDIR:-/tmp}/sysinfo-installer-out.XXXXXX") || fail "unable to create output temp file"
err_file=$(mktemp "${TMPDIR:-/tmp}/sysinfo-installer-err.XXXXXX") || fail "unable to create error temp file"

if sh "$SCRIPT" >"$out_file" 2>"$err_file"; then
    fail "non-interactive installer without mode should fail"
fi

combined_output=$(cat "$out_file" "$err_file")
assert_contains "$combined_output" "Non-interactive use requires an explicit mode"

test_home=$(mktemp -d "${TMPDIR:-/tmp}/sysinfo-installer-home.XXXXXX") || fail "unable to create temporary HOME"

repo_dir=$(pwd -P)

HOME=$test_home SYSINFO_RAW_BASE_URL=$repo_dir sh "$SCRIPT" --command-tool --user >"$out_file" 2>"$err_file" || {
    combined_output=$(cat "$out_file" "$err_file")
    printf '%s\n' "$combined_output" >&2
    fail "user install failed"
}

installed_script=$test_home/.local/bin/sysinfo
[ -x "$installed_script" ] || fail "installed sysinfo is not executable"

installed_version=$(sh "$installed_script" --version) || fail "installed sysinfo version failed"
[ "$installed_version" = "1.5.1" ] || fail "unexpected installed version: $installed_version"

HOME=$test_home sh "$SCRIPT" --uninstall --user >"$out_file" 2>"$err_file" || {
    combined_output=$(cat "$out_file" "$err_file")
    printf '%s\n' "$combined_output" >&2
    fail "user uninstall failed"
}

[ ! -e "$installed_script" ] || fail "installed sysinfo was not removed"

printf '%s\n' "test-installer: ok"
