#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="${QUOTAS_CONFIG_PATH:-$SCRIPT_DIR/quotas-widget.conf}"

API_URL=""
MANAGEMENT_KEY=""
HTTP_STATUS=""
HTTP_BODY=""
API_CALL_BODY=""
QUOTA_ACCOUNT=""
QUOTA_REMAINING=""

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

api_call() {
    local auth_index="$1" method="$2" upstream_url="$3" headers_json="$4" data="${5:-}"
    local request_body wrapper_status

    if [[ -n "$data" ]]; then
        request_body="$(jq -cn \
            --argjson authIndex "$auth_index" \
            --arg method "$method" \
            --arg url "$upstream_url" \
            --argjson header "$headers_json" \
            --arg data "$data" \
            '{authIndex: $authIndex, method: $method, url: $url, header: $header, data: $data}')" || {
            die 'cannot build Management API proxy request' || return 1
        }
    else
        request_body="$(jq -cn \
            --argjson authIndex "$auth_index" \
            --arg method "$method" \
            --arg url "$upstream_url" \
            --argjson header "$headers_json" \
            '{authIndex: $authIndex, method: $method, url: $url, header: $header}')" || {
            die 'cannot build Management API proxy request' || return 1
        }
    fi

    curl_json POST "$API_URL/v0/management/api-call" "$request_body" || return 1
    wrapper_status="$(jq -er '.status_code | select(type == "number")' <<<"$HTTP_BODY")" || {
        die 'Management API proxy response is missing status_code' || return 1
    }
    ((wrapper_status < 400)) || {
        die "Upstream API returned status $wrapper_status" || return 1
    }
    API_CALL_BODY="$(jq -ce '.body | if type == "string" then (fromjson? // .) else . end' <<<"$HTTP_BODY")" || {
        die 'Management API proxy response is missing a valid body' || return 1
    }
}

get_codex_quota() {
    local auth_index="$1" headers_json

    headers_json="$(jq -cn \
        --arg authorization 'Bearer $TOKEN$' \
        --arg userAgent 'codex_cli_rs/0.76.0 (Debian 13.0.0; x86_64) WindowsTerminal' \
        --arg accept 'application/json' \
        '{Authorization: $authorization, "User-Agent": $userAgent, Accept: $accept}')"
    api_call "$auth_index" GET 'https://chatgpt.com/backend-api/wham/usage' "$headers_json"
}

get_antigravity_quota() {
    local file_json="$1" auth_index="$2" project_id name encoded_name data headers_json

    project_id="$(jq -r '
        .project_id //
        .projectId //
        .metadata.project_id //
        .metadata.projectId //
        .attributes.project_id //
        .attributes.projectId //
        .attributes.gemini_virtual_project //
        empty
    ' <<<"$file_json")"

    if [[ -z "$project_id" ]]; then
        name="$(jq -er '.name | select(type == "string" and length > 0)' <<<"$file_json")" || {
            die 'Antigravity account is missing its auth-file name' || return 1
        }
        encoded_name="$(jq -rn --arg value "$name" '$value | @uri')"
        curl_json GET "$API_URL/v0/management/auth-files/download?name=$encoded_name" || return 1
        project_id="$(jq -r '
            .project_id //
            .projectId //
            .installed.project_id //
            .installed.projectId //
            .web.project_id //
            .web.projectId //
            empty
        ' <<<"$HTTP_BODY")"
    fi

    [[ -n "$project_id" ]] || {
        die 'cannot find Project ID for Antigravity account' || return 1
    }
    data="$(jq -cn --arg project "$project_id" '{project: $project}')"
    headers_json="$(jq -cn \
        --arg authorization 'Bearer $TOKEN$' \
        --arg userAgent 'antigravity/cli/1.0.13 (aidev_client; os_type=darwin; arch=arm64)' \
        '{Authorization: $authorization, "User-Agent": $userAgent}')"
    api_call "$auth_index" POST \
        'https://daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary' \
        "$headers_json" "$data"
}

