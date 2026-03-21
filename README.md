# SysInfo

`sysinfo` is a small POSIX `sh` script that prints a compact system summary for terminals and login shells.

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

## Quick Install

### Quick test

```sh
curl -fsSL https://raw.githubusercontent.com/perez2006/sysinfo/main/install-system-info.sh | sh
```

### Install as command

```sh
curl -fsSL https://raw.githubusercontent.com/perez2006/sysinfo/main/install-system-info.sh | sh -s -- --command-tool
```

### Enable auto-start on login

```sh
curl -fsSL https://raw.githubusercontent.com/perez2006/sysinfo/main/install-system-info.sh | sh -s -- --auto-start
```

You can use `wget -qO-` instead of `curl -fsSL` if needed.

## Installation Modes

The installer supports:

1. Quick test without installing anything
2. Command installation as `sysinfo`
3. Auto-start for interactive login shells

By default the installer prefers:

- System install in `/usr/local/bin` when root or `sudo` is available
- User install in `~/.local/bin` when system install is not available

You can force the scope:

```sh
sh install-system-info.sh --command-tool --user
sh install-system-info.sh --auto-start --system
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
```

## Requirements

- POSIX-compatible `sh`
- `curl` or `wget` for the installer and public IP lookup
- `sudo` or root only when installing system-wide

## Validation

This repository includes a GitHub Actions workflow that runs syntax checks and `shellcheck` on every push and pull request.
