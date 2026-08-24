#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR=""
CONFIG_ROOT=""
BAR_FILE=""
QS_BIN=""
WORK_DIR=""
HELP_REQUESTED=0
UNINSTALL_CHANGED=0

usage() {
    cat <<'EOF'
Usage:
  uninstall.sh [--install-dir PATH]

Options:
  --install-dir PATH  end4-dots bar modules directory
  -h, --help          show this help

Credentials in Secret Service and quotas-widget.conf are preserved.

Использование:
  uninstall.sh [--install-dir ПУТЬ]

Параметры:
  --install-dir ПУТЬ  каталог модулей панели end4-dots
  -h, --help          показать эту справку

Данные Secret Service и quotas-widget.conf сохраняются.
EOF
}

die() {
    printf 'Error: %s\n' "$1" >&2
    return 1
}

warn() {
    printf 'Warning: %s\n' "$1" >&2
}

cleanup_work_dir() {
    [[ -z "$WORK_DIR" ]] || rm -rf -- "$WORK_DIR"
}

parse_args() {
    local install_dir_seen=0

    while (($#)); do
        case "$1" in
            --install-dir)
                (($# >= 2)) || {
                    die '--install-dir requires a value' || return 1
                }
                ((install_dir_seen == 0)) || {
                    die '--install-dir may only be specified once' || return 1
                }
                INSTALL_DIR="$2"
                install_dir_seen=1
                shift 2
                ;;
            -h|--help)
                HELP_REQUESTED=1
                usage
                shift
                ;;
            *)
                die "unknown argument: $1" || return 1
                ;;
        esac
    done
}

resolve_layout() {
    local config_home

    if [[ -z "$INSTALL_DIR" ]]; then
        config_home="${XDG_CONFIG_HOME:-${HOME:?HOME is not set}/.config}"
        INSTALL_DIR="$config_home/quickshell/ii/modules/ii/bar"
    elif [[ "$INSTALL_DIR" != /* ]]; then
        INSTALL_DIR="$PWD/$INSTALL_DIR"
    fi
    while [[ "$INSTALL_DIR" != '/' && "$INSTALL_DIR" == */ ]]; do
        INSTALL_DIR="${INSTALL_DIR%/}"
    done

    case "$INSTALL_DIR" in
        */modules/ii/bar) ;;
        *)
            die '--install-dir must point to a modules/ii/bar directory' || return 1
            ;;
    esac

    if [[ -d "$INSTALL_DIR" ]]; then
        INSTALL_DIR="$(cd -- "$INSTALL_DIR" && pwd -P)" || {
            die "cannot resolve installation directory: $INSTALL_DIR" || return 1
        }
        case "$INSTALL_DIR" in
            */modules/ii/bar) ;;
            *)
                die 'resolved --install-dir escapes the modules/ii/bar scope' || return 1
                ;;
        esac
    fi
    CONFIG_ROOT="${INSTALL_DIR%/modules/ii/bar}"
    BAR_FILE="$INSTALL_DIR/BarContent.qml"
}

require_dependencies() {
    local command
    local -a missing=()

    for command in awk cp grep mktemp mv rm stat; do
        command -v "$command" >/dev/null 2>&1 || missing+=("$command")
    done
    if ((${#missing[@]})); then
        printf 'Missing required commands:' >&2
        printf ' %s' "${missing[@]}" >&2
        printf '\n' >&2
        return 1
    fi

    if command -v quickshell >/dev/null 2>&1; then
        QS_BIN='quickshell'
    elif command -v qs >/dev/null 2>&1; then
        QS_BIN='qs'
    else
        QS_BIN=''
    fi
}

transform_bar_content() {
    local transformed="$1" start_count end_count awk_status

    [[ -f "$BAR_FILE" && ! -L "$BAR_FILE" ]] || {
        die "BarContent.qml is not a safe regular file: $BAR_FILE" || return 1
    }
    start_count="$(grep -Ec '^[[:space:]]*// quickshell-quotas-widget:start[[:space:]]*$' "$BAR_FILE" || true)"
    end_count="$(grep -Ec '^[[:space:]]*// quickshell-quotas-widget:end[[:space:]]*$' "$BAR_FILE" || true)"
    if [[ "$start_count" == '0' && "$end_count" == '0' ]]; then
        return 2
    fi
    [[ "$start_count" == '1' && "$end_count" == '1' ]] || {
        die 'BarContent.qml has duplicate or unbalanced managed markers' || return 1
    }

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
        {
            line_count = split($0, lines, "\n")
            for (i = 1; i <= line_count; i++) {
                if (lines[i] ~ /^[[:space:]]*\/\/ quickshell-quotas-widget:start[[:space:]]*$/) {
                    marker_start_line = i
                }
                if (lines[i] ~ /^[[:space:]]*\/\/ quickshell-quotas-widget:end[[:space:]]*$/) {
                    marker_end_line = i
                }
            }
            if (marker_end_line != marker_start_line + 5) exit 43
            match(lines[marker_start_line], /^[[:space:]]*/)
            indent = substr(lines[marker_start_line], RSTART, RLENGTH)
            if (lines[marker_start_line] != indent "// quickshell-quotas-widget:start" ||
                lines[marker_start_line + 1] != indent "Quotas {" ||
                lines[marker_start_line + 2] != indent "    visible: true" ||
                lines[marker_start_line + 3] != indent "    Layout.fillWidth: false" ||
                lines[marker_start_line + 4] != indent "}" ||
                lines[marker_start_line + 5] != indent "// quickshell-quotas-widget:end") exit 43
            print remove_marker_block($0)
        }
    ' "$BAR_FILE" >"$transformed"; then
        awk_status=0
    else
        awk_status=$?
    fi
    ((awk_status == 0)) || {
        rm -f -- "$transformed"
        die 'BarContent.qml has an invalid managed block' || return 1
    }
}

remove_bar_integration() {
    local transformed="$WORK_DIR/BarContent.qml" bar_mode timestamp backup target_tmp status

    if [[ ! -e "$BAR_FILE" ]]; then
        return 0
    fi
    if transform_bar_content "$transformed"; then
        status=0
    else
        status=$?
    fi
    case "$status" in
        0) ;;
        2) return 0 ;;
        *) return "$status" ;;
    esac

    bar_mode="$(stat -c '%a' "$BAR_FILE")" || {
        die 'cannot inspect BarContent.qml mode' || return 1
    }
    timestamp="${QUOTAS_TIMESTAMP:-$(date +%Y%m%d-%H%M%S)}"
    backup="$BAR_FILE.backup.$timestamp"
    [[ ! -e "$backup" ]] || {
        die "backup already exists: $backup" || return 1
    }
    cp -p -- "$BAR_FILE" "$backup" || {
        die 'cannot back up BarContent.qml' || return 1
    }
    target_tmp="$(mktemp "$INSTALL_DIR/.BarContent.qml.uninstall.XXXXXX")" || {
        die 'cannot create temporary BarContent.qml' || return 1
    }
    if ! cp -- "$transformed" "$target_tmp" ||
        ! chmod "$bar_mode" "$target_tmp" ||
        ! mv -f -- "$target_tmp" "$BAR_FILE"; then
        rm -f -- "$target_tmp"
        die 'cannot update BarContent.qml' || return 1
    fi
    UNINSTALL_CHANGED=1
    printf 'Bar integration removed; backup: %s\n' "$backup"
}

