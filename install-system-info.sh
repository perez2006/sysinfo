#!/bin/sh

PROGRAM_NAME=${0##*/}

REPO_OWNER="${SYSINFO_REPO_OWNER:-perez2006}"
REPO_NAME="${SYSINFO_REPO_NAME:-sysinfo}"
REPO_BRANCH="${SYSINFO_REPO_BRANCH:-main}"
RAW_BASE_URL="${SYSINFO_RAW_BASE_URL:-https://raw.githubusercontent.com/$REPO_OWNER/$REPO_NAME/$REPO_BRANCH}"
SCRIPT_URL="$RAW_BASE_URL/system-info.sh"

SYSTEM_BIN_PATH="/usr/local/bin/sysinfo"
SYSTEM_PROFILE_PATH="/etc/profile.d/01-sysinfo.sh"
USER_BIN_PATH="${HOME}/.local/bin/sysinfo"
USER_PROFILE_PATH="${HOME}/.profile"

MODE=""
SCOPE="auto"
TEMP_DIR=""
INSTALLED_BIN_PATH=""
INSTALLED_SCOPE=""

RED=$(printf '\033[0;31m')
GREEN=$(printf '\033[0;32m')
YELLOW=$(printf '\033[1;33m')
CYAN=$(printf '\033[0;36m')
WHITE=$(printf '\033[1;37m')
GRAY=$(printf '\033[0;90m')
NC=$(printf '\033[0m')

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

say() {
    printf '%b%s%b\n' "$1" "$2" "$NC"
}

show_success() {
    say "$GREEN" "✓ $1"
}

show_error() {
    say "$RED" "✗ $1"
}

show_info() {
    say "$CYAN" "• $1"
}

show_warn() {
    say "$YELLOW" "! $1"
}

show_help() {
    printf '%s\n' \
        "Usage: $PROGRAM_NAME [options]" \
        "" \
        "Options:" \
        "  --quick-test     Run the script once without installing it" \
        "  --command-tool   Install sysinfo as a command" \
        "  --auto-start     Install sysinfo and run it on login" \
        "  --user           Force user-scope install (~/.local/bin)" \
        "  --system         Force system-scope install (/usr/local/bin)" \
        "  -h, --help       Show this help text" \
        "" \
        "Environment overrides:" \
        "  SYSINFO_REPO_OWNER" \
        "  SYSINFO_REPO_NAME" \
        "  SYSINFO_REPO_BRANCH" \
        "  SYSINFO_RAW_BASE_URL"
}

cleanup() {
    [ -n "$TEMP_DIR" ] && rm -rf "$TEMP_DIR" 2>/dev/null
}

make_temp_dir() {
    TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/sysinfo.XXXXXX" 2>/dev/null)
    [ -n "$TEMP_DIR" ] || {
        show_error "Unable to create a temporary directory"
        exit 1
    }
}

download_file() {
    output_file=$1

    if command_exists curl; then
        curl -fsSL "$SCRIPT_URL" -o "$output_file" 2>/dev/null && return 0
    fi

    if command_exists wget; then
        wget -q "$SCRIPT_URL" -O "$output_file" 2>/dev/null && return 0
    fi

    return 1
}

run_privileged() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
        return $?
    fi

    sudo "$@"
}

ensure_system_access() {
    if [ "$(id -u)" -eq 0 ]; then
        return 0
    fi

    if command_exists sudo; then
        return 0
    fi

    show_error "System install requires root or sudo"
    return 1
}

resolve_scope() {
    case "$1" in
        user|system)
            printf '%s\n' "$1"
            ;;
        auto)
            if [ "$(id -u)" -eq 0 ] || command_exists sudo; then
                printf '%s\n' "system"
            else
                printf '%s\n' "user"
            fi
            ;;
        *)
            show_error "Unknown install scope: $1"
            return 1
            ;;
    esac
}

