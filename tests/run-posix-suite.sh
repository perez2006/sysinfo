#!/bin/sh

set -u

SHELL_BIN=${1:-sh}

"$SHELL_BIN" -n system-info.sh
"$SHELL_BIN" -n install-system-info.sh
"$SHELL_BIN" -n tests/test-system-info.sh
"$SHELL_BIN" -n tests/test-installer.sh
"$SHELL_BIN" -n tests/test-fixtures.sh

"$SHELL_BIN" tests/test-system-info.sh
"$SHELL_BIN" tests/test-installer.sh
"$SHELL_BIN" tests/test-fixtures.sh
