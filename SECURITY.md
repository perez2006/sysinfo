# Security

## Installing Safely

The quick install command uses the common `curl | sh` pattern. For higher-assurance installs, download the script first, inspect it, and verify checksums from the matching file in `checksums/`.

Example:

```sh
curl -fsSLO https://raw.githubusercontent.com/perez2006/sysinfo/v1.5.1/install-system-info.sh
curl -fsSLO https://raw.githubusercontent.com/perez2006/sysinfo/main/checksums/v1.5.1.sha256
sha256sum -c v1.5.1.sha256
sh install-system-info.sh --command-tool --ref v1.5.1
```

## Reporting Issues

Open a GitHub issue with enough detail to reproduce the behavior. Do not include secrets, tokens, or private hostnames in public reports.
