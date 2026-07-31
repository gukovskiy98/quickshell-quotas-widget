#!/usr/bin/env bash
set -Eeuo pipefail

API_URL=""
MANAGEMENT_KEY=""
KEY_INPUT_MODE="tty"
INSTALL_DIR=""
QS_BIN=""
CONFIG_ROOT=""
HELP_REQUESTED=0
WORK_DIR=""
ARCHIVE_PATH=""
PAYLOAD_DIR=""
FALLBACK_CONFIG=""
CREDENTIAL_BACKEND=""
declare -a TX_REPLACED_PATHS=()
declare -a TX_BACKUP_PATHS=()
declare -a TX_CREATED_PATHS=()
TX_ACTIVE=0
TX_TIMESTAMP=""
TX_ROLLING_BACK=0

usage() {
    cat <<'EOF'
Usage: install.sh --api-url URL [OPTIONS]

Install the Quotas widget into an end4-dots Quickshell configuration.

Options:
  --api-url URL             Management API URL (http:// or https://)
  --management-key KEY      Read the management key from this argument
  --management-key-stdin    Read the management key from standard input
  --install-dir PATH        Override the widget installation directory
  -h, --help                Show this help
EOF
    printf '\n'
    printf '%b\n' \
        '\xD0\x98\xD1\x81\xD0\xBF\xD0\xBE\xD0\xBB\xD1\x8C\xD0\xB7\xD0\xBE\xD0\xB2\xD0\xB0\xD0\xBD\xD0\xB8\xD0\xB5: install.sh --api-url URL [\xD0\x9F\xD0\x90\xD0\xA0\xD0\x90\xD0\x9C\xD0\x95\xD0\xA2\xD0\xA0\xD0\xAB]' \
        '' \
        '\xD0\xA3\xD1\x81\xD1\x82\xD0\xB0\xD0\xBD\xD0\xB0\xD0\xB2\xD0\xBB\xD0\xB8\xD0\xB2\xD0\xB0\xD0\xB5\xD1\x82 \xD0\xB2\xD0\xB8\xD0\xB4\xD0\xB6\xD0\xB5\xD1\x82 Quotas \xD0\xB2 \xD0\xBA\xD0\xBE\xD0\xBD\xD1\x84\xD0\xB8\xD0\xB3\xD1\x83\xD1\x80\xD0\xB0\xD1\x86\xD0\xB8\xD1\x8E Quickshell \xD0\xB8\xD0\xB7 end4-dots.' \
        '' \
        '\xD0\x9F\xD0\xB0\xD1\x80\xD0\xB0\xD0\xBC\xD0\xB5\xD1\x82\xD1\x80\xD1\x8B:' \
        '  --api-url URL             URL API \xD1\x83\xD0\xBF\xD1\x80\xD0\xB0\xD0\xB2\xD0\xBB\xD0\xB5\xD0\xBD\xD0\xB8\xD1\x8F (http:// \xD0\xB8\xD0\xBB\xD0\xB8 https://)' \
        '  --management-key KEY      \xD0\x9F\xD1\x80\xD0\xBE\xD1\x87\xD0\xB8\xD1\x82\xD0\xB0\xD1\x82\xD1\x8C \xD0\xBA\xD0\xBB\xD1\x8E\xD1\x87 \xD1\x83\xD0\xBF\xD1\x80\xD0\xB0\xD0\xB2\xD0\xBB\xD0\xB5\xD0\xBD\xD0\xB8\xD1\x8F \xD0\xB8\xD0\xB7 \xD0\xB0\xD1\x80\xD0\xB3\xD1\x83\xD0\xBC\xD0\xB5\xD0\xBD\xD1\x82\xD0\xB0' \
        '  --management-key-stdin    \xD0\x9F\xD1\x80\xD0\xBE\xD1\x87\xD0\xB8\xD1\x82\xD0\xB0\xD1\x82\xD1\x8C \xD0\xBA\xD0\xBB\xD1\x8E\xD1\x87 \xD1\x83\xD0\xBF\xD1\x80\xD0\xB0\xD0\xB2\xD0\xBB\xD0\xB5\xD0\xBD\xD0\xB8\xD1\x8F \xD0\xB8\xD0\xB7 \xD1\x81\xD1\x82\xD0\xB0\xD0\xBD\xD0\xB4\xD0\xB0\xD1\x80\xD1\x82\xD0\xBD\xD0\xBE\xD0\xB3\xD0\xBE \xD0\xB2\xD0\xB2\xD0\xBE\xD0\xB4\xD0\xB0' \
        '  --install-dir PATH        \xD0\x98\xD0\xB7\xD0\xBC\xD0\xB5\xD0\xBD\xD0\xB8\xD1\x82\xD1\x8C \xD0\xBA\xD0\xB0\xD1\x82\xD0\xB0\xD0\xBB\xD0\xBE\xD0\xB3 \xD1\x83\xD1\x81\xD1\x82\xD0\xB0\xD0\xBD\xD0\xBE\xD0\xB2\xD0\xBA\xD0\xB8 \xD0\xB2\xD0\xB8\xD0\xB4\xD0\xB6\xD0\xB5\xD1\x82\xD0\xB0' \
        '  -h, --help                \xD0\x9F\xD0\xBE\xD0\xBA\xD0\xB0\xD0\xB7\xD0\xB0\xD1\x82\xD1\x8C \xD1\x8D\xD1\x82\xD1\x83 \xD1\x81\xD0\xBF\xD1\x80\xD0\xB0\xD0\xB2\xD0\xBA\xD1\x83'
}

die() {
    printf 'Error: %s\n' "$1" >&2
    printf '%b %s\n' '\xD0\x9E\xD1\x88\xD0\xB8\xD0\xB1\xD0\xBA\xD0\xB0:' "$1" >&2
    return 1
}

warn() {
    printf 'Warning: %s\n' "$1" >&2
    printf '%b %s\n' '\xD0\x9F\xD1\x80\xD0\xB5\xD0\xB4\xD1\x83\xD0\xBF\xD1\x80\xD0\xB5\xD0\xB6\xD0\xB4\xD0\xB5\xD0\xBD\xD0\xB8\xD0\xB5:' "$1" >&2
}

normalize_api_url() {
    local url="$1" scheme rest

    case "$url" in
        http://*)
            scheme='http://'
            rest="${url#http://}"
            ;;
        https://*)
            scheme='https://'
            rest="${url#https://}"
            ;;
        *)
            die 'API URL must use http:// or https://' || return 1
            ;;
    esac

    while [[ "$rest" == */ ]]; do
        rest="${rest%/}"
    done
    [[ -n "$rest" ]] || {
        die 'API URL must not be empty' || return 1
    }

    printf '%s%s\n' "$scheme" "$rest"
}

