#!/usr/bin/env bash
set -Eeuo pipefail

API_URL=""
MANAGEMENT_KEY=""
KEY_INPUT_MODE="tty"
INSTALL_DIR=""
QS_BIN=""
CONFIG_ROOT=""
HELP_REQUESTED=0

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

Использование: install.sh --api-url URL [ПАРАМЕТРЫ]

Устанавливает виджет Quotas в конфигурацию Quickshell из end4-dots.

Параметры:
  --api-url URL             URL API управления (http:// или https://)
  --management-key KEY      Прочитать ключ управления из аргумента
  --management-key-stdin    Прочитать ключ управления из стандартного ввода
  --install-dir PATH        Изменить каталог установки виджета
  -h, --help                Показать эту справку
EOF
}

die() {
    printf 'Error: %s\nОшибка: %s\n' "$1" "$1" >&2
    return 1
}

warn() {
    printf 'Warning: %s\nПредупреждение: %s\n' "$1" "$1" >&2
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
                [[ $# -ge 2 ]] || {
                    die 'missing value for --management-key' || return 1
                }
                [[ -n "$2" ]] || {
                    die '--management-key must not be empty' || return 1
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
}

if [[ "${QUOTAS_INSTALLER_SOURCE_ONLY:-0}" != "1" ]]; then
    main "$@"
fi
