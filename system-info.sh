#!/bin/sh

VERSION="1.3.0"
PROGRAM_NAME=${0##*/}

COLOR_MODE="auto"
OUTPUT_MODE="pretty"
SHOW_PUBLIC_IP=1
REQUEST_TIMEOUT=2
AUTO_MODE=0

SHOW_CPU=0
SHOW_MEMORY=0
SHOW_DISK=0

COLOR_HEADER=""
COLOR_LABEL=""
COLOR_VALUE=""
COLOR_RESET=""
UNICODE_MODE=0

OS_NAME=""
OS_VERSION=""
KERNEL_VERSION=""
ARCHITECTURE=""
ENVIRONMENT_NAME=""
HOSTNAME_VALUE=""
USER_VALUE=""
PACKAGE_MANAGERS=""
INIT_SYSTEM=""
TIMEZONE_VALUE=""
UPTIME_VALUE=""
LOCAL_IP=""
PUBLIC_IP=""
CPU_VALUE=""
MEMORY_VALUE=""
DISK_VALUE=""

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

safe_cat() {
    if [ -r "$1" ]; then
        cat "$1" 2>/dev/null
    fi
}

normalize_line() {
    printf '%s' "$1" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

probe_command() {
    "$@" >/dev/null 2>&1
}

append_csv() {
    if [ -n "$1" ]; then
        printf '%s, %s' "$1" "$2"
    else
        printf '%s' "$2"
    fi
}

plural_suffix() {
    if [ "$1" -eq 1 ]; then
        printf '%s' ""
    else
        printf '%s' "s"
    fi
}

append_json_field() {
    key=$1
    value=$2

    if [ -n "$JSON_FIELDS" ]; then
        JSON_FIELDS=$(printf '%s,\n  "%s": "%s"' "$JSON_FIELDS" "$key" "$(json_escape "$value")")
    else
        JSON_FIELDS=$(printf '  "%s": "%s"' "$key" "$(json_escape "$value")")
    fi
}

use_color() {
    case "$COLOR_MODE" in
        always) return 0 ;;
        never) return 1 ;;
        auto)
            [ -t 1 ] || return 1
            [ "${TERM:-}" != "dumb" ]
            ;;
        *)
            return 1
            ;;
    esac
}

use_unicode() {
    case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
        *UTF-8*|*utf8*|*UTF8*) return 0 ;;
        *) return 1 ;;
    esac
}

configure_output() {
    if use_color; then
        COLOR_HEADER=$(printf '\033[1;38;5;230m')
        COLOR_LABEL=$(printf '\033[38;5;179m')
        COLOR_VALUE=$(printf '\033[1;38;5;114m')
        COLOR_RESET=$(printf '\033[0m')
    else
        COLOR_HEADER=""
        COLOR_LABEL=""
        COLOR_VALUE=""
        COLOR_RESET=""
    fi

    if use_unicode && [ "$OUTPUT_MODE" = "pretty" ]; then
        UNICODE_MODE=1
    else
        UNICODE_MODE=0
    fi
}

fail() {
    printf '%s: %s\n' "$PROGRAM_NAME" "$1" >&2
    exit 1
}

show_help() {
    printf '%s\n' \
        "Usage: $PROGRAM_NAME [options]" \
        "" \
        "Display a compact system summary for terminals and login shells." \
        "" \
        "Options:" \
        "  --auto              Suppress output when the current shell is not interactive" \
        "  --plain             Disable colors and icons" \
        "  --json              Print the collected data as JSON" \
        "  --color             Force ANSI colors" \
        "  --no-color          Disable ANSI colors" \
        "  --cpu               Include CPU model" \
        "  --memory            Include memory usage" \
        "  --disk              Include root disk usage" \
        "  --resources         Include CPU, memory, and disk" \
        "  --no-public-ip      Skip public IP discovery" \
        "  --timeout SECONDS   Network timeout for public IP lookup (default: 2)" \
        "  -h, --help          Show this help text" \
        "  -v, --version       Show the script version"
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --auto)
                AUTO_MODE=1
                ;;
            --plain)
                OUTPUT_MODE="plain"
                COLOR_MODE="never"
                ;;
            --json)
                OUTPUT_MODE="json"
                COLOR_MODE="never"
                ;;
            --no-color)
                COLOR_MODE="never"
                ;;
            --color)
                COLOR_MODE="always"
                ;;
            --cpu)
                SHOW_CPU=1
                ;;
            --memory)
                SHOW_MEMORY=1
                ;;
            --disk)
                SHOW_DISK=1
                ;;
            --resources)
                SHOW_CPU=1
                SHOW_MEMORY=1
                SHOW_DISK=1
                ;;
            --no-public-ip)
                SHOW_PUBLIC_IP=0
                ;;
            --timeout)
                shift
                [ $# -gt 0 ] || fail "missing value for --timeout"
                REQUEST_TIMEOUT=$1
                ;;
            --timeout=*)
                REQUEST_TIMEOUT=${1#*=}
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--version)
                printf '%s\n' "$VERSION"
                exit 0
                ;;
            *)
                fail "unknown option: $1"
                ;;
        esac
        shift
    done

    case "$REQUEST_TIMEOUT" in
        ''|*[!0-9]*)
            fail "timeout must be an integer"
            ;;
    esac
}