parse_args() {
    HELP_REQUESTED=0

    while (($#)); do
        case "$1" in
            --api-url)
                [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || {
                    die 'missing value for --api-url' || return 1
                }
                API_URL="$(normalize_api_url "$2")" || return 1
                shift 2
                ;;
            --management-key)
                [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || {
                    die 'missing value for --management-key' || return 1
                }
                [[ "$KEY_INPUT_MODE" != 'stdin' ]] || {
                    die '--management-key and --management-key-stdin are mutually exclusive' || return 1
                }
                MANAGEMENT_KEY="$2"
                KEY_INPUT_MODE='argument'
                shift 2
                ;;
            --management-key-stdin)
                [[ "$KEY_INPUT_MODE" != 'argument' ]] || {
                    die '--management-key and --management-key-stdin are mutually exclusive' || return 1
                }
                MANAGEMENT_KEY=""
                KEY_INPUT_MODE='stdin'
                shift
                ;;
            --install-dir)
                [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || {
                    die 'missing value for --install-dir' || return 1
                }
                INSTALL_DIR="$2"
                shift 2
                ;;
            -h|--help)
                HELP_REQUESTED=1
                usage
                return 0
                ;;
            *)
                die "unknown flag: $1" || return 1
                ;;
        esac
    done

    [[ -n "$API_URL" ]] || {
        die 'missing required flag: --api-url' || return 1
    }
}

read_management_key() {
    local tty_path tty_in tty_out

    case "$KEY_INPUT_MODE" in
        argument)
            ;;
        stdin)
            IFS= read -r MANAGEMENT_KEY || [[ -n "$MANAGEMENT_KEY" ]] || {
                die 'management key input is empty' || return 1
            }
            ;;
        tty)
            tty_path="${QUOTAS_TTY_PATH:-/dev/tty}"
            exec {tty_in}<"$tty_path" || {
                die 'cannot open terminal for management key input' || return 1
            }
            exec {tty_out}>>"$tty_path" || {
                exec {tty_in}<&-
                die 'cannot open terminal for management key prompt' || return 1
            }
            printf '%b' \
                'Management key / \xD0\x9A\xD0\xBB\xD1\x8E\xD1\x87 \xD1\x83\xD0\xBF\xD1\x80\xD0\xB0\xD0\xB2\xD0\xBB\xD0\xB5\xD0\xBD\xD0\xB8\xD1\x8F: ' >&"$tty_out"
            IFS= read -r -s -u "$tty_in" MANAGEMENT_KEY || [[ -n "$MANAGEMENT_KEY" ]]
            printf '\n' >&"$tty_out"
            exec {tty_in}<&-
            exec {tty_out}>&-
            ;;
        *)
            die 'invalid management key input mode' || return 1
            ;;
    esac

    [[ -n "$MANAGEMENT_KEY" ]] || {
        die 'management key input is empty' || return 1
    }
}

_curl_to_file() {
    local output_file="$1" url="$2"
    shift 2
    local curl_bin="${QUOTAS_CURL_BIN:-curl}" status curl_status
    local -a curl_args=(
        --disable
        --silent
        --show-error
        --location
        --connect-timeout 10
        --max-time 30
        --output "$output_file"
        --write-out '%{http_code}'
    )

    curl_args+=("$@")
    if status="$("$curl_bin" "${curl_args[@]}" "$url")"; then
        curl_status=0
    else
        curl_status=$?
    fi
    ((curl_status == 0)) || {
        die "curl transport failure (exit $curl_status)" || return 1
    }
    [[ "$status" =~ ^2[0-9][0-9]$ ]] || {
        die "remote server returned HTTP $status" || return 1
    }
}

validate_api() {
    local body_file header_file

    if [[ -z "$WORK_DIR" ]]; then
        WORK_DIR="$(mktemp -d)" || {
            die 'cannot create temporary installer directory' || return 1
        }
    else
        mkdir -p -- "$WORK_DIR" || {
            die 'cannot create temporary installer directory' || return 1
        }
    fi
    chmod 700 "$WORK_DIR" || {
        die 'cannot secure temporary installer directory' || return 1
    }
    body_file="$(mktemp "$WORK_DIR/api-response.XXXXXX")" || {
        die 'cannot create temporary API response file' || return 1
    }
    header_file="$(mktemp "$WORK_DIR/api-header.XXXXXX")" || {
        rm -f -- "$body_file"
        die 'cannot create temporary API header file' || return 1
    }
    chmod 600 "$body_file" "$header_file" || {
        rm -f -- "$body_file" "$header_file"
        die 'cannot secure temporary API request files' || return 1
    }
    printf 'Authorization: Bearer %s\n' "$MANAGEMENT_KEY" >"$header_file" || {
        rm -f -- "$body_file" "$header_file"
        die 'cannot write temporary API header file' || return 1
    }

    if ! _curl_to_file "$body_file" "$API_URL/v0/management/auth-files" \
        --request GET --header "@$header_file"; then
        rm -f -- "$body_file" "$header_file"
        return 1
    fi
    rm -f -- "$header_file"

    jq -e -s . "$body_file" >/dev/null 2>&1 || {
        rm -f -- "$body_file"
        die 'Management API returned invalid JSON' || return 1
    }
    jq -e -s 'length == 1' "$body_file" >/dev/null 2>&1 || {
        rm -f -- "$body_file"
        die 'Management API must return a single JSON document' || return 1
    }
    jq -e -s '.[0].files | type == "array"' "$body_file" >/dev/null 2>&1 || {
        rm -f -- "$body_file"
        die 'Management API response is missing a files array' || return 1
    }
    rm -f -- "$body_file"
}

