#!/usr/bin/env bash
set -euo pipefail

: "${MOCK_SECRET_STORE_DIR:?MOCK_SECRET_STORE_DIR is required}"

command_name="${1:-}"
shift || true

case "$command_name" in
    store)
        key="${!#}"
        ((${MOCK_SECRET_FAIL_STORE:-0} == 0)) || exit "$MOCK_SECRET_FAIL_STORE"
        [[ "${MOCK_SECRET_FAIL_STORE_KEY:-}" != "$key" ]] || exit "${MOCK_SECRET_FAIL_STORE_KEY_CODE:-1}"
        mkdir -p -- "$MOCK_SECRET_STORE_DIR"
        cat >"$MOCK_SECRET_STORE_DIR/$key"
        ;;
    lookup)
        key="${!#}"
        if [[ -n "${MOCK_SECRET_LOOKUP_LOG:-}" ]]; then
            printf '%s\n' "$key" >>"$MOCK_SECRET_LOOKUP_LOG"
        fi
        ((${MOCK_SECRET_FAIL_LOOKUP:-0} == 0)) || exit "$MOCK_SECRET_FAIL_LOOKUP"
        if [[ "${MOCK_SECRET_LOOKUP_OVERRIDE_KEY:-}" == "$key" ]]; then
            printf '%s' "${MOCK_SECRET_LOOKUP_OVERRIDE_VALUE:-}"
            exit 0
        fi
        [[ -f "$MOCK_SECRET_STORE_DIR/$key" ]] || exit 1
        cat -- "$MOCK_SECRET_STORE_DIR/$key"
        ;;
    *)
        printf 'unsupported secret-tool command: %s\n' "$command_name" >&2
        exit 2
        ;;
esac