should_render() {
    if [ "$AUTO_MODE" -eq 1 ] || [ "${SYSINFO_LOGIN_HOOK:-0}" = "1" ]; then
        case "$-" in
            *i*) return 0 ;;
        esac
        [ -t 1 ] || return 1
    fi
    return 0
}

http_get() {
    if command_exists curl; then
        curl -fsSL --connect-timeout "$REQUEST_TIMEOUT" --max-time "$REQUEST_TIMEOUT" "$1" 2>/dev/null
        return $?
    fi

    if command_exists wget; then
        wget -q -T "$REQUEST_TIMEOUT" -O- "$1" 2>/dev/null
        return $?
    fi

    return 1
}

is_ip_address() {
    case "$1" in
        ''|*[!0-9A-Fa-f:.]*)
            return 1
            ;;
        *:*|*.*.*.*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

get_environment() {
    virt_type=""
    dmi_vendor=""
    dmi_product=""
    bios_vendor=""

    [ -f /.dockerenv ] && {
        printf '%s\n' "Docker"
        return
    }

    case "${container:-}" in
        lxc) printf '%s\n' "LXC"; return ;;
        docker) printf '%s\n' "Docker"; return ;;
        systemd-nspawn) printf '%s\n' "systemd-nspawn"; return ;;
        '') ;;
        *)
            printf 'Container (%s)\n' "$container"
            return
            ;;
    esac

    if [ -f /proc/1/environ ] && grep -q "container=lxc" /proc/1/environ 2>/dev/null; then
        printf '%s\n' "LXC"
        return
    fi

    if [ -f /proc/1/cgroup ]; then
        if grep -q "/lxc/" /proc/1/cgroup 2>/dev/null; then
            printf '%s\n' "LXC"
            return
        fi
        if grep -q "docker" /proc/1/cgroup 2>/dev/null; then
            printf '%s\n' "Docker"
            return
        fi
    fi

    if command_exists systemd-detect-virt; then
        virt_type=$(normalize_line "$(systemd-detect-virt 2>/dev/null)")
        case "$virt_type" in
            ''|none) ;;
            lxc) printf '%s\n' "LXC"; return ;;
            docker) printf '%s\n' "Docker"; return ;;
            systemd-nspawn) printf '%s\n' "systemd-nspawn"; return ;;
            kvm|qemu) printf '%s\n' "VM (KVM/QEMU)"; return ;;
            vmware) printf '%s\n' "VM (VMware)"; return ;;
            virtualbox|oracle) printf '%s\n' "VM (VirtualBox)"; return ;;
            xen) printf '%s\n' "VM (Xen)"; return ;;
            microsoft) printf '%s\n' "VM (Hyper-V)"; return ;;
            *)
                printf 'VM (%s)\n' "$virt_type"
                return
                ;;
        esac
    fi

    dmi_vendor=$(safe_cat /sys/class/dmi/id/sys_vendor)
    dmi_product=$(safe_cat /sys/class/dmi/id/product_name)
    bios_vendor=$(safe_cat /sys/class/dmi/id/bios_vendor)

    case "$dmi_vendor $dmi_product $bios_vendor" in
        *QEMU*|*Bochs*)
            printf '%s\n' "VM (QEMU)"
            return
            ;;
        *VMware*)
            printf '%s\n' "VM (VMware)"
            return
            ;;
        *VirtualBox*|*innotek*)
            printf '%s\n' "VM (VirtualBox)"
            return
            ;;
        *Microsoft*Virtual*|*Hyper-V*)
            printf '%s\n' "VM (Hyper-V)"
            return
            ;;
        *Xen*)
            printf '%s\n' "VM (Xen)"
            return
            ;;
        *KVM*)
            printf '%s\n' "VM (KVM)"
            return
            ;;
    esac

    if [ -f /proc/cpuinfo ] && grep -q "^flags.*hypervisor" /proc/cpuinfo 2>/dev/null; then
        printf '%s\n' "VM (Unknown)"
        return
    fi

    if [ -d /proc/xen ]; then
        printf '%s\n' "VM (Xen)"
        return
    fi

    printf '%s\n' "Bare Metal"
}

