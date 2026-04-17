#!/bin/sh

set -u

SCRIPT=${SYSINFO_SCRIPT:-./system-info.sh}
out_file=""
err_file=""

cleanup() {
    [ -n "$out_file" ] && rm -f "$out_file"
    [ -n "$err_file" ] && rm -f "$err_file"
}

fail() {
    printf 'test-system-info: %s\n' "$1" >&2
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

plain_output=$(sh "$SCRIPT" --plain --no-public-ip --resources) || fail "plain output failed"
assert_contains "$plain_output" "Public IP: disabled"
assert_contains "$plain_output" "Kernel:"
assert_contains "$plain_output" "Memory:"
assert_contains "$plain_output" "Disk:"

json_output=$(sh "$SCRIPT" --json --no-public-ip --resources) || fail "json output failed"
assert_contains "$json_output" '"public_ip": "disabled"'
assert_contains "$json_output" '"kernel_version":'
assert_contains "$json_output" '"memory":'
assert_contains "$json_output" '"disk":'

if command -v jq >/dev/null 2>&1; then
    printf '%s\n' "$json_output" | jq -e '.public_ip == "disabled" and (.kernel_version | length > 0)' >/dev/null || fail "json validation failed"
fi

out_file=$(mktemp "${TMPDIR:-/tmp}/sysinfo-test-out.XXXXXX") || fail "unable to create output temp file"
err_file=$(mktemp "${TMPDIR:-/tmp}/sysinfo-test-err.XXXXXX") || fail "unable to create error temp file"

if sh "$SCRIPT" --timeout 0 --no-public-ip >"$out_file" 2>"$err_file"; then
    fail "timeout 0 should fail"
fi

timeout_error=$(cat "$err_file")
assert_contains "$timeout_error" "timeout must be greater than zero"

printf '%s\n' "test-system-info: ok"
