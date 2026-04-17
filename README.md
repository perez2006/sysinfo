# SysInfo

`sysinfo` is a small POSIX `sh` script that prints a compact system summary for terminals and login shells.

Current release: `v1.5.0`

## What It Shows

- OS name and version
- Kernel and architecture
- Hostname and current user
- Package managers detected on the machine
- Init/service manager
- Timezone and uptime
- Local IP
- Public IP with timeout and graceful fallback
- Container / VM / bare-metal environment detection
- Optional CPU, memory, and disk information

## Quick Install

### Quick test from `main`

```sh
curl -fsSL https://raw.githubusercontent.com/perez2006/sysinfo/main/install-system-info.sh | sh
```

### Install as command

```sh
curl -fsSL https://raw.githubusercontent.com/perez2006/sysinfo/main/install-system-info.sh | sh -s -- --command-tool
```

### Install a specific version or tag

```sh
curl -fsSL https://raw.githubusercontent.com/perez2006/sysinfo/main/install-system-info.sh | sh -s -- --command-tool --ref v1.5.0
```

### Enable auto-start on login

```sh
curl -fsSL https://raw.githubusercontent.com/perez2006/sysinfo/main/install-system-info.sh | sh -s -- --auto-start
```

### Uninstall

```sh
curl -fsSL https://raw.githubusercontent.com/perez2006/sysinfo/main/install-system-info.sh | sh -s -- --uninstall
```

You can use `wget -qO-` instead of `curl -fsSL` if needed.

## Installation Modes

The installer supports:

1. Quick test without installing anything
2. Command installation as `sysinfo`
3. Auto-start for interactive login shells
4. Uninstall for command and auto-start hooks

By default the installer prefers:

- System install in `/usr/local/bin` when root or `sudo` is available
- User install in `~/.local/bin` when system install is not available

You can force the scope:

```sh
sh install-system-info.sh --command-tool --user
sh install-system-info.sh --auto-start --system
sh install-system-info.sh --uninstall --user
```

## Usage

After installing:

```sh
sysinfo
```

Useful flags:

```sh
sysinfo --plain
sysinfo --json
sysinfo --no-public-ip
sysinfo --timeout 1
sysinfo --resources
sysinfo --cpu --memory --disk
```

## Sample Output

```text
Ubuntu 24.04 - Docker
  💻 Version:    24.04
  🧩 Kernel:     6.8.0-31-generic
  🏗️ Arch:       x86_64
  🏠 Hostname:   api-01
  👤 User:       ubuntu
  📦 Packages:   apt, snap
  📋 Services:   systemd
  🕐 Timezone:   UTC
  ⏳ Uptime:     2 days, 4 hours, 18 minutes
  📍 Local IP:   172.17.0.2
  🌍 Public IP:  203.0.113.1
  🧠 CPU:        AMD EPYC 7B13
  🧮 Memory:     1536 MB / 4096 MB
  💽 Disk:       8.2G / 20G (42%)
```

## PATH Note For User Installs

When `sysinfo` is installed in `~/.local/bin`, the installer now prints an exact command you can run if that directory is not in your `PATH`.

## Requirements

- POSIX-compatible `sh`
- `curl` or `wget` for the installer and public IP lookup
- Standard Unix tools such as `awk`, `df`, and `uname`
- `sudo` or root only when installing system-wide

## Validation

This repository includes a GitHub Actions workflow that runs syntax checks, `shellcheck`, JSON validation with `jq`, and the scripts in `tests/` on every push and pull request. The workflow validates Ubuntu, Debian, Alpine, and macOS.

## Release Notes

### v1.5.0

- Adds deterministic fixture tests for OS, kernel, architecture, hostname, user, package manager, init system, timezone, uptime, local IP, CPU, memory, and disk output.
- Adds test-only filesystem overrides through `SYSINFO_PROC_DIR`, `SYSINFO_ETC_DIR`, `SYSINFO_DMI_DIR`, and `SYSINFO_DOCKER_ENV_FILE`.
- Validates JSON output with `jq` when available.
- Expands CI coverage across Ubuntu, Debian, Alpine, and macOS.
- Centralizes POSIX syntax and smoke tests in `tests/run-posix-suite.sh`.

### v1.4.0

- Improves init system detection so `systemd` is not reported just because `systemctl` exists.
- Tightens public IP validation for IPv4 responses.
- Rejects `--timeout 0` so network lookups cannot accidentally run without a time limit.
- Allows `SYSINFO_RAW_BASE_URL` to point at a local directory for offline installer testing.
- Adds CI smoke tests for version, plain output, JSON output, resources mode, installer help, user install/uninstall, and non-interactive installer behavior.
