#!/bin/sh

set -u

SCRIPT=${SYSINFO_SCRIPT:-./system-info.sh}
fixture_dir=""

cleanup() {
    [ -n "$fixture_dir" ] && rm -rf "$fixture_dir"
}

fail() {
    printf 'test-fixtures: %s\n' "$1" >&2
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

write_executable() {
    path=$1
    content=$2

    printf '%s\n' "$content" > "$path" || fail "unable to write $path"
    chmod 0755 "$path" || fail "unable to chmod $path"
}

trap cleanup EXIT HUP INT TERM

fixture_dir=$(mktemp -d "${TMPDIR:-/tmp}/sysinfo-fixture.XXXXXX") || fail "unable to create fixture dir"
mkdir -p "$fixture_dir/etc" "$fixture_dir/proc/1" "$fixture_dir/proc/sys/kernel" "$fixture_dir/dmi" "$fixture_dir/bin" || fail "unable to create fixture layout"

cat > "$fixture_dir/etc/os-release" <<'EOF' || fail "unable to write os-release"
NAME="FixtureOS"
VERSION_ID="42.1"
ID=ubuntu
EOF

printf '%s\n' "Test/Zone" > "$fixture_dir/etc/timezone" || fail "unable to write timezone"
printf '%s\n' "systemd" > "$fixture_dir/proc/1/comm" || fail "unable to write pid1 comm"
printf '%s\n' "3661.00 10.00" > "$fixture_dir/proc/uptime" || fail "unable to write uptime"
printf '%s\n' "fixture-host" > "$fixture_dir/proc/sys/kernel/hostname" || fail "unable to write hostname"

cat > "$fixture_dir/proc/cpuinfo" <<'EOF' || fail "unable to write cpuinfo"
processor   : 0
model name  : Fixture CPU 9000
flags       : fpu vme de pse
EOF

cat > "$fixture_dir/proc/meminfo" <<'EOF' || fail "unable to write meminfo"
MemTotal:        1048576 kB
MemAvailable:     524288 kB
EOF

printf '%s\n' "Fixture Vendor" > "$fixture_dir/dmi/sys_vendor" || fail "unable to write dmi vendor"
printf '%s\n' "Fixture Machine" > "$fixture_dir/dmi/product_name" || fail "unable to write dmi product"
printf '%s\n' "Fixture BIOS" > "$fixture_dir/dmi/bios_vendor" || fail "unable to write dmi bios"

write_executable "$fixture_dir/bin/hostname" '#!/bin/sh
if [ "${1:-}" = "-I" ]; then
    printf "%s\n" "10.10.0.5"
else
    printf "%s\n" "fixture-host"
fi'

write_executable "$fixture_dir/bin/uname" '#!/bin/sh
case "${1:-}" in
    -s) printf "%s\n" "Linux" ;;
    -r) printf "%s\n" "6.5.0-fixture" ;;
    -m) printf "%s\n" "x86_64" ;;
    -n) printf "%s\n" "fixture-host" ;;
    *) printf "%s\n" "Linux" ;;
esac'

write_executable "$fixture_dir/bin/apt" '#!/bin/sh
case "${1:-}" in
    --version) printf "%s\n" "apt fixture"; exit 0 ;;
esac
exit 1'

write_executable "$fixture_dir/bin/systemd-detect-virt" '#!/bin/sh
printf "%s\n" "none"'

write_executable "$fixture_dir/bin/df" '#!/bin/sh
printf "%s\n" "Filesystem      Size  Used Avail Use% Mounted on"
printf "%s\n" "/dev/root        10G   4G    6G  40% /"'

fixture_path=$fixture_dir/bin:$PATH
fixture_output=$(
    PATH=$fixture_path \
    USER=fixtureuser \
    SYSINFO_PROC_DIR=$fixture_dir/proc \
    SYSINFO_ETC_DIR=$fixture_dir/etc \
    SYSINFO_DMI_DIR=$fixture_dir/dmi \
    SYSINFO_DOCKER_ENV_FILE=$fixture_dir/no-docker \
    sh "$SCRIPT" --plain --no-public-ip --resources
) || fail "fixture run failed"

assert_contains "$fixture_output" "FixtureOS 42.1 - Bare Metal"
assert_contains "$fixture_output" "Version:   42.1"
assert_contains "$fixture_output" "Kernel:    6.5.0-fixture"
assert_contains "$fixture_output" "Arch:      x86_64"
assert_contains "$fixture_output" "Hostname:  fixture-host"
assert_contains "$fixture_output" "User:      fixtureuser"
assert_contains "$fixture_output" "Packages:  apt"
assert_contains "$fixture_output" "Services:  systemd"
assert_contains "$fixture_output" "Timezone:  Test/Zone"
assert_contains "$fixture_output" "Uptime:    1 hour, 1 minute"
assert_contains "$fixture_output" "Local IP:  10.10.0.5"
assert_contains "$fixture_output" "Public IP: disabled"
assert_contains "$fixture_output" "CPU:       Fixture CPU 9000"
assert_contains "$fixture_output" "Memory:    512 MB / 1024 MB"
assert_contains "$fixture_output" "Disk:      4G / 10G (40%)"

printf '%s\n' "test-fixtures: ok"