copy_executable() {
    src=$1
    dest=$2
    scope=$3
    dest_dir=$(dirname "$dest")

    if [ "$scope" = "system" ]; then
        ensure_system_access || return 1
        run_privileged mkdir -p "$dest_dir" || return 1

        if command_exists install; then
            run_privileged install -m 0755 "$src" "$dest" || return 1
        else
            run_privileged cp "$src" "$dest" || return 1
            run_privileged chmod 0755 "$dest" || return 1
        fi
        return 0
    fi

    mkdir -p "$dest_dir" || return 1
    cp "$src" "$dest" || return 1
    chmod 0755 "$dest" || return 1
}

write_system_profile_hook() {
    hook_file="$TEMP_DIR/profile-hook.sh"

    {
        printf '%s\n' "#!/bin/sh"
        printf 'if [ -x "%s" ]; then\n' "$SYSTEM_BIN_PATH"
        printf '    SYSINFO_LOGIN_HOOK=1 "%s" --auto\n' "$SYSTEM_BIN_PATH"
        printf '%s\n' "fi"
    } > "$hook_file"

    ensure_system_access || return 1
    run_privileged mkdir -p "$(dirname "$SYSTEM_PROFILE_PATH")" || return 1

    if command_exists install; then
        run_privileged install -m 0644 "$hook_file" "$SYSTEM_PROFILE_PATH" || return 1
    else
        run_privileged cp "$hook_file" "$SYSTEM_PROFILE_PATH" || return 1
        run_privileged chmod 0644 "$SYSTEM_PROFILE_PATH" || return 1
    fi
}

write_user_profile_hook() {
    marker_begin="# >>> sysinfo auto-start >>>"
    marker_end="# <<< sysinfo auto-start <<<"

    if [ -f "$USER_PROFILE_PATH" ] && grep -qF "$marker_begin" "$USER_PROFILE_PATH" 2>/dev/null; then
        show_success "Auto-start already configured in $USER_PROFILE_PATH"
        return 0
    fi

    {
        printf '\n%s\n' "$marker_begin"
        printf 'if [ -x "%s" ]; then\n' "$USER_BIN_PATH"
        printf '    SYSINFO_LOGIN_HOOK=1 "%s" --auto\n' "$USER_BIN_PATH"
        printf 'fi\n'
        printf '%s\n' "$marker_end"
    } >> "$USER_PROFILE_PATH" || return 1
}

warn_about_user_path() {
    case ":${PATH:-}:" in
        *":$HOME/.local/bin:"*)
            ;;
        *)
            show_warn "Add $HOME/.local/bin to PATH if 'sysinfo' is not found in new shells"
            ;;
    esac
}

download_script_to_temp() {
    temp_script="$TEMP_DIR/system-info.sh"

    if ! download_file "$temp_script"; then
        show_error "Failed to download $SCRIPT_URL"
        return 1
    fi

    chmod 0755 "$temp_script" 2>/dev/null || true
    printf '%s\n' "$temp_script"
}

install_command_tool_with_scope() {
    scope=$1
    temp_script=$(download_script_to_temp) || return 1

    case "$scope" in
        system)
            target_path=$SYSTEM_BIN_PATH
            ;;
        user)
            target_path=$USER_BIN_PATH
            ;;
        *)
            show_error "Unknown install scope: $scope"
            return 1
            ;;
    esac

    if copy_executable "$temp_script" "$target_path" "$scope"; then
        INSTALLED_BIN_PATH=$target_path
        INSTALLED_SCOPE=$scope
        show_success "Installed sysinfo to $target_path"
        if [ "$scope" = "user" ]; then
            warn_about_user_path
        fi
        return 0
    fi

    show_error "Installation failed for $target_path"
    return 1
}

ensure_command_tool() {
    scope=$1

    case "$scope" in
        system)
            if [ -x "$SYSTEM_BIN_PATH" ]; then
                INSTALLED_BIN_PATH=$SYSTEM_BIN_PATH
                INSTALLED_SCOPE="system"
                return 0
            fi
            ;;
        user)
            if [ -x "$USER_BIN_PATH" ]; then
                INSTALLED_BIN_PATH=$USER_BIN_PATH
                INSTALLED_SCOPE="user"
                return 0
            fi
            ;;
    esac

    install_command_tool_with_scope "$scope"
}