get_hostname() {
    if command_exists hostname; then
        hostname 2>/dev/null && return
    fi

    safe_cat /proc/sys/kernel/hostname && return
    safe_cat /etc/hostname && return

    uname -n 2>/dev/null || printf '%s\n' "unknown"
}

get_pkg_mgr() {
    pkg_list=""
    os_id=""

    if command_exists apt && probe_command apt --version; then
        pkg_list=$(append_csv "$pkg_list" "apt")
    fi
    if command_exists nala && probe_command nala --version; then
        pkg_list=$(append_csv "$pkg_list" "nala")
    fi
    if command_exists flatpak && probe_command flatpak --version; then
        pkg_list=$(append_csv "$pkg_list" "flatpak")
    fi
    if command_exists snap && probe_command snap version; then
        pkg_list=$(append_csv "$pkg_list" "snap")
    fi
    if command_exists opkg && probe_command opkg --version; then
        pkg_list=$(append_csv "$pkg_list" "opkg")
    fi
    if command_exists brew && probe_command brew --version; then
        pkg_list=$(append_csv "$pkg_list" "brew")
    fi
    if command_exists dnf && probe_command dnf --version; then
        pkg_list=$(append_csv "$pkg_list" "dnf")
    fi
    if command_exists yum && probe_command yum --version; then
        pkg_list=$(append_csv "$pkg_list" "yum")
    fi
    if command_exists zypper && probe_command zypper --version; then
        pkg_list=$(append_csv "$pkg_list" "zypper")
    fi
    if command_exists pacman && probe_command pacman --version; then
        pkg_list=$(append_csv "$pkg_list" "pacman")
    fi
    if command_exists apk && probe_command apk --version; then
        pkg_list=$(append_csv "$pkg_list" "apk")
    fi
    if command_exists emerge && probe_command emerge --version; then
        pkg_list=$(append_csv "$pkg_list" "emerge")
    fi
    if command_exists xbps-install && probe_command xbps-install --version; then
        pkg_list=$(append_csv "$pkg_list" "xbps")
    fi
    if command_exists nix-env && probe_command nix-env --version; then
        pkg_list=$(append_csv "$pkg_list" "nix")
    fi
    if command_exists eopkg && probe_command eopkg --version; then
        pkg_list=$(append_csv "$pkg_list" "eopkg")
    fi
    if command_exists swupd && probe_command swupd --version; then
        pkg_list=$(append_csv "$pkg_list" "swupd")
    fi
    if command_exists installpkg; then
        pkg_list=$(append_csv "$pkg_list" "installpkg")
    fi
    if command_exists urpmi && probe_command urpmi --version; then
        pkg_list=$(append_csv "$pkg_list" "urpmi")
    fi
    if command_exists guix && probe_command guix --version; then
        pkg_list=$(append_csv "$pkg_list" "guix")
    fi
    if command_exists microdnf && probe_command microdnf --help; then
        pkg_list=$(append_csv "$pkg_list" "microdnf")
    fi

    if [ -n "$pkg_list" ]; then
        printf '%s\n' "$pkg_list"
        return
    fi

    if [ -f /etc/os-release ]; then
        os_id=$(normalize_line "$(grep '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')")
        case "$os_id" in
            ubuntu|debian|linuxmint|mint|kali|pop|elementary|zorin|mx|deepin|parrot|tails|raspbian|devuan)
                printf '%s\n' "apt (expected)"
                ;;
            fedora|rhel|centos|rocky|almalinux|alma|oracle|ol|scientific|amzn|amazonlinux)
                printf '%s\n' "dnf/yum (expected)"
                ;;
            opensuse*|sles|sled)
                printf '%s\n' "zypper (expected)"
                ;;
            arch|manjaro|endeavouros|artix|garuda|blackarch)
                printf '%s\n' "pacman (expected)"
                ;;
            alpine|postmarketos)
                printf '%s\n' "apk (expected)"
                ;;
            gentoo|funtoo|calculate|sabayon)
                printf '%s\n' "emerge (expected)"
                ;;
            void)
                printf '%s\n' "xbps (expected)"
                ;;
            openwrt)
                printf '%s\n' "opkg (expected)"
                ;;
            nixos)
                printf '%s\n' "nix (expected)"
                ;;
            solus)
                printf '%s\n' "eopkg (expected)"
                ;;
            *)
                printf '%s\n' "unknown"
                ;;
        esac
        return
    fi

    printf '%s\n' "unknown"
}

