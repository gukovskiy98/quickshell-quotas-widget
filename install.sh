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
    local credential_input tmp_config

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
    local content="$1" start_token="$2" after open_offset index depth=0 char

    [[ "$content" == *"$start_token"* ]] || return 1
    after="${content#*"$start_token"}"
    [[ "$after" == *'{'* ]] || return 1
    open_offset="${after%%\{*}"
    after="${after:${#open_offset}}"

    for ((index = 0; index < ${#after}; index++)); do
        char="${after:index:1}"
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

main() {
    require_bash_version "${BASH_VERSINFO[0]}" || return 1
    parse_args "$@" || return 1
    ((HELP_REQUESTED == 0)) || return 0
    resolve_layout || return 1
    require_dependencies || return 1
    validate_end4_layout || return 1
    read_management_key || return 1
    validate_api || return 1
    store_credentials || return 1
    fetch_latest_release || return 1
    validate_archive || return 1
}

if [[ "${QUOTAS_INSTALLER_SOURCE_ONLY:-0}" != "1" ]]; then
    trap cleanup_work_dir EXIT
    main "$@"
fi