cleanup_work_dir() {
    [[ -z "$WORK_DIR" ]] || rm -rf -- "$WORK_DIR"
}

begin_transaction() {
    TX_REPLACED_PATHS=()
    TX_BACKUP_PATHS=()
    TX_CREATED_PATHS=()
    TX_TIMESTAMP="${QUOTAS_TIMESTAMP:-$(date +%Y%m%d-%H%M%S)}"
    TX_ROLLING_BACK=0
    TX_ACTIVE=1
}

backup_changed_file() {
    local path="$1" backup index

    ((TX_ACTIVE == 1)) || {
        die 'cannot backup a file outside an active transaction' || return 1
    }
    [[ -e "$path" && ! -L "$path" ]] || {
        die "cannot backup missing or unsafe file: $path" || return 1
    }
    for ((index = 0; index < ${#TX_REPLACED_PATHS[@]}; index++)); do
        [[ "${TX_REPLACED_PATHS[index]}" != "$path" ]] || return 0
    done

    backup="$path.backup.$TX_TIMESTAMP"
    [[ ! -e "$backup" ]] || {
        die "backup already exists: $backup" || return 1
    }
    cp -p -- "$path" "$backup" || {
        die "cannot backup file: $path" || return 1
    }
    TX_REPLACED_PATHS+=("$path")
    TX_BACKUP_PATHS+=("$backup")
}

track_created_file() {
    local path="$1" tracked

    ((TX_ACTIVE == 1)) || {
        die 'cannot track a file outside an active transaction' || return 1
    }
    for tracked in "${TX_CREATED_PATHS[@]}"; do
        [[ "$tracked" != "$path" ]] || return 0
    done
    TX_CREATED_PATHS+=("$path")
}

rollback_transaction() {
    local index status=0

    ((TX_ACTIVE == 1)) || return 0
    ((TX_ROLLING_BACK == 0)) || return 1
    TX_ROLLING_BACK=1
    for ((index = ${#TX_REPLACED_PATHS[@]} - 1; index >= 0; index--)); do
        _restore_file "${TX_BACKUP_PATHS[index]}" "${TX_REPLACED_PATHS[index]}" || status=1
    done
    for ((index = ${#TX_CREATED_PATHS[@]} - 1; index >= 0; index--)); do
        rm -f -- "${TX_CREATED_PATHS[index]}" || status=1
    done
    TX_ROLLING_BACK=0
    ((status == 0)) || {
        warn 'installation rollback was incomplete; timestamped backups were preserved'
        return 1
    }
    TX_ACTIVE=0
}

commit_transaction() {
    TX_ACTIVE=0
    TX_ROLLING_BACK=0
    TX_REPLACED_PATHS=()
    TX_BACKUP_PATHS=()
    TX_CREATED_PATHS=()
}

_restore_file() {
    local backup="$1" destination="$2" tmp_file

    [[ -f "$backup" && ! -L "$backup" ]] || return 1
    if [[ -e "$destination" ]]; then
        [[ -f "$destination" && ! -L "$destination" ]] || return 1
    fi
    tmp_file="$(mktemp "$destination.rollback.XXXXXX")" || return 1
    if ! cp -p -- "$backup" "$tmp_file" || ! mv -fT -- "$tmp_file" "$destination"; then
        rm -f -- "$tmp_file"
        return 1
    fi
}

_install_file() {
    local source="$1" destination="$2" mode="$3" tmp_file current_mode

    [[ -f "$source" && ! -L "$source" ]] || {
        die "missing safe payload file: $source" || return 1
    }
    if [[ -e "$destination" ]]; then
        [[ -f "$destination" && ! -L "$destination" ]] || {
            die "unsafe installation destination: $destination" || return 1
        }
        current_mode="$(stat -c '%a' "$destination")" || {
            die "cannot inspect installation destination: $destination" || return 1
        }
        if cmp -s -- "$source" "$destination" && [[ "$current_mode" == "$mode" ]]; then
            return 0
        fi
        ((TX_ACTIVE == 0)) || backup_changed_file "$destination" || return 1
    else
        ((TX_ACTIVE == 0)) || track_created_file "$destination" || return 1
    fi

    tmp_file="$(mktemp "$destination.tmp.XXXXXX")" || {
        die "cannot create temporary installation file for: $destination" || return 1
    }
    cp -- "$source" "$tmp_file" && chmod "$mode" "$tmp_file" && mv -f -- "$tmp_file" "$destination" || {
        rm -f -- "$tmp_file"
        die "cannot install file: $destination" || return 1
    }
}

install_payload() {
    mkdir -p -- "$INSTALL_DIR" || {
        die 'cannot create widget installation directory' || return 1
    }
    _install_file "$PAYLOAD_DIR/Quotas.qml" "$INSTALL_DIR/Quotas.qml" 644 || return 1
    _install_file "$PAYLOAD_DIR/QuotasPopup.qml" "$INSTALL_DIR/QuotasPopup.qml" 644 || return 1
    _install_file "$PAYLOAD_DIR/get-quotas.sh" "$INSTALL_DIR/get-quotas.sh" 700
}

fetch_latest_release() {
    local github_api="${QUOTAS_GITHUB_API_BASE:-https://api.github.com}"
    local metadata_file asset_count download_url

    if [[ -z "$WORK_DIR" ]]; then
        WORK_DIR="$(mktemp -d)" || {
            die 'cannot create temporary installer directory' || return 1
        }
    else
        mkdir -p -- "$WORK_DIR" || {
            die 'cannot create temporary installer directory' || return 1
        }
    fi
    chmod 700 "$WORK_DIR" || {
        die 'cannot secure temporary installer directory' || return 1
    }
    metadata_file="$WORK_DIR/latest-release.json"
    ARCHIVE_PATH="$WORK_DIR/release.tar.gz"
    PAYLOAD_DIR="$WORK_DIR/payload"

    _curl_to_file "$metadata_file" \
        "$github_api/repos/gukovskiy98/quickshell-quotas-widget/releases/latest" \
        --request GET || return 1
    jq -e '.assets | type == "array"' "$metadata_file" >/dev/null 2>&1 || {
        die 'GitHub latest release response is invalid' || return 1
    }
    asset_count="$(jq -r '[.assets[] | select(.name? | strings | test("^quickshell-quotas-widget-v[^/]+\\.tar\\.gz$"))] | length' "$metadata_file")" || {
        die 'GitHub latest release response is invalid' || return 1
    }
    [[ "$asset_count" == '1' ]] || {
        die 'latest release must contain exactly one matching archive asset' || return 1
    }
    download_url="$(jq -r '.assets[] | select(.name? | strings | test("^quickshell-quotas-widget-v[^/]+\\.tar\\.gz$")) | .browser_download_url // empty' "$metadata_file")" || {
        die 'GitHub latest release response is invalid' || return 1
    }
    [[ "$download_url" == http://* || "$download_url" == https://* ]] || {
        die 'latest release archive has an invalid download URL' || return 1
    }

    _curl_to_file "$ARCHIVE_PATH" "$download_url" --request GET
}

validate_archive() {
    local tar_bin="${QUOTAS_TAR_BIN:-tar}" list_file verbose_list_file entry line
    local quotas_count=0 popup_count=0 fetcher_count=0

    [[ -n "$ARCHIVE_PATH" && -f "$ARCHIVE_PATH" ]] || {
        die 'release archive is missing' || return 1
    }
    if [[ -z "$WORK_DIR" ]]; then
        WORK_DIR="$(mktemp -d)" || {
            die 'cannot create temporary installer directory' || return 1
        }
    fi
    PAYLOAD_DIR="${PAYLOAD_DIR:-$WORK_DIR/payload}"
    list_file="$WORK_DIR/archive-entries"
    verbose_list_file="$WORK_DIR/archive-entries-verbose"
    "$tar_bin" -tzf "$ARCHIVE_PATH" >"$list_file" || {
        die 'cannot read release archive' || return 1
    }
    "$tar_bin" -tvzf "$ARCHIVE_PATH" >"$verbose_list_file" || {
        die 'cannot inspect release archive' || return 1
    }

    while IFS= read -r entry || [[ -n "$entry" ]]; do
        [[ -n "$entry" && "$entry" != /* ]] || {
            die 'unsafe archive entry' || return 1
        }
        case "$entry" in
            *'//'*|'.'|'..'|'./'*|'../'*|*'/./'*|*'/../'*|*'/.'|*'/..')
                die 'unsafe archive entry' || return 1
                ;;
        esac
        [[ "$entry" != */* ]] || {
            die 'unsafe archive entry' || return 1
        }
        case "$entry" in
            Quotas.qml) quotas_count=$((quotas_count + 1)) ;;
            QuotasPopup.qml) popup_count=$((popup_count + 1)) ;;
            get-quotas.sh) fetcher_count=$((fetcher_count + 1)) ;;
            *)
                die "unexpected archive entry: $entry" || return 1
                ;;
        esac
    done <"$list_file"

    [[ $quotas_count -eq 1 && $popup_count -eq 1 && $fetcher_count -eq 1 ]] || {
        die 'release archive must contain each payload file exactly once' || return 1
    }
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "${line:0:1}" == '-' ]] || {
            die 'release archive payload entries must be regular files' || return 1
        }
    done <"$verbose_list_file"

    rm -rf -- "$PAYLOAD_DIR"
    mkdir -p -- "$PAYLOAD_DIR" || {
        die 'cannot create payload directory' || return 1
    }
    "$tar_bin" -xzf "$ARCHIVE_PATH" -C "$PAYLOAD_DIR" --no-same-owner --no-same-permissions || {
        rm -rf -- "$PAYLOAD_DIR"
        die 'cannot extract release archive' || return 1
    }
}

store_keyring_credentials() {
    local secret_tool="${QUOTAS_SECRET_TOOL_BIN:-secret-tool}"
    local stored_api_url stored_management_key sentinel='x'
    local api_lookup_ok=0 key_lookup_ok=0

    [[ -x "$secret_tool" ]] || command -v "$secret_tool" >/dev/null 2>&1 || return 1
    printf '%s' "$API_URL" | "$secret_tool" store \
        --label='Quotas API URL' application quotas key quotasApiUrl || return 1
    printf '%s' "$MANAGEMENT_KEY" | "$secret_tool" store \
        --label='Quotas Management Key' application quotas key quotasManagementKey || return 1
    if stored_api_url="$("$secret_tool" lookup application quotas key quotasApiUrl && printf '%s' "$sentinel")"; then
        api_lookup_ok=1
        stored_api_url="${stored_api_url%$sentinel}"
    fi
    if stored_management_key="$("$secret_tool" lookup application quotas key quotasManagementKey && printf '%s' "$sentinel")"; then
        key_lookup_ok=1
        stored_management_key="${stored_management_key%$sentinel}"
    fi
    ((api_lookup_ok == 1 && key_lookup_ok == 1)) || return 1
    [[ "$stored_api_url" == "$API_URL" && "$stored_management_key" == "$MANAGEMENT_KEY" ]]
}

write_fallback_config() {
    local credential_input tmp_config current_mode

    mkdir -p -- "$INSTALL_DIR" || {
        die 'cannot create credential configuration directory' || return 1
    }
    credential_input="$(mktemp "$WORK_DIR/credentials.XXXXXX")" || {
        die 'cannot create temporary credential input' || return 1
    }
    chmod 600 "$credential_input" || {
        rm -f -- "$credential_input"
        die 'cannot secure temporary credential input' || return 1
    }
    printf '%s\0%s' "$API_URL" "$MANAGEMENT_KEY" >"$credential_input" || {
        rm -f -- "$credential_input"
        die 'cannot write temporary credential input' || return 1
    }
    tmp_config="$(mktemp "$INSTALL_DIR/quotas-widget.conf.XXXXXX")" || {
        rm -f -- "$credential_input"
        die 'cannot create temporary credential configuration' || return 1
    }
    if ! jq -Rs 'split("\u0000") | {apiUrl:.[0], managementKey:.[1]}' \
        <"$credential_input" >"$tmp_config"; then
        rm -f -- "$credential_input" "$tmp_config"
        die 'cannot write credential fallback configuration' || return 1
    fi
    rm -f -- "$credential_input" || {
        rm -f -- "$tmp_config"
        die 'cannot remove temporary credential input' || return 1
    }
    chmod 600 "$tmp_config" || {
        rm -f -- "$tmp_config"
        die 'cannot secure credential fallback configuration' || return 1
    }
    if [[ -e "$FALLBACK_CONFIG" ]]; then
        [[ -f "$FALLBACK_CONFIG" && ! -L "$FALLBACK_CONFIG" ]] || {
            rm -f -- "$tmp_config"
            die 'credential fallback destination is unsafe' || return 1
        }
        current_mode="$(stat -c '%a' "$FALLBACK_CONFIG")" || {
            rm -f -- "$tmp_config"
            die 'cannot inspect credential fallback configuration' || return 1
        }
        if cmp -s -- "$tmp_config" "$FALLBACK_CONFIG" && [[ "$current_mode" == '600' ]]; then
            rm -f -- "$tmp_config"
            return 0
        fi
        ((TX_ACTIVE == 0)) || backup_changed_file "$FALLBACK_CONFIG" || {
            rm -f -- "$tmp_config"
            return 1
        }
    else
        ((TX_ACTIVE == 0)) || track_created_file "$FALLBACK_CONFIG" || {
            rm -f -- "$tmp_config"
            return 1
        }
    fi
    mv -f -- "$tmp_config" "$FALLBACK_CONFIG" || {
        rm -f -- "$tmp_config"
        die 'cannot install credential fallback configuration' || return 1
    }
}

store_credentials() {
    local fallback_warning

    FALLBACK_CONFIG="$INSTALL_DIR/quotas-widget.conf"
    CREDENTIAL_BACKEND=""

    if store_keyring_credentials; then
        if [[ -e "$FALLBACK_CONFIG" ]]; then
            [[ -f "$FALLBACK_CONFIG" && ! -L "$FALLBACK_CONFIG" ]] || {
                die 'credential fallback destination is unsafe' || return 1
            }
            ((TX_ACTIVE == 0)) || backup_changed_file "$FALLBACK_CONFIG" || return 1
        fi
        rm -f -- "$FALLBACK_CONFIG" || {
            die 'cannot remove obsolete credential fallback configuration' || return 1
        }
        CREDENTIAL_BACKEND='keyring'
        return 0
    fi

    fallback_warning="$(printf '%b' 'Secret Service credential storage failed verification; using a local protected file / \xD0\x9F\xD1\x80\xD0\xBE\xD0\xB2\xD0\xB5\xD1\x80\xD0\xBA\xD0\xB0 \xD1\x85\xD1\x80\xD0\xB0\xD0\xBD\xD0\xB8\xD0\xBB\xD0\xB8\xD1\x89\xD0\xB0 Secret Service \xD0\xBD\xD0\xB5 \xD1\x83\xD0\xB4\xD0\xB0\xD0\xBB\xD0\xB0\xD1\x81\xD1\x8C; \xD0\xB8\xD1\x81\xD0\xBF\xD0\xBE\xD0\xBB\xD1\x8C\xD0\xB7\xD1\x83\xD0\xB5\xD1\x82\xD1\x81\xD1\x8F \xD0\xB7\xD0\xB0\xD1\x89\xD0\xB8\xD1\x89\xD0\xB5\xD0\xBD\xD0\xBD\xD1\x8B\xD0\xB9 \xD0\xBB\xD0\xBE\xD0\xBA\xD0\xB0\xD0\xBB\xD1\x8C\xD0\xBD\xD1\x8B\xD0\xB9 \xD1\x84\xD0\xB0\xD0\xB9\xD0\xBB')"
    warn "$fallback_warning"
    write_fallback_config || return 1
    CREDENTIAL_BACKEND='file'
}

_canonicalize_future_dir() {
    local path="$1" probe component suffix='' physical

    [[ -n "$path" ]] || {
        die 'directory path must not be empty' || return 1
    }
    [[ "$path" == /* ]] || path="$PWD/$path"
    while [[ "$path" != '/' && "$path" == */ ]]; do
        path="${path%/}"
    done

    probe="$path"
    while [[ ! -d "$probe" ]]; do
        [[ ! -e "$probe" ]] || {
            die "path is not a directory: $probe" || return 1
        }
        [[ "$probe" != '/' ]] || {
            die "no valid parent directory for: $path" || return 1
        }
        component="${probe##*/}"
        suffix="/$component$suffix"
        probe="${probe%/*}"
        [[ -n "$probe" ]] || probe='/'
    done

    physical="$(cd -- "$probe" 2>/dev/null && pwd -P)" || {
        die "cannot resolve directory: $probe" || return 1
    }
    printf '%s%s\n' "${physical%/}" "$suffix"
}

resolve_layout() {
    local config_home root_candidate

    if [[ -z "$INSTALL_DIR" ]]; then
        config_home="${XDG_CONFIG_HOME:-${HOME:?HOME is not set}/.config}"
        INSTALL_DIR="$config_home/quickshell/ii/modules/ii/bar"
    fi

    INSTALL_DIR="$(_canonicalize_future_dir "$INSTALL_DIR")" || return 1
    root_candidate="$INSTALL_DIR"
    root_candidate="${root_candidate%/*}"
    root_candidate="${root_candidate%/*}"
    root_candidate="${root_candidate%/*}"
    CONFIG_ROOT="$(_canonicalize_future_dir "$root_candidate")" || return 1
}

require_bash_version() {
    local major="$1"
    ((major >= 4)) || {
        die "Bash $major is unsupported; Bash 4 or newer is required" || return 1
    }
}

require_dependencies() {
    local -a missing=()
    local command

    if command -v quickshell >/dev/null 2>&1; then
        QS_BIN='quickshell'
    elif command -v qs >/dev/null 2>&1; then
        QS_BIN='qs'
    else
        QS_BIN=''
        missing+=('quickshell or qs')
    fi

    for command in hyprctl curl jq tar; do
        command -v "$command" >/dev/null 2>&1 || missing+=("$command")
    done

    if ! command -v notify-send >/dev/null 2>&1; then
        warn 'notify-send is missing; refresh still works without desktop notifications'
    fi

    if ((${#missing[@]})); then
        printf 'Missing required commands:' >&2
        printf ' %s' "${missing[@]}" >&2
        printf '\n' >&2
        printf 'Install them with your package manager (pacman, apt-get, dnf, or zypper), then retry.\n' >&2
        return 1
    fi
}

_qml_braced_block() {
    local content="$1" start_token="$2" after open_offset index depth=0 char next_char
    local quote='' escaped=0 line_comment=0

    [[ "$content" == *"$start_token"* ]] || return 1
    after="${content#*"$start_token"}"
    [[ "$after" == *'{'* ]] || return 1
    open_offset="${after%%\{*}"
    after="${after:${#open_offset}}"

    for ((index = 0; index < ${#after}; index++)); do
        char="${after:index:1}"
        next_char="${after:index+1:1}"
        if ((line_comment == 1)); then
            [[ "$char" != $'\n' ]] || line_comment=0
            continue
        fi
        if [[ -n "$quote" ]]; then
            if ((escaped == 1)); then
                escaped=0
            elif [[ "$char" == '\\' ]]; then
                escaped=1
            elif [[ "$char" == "$quote" ]]; then
                quote=''
            fi
            continue
        fi
        if [[ "$char" == '/' && "$next_char" == '/' ]]; then
            line_comment=1
            continue
        fi
        if [[ "$char" == '"' || "$char" == "'" ]]; then
            quote="$char"
            continue
        fi
        case "$char" in
            '{') depth=$((depth + 1)) ;;
            '}')
                depth=$((depth - 1))
                if ((depth == 0)); then
                    printf '%s\n' "${after:0:index+1}"
                    return 0
                fi
                ;;
        esac
    done

    return 1
}

validate_end4_layout() {
    local shell_file="$CONFIG_ROOT/shell.qml"
    local bar_file="$CONFIG_ROOT/modules/ii/bar/BarContent.qml"
    local shell_content bar_content group_start group_content resources_prefix media_prefix

    [[ -f "$shell_file" ]] || {
        die "missing end4-dots file: $shell_file" || return 1
    }
    [[ -f "$bar_file" ]] || {
        die "missing end4-dots file: $bar_file" || return 1
    }

    shell_content="$(<"$shell_file")"
    [[ "$shell_content" == *'ShellRoot'* ]] || {
        die 'shell.qml is missing ShellRoot' || return 1
    }
    [[ "$shell_content" == *'families:'* && "$shell_content" == *'"ii"'* && "$shell_content" == *'"waffle"'* ]] || {
        die 'shell.qml is missing families: ["ii", "waffle"]' || return 1
    }
    [[ "$shell_content" == *'IllogicalImpulseFamily'* ]] || {
        die 'shell.qml is missing IllogicalImpulseFamily' || return 1
    }

    bar_content="$(<"$bar_file")"
    [[ "$bar_content" == *'id: leftCenterGroup'* ]] || {
        die 'BarContent.qml is missing leftCenterGroup' || return 1
    }
    group_start="${bar_content%%'id: leftCenterGroup'*}"
    [[ "$group_start" == *'BarGroup'* ]] || {
        die 'BarContent.qml is missing BarGroup for leftCenterGroup' || return 1
    }
    group_start="${group_start%BarGroup*}"
    group_content="$(_qml_braced_block "${bar_content:${#group_start}}" 'BarGroup')" || {
        die 'BarContent.qml has an invalid leftCenterGroup BarGroup block' || return 1
    }
    [[ "$group_content" == *'id: leftCenterGroup'* ]] || {
        die 'BarContent.qml is missing leftCenterGroup in BarGroup' || return 1
    }
    [[ "$group_content" == *'Resources'* ]] || {
        die 'BarContent.qml leftCenterGroup is missing Resources' || return 1
    }
    [[ "$group_content" == *'Media'* ]] || {
        die 'BarContent.qml leftCenterGroup is missing Media' || return 1
    }
    resources_prefix="${group_content%%Resources*}"
    media_prefix="${group_content%%Media*}"
    ((${#resources_prefix} < ${#media_prefix})) || {
        die 'BarContent.qml requires Media after Resources in leftCenterGroup' || return 1
    }
}

integrate_bar_content() {
    local bar_file="$CONFIG_ROOT/modules/ii/bar/BarContent.qml"
    local transformed awk_status

    if [[ -z "$WORK_DIR" ]]; then
        WORK_DIR="$(mktemp -d)" || {
            die 'cannot create temporary installer directory' || return 1
        }
    else
        mkdir -p -- "$WORK_DIR" || {
            die 'cannot create temporary installer directory' || return 1
        }
    fi
    chmod 700 "$WORK_DIR" || {
        die 'cannot secure temporary installer directory' || return 1
    }
    transformed="$WORK_DIR/BarContent.qml.transformed"

    if awk '
        BEGIN {
            RS = "\0"
            ORS = ""
        }
        function remove_marker_block(text,    i, block_start, block_end) {
            block_start = 1
            for (i = 1; i < marker_start_line; i++) block_start += length(lines[i]) + 1
            block_end = block_start - 1
            for (i = marker_start_line; i <= marker_end_line; i++) {
                block_end += length(lines[i])
                if (i < marker_end_line) block_end++
            }
            if (substr(text, block_end + 1, 1) == "\n") {
                return substr(text, 1, block_start - 1) substr(text, block_end + 2)
            }
            if (block_start > 1 && substr(text, block_start - 1, 1) == "\n") {
                return substr(text, 1, block_start - 2) substr(text, block_end + 1)
            }
            return substr(text, 1, block_start - 1) substr(text, block_end + 1)
        }
        function inspect_markers(text,    i, indent) {
            line_count = split(text, lines, "\n")
            start_count = 0
            end_count = 0
            for (i = 1; i <= line_count; i++) {
                if (lines[i] ~ /^[[:space:]]*\/\/ quickshell-quotas-widget:start[[:space:]]*$/) {
                    start_count++
                    marker_start_line = i
                }
                if (lines[i] ~ /^[[:space:]]*\/\/ quickshell-quotas-widget:end[[:space:]]*$/) {
                    end_count++
                    marker_end_line = i
                }
            }
            if (start_count == 0 && end_count == 0) return text
            if (start_count != 1 || end_count != 1 || marker_end_line != marker_start_line + 5) exit 43
            match(lines[marker_start_line], /^[[:space:]]*/)
            indent = substr(lines[marker_start_line], RSTART, RLENGTH)
            if (lines[marker_start_line] != indent "// quickshell-quotas-widget:start" ||
                lines[marker_start_line + 1] != indent "Quotas {" ||
                lines[marker_start_line + 2] != indent "    visible: true" ||
                lines[marker_start_line + 3] != indent "    Layout.fillWidth: false" ||
                lines[marker_start_line + 4] != indent "}" ||
                lines[marker_start_line + 5] != indent "// quickshell-quotas-widget:end") exit 43
            had_markers = 1
            return remove_marker_block(text)
        }
        function nearest_bar(    level) {
            for (level = depth; level >= 1; level--) {
                if (frame_bar[level]) return frame_bar[level]
            }
            return 0
        }
        function flush_token() {
            if (token == "") return
            if (expect_id_depth == depth && frame_type[depth] == "BarGroup") {
                if (token == "leftCenterGroup") bar_has_id[frame_bar[depth]] = 1
                expect_id_depth = 0
            }
            last_ident = token
            token = ""
        }
        function reset_token_context() {
            token = ""
            last_ident = ""
            expect_id_depth = 0
        }
        function scan(text,    i, c, nextc, component, owner, bar, line_start, line, suffix, block, transformed) {
            depth = 0
            quote = ""
            escaped = 0
            line_comment = 0
            bar_count = 0
            resource_count = 0
            reset_token_context()
            for (i = 1; i <= length(text); i++) {
                c = substr(text, i, 1)
                nextc = substr(text, i + 1, 1)
                if (line_comment) {
                    if (c == "\n") line_comment = 0
                    continue
                }
                if (quote != "") {
                    if (escaped) escaped = 0
                    else if (c == "\\") escaped = 1
                    else if (c == quote) quote = ""
                    continue
                }
                if (c == "/" && nextc == "/") {
                    flush_token()
                    line_comment = 1
                    i++
                    continue
                }
                if (c == "\"" || c == sprintf("%c", 39)) {
                    flush_token()
                    quote = c
                    continue
                }
                if (c ~ /[[:alnum:]_]/) {
                    token = token c
                    continue
                }
                flush_token()
                if (c ~ /[[:space:]]/) continue
                if (c == ":") {
                    if (last_ident == "id" && frame_type[depth] == "BarGroup") expect_id_depth = depth
                    last_ident = ""
                    continue
                }
                if (c == "{") {
                    component = last_ident
                    depth++
                    frame_type[depth] = component
                    frame_bar[depth] = nearest_bar()
                    if (component == "BarGroup") {
                        bar_count++
                        frame_bar[depth] = bar_count
                    } else if (component == "Resources") {
                        resource_count++
                        frame_resource[depth] = resource_count
                        resource_owner[resource_count] = frame_bar[depth]
                        resource_open[resource_count] = i
                    }
                    reset_token_context()
                    continue
                }
                if (c == "}") {
                    if (depth < 1) exit 44
                    if (frame_type[depth] == "Resources") resource_close[frame_resource[depth]] = i
                    delete frame_type[depth]
                    delete frame_bar[depth]
                    delete frame_resource[depth]
                    depth--
                    reset_token_context()
                    continue
                }
                reset_token_context()
            }
            flush_token()
            if (depth != 0 || quote != "") exit 44

            target_count = 0
            for (bar = 1; bar <= bar_count; bar++) {
                if (bar_has_id[bar]) {
                    target_count++
                    target_bar = bar
                }
            }
            if (target_count != 1) exit 41
            target_resource_count = 0
            for (i = 1; i <= resource_count; i++) {
                if (resource_owner[i] == target_bar && resource_close[i]) {
                    target_resource_count++
                    target_resource = i
                }
            }
            if (target_resource_count != 1) exit 42

            line_start = resource_open[target_resource]
            while (line_start > 1 && substr(text, line_start - 1, 1) != "\n") line_start--
            line = substr(text, line_start, resource_open[target_resource] - line_start)
            match(line, /^[[:space:]]*/)
            indent = substr(line, RSTART, RLENGTH)
            block = indent "// quickshell-quotas-widget:start\n" \
                indent "Quotas {\n" \
                indent "    visible: true\n" \
                indent "    Layout.fillWidth: false\n" \
                indent "}\n" \
                indent "// quickshell-quotas-widget:end"
            suffix = substr(text, resource_close[target_resource] + 1)
            if (substr(suffix, 1, 1) == "\n") {
                transformed = substr(text, 1, resource_close[target_resource]) "\n" block suffix
            } else {
                transformed = substr(text, 1, resource_close[target_resource]) "\n" block "\n" suffix
            }
            return transformed
        }
        {
            original = $0
            base = inspect_markers(original)
            transformed = scan(base)
            if (had_markers && transformed != original) exit 43
            print had_markers ? original : transformed
        }
    ' "$bar_file" >"$transformed"; then
        awk_status=0
    else
        awk_status=$?
    fi
    case $awk_status in
        0) ;;
        41|42)
            rm -f -- "$transformed"
            die 'BarContent.qml must contain exactly one safe insertion point' || return 1
            ;;
        43)
            rm -f -- "$transformed"
            die 'BarContent.qml has an invalid managed block or managed markers' || return 1
            ;;
        *)
            rm -f -- "$transformed"
            die 'cannot transform BarContent.qml safely' || return 1
            ;;
    esac

    _install_file "$transformed" "$bar_file" 644
}

run_smoke_test() {
    local smoke_stdout="$WORK_DIR/smoke.stdout" smoke_stderr="$WORK_DIR/smoke.stderr"
    local fetcher="$INSTALL_DIR/get-quotas.sh" status

    if "$fetcher" >"$smoke_stdout" 2>"$smoke_stderr"; then
        status=0
    else
        status=$?
    fi
    ((status == 0)) || {
        die "installed fetcher smoke test failed (exit $status); see $smoke_stderr" || return 1
    }
    jq -e '
        (.quotas | type == "array") and
        (.minRemaining | type == "number") and
        (.avgRemaining | type == "number") and
        (.lastUpdated | type == "string")
    ' "$smoke_stdout" >/dev/null 2>&1 || {
        die 'installed fetcher smoke test returned invalid quota JSON' || return 1
    }
}

restart_quickshell() {
    local qs_bin="${QUOTAS_QS_BIN:-$QS_BIN}" instances

    [[ "${QUOTAS_SKIP_RESTART:-0}" != '1' ]] || return 0
    if ! instances="$($qs_bin -p "$CONFIG_ROOT" list --json 2>/dev/null)"; then
        warn 'cannot inspect Quickshell instances; restart was skipped'
        return 0
    fi
    if ! jq -e 'type == "array" and length > 0' <<<"$instances" >/dev/null 2>&1; then
        warn 'Quickshell is not running for this configuration; start it manually if needed'
        return 0
    fi
    if ! "$qs_bin" -p "$CONFIG_ROOT" kill >/dev/null 2>&1; then
        warn 'cannot stop Quickshell; the committed installation was kept'
        return 0
    fi
    if ! "$qs_bin" -p "$CONFIG_ROOT" --daemonize >/dev/null 2>&1; then
        warn 'cannot start Quickshell; the committed installation was kept'
    fi
}

handle_transaction_failure() {
    local status=$?

    ((TX_ACTIVE == 0 || TX_ROLLING_BACK == 1)) || rollback_transaction || true
    return "$status"
}

handle_transaction_signal() {
    local status="$1"

    ((TX_ROLLING_BACK == 0)) || return 0
    ((TX_ACTIVE == 0)) || rollback_transaction || true
    exit "$status"
}

main() {
    require_bash_version "${BASH_VERSINFO[0]}" || return 1
    parse_args "$@" || return 1
    ((HELP_REQUESTED == 0)) || return 0
    read_management_key || return 1
    resolve_layout || return 1
    require_dependencies || return 1
    validate_end4_layout || return 1
    validate_api || return 1
    fetch_latest_release || return 1
    validate_archive || return 1
    begin_transaction || return 1
    store_credentials || {
        rollback_transaction || true
        return 1
    }
    install_payload || {
        rollback_transaction || true
        return 1
    }
    integrate_bar_content || {
        rollback_transaction || true
        return 1
    }
    run_smoke_test || {
        rollback_transaction || true
        return 1
    }
    commit_transaction || return 1
    restart_quickshell
    printf 'Quotas widget installed in %s using %s credential storage.\n' \
        "$INSTALL_DIR" "$CREDENTIAL_BACKEND"
}

if [[ "${QUOTAS_INSTALLER_SOURCE_ONLY:-0}" != "1" ]]; then
    trap cleanup_work_dir EXIT
    trap handle_transaction_failure ERR
    trap 'handle_transaction_signal 130' INT
    trap 'handle_transaction_signal 143' TERM
    main "$@"
fi