get_init_system() {
    pid1=""

    if [ "$(uname -s 2>/dev/null)" = "Darwin" ]; then
        printf '%s\n' "launchd"
        return
    fi

    if command_exists systemctl && probe_command systemctl --version; then
        printf '%s\n' "systemd"
        return
    fi

    if [ -x /sbin/openrc ] || command_exists rc-service; then
        printf '%s\n' "openrc"
        return
    fi

    if command_exists service; then
        printf '%s\n' "service"
        return
    fi

    if [ -x /usr/bin/runsv ] || [ -x /bin/runsv ] || [ -x /sbin/runsv ]; then
        printf '%s\n' "runit"
        return
    fi

    pid1=$(safe_cat /proc/1/comm)
    case "$pid1" in
        systemd) printf '%s\n' "systemd" ;;
        *init) printf '%s\n' "sysvinit" ;;
        '') printf '%s\n' "unknown" ;;
        *) printf '%s\n' "$pid1" ;;
    esac
}

get_timezone() {
    timezone_value=""

    timezone_value=$(normalize_line "$(safe_cat /etc/timezone)")
    if [ -n "$timezone_value" ]; then
        printf '%s\n' "$timezone_value"
        return
    fi

    if [ -f /etc/config/system ]; then
        timezone_value=$(normalize_line "$(grep "option zonename" /etc/config/system 2>/dev/null | awk -F"'" '{print $2}')")
        if [ -n "$timezone_value" ]; then
            printf '%s\n' "$timezone_value"
            return
        fi
    fi

    if [ -L /etc/localtime ]; then
        timezone_value=$(readlink /etc/localtime 2>/dev/null | sed 's|.*/zoneinfo/||')
        timezone_value=$(normalize_line "$timezone_value")
        if [ -n "$timezone_value" ]; then
            printf '%s\n' "$timezone_value"
            return
        fi
    fi

    if command_exists timedatectl; then
        timezone_value=$(normalize_line "$(timedatectl show --property=Timezone --value 2>/dev/null)")
        if [ -n "$timezone_value" ]; then
            printf '%s\n' "$timezone_value"
            return
        fi
    fi

    if [ "$(uname -s 2>/dev/null)" = "Darwin" ] && command_exists systemsetup; then
        timezone_value=$(normalize_line "$(systemsetup -gettimezone 2>/dev/null | sed 's/^Time Zone: //')")
        if [ -n "$timezone_value" ]; then
            printf '%s\n' "$timezone_value"
            return
        fi
    fi

    timezone_value=$(normalize_line "$(date +%Z 2>/dev/null)")
    if [ -n "$timezone_value" ]; then
        printf '%s\n' "$timezone_value"
        return
    fi

    printf '%s\n' "${TZ:-UTC}"
}

get_local_ip() {
    ip_value=""
    route_iface=""
    interfaces=""
    iface=""

    if command_exists hostname; then
        ip_value=$(normalize_line "$(hostname -I 2>/dev/null | awk '{print $1}')")
        case "$ip_value" in
            ''|127.*) ;;
            *)
                printf '%s\n' "$ip_value"
                return
                ;;
        esac
    fi

    if command_exists ip; then
        ip_value=$(normalize_line "$(ip -4 route get 1.1.1.1 2>/dev/null | awk '/src/ {for (i = 1; i <= NF; i++) if ($i == "src") {print $(i + 1); exit}}')")
        if [ -n "$ip_value" ]; then
            printf '%s\n' "$ip_value"
            return
        fi

        ip_value=$(normalize_line "$(ip -4 addr show scope global 2>/dev/null | awk '/inet / {split($2, a, "/"); print a[1]; exit}')")
        if [ -n "$ip_value" ]; then
            printf '%s\n' "$ip_value"
            return
        fi
    fi

    if [ "$(uname -s 2>/dev/null)" = "Darwin" ] && command_exists route && command_exists ipconfig; then
        route_iface=$(normalize_line "$(route get default 2>/dev/null | awk '/interface:/ {print $2; exit}')")
        if [ -n "$route_iface" ]; then
            ip_value=$(normalize_line "$(ipconfig getifaddr "$route_iface" 2>/dev/null)")
            if [ -n "$ip_value" ]; then
                printf '%s\n' "$ip_value"
                return
            fi
        fi
    fi

    if command_exists ifconfig; then
        interfaces=$(ifconfig -a 2>/dev/null | awk -F: '/^[[:alnum:]_.-]+:/ {print $1}')
        for iface in $interfaces; do
            case "$iface" in
                lo|lo0) continue ;;
            esac

            ip_value=$(normalize_line "$(ifconfig "$iface" 2>/dev/null | awk '/inet / && $2 != "127.0.0.1" {print $2; exit}')")
            if [ -n "$ip_value" ]; then
                printf '%s\n' "$ip_value"
                return
            fi
        done
    fi

    printf '%s\n' "unavailable"
}

