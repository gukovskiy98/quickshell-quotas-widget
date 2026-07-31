#!/usr/bin/env bash
set -euo pipefail

: "${MOCK_JQ_ARGV_LOG:?MOCK_JQ_ARGV_LOG is required}"
: "${REAL_JQ_BIN:?REAL_JQ_BIN is required}"

printf '%s\0' "$@" >"$MOCK_JQ_ARGV_LOG"
if [[ -n "${MOCK_JQ_STDIN_MODE_LOG:-}" ]]; then
    stat -Lc '%a' /proc/$$/fd/0 >"$MOCK_JQ_STDIN_MODE_LOG"
fi
if [[ -n "${MOCK_JQ_STDIN_PATH_LOG:-}" ]]; then
    readlink /proc/$$/fd/0 >"$MOCK_JQ_STDIN_PATH_LOG"
fi
exec "$REAL_JQ_BIN" "$@"
