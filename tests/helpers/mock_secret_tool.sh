#!/usr/bin/env bash
set -euo pipefail

: "${MOCK_SECRET_STORE_DIR:?MOCK_SECRET_STORE_DIR is required}"

command_name="${1:-}"
shift || true

case "$command_name" in
    store)
        ((${MOCK_SECRET_FAIL_STORE:-0} == 0)) || exit "$MOCK_SECRET_FAIL_STORE"
        key="${!#}"
        mkdir -p -- "$MOCK_SECRET_STORE_DIR"
        cat >"$MOCK_SECRET_STORE_DIR/$key"
        ;;
    lookup)
        ((${MOCK_SECRET_FAIL_LOOKUP:-0} == 0)) || exit "$MOCK_SECRET_FAIL_LOOKUP"
        key="${!#}"
        [[ -f "$MOCK_SECRET_STORE_DIR/$key" ]] || exit 1
        cat -- "$MOCK_SECRET_STORE_DIR/$key"
        ;;
    *)
        printf 'unsupported secret-tool command: %s\n' "$command_name" >&2
        exit 2
        ;;
esac