get_public_ip() {
    ip_value=""
    service_url=""

    if [ "$SHOW_PUBLIC_IP" -ne 1 ]; then
        printf '%s\n' "disabled"
        return
    fi

    if ! command_exists curl && ! command_exists wget; then
        printf '%s\n' "curl/wget needed"
        return
    fi

    for service_url in \
        "https://api.ipify.org" \
        "https://ifconfig.io/ip" \
        "https://ipinfo.io/ip"
    do
        ip_value=$(normalize_line "$(http_get "$service_url")")
        if is_ip_address "$ip_value"; then
            printf '%s\n' "$ip_value"
            return
        fi
    done

    printf '%s\n' "network unavailable"
}

get_os_name() {
    if [ -f /etc/os-release ]; then
        normalize_line "$(grep '^NAME=' /etc/os-release | cut -d= -f2 | tr -d '"')"
        return
    fi

    if [ "$(uname -s 2>/dev/null)" = "Darwin" ] && command_exists sw_vers; then
        normalize_line "$(sw_vers -productName 2>/dev/null)"
        return
    fi

    if command_exists busybox; then
        printf '%s\n' "BusyBox"
        return
    fi

    uname -s 2>/dev/null || printf '%s\n' "Unknown"
}

get_os_version() {
    version_id=""
    pretty_name=""

    if [ -f /etc/os-release ]; then
        version_id=$(normalize_line "$(grep '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '"')")
        if [ -n "$version_id" ]; then
            printf '%s\n' "$version_id"
            return
        fi

        pretty_name=$(normalize_line "$(grep '^VERSION=' /etc/os-release | cut -d= -f2 | tr -d '"')")
        if [ -n "$pretty_name" ]; then
            printf '%s\n' "$pretty_name"
            return
        fi
    fi

    if [ "$(uname -s 2>/dev/null)" = "Darwin" ] && command_exists sw_vers; then
        normalize_line "$(sw_vers -productVersion 2>/dev/null)"
        return
    fi

    uname -r 2>/dev/null || printf '%s\n' "Unknown"
}

get_kernel_version() {
    uname -r 2>/dev/null || printf '%s\n' "Unknown"
}

get_architecture() {
    uname -m 2>/dev/null || printf '%s\n' "Unknown"
}

get_user_name() {
    if [ -n "${USER:-}" ]; then
        printf '%s\n' "$USER"
        return
    fi

    if command_exists id; then
        id -un 2>/dev/null && return
    fi

    printf '%s\n' "unknown"
}

get_uptime() {
    uptime_seconds=""
    days=0
    hours=0
    minutes=0
    parts=""

    if [ -r /proc/uptime ]; then
        uptime_seconds=$(awk '{print int($1)}' /proc/uptime 2>/dev/null)
    elif command_exists uptime; then
        uptime_value=$(uptime 2>/dev/null | awk -F'up ' 'NF > 1 {print $2}' | awk -F',' '{print $1}')
        if [ -n "$uptime_value" ]; then
            normalize_line "$uptime_value"
            return
        fi
    fi

    case "$uptime_seconds" in
        ''|*[!0-9]*)
            printf '%s\n' "unknown"
            return
            ;;
    esac

    days=$((uptime_seconds / 86400))
    hours=$(((uptime_seconds % 86400) / 3600))
    minutes=$(((uptime_seconds % 3600) / 60))

    if [ "$days" -gt 0 ]; then
        parts=$(append_csv "$parts" "$days day$(plural_suffix "$days")")
    fi
    if [ "$hours" -gt 0 ]; then
        parts=$(append_csv "$parts" "$hours hour$(plural_suffix "$hours")")
    fi
    if [ "$minutes" -gt 0 ] || [ -z "$parts" ]; then
        parts=$(append_csv "$parts" "$minutes minute$(plural_suffix "$minutes")")
    fi

    printf '%s\n' "$parts"
}

get_cpu_info() {
    cpu_value=""

    if [ -f /proc/cpuinfo ]; then
        cpu_value=$(normalize_line "$(awk -F: '/model name/ {print $2; exit}' /proc/cpuinfo 2>/dev/null)")
        [ -n "$cpu_value" ] && {
            printf '%s\n' "$cpu_value"
            return
        }
    fi

    if [ "$(uname -s 2>/dev/null)" = "Darwin" ] && command_exists sysctl; then
        cpu_value=$(normalize_line "$(sysctl -n machdep.cpu.brand_string 2>/dev/null)")
        [ -n "$cpu_value" ] && {
            printf '%s\n' "$cpu_value"
            return
        }
    fi

    printf '%s\n' "unavailable"
}

get_memory_info() {
    total_kb=""
    available_kb=""
    used_mb=0
    total_mb=0

    if [ -f /proc/meminfo ]; then
        total_kb=$(awk '/MemTotal:/ {print $2; exit}' /proc/meminfo 2>/dev/null)
        available_kb=$(awk '/MemAvailable:/ {print $2; exit}' /proc/meminfo 2>/dev/null)
        [ -z "$available_kb" ] && available_kb=$(awk '/MemFree:/ {print $2; exit}' /proc/meminfo 2>/dev/null)

        case "$total_kb" in
            ''|*[!0-9]*)
                ;;
            *)
                case "$available_kb" in
                    ''|*[!0-9]*)
                        ;;
                    *)
                        total_mb=$((total_kb / 1024))
                        used_mb=$(((total_kb - available_kb) / 1024))
                        printf '%s\n' "$used_mb MB / $total_mb MB"
                        return
                        ;;
                esac
                ;;
        esac
    fi

    if command_exists free; then
        memory_line=$(free -m 2>/dev/null | awk '/^Mem:/ {print $3 " MB / " $2 " MB"; exit}')
        [ -n "$memory_line" ] && {
            printf '%s\n' "$memory_line"
            return
        }
    fi

    printf '%s\n' "unavailable"
}