install_quick_test() {
    temp_script=$(download_script_to_temp) || return 1
    show_info "Running sysinfo without installing"
    sh "$temp_script"
}

install_command_tool() {
    scope=$(resolve_scope "$SCOPE") || return 1
    install_command_tool_with_scope "$scope" || return 1
    printf '\n'
    "$INSTALLED_BIN_PATH" --plain 2>/dev/null || true
}

install_auto_start() {
    scope=$(resolve_scope "$SCOPE") || return 1

    ensure_command_tool "$scope" || return 1

    if [ "$scope" = "system" ]; then
        if write_system_profile_hook; then
            show_success "Auto-start installed at $SYSTEM_PROFILE_PATH"
            show_info "It will run for interactive login shells"
        else
            show_error "Failed to install system profile hook"
            return 1
        fi
    else
        if write_user_profile_hook; then
            show_success "Auto-start configured in $USER_PROFILE_PATH"
            show_info "Open a new login shell to see the banner automatically"
        else
            show_error "Failed to update $USER_PROFILE_PATH"
            return 1
        fi
    fi

    printf '\n'
    "$INSTALLED_BIN_PATH" --plain --auto 2>/dev/null || true
}

show_menu() {
    if command_exists clear; then
        clear
    fi

    printf '\n'
    printf '%b%s%b\n' "$WHITE" "SysInfo Installer" "$NC"
    printf '%b%s%b\n' "$GRAY" "----------------------------------------" "$NC"
    printf '\n'
    printf '%b[1]%b Quick Test    %b- run once without installing%b\n' "$WHITE" "$NC" "$GRAY" "$NC"
    printf '%b[2]%b Command Tool  %b- install as sysinfo%b\n' "$WHITE" "$NC" "$GRAY" "$NC"
    printf '%b[3]%b Auto-start    %b- show on interactive login%b\n' "$WHITE" "$NC" "$GRAY" "$NC"
    printf '\n'
    printf '%b[q]%b Quit\n' "$WHITE" "$NC"
    printf '\n'
    printf '%bScope:%b %s\n' "$CYAN" "$NC" "$(resolve_scope "$SCOPE" 2>/dev/null || printf '%s' "$SCOPE")"
    printf '\n'
    printf '%b>%b ' "$YELLOW" "$NC"
}

run_interactive_menu() {
    while :; do
        show_menu
        IFS= read -r choice < /dev/tty || exit 1

        case "$choice" in
            ""|1)
                install_quick_test
                break
                ;;
            2)
                install_command_tool
                break
                ;;
            3)
                install_auto_start
                break
                ;;
            q|Q)
                printf '\n'
                exit 0
                ;;
            *)
                printf '\n'
                show_error "Invalid choice"
                printf 'Press Enter to continue...'
                IFS= read -r _dummy < /dev/tty || true
                ;;
        esac
    done
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --quick-test)
                MODE="quick-test"
                ;;
            --command-tool)
                MODE="command-tool"
                ;;
            --auto-start)
                MODE="auto-start"
                ;;
            --user)
                SCOPE="user"
                ;;
            --system)
                SCOPE="system"
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                show_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
        shift
    done
}

main() {
    trap cleanup EXIT INT TERM
    parse_args "$@"
    make_temp_dir

    if [ -z "$MODE" ]; then
        if [ -t 0 ] && [ -t 1 ]; then
            run_interactive_menu
            return
        fi

        show_error "Non-interactive use requires an explicit mode"
        show_help
        exit 1
    fi

    case "$MODE" in
        quick-test)
            install_quick_test
            ;;
        command-tool)
            install_command_tool
            ;;
        auto-start)
            install_auto_start
            ;;
        *)
            show_error "Unsupported mode: $MODE"
            exit 1
            ;;
    esac
}

main "$@"