remove_payload() {
    local name path

    for name in Quotas.qml QuotasPopup.qml get-quotas.sh; do
        path="$INSTALL_DIR/$name"
        if [[ -e "$path" || -L "$path" ]]; then
            [[ ! -d "$path" ]] || {
                die "refusing to remove directory: $path" || return 1
            }
            rm -f -- "$path" || {
                die "cannot remove payload file: $path" || return 1
            }
            UNINSTALL_CHANGED=1
        fi
    done
}

validate_payload_targets() {
    local name path

    for name in Quotas.qml QuotasPopup.qml get-quotas.sh; do
        path="$INSTALL_DIR/$name"
        [[ ! -d "$path" ]] || {
            die "refusing to remove directory: $path" || return 1
        }
    done
}

warn_about_unmanaged_reference() {
    [[ ! -f "$BAR_FILE" ]] || ! grep -Eq '^[[:space:]]*Quotas[[:space:]]*\{' "$BAR_FILE" || {
        warn 'BarContent.qml still contains an unmanaged Quotas component; remove it manually if it belongs to this widget'
    }
}

restart_quickshell() {
    local instances

    [[ "$UNINSTALL_CHANGED" == '1' ]] || return 0
    [[ "${QUOTAS_SKIP_RESTART:-0}" != '1' ]] || return 0
    [[ -n "$QS_BIN" ]] || {
        warn 'Quickshell executable was not found; restart was skipped'
        return 0
    }
    command -v jq >/dev/null 2>&1 || {
        warn 'jq was not found; Quickshell restart was skipped'
        return 0
    }
    if ! instances="$("$QS_BIN" -p "$CONFIG_ROOT" list --json 2>/dev/null)"; then
        warn 'cannot inspect Quickshell instances; restart was skipped'
        return 0
    fi
    if ! jq -e 'type == "array" and length > 0' <<<"$instances" >/dev/null 2>&1; then
        warn 'Quickshell is not running for this configuration'
        return 0
    fi
    if ! "$QS_BIN" -p "$CONFIG_ROOT" kill >/dev/null 2>&1; then
        warn 'cannot stop Quickshell; restart it manually'
        return 0
    fi
    "$QS_BIN" -p "$CONFIG_ROOT" --daemonize >/dev/null 2>&1 || {
        warn 'cannot start Quickshell; start it manually'
    }
}

uninstall_main() {
    parse_args "$@" || return 1
    ((HELP_REQUESTED == 0)) || return 0
    resolve_layout || return 1
    require_dependencies || return 1

    if [[ ! -d "$INSTALL_DIR" ]]; then
        printf 'Quotas widget is already absent from %s.\n' "$INSTALL_DIR"
        return 0
    fi
    WORK_DIR="$(mktemp -d)" || {
        die 'cannot create temporary uninstall directory' || return 1
    }
    chmod 700 "$WORK_DIR" || {
        die 'cannot secure temporary uninstall directory' || return 1
    }

    validate_payload_targets || return 1
    remove_bar_integration || return 1
    remove_payload || return 1
    warn_about_unmanaged_reference
    restart_quickshell

    if [[ "$UNINSTALL_CHANGED" == '1' ]]; then
        printf 'Quotas widget removed from %s. Credentials were preserved.\n' "$INSTALL_DIR"
    else
        printf 'Quotas widget is already absent from %s. Credentials were preserved.\n' "$INSTALL_DIR"
    fi
}

if [[ "${QUOTAS_UNINSTALLER_SOURCE_ONLY:-0}" != '1' ]]; then
    trap cleanup_work_dir EXIT
    uninstall_main "$@"
fi