get_disk_info() {
    disk_line=""

    if command_exists df; then
        disk_line=$(df -h / 2>/dev/null | awk 'NR == 2 {print $3 " / " $2 " (" $5 ")"; exit}')
        [ -n "$disk_line" ] && {
            printf '%s\n' "$disk_line"
            return
        }
    fi

    printf '%s\n' "unavailable"
}

collect_system_info() {
    OS_NAME=$(get_os_name)
    OS_VERSION=$(get_os_version)
    KERNEL_VERSION=$(get_kernel_version)
    ARCHITECTURE=$(get_architecture)
    ENVIRONMENT_NAME=$(get_environment)
    HOSTNAME_VALUE=$(get_hostname)
    USER_VALUE=$(get_user_name)
    PACKAGE_MANAGERS=$(get_pkg_mgr)
    INIT_SYSTEM=$(get_init_system)
    TIMEZONE_VALUE=$(get_timezone)
    UPTIME_VALUE=$(get_uptime)
    LOCAL_IP=$(get_local_ip)
    PUBLIC_IP=$(get_public_ip)

    if [ "$SHOW_CPU" -eq 1 ]; then
        CPU_VALUE=$(get_cpu_info)
    fi
    if [ "$SHOW_MEMORY" -eq 1 ]; then
        MEMORY_VALUE=$(get_memory_info)
    fi
    if [ "$SHOW_DISK" -eq 1 ]; then
        DISK_VALUE=$(get_disk_info)
    fi
}

json_escape() {
    printf '%s' "$1" | tr -d '\r\n' | sed 's/\\/\\\\/g; s/"/\\"/g'
}

