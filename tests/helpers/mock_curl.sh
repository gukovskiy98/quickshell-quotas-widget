#!/usr/bin/env bash
set -euo pipefail

: "${MOCK_CURL_LOG:?MOCK_CURL_LOG is required}"
: "${MOCK_CURL_HEADERS_LOG:?MOCK_CURL_HEADERS_LOG is required}"
: "${MOCK_CURL_QUEUE_DIR:?MOCK_CURL_QUEUE_DIR is required}"

output_path=""
header_files=()
args=("$@")

{
    printf 'curl'
    printf ' %q' "${args[@]}"
    printf '\n'
} >>"$MOCK_CURL_LOG"

while (($#)); do
    case "$1" in
        --output)
            output_path="$2"
            if [[ -n "${MOCK_CURL_OUTPUTS_LOG:-}" ]]; then
                printf '%s\n' "$output_path" >>"$MOCK_CURL_OUTPUTS_LOG"
            fi
            shift 2
            ;;
        --header)
            if [[ "$2" == @* ]]; then
                header_files+=("${2#@}")
                if [[ -n "${MOCK_CURL_HEADER_PATHS_LOG:-}" ]]; then
                    printf '%s\n' "${2#@}" >>"$MOCK_CURL_HEADER_PATHS_LOG"
                fi
            fi
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

for header_file in "${header_files[@]}"; do
    cat -- "$header_file" >>"$MOCK_CURL_HEADERS_LOG"
    if [[ -n "${MOCK_CURL_HEADER_MODES_LOG:-}" ]]; then
        stat -c '%a' "$header_file" >>"$MOCK_CURL_HEADER_MODES_LOG"
    fi
done

if [[ -n "${MOCK_CURL_BLOCK_READY:-}" ]]; then
    : >"$MOCK_CURL_BLOCK_READY"
    sleep "${MOCK_CURL_BLOCK_SECONDS:-60}"
fi

counter_file="$MOCK_CURL_QUEUE_DIR/.counter"
counter=0
[[ ! -f "$counter_file" ]] || counter="$(<"$counter_file")"
counter=$((counter + 1))
printf '%s\n' "$counter" >"$counter_file"

queue_file="$MOCK_CURL_QUEUE_DIR/$counter"
[[ -f "$queue_file" ]] || {
    printf 'missing mock curl response: %s\n' "$queue_file" >&2
    exit 1
}

IFS= read -r status <"$queue_file"
if [[ -n "$output_path" ]]; then
    sed '1d' "$queue_file" >"$output_path"
fi
printf '%s' "$status"
exit "${MOCK_CURL_EXIT_CODE:-0}"
