#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="${QUOTAS_CONFIG_PATH:-$SCRIPT_DIR/quotas-widget.conf}"

API_URL=""
MANAGEMENT_KEY=""
HTTP_STATUS=""
HTTP_BODY=""

die() {
    printf 'Error: %s\n' "$1" >&2
    return 1
}

load_credentials() {
    local secret_tool_bin="${QUOTAS_SECRET_TOOL_BIN:-secret-tool}"
    local mode api_url management_key api_ok=0 key_ok=0

    if [[ -e "$CONFIG_PATH" ]]; then
        [[ -f "$CONFIG_PATH" ]] || {
            die "fallback configuration is not a regular file: $CONFIG_PATH" || return 1
        }

        mode="$(stat -c '%a' "$CONFIG_PATH")" || {
            die "cannot inspect fallback configuration permissions: $CONFIG_PATH" || return 1
        }
        case "$mode" in
            0|200|400|600) ;;
            *)
                die "fallback configuration permissions must be 600 or stricter: $CONFIG_PATH" || return 1
                ;;
        esac

        api_url="$(jq -er '.apiUrl | select(type == "string" and length > 0)' "$CONFIG_PATH" 2>/dev/null)" || {
            die 'invalid fallback configuration: apiUrl must be a non-empty string' || return 1
        }
        management_key="$(jq -er '.managementKey | select(type == "string" and length > 0)' "$CONFIG_PATH" 2>/dev/null)" || {
            die 'invalid fallback configuration: managementKey must be a non-empty string' || return 1
        }
    else
        command -v "$secret_tool_bin" >/dev/null 2>&1 || {
            die 'Secret Service is unavailable and no fallback configuration exists' || return 1
        }

        if api_url="$("$secret_tool_bin" lookup application quotas key quotasApiUrl 2>/dev/null)"; then
            [[ -n "$api_url" ]] && api_ok=1
        fi
        if management_key="$("$secret_tool_bin" lookup application quotas key quotasManagementKey 2>/dev/null)"; then
            [[ -n "$management_key" ]] && key_ok=1
        fi

        if ((api_ok != key_ok)); then
            die 'incomplete credentials in Secret Service' || return 1
        fi
        ((api_ok == 1)) || {
            die 'credentials are unavailable in Secret Service' || return 1
        }
    fi

    API_URL="${api_url%/}"
    MANAGEMENT_KEY="$management_key"
}

curl_json() {
    local method="$1" url="$2" request_body="${3:-}"
    local curl_bin="${QUOTAS_CURL_BIN:-curl}"
    local response_file header_file status curl_status
    local -a curl_args

    response_file="$(mktemp)" || {
        die 'cannot create temporary response file' || return 1
    }
    header_file="$(mktemp)" || {
        rm -f -- "$response_file"
        die 'cannot create temporary header file' || return 1
    }
    chmod 600 "$response_file" "$header_file" || {
        rm -f -- "$response_file" "$header_file"
        die 'cannot secure temporary request files' || return 1
    }
    printf 'Authorization: Bearer %s\nContent-Type: application/json\n' "$MANAGEMENT_KEY" >"$header_file" || {
        rm -f -- "$response_file" "$header_file"
        die 'cannot write temporary header file' || return 1
    }

    curl_args=(
        --silent
        --show-error
        --location
        --connect-timeout 10
        --max-time 30
        --output "$response_file"
        --write-out '%{http_code}'
        --request "$method"
        --header "@$header_file"
    )
    if [[ -n "$request_body" ]]; then
        curl_args+=(--data "$request_body")
    fi

    if status="$("$curl_bin" "${curl_args[@]}" "$url")"; then
        curl_status=0
    else
        curl_status=$?
    fi
    HTTP_STATUS="$status"
    HTTP_BODY="$(<"$response_file")"
    rm -f -- "$response_file" "$header_file"

    ((curl_status == 0)) || {
        die "curl transport failure (exit $curl_status)" || return 1
    }
    [[ "$HTTP_STATUS" =~ ^2[0-9][0-9]$ ]] || {
        die "Management API returned HTTP $HTTP_STATUS" || return 1
    }
    jq -e . >/dev/null 2>&1 <<<"$HTTP_BODY" || {
        die 'Management API returned invalid JSON' || return 1
    }
}

fetch_auth_files() {
    curl_json GET "$API_URL/v0/management/auth-files" || return 1
    jq -e '.files | type == "array"' >/dev/null 2>&1 <<<"$HTTP_BODY" || {
        die 'Management API response is missing the files array' || return 1
    }
}

main() {
    local last_updated

    load_credentials || return 1
    printf 'Connecting to %s...\n' "$API_URL" >&2
    fetch_auth_files || return 1

    last_updated="${QUOTAS_NOW:-}"
    [[ -n "$last_updated" ]] || last_updated="$(date '+%H:%M • %d/%m/%Y')"
    jq -cn --arg lastUpdated "$last_updated" \
        '{quotas: [], minRemaining: 1, avgRemaining: 1, lastUpdated: $lastUpdated}'
}

if [[ "${QUOTAS_FETCHER_SOURCE_ONLY:-0}" != "1" ]]; then
    main "$@"
fi