field_icon() {
    label=$1

    if [ "$UNICODE_MODE" -ne 1 ]; then
        printf '%s' "-"
        return
    fi

    case "$label" in
        Version) printf '%s' "💻" ;;
        Kernel) printf '%s' "🧩" ;;
        Arch) printf '%s' "🏗️" ;;
        Hostname) printf '%s' "🏠" ;;
        User) printf '%s' "👤" ;;
        Packages) printf '%s' "📦" ;;
        Services) printf '%s' "📋" ;;
        Timezone) printf '%s' "🕐" ;;
        Uptime) printf '%s' "⏳" ;;
        Local\ IP) printf '%s' "📍" ;;
        Public\ IP) printf '%s' "🌍" ;;
        CPU) printf '%s' "🧠" ;;
        Memory) printf '%s' "🧮" ;;
        Disk) printf '%s' "💽" ;;
        *) printf '%s' "•" ;;
    esac
}

print_field() {
    label=$1
    value=$2
    icon=$(field_icon "$label")

    if [ "$OUTPUT_MODE" = "plain" ]; then
        printf '  %-10s %s\n' "$label:" "$value"
        return
    fi

    printf '  %b%s%b %-10s %b%s%b\n' \
        "$COLOR_LABEL" "$icon" "$COLOR_RESET" \
        "$label:" \
        "$COLOR_VALUE" "$value" "$COLOR_RESET"
}

render_pretty() {
    header="$OS_NAME"

    if [ -n "$OS_VERSION" ]; then
        header="$header $OS_VERSION"
    fi
    if [ -n "$ENVIRONMENT_NAME" ]; then
        header="$header - $ENVIRONMENT_NAME"
    fi

    if [ "$OUTPUT_MODE" = "plain" ]; then
        printf '%s\n' "$header"
    else
        printf '\n%b%s%b\n' "$COLOR_HEADER" "$header" "$COLOR_RESET"
    fi

    print_field "Version" "$OS_VERSION"
    print_field "Kernel" "$KERNEL_VERSION"
    print_field "Arch" "$ARCHITECTURE"
    print_field "Hostname" "$HOSTNAME_VALUE"
    print_field "User" "$USER_VALUE"
    print_field "Packages" "$PACKAGE_MANAGERS"
    print_field "Services" "$INIT_SYSTEM"
    print_field "Timezone" "$TIMEZONE_VALUE"
    print_field "Uptime" "$UPTIME_VALUE"
    print_field "Local IP" "$LOCAL_IP"
    print_field "Public IP" "$PUBLIC_IP"

    if [ "$SHOW_CPU" -eq 1 ]; then
        print_field "CPU" "$CPU_VALUE"
    fi
    if [ "$SHOW_MEMORY" -eq 1 ]; then
        print_field "Memory" "$MEMORY_VALUE"
    fi
    if [ "$SHOW_DISK" -eq 1 ]; then
        print_field "Disk" "$DISK_VALUE"
    fi

    printf '\n'
}

render_json() {
    JSON_FIELDS=""

    append_json_field "os_name" "$OS_NAME"
    append_json_field "os_version" "$OS_VERSION"
    append_json_field "kernel_version" "$KERNEL_VERSION"
    append_json_field "architecture" "$ARCHITECTURE"
    append_json_field "environment" "$ENVIRONMENT_NAME"
    append_json_field "hostname" "$HOSTNAME_VALUE"
    append_json_field "user" "$USER_VALUE"
    append_json_field "package_managers" "$PACKAGE_MANAGERS"
    append_json_field "init_system" "$INIT_SYSTEM"
    append_json_field "timezone" "$TIMEZONE_VALUE"
    append_json_field "uptime" "$UPTIME_VALUE"
    append_json_field "local_ip" "$LOCAL_IP"
    append_json_field "public_ip" "$PUBLIC_IP"

    if [ "$SHOW_CPU" -eq 1 ]; then
        append_json_field "cpu" "$CPU_VALUE"
    fi
    if [ "$SHOW_MEMORY" -eq 1 ]; then
        append_json_field "memory" "$MEMORY_VALUE"
    fi
    if [ "$SHOW_DISK" -eq 1 ]; then
        append_json_field "disk" "$DISK_VALUE"
    fi

    printf '{\n%s\n}\n' "$JSON_FIELDS"
}

main() {
    parse_args "$@"

    should_render || exit 0

    configure_output
    collect_system_info

    if [ "$OUTPUT_MODE" = "json" ]; then
        render_json
    else
        render_pretty
    fi
}

main "$@"