format_refresh_in() {
    local value="${1:-}" reset_ms now_seconds diff_seconds days hours minutes

    [[ -n "$value" ]] || return 0
    if [[ "$value" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        reset_ms="$(jq -nr --argjson value "$value" '$value | if . < 10000000000 then . * 1000 else . end | floor')"
    else
        reset_ms="$(date -d "$value" '+%s000' 2>/dev/null)" || return 0
    fi

    now_seconds="${QUOTAS_EPOCH_NOW:-}"
    if [[ -z "$now_seconds" ]]; then
        now_seconds="$(date '+%s')"
    fi
    diff_seconds=$((reset_ms / 1000 - now_seconds))
    ((diff_seconds > 0)) || diff_seconds=0
    days=$((diff_seconds / 86400))
    hours=$(((diff_seconds % 86400) / 3600))
    minutes=$(((diff_seconds % 3600) / 60))

    if ((days > 0)); then
        printf '%d %s, %d %s\n' \
            "$days" "$([[ $days -eq 1 ]] && printf day || printf days)" \
            "$hours" "$([[ $hours -eq 1 ]] && printf hour || printf hours)"
    else
        printf '%d %s, %d %s\n' \
            "$hours" "$([[ $hours -eq 1 ]] && printf hour || printf hours)" \
            "$minutes" "$([[ $minutes -eq 1 ]] && printf minute || printf minutes)"
    fi
}

build_codex_account() {
    local file_json="$1" quota_json="$2" name remaining reset_time percentage

    name="$(jq -r '.name // ""' <<<"$file_json")"
    remaining="$(jq -r '
        .rate_limit.primary_window.used_percent
        | select(type == "number")
        | (1 - (. / 100))
        | if . < 0 then 0 else . end
    ' <<<"$quota_json")"
    if [[ -z "$remaining" ]]; then
        QUOTA_ACCOUNT="$(jq -cn --arg name "$name" \
            '{name: $name, type: "codex", groups: [], minRemaining: null}')"
        QUOTA_REMAINING=""
        return 0
    fi
    reset_time="$(format_refresh_in "$(jq -r '.rate_limit.primary_window.reset_at // empty' <<<"$quota_json")")"
    LC_NUMERIC=C printf -v percentage '%.2f%%' "$(jq -nr --argjson remaining "$remaining" '$remaining * 100')"
    QUOTA_ACCOUNT="$(jq -cn \
        --arg name "$name" \
        --arg resetTime "$reset_time" \
        --arg percentage "$percentage" \
        --argjson remaining "$remaining" \
        '{
          name: $name,
          type: "codex",
          groups: [{
            name: "Codex Limit",
            items: [{
              label: "Primary Window",
              val: $percentage,
              resetTime: $resetTime
            }]
          }],
          minRemaining: $remaining
        }')"
    QUOTA_REMAINING="$remaining"
}

build_antigravity_account() {
    local file_json="$1" quota_json="$2" name transformed

    name="$(jq -r '.name // ""' <<<"$file_json")"
    transformed="$(jq -c '
        [(.groups // [])[] as $group
          | [$group.buckets[]?
              | select(.remainingFraction | type == "number")
              | {
                  label: ((.displayName | select(type == "string" and length > 0)) // .bucketId),
                  remaining: .remainingFraction,
                  resetValue: (.resetTime // null)
                }
            ] as $items
          | select(($items | length) > 0)
          | {
              name: (($group.displayName | select(type == "string" and length > 0)) // "Limits"),
              items: $items
            }
        ]
    ' <<<"$quota_json")"

    QUOTA_REMAINING="$(jq -r '[.[].items[].remaining] | if length == 0 then empty else min end' <<<"$transformed")"
    QUOTA_ACCOUNT="$(jq -cn --arg name "$name" --argjson groups "$transformed" --argjson minRemaining "${QUOTA_REMAINING:-null}" \
        '{name: $name, type: "antigravity", groups: $groups, minRemaining: $minRemaining}')"
    local group_index item_index remaining reset_value reset_text percentage
    while IFS=$'\t' read -r group_index item_index remaining reset_value; do
        reset_text="$(format_refresh_in "$reset_value")"
        LC_NUMERIC=C printf -v percentage '%.2f%%' "$(jq -nr --argjson remaining "$remaining" '$remaining * 100')"
        QUOTA_ACCOUNT="$(jq -c \
            --argjson groupIndex "$group_index" \
            --argjson itemIndex "$item_index" \
            --arg percentage "$percentage" \
            --arg resetTime "$reset_text" \
            '.groups[$groupIndex].items[$itemIndex].val = $percentage
             | .groups[$groupIndex].items[$itemIndex].resetTime = $resetTime' \
            <<<"$QUOTA_ACCOUNT")"
    done < <(jq -r '
        to_entries[] as $group
        | $group.value.items
        | to_entries[]
        | [$group.key, .key, .value.remaining, (.value.resetValue // "")]
        | @tsv
    ' <<<"$transformed")
    QUOTA_ACCOUNT="$(jq -c '.groups |= map(.items |= map(del(.remaining, .resetValue)))' <<<"$QUOTA_ACCOUNT")"
}

fetch_all_quotas() (
    local accounts_file remaining_file file_json type auth_index name
    local last_updated timestamp quotas min_remaining avg_remaining

    accounts_file=""
    remaining_file=""
    trap '[[ -z "$accounts_file" ]] || rm -f -- "$accounts_file"; [[ -z "$remaining_file" ]] || rm -f -- "$remaining_file"' EXIT

    accounts_file="$(mktemp)" || {
        die 'cannot create temporary account file' || return 1
    }
    remaining_file="$(mktemp)" || {
        rm -f -- "$accounts_file"
        die 'cannot create temporary remaining-fraction file' || return 1
    }
    chmod 600 "$accounts_file" "$remaining_file" || {
        rm -f -- "$accounts_file" "$remaining_file"
        die 'cannot secure temporary quota files' || return 1
    }

    while IFS= read -r file_json; do
        type="$(jq -r '.type // .provider // ""' <<<"$file_json")"
        auth_index="$(jq -r '.auth_index // .authIndex // empty' <<<"$file_json")"
        name="$(jq -r '.name // "unnamed account"' <<<"$file_json")"
        if jq -e '.disabled == true or .runtime_only == true or .runtimeOnly == true' >/dev/null <<<"$file_json" || [[ -z "$auth_index" ]]; then
            continue
        fi

        QUOTA_ACCOUNT=""
        QUOTA_REMAINING=""
        case "$type" in
            codex)
                if get_codex_quota "$auth_index" && build_codex_account "$file_json" "$API_CALL_BODY"; then
                    :
                else
                    printf '[ERROR] %s (%s): quota request failed\n' "$name" "$type" >&2
                    continue
                fi
                ;;
            antigravity)
                if get_antigravity_quota "$file_json" "$auth_index" && build_antigravity_account "$file_json" "$API_CALL_BODY"; then
                    :
                else
                    printf '[ERROR] %s (%s): quota request failed\n' "$name" "$type" >&2
                    continue
                fi
                ;;
            *)
                printf '[SKIP] %s: unsupported provider %s\n' "$name" "${type:-unknown}" >&2
                continue
                ;;
        esac

        printf '%s\n' "$QUOTA_ACCOUNT" >>"$accounts_file"
        if [[ -n "$QUOTA_REMAINING" ]]; then
            if [[ "$type" == antigravity ]]; then
                jq -r '[.groups[]?.buckets[]? | select(.remainingFraction | type == "number") | .remainingFraction] | .[]?' <<<"$API_CALL_BODY" >>"$remaining_file"
            else
                printf '%s\n' "$QUOTA_REMAINING" >>"$remaining_file"
            fi
        fi
        printf '[OK] %s (%s)\n' "$name" "$type" >&2
    done < <(jq -c '.files[]' <<<"$HTTP_BODY")

    quotas="$(jq -s '.' "$accounts_file")"
    min_remaining="$(jq -s 'if length == 0 then 1 else min end' "$remaining_file")"
    avg_remaining="$(jq -s 'if length == 0 then 1 else add / length end' "$remaining_file")"
    rm -f -- "$accounts_file" "$remaining_file"
    accounts_file=""
    remaining_file=""

    last_updated="${QUOTAS_NOW:-}"
    if [[ -z "$last_updated" ]]; then
        timestamp="$(date '+%H:%M %d/%m/%Y')"
        last_updated="${timestamp%% *} $(printf '%b' '\xE2\x80\xA2') ${timestamp#* }"
    fi
    jq -cn \
        --argjson quotas "$quotas" \
        --argjson minRemaining "$min_remaining" \
        --argjson avgRemaining "$avg_remaining" \
        --arg lastUpdated "$last_updated" \
        '{quotas: $quotas, minRemaining: $minRemaining, avgRemaining: $avgRemaining, lastUpdated: $lastUpdated}'
)

main() {
    load_credentials || return 1
    printf 'Connecting to %s...\n' "$API_URL" >&2
    fetch_auth_files || return 1
    fetch_all_quotas
}

if [[ "${QUOTAS_FETCHER_SOURCE_ONLY:-0}" != "1" ]]; then
    main "$@"
fi
