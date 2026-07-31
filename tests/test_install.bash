#!/usr/bin/env bash
set -uo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/test_helper.bash"
QUOTAS_INSTALLER_SOURCE_ONLY=1 source "$repo_root/install.sh"

CURL_MOCK="$repo_root/tests/helpers/mock_curl.sh"
JQ_MOCK="$repo_root/tests/helpers/mock_jq.sh"

reset_installer_state() {
    API_URL=""
    MANAGEMENT_KEY=""
    KEY_INPUT_MODE="tty"
    INSTALL_DIR=""
    QS_BIN=""
    CONFIG_ROOT=""
    WORK_DIR=""
    ARCHIVE_PATH=""
    PAYLOAD_DIR=""
    FALLBACK_CONFIG=""
    CREDENTIAL_BACKEND=""
    TX_ACTIVE=0
    TX_TIMESTAMP=""
    TX_ROLLING_BACK=0
    TX_REPLACED_PATHS=()
    TX_BACKUP_PATHS=()
    TX_REPLACED_MODES=()
    TX_CREATED_PATHS=()
    unset QUOTAS_TIMESTAMP QUOTAS_SKIP_RESTART QUOTAS_QS_BIN QUOTAS_WRITABLE_PROBE_FAIL
}

prepare_installer_fixture() {
    reset_installer_state
    API_URL='https://management.example'
    MANAGEMENT_KEY='never-log-this-key'
    INSTALL_DIR="$TEST_TMP_ROOT/install"
    WORK_DIR="$TEST_TMP_ROOT/work"
    MOCK_SECRET_STORE_DIR="$TEST_TMP_ROOT/secrets"
    MOCK_SECRET_LOOKUP_LOG="$TEST_TMP_ROOT/secret-lookups.log"
    QUOTAS_SECRET_TOOL_BIN="$repo_root/tests/helpers/mock_secret_tool.sh"
    unset MOCK_SECRET_FAIL_STORE MOCK_SECRET_FAIL_STORE_KEY MOCK_SECRET_FAIL_STORE_KEY_CODE
    unset MOCK_SECRET_FAIL_LOOKUP MOCK_SECRET_LOOKUP_OVERRIDE_KEY MOCK_SECRET_LOOKUP_OVERRIDE_VALUE
    export QUOTAS_SECRET_TOOL_BIN MOCK_SECRET_STORE_DIR MOCK_SECRET_LOOKUP_LOG
    export MOCK_SECRET_FAIL_STORE MOCK_SECRET_FAIL_STORE_KEY MOCK_SECRET_FAIL_STORE_KEY_CODE
    export MOCK_SECRET_FAIL_LOOKUP MOCK_SECRET_LOOKUP_OVERRIDE_KEY MOCK_SECRET_LOOKUP_OVERRIDE_VALUE
    mkdir -p "$INSTALL_DIR" "$WORK_DIR" "$MOCK_SECRET_STORE_DIR"
    : >"$MOCK_SECRET_LOOKUP_LOG"
}

prepare_remote_fixture() {
    reset_installer_state
    API_URL='https://management.example'
    MANAGEMENT_KEY='never-log-this-key'
    INSTALL_DIR="$TEST_TMP_ROOT/install"
    MOCK_CURL_QUEUE_DIR="$TEST_TMP_ROOT/curl-queue"
    MOCK_CURL_LOG="$TEST_TMP_ROOT/curl.log"
    MOCK_CURL_HEADERS_LOG="$TEST_TMP_ROOT/curl-headers.log"
    MOCK_CURL_HEADER_MODES_LOG="$TEST_TMP_ROOT/curl-header-modes.log"
    MOCK_CURL_OUTPUTS_LOG="$TEST_TMP_ROOT/curl-outputs.log"
    MOCK_CURL_HEADER_PATHS_LOG="$TEST_TMP_ROOT/curl-header-paths.log"
    QUOTAS_CURL_BIN="$CURL_MOCK"
    QUOTAS_GITHUB_API_BASE='https://github.example'
    QUOTAS_TAR_BIN='tar'
    WORK_DIR="$TEST_TMP_ROOT/work"
    mkdir -p "$MOCK_CURL_QUEUE_DIR" "$WORK_DIR"
    : >"$MOCK_CURL_LOG"
    : >"$MOCK_CURL_HEADERS_LOG"
    : >"$MOCK_CURL_HEADER_MODES_LOG"
    : >"$MOCK_CURL_OUTPUTS_LOG"
    : >"$MOCK_CURL_HEADER_PATHS_LOG"
}

queue_http_text() {
    local status="$1" body="$2" count
    count="$(find "$MOCK_CURL_QUEUE_DIR" -maxdepth 1 -type f ! -name '.counter' | wc -l)"
    printf '%s\n%s\n' "$status" "$body" >"$MOCK_CURL_QUEUE_DIR/$((count + 1))"
}

queue_http_file() {
    local status="$1" body_file="$2" count
    count="$(find "$MOCK_CURL_QUEUE_DIR" -maxdepth 1 -type f ! -name '.counter' | wc -l)"
    {
        printf '%s\n' "$status"
        cat -- "$body_file"
    } >"$MOCK_CURL_QUEUE_DIR/$((count + 1))"
}

run_with_mock_curl() {
    export QUOTAS_CURL_BIN QUOTAS_GITHUB_API_BASE QUOTAS_TAR_BIN
    export MOCK_CURL_QUEUE_DIR MOCK_CURL_LOG MOCK_CURL_HEADERS_LOG MOCK_CURL_HEADER_MODES_LOG
    export MOCK_CURL_OUTPUTS_LOG MOCK_CURL_HEADER_PATHS_LOG
    export MOCK_CURL_EXIT_CODE
    "$@"
}

assert_remote_failure() {
    local expected="$1"
    shift
    local output status persistent_file="${INSTALL_DIR:-$TEST_TMP_ROOT/install}/Quotas.qml"
    if output="$(run_with_mock_curl "$@" 2>&1)"; then
        status=0
    else
        status=$?
    fi
    [[ $status -ne 0 ]] || fail 'remote operation must fail' || return 1
    assert_contains "$output" "$expected" || return 1
    [[ ! -e "$persistent_file" ]] || fail 'persistent file must not exist after validation failure' || return 1
    [[ "$output" != *"$MANAGEMENT_KEY"* ]] || fail 'management key leaked into output'
}

create_release_archive() {
    local archive="$1"
    mkdir -p "$TEST_TMP_ROOT/payload"
    printf 'qml\n' >"$TEST_TMP_ROOT/payload/Quotas.qml"
    printf 'qml\n' >"$TEST_TMP_ROOT/payload/QuotasPopup.qml"
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'printf '\''%s\n'\'' '\''{"quotas":[],"minRemaining":1,"avgRemaining":2,"lastUpdated":"2026-07-31T14:30:00Z"}'\''' \
        >"$TEST_TMP_ROOT/payload/get-quotas.sh"
    tar -C "$TEST_TMP_ROOT/payload" -czf "$archive" \
        Quotas.qml QuotasPopup.qml get-quotas.sh
}

create_release_archive_with_fetcher() {
    local archive="$1" fetcher_body="$2"
    mkdir -p "$TEST_TMP_ROOT/payload"
    printf 'new quotas qml\n' >"$TEST_TMP_ROOT/payload/Quotas.qml"
    printf 'new popup qml\n' >"$TEST_TMP_ROOT/payload/QuotasPopup.qml"
    printf '#!/usr/bin/env bash\n%s\n' "$fetcher_body" >"$TEST_TMP_ROOT/payload/get-quotas.sh"
    tar -C "$TEST_TMP_ROOT/payload" -czf "$archive" \
        Quotas.qml QuotasPopup.qml get-quotas.sh
}

queue_latest_release() {
    local assets_json="$1"
    queue_http_text 200 "{\"assets\":$assets_json}"
}

prepare_end4_fixture() {
    reset_installer_state
    local fixture="$repo_root/tests/fixtures/end4-dots/ii"
    CONFIG_ROOT="$TEST_TMP_ROOT/config"
    mkdir -p "$CONFIG_ROOT/modules/ii/bar"
    cp "$fixture/shell.qml" "$CONFIG_ROOT/shell.qml"
    cp "$fixture/modules/ii/bar/BarContent.qml" "$CONFIG_ROOT/modules/ii/bar/BarContent.qml"
}

prepare_transaction_fixture() {
    prepare_end4_fixture
    INSTALL_DIR="$CONFIG_ROOT/modules/ii/bar"
    WORK_DIR="$TEST_TMP_ROOT/work"
    PAYLOAD_DIR="$TEST_TMP_ROOT/payload"
    QUOTAS_TIMESTAMP='20260731-143000'
    mkdir -p "$WORK_DIR" "$PAYLOAD_DIR"
    printf 'new quotas qml\n' >"$PAYLOAD_DIR/Quotas.qml"
    printf 'new popup qml\n' >"$PAYLOAD_DIR/QuotasPopup.qml"
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'printf '\''%s\n'\'' '\''{"quotas":[],"minRemaining":1,"avgRemaining":2,"lastUpdated":"2026-07-31T14:30:00Z"}'\''' \
        >"$PAYLOAD_DIR/get-quotas.sh"
}

prepare_main_fixture() {
    local release_archive="$1" fixture="$repo_root/tests/fixtures/end4-dots/ii"

    prepare_remote_fixture
    CONFIG_ROOT="$TEST_TMP_ROOT/config"
    INSTALL_DIR="$CONFIG_ROOT/modules/ii/bar"
    MOCK_SECRET_STORE_DIR="$TEST_TMP_ROOT/secrets"
    QUOTAS_SECRET_TOOL_BIN="$repo_root/tests/helpers/mock_secret_tool.sh"
    QUOTAS_SKIP_RESTART=1
    QUOTAS_TIMESTAMP='20260731-143000'
    export QUOTAS_SECRET_TOOL_BIN MOCK_SECRET_STORE_DIR QUOTAS_SKIP_RESTART QUOTAS_TIMESTAMP
    mkdir -p "$INSTALL_DIR" "$MOCK_SECRET_STORE_DIR"
    cp "$fixture/shell.qml" "$CONFIG_ROOT/shell.qml"
    cp "$fixture/modules/ii/bar/BarContent.qml" "$INSTALL_DIR/BarContent.qml"
    prepare_required_commands
    rm "$TEST_TMP_ROOT/bin/curl" "$TEST_TMP_ROOT/bin/jq" "$TEST_TMP_ROOT/bin/tar"
    queue_http_text 200 '{"files":[]}'
    queue_latest_release '[{"name":"quickshell-quotas-widget-v1.0.0.tar.gz","browser_download_url":"https://download.example/release.tar.gz"}]'
    queue_http_file 200 "$release_archive"
}

write_smoke_fetcher() {
    local stdout="$1" exit_code="$2"

    mkdir -p "$INSTALL_DIR" "$WORK_DIR"
    {
        printf '%s\n' '#!/usr/bin/env bash'
        printf 'printf %%s %q\n' "$stdout"
        printf '%s\n' "printf 'fetcher diagnostic' >&2" "exit $exit_code"
    } >"$INSTALL_DIR/get-quotas.sh"
    chmod 700 "$INSTALL_DIR/get-quotas.sh"
}

make_qs_mock() {
    local mock="$TEST_TMP_ROOT/mock-qs"

    cat >"$mock" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$MOCK_QS_LOG"
case "$3" in
    list)
        printf '%s\n' "${MOCK_QS_LIST_JSON:-[]}"
        exit "${MOCK_QS_LIST_EXIT:-0}"
        ;;
    kill)
        exit "${MOCK_QS_KILL_EXIT:-0}"
        ;;
    --daemonize)
        exit "${MOCK_QS_DAEMON_EXIT:-0}"
        ;;
esac
exit 64
EOF
    chmod +x "$mock"
    QUOTAS_QS_BIN="$mock"
    MOCK_QS_LOG="$TEST_TMP_ROOT/qs.log"
    : >"$MOCK_QS_LOG"
    export QUOTAS_QS_BIN MOCK_QS_LOG MOCK_QS_LIST_JSON MOCK_QS_LIST_EXIT
    export MOCK_QS_KILL_EXIT MOCK_QS_DAEMON_EXIT
}

make_command() {
    local name="$1"
    mkdir -p "$TEST_TMP_ROOT/bin"
    printf '#!/usr/bin/env bash\nexit 0\n' >"$TEST_TMP_ROOT/bin/$name"
    chmod +x "$TEST_TMP_ROOT/bin/$name"
}

prepare_required_commands() {
    local command
    for command in hyprctl quickshell curl jq tar notify-send; do
        make_command "$command"
    done
}

test_parse_required_api_url() {
    reset_installer_state
    parse_args --api-url 'http://localhost:8080/' --management-key 'secret' || return 1
    assert_eq 'http://localhost:8080' "$API_URL" || return 1
    assert_eq 'secret' "$MANAGEMENT_KEY" || return 1
    assert_eq 'argument' "$KEY_INPUT_MODE" || return 1
}

test_rejects_conflicting_key_modes() {
    reset_installer_state
    local output status
    set +e
    output="$(parse_args --api-url http://localhost --management-key secret --management-key-stdin 2>&1)"
    status=$?
    set -e
    [[ $status -ne 0 ]] || fail 'conflicting modes must fail' || return 1
    assert_contains "$output" 'mutually exclusive' || return 1
}

test_rejects_unsupported_url_scheme() {
    reset_installer_state
    if normalize_api_url 'file:///tmp/api' >/dev/null 2>&1; then
        fail 'file URL must be rejected'
    fi
}

test_resolves_default_layout() {
    reset_installer_state
    HOME="$TEST_TMP_ROOT/home"
    XDG_CONFIG_HOME="$TEST_TMP_ROOT/config"
    INSTALL_DIR=''
    resolve_layout || return 1
    assert_eq "$TEST_TMP_ROOT/config/quickshell/ii/modules/ii/bar" "$INSTALL_DIR" || return 1
    assert_eq "$TEST_TMP_ROOT/config/quickshell/ii" "$CONFIG_ROOT" || return 1
}

test_accepts_compatible_end4_layout() {
    prepare_end4_fixture
    validate_end4_layout || return 1
}

test_help_exits_zero() {
    reset_installer_state
    local output status
    set +e
    output="$(parse_args --help 2>&1)"
    status=$?
    set -e
    assert_eq '0' "$status" || return 1
    assert_contains "$output" 'Usage:' || return 1
}

test_rejects_unknown_flag() {
    reset_installer_state
    local output status
    set +e
    output="$(parse_args --unknown 2>&1)"
    status=$?
    set -e
    [[ $status -ne 0 ]] || fail 'unknown flag must fail' || return 1
    assert_contains "$output" '--unknown' || return 1
}

test_rejects_missing_flag_value() {
    reset_installer_state
    local output status
    set +e
    output="$(parse_args --api-url 2>&1)"
    status=$?
    set -e
    [[ $status -ne 0 ]] || fail 'missing flag value must fail' || return 1
    assert_contains "$output" '--api-url' || return 1
}

test_rejects_empty_key() {
    reset_installer_state
    local output status
    set +e
    output="$(parse_args --management-key '' 2>&1)"
    status=$?
    set -e
    [[ $status -ne 0 ]] || fail 'empty key must fail' || return 1
    assert_contains "$output" '--management-key' || return 1
}

test_rejects_option_as_management_key_value() {
    reset_installer_state
    local output status
    set +e
    output="$(parse_args --api-url http://localhost --management-key --management-key-stdin 2>&1)"
    status=$?
    set -e
    [[ $status -ne 0 ]] || fail 'management key option token must fail' || return 1
    assert_contains "$output" '--management-key' || return 1
}

test_usage_remains_bilingual() {
    local output russian_usage
    russian_usage="$(printf '%b' '\xD0\x98\xD1\x81\xD0\xBF\xD0\xBE\xD0\xBB\xD1\x8C\xD0\xB7\xD0\xBE\xD0\xB2\xD0\xB0\xD0\xBD\xD0\xB8\xD0\xB5')"
    output="$(usage)"
    assert_contains "$output" 'Usage:' || return 1
    assert_contains "$output" "$russian_usage" || return 1
}

test_shell_sources_are_ascii() {
    local output status
    set +e
    output="$(LC_ALL=C grep -n '[^ -~]' "$repo_root/install.sh" "$repo_root"/tests/*.bash 2>&1)"
    status=$?
    set -e
    [[ $status -eq 1 ]] || fail "non-ASCII shell source: $output" || return 1
}

test_accepts_http_url() {
    reset_installer_state
    assert_eq 'http://example.com/api' "$(normalize_api_url 'http://example.com/api///')" || return 1
}

test_accepts_https_url() {
    reset_installer_state
    assert_eq 'https://example.com' "$(normalize_api_url 'https://example.com/')" || return 1
}

test_resolves_custom_install_dir() {
    reset_installer_state
    INSTALL_DIR="$TEST_TMP_ROOT/custom/modules/ii/bar"
    mkdir -p "$INSTALL_DIR"
    resolve_layout || return 1
    assert_eq "$TEST_TMP_ROOT/custom/modules/ii/bar" "$INSTALL_DIR" || return 1
    assert_eq "$TEST_TMP_ROOT/custom" "$CONFIG_ROOT" || return 1
}

test_rejects_bash_3() {
    local output status
    set +e
    output="$(require_bash_version 3 2>&1)"
    status=$?
    set -e
    [[ $status -ne 0 ]] || fail 'Bash 3 must fail' || return 1
    assert_contains "$output" 'Bash 3' || return 1
}

test_accepts_bash_4() {
    require_bash_version 4 || return 1
}

test_rejects_missing_bar_content() {
    prepare_end4_fixture
    rm "$CONFIG_ROOT/modules/ii/bar/BarContent.qml"
    local output status
    set +e
    output="$(validate_end4_layout 2>&1)"
    status=$?
    set -e
    [[ $status -ne 0 ]] || fail 'missing BarContent.qml must fail' || return 1
    assert_contains "$output" 'BarContent.qml' || return 1
}

test_rejects_missing_shell_qml() {
    prepare_end4_fixture
    rm "$CONFIG_ROOT/shell.qml"
    local output status
    set +e
    output="$(validate_end4_layout 2>&1)"
    status=$?
    set -e
    [[ $status -ne 0 ]] || fail 'missing shell.qml must fail' || return 1
    assert_contains "$output" 'shell.qml' || return 1
}

test_rejects_missing_left_center_group() {
    prepare_end4_fixture
    printf 'import QtQuick\nItem { Resources {} Media {} }\n' >"$CONFIG_ROOT/modules/ii/bar/BarContent.qml"
    local output status
    set +e
    output="$(validate_end4_layout 2>&1)"
    status=$?
    set -e
    [[ $status -ne 0 ]] || fail 'missing leftCenterGroup must fail' || return 1
    assert_contains "$output" 'leftCenterGroup' || return 1
}

test_rejects_missing_resources() {
    prepare_end4_fixture
    printf 'import QtQuick\nItem { BarGroup { id: leftCenterGroup Media {} } }\n' >"$CONFIG_ROOT/modules/ii/bar/BarContent.qml"
    local output status
    set +e
    output="$(validate_end4_layout 2>&1)"
    status=$?
    set -e
    [[ $status -ne 0 ]] || fail 'missing Resources must fail' || return 1
    assert_contains "$output" 'Resources' || return 1
}

assert_missing_dependency() {
    local command_name="$1"
    prepare_required_commands
    rm "$TEST_TMP_ROOT/bin/$command_name"
    reset_installer_state
    local output status
    set +e
    output="$(PATH="$TEST_TMP_ROOT/bin" require_dependencies 2>&1)"
    status=$?
    set -e
    [[ $status -ne 0 ]] || fail "missing $command_name must fail" || return 1
    assert_contains "$output" "$command_name" || return 1
}

test_reports_missing_hyprctl() {
    assert_missing_dependency hyprctl
}

test_reports_missing_quickshell() {
    assert_missing_dependency quickshell
}

test_reports_missing_curl() {
    assert_missing_dependency curl
}

test_reports_missing_jq() {
    assert_missing_dependency jq
}

test_reports_missing_tar() {
    assert_missing_dependency tar
}

test_warns_when_notify_send_is_missing() {
    prepare_required_commands
    rm "$TEST_TMP_ROOT/bin/notify-send"
    reset_installer_state
    local output status
    set +e
    output="$(PATH="$TEST_TMP_ROOT/bin" require_dependencies 2>&1)"
    status=$?
    set -e
    assert_eq '0' "$status" || return 1
    assert_contains "$output" 'notify-send' || return 1
    assert_contains "$output" 'refresh still works' || return 1
}

test_reads_management_key_from_stdin_without_leaking_it() {
    prepare_remote_fixture
    local fixture="$repo_root/tests/fixtures/end4-dots/ii"
    local key='stdin-super-secret' output status
    CONFIG_ROOT="$TEST_TMP_ROOT/config"
    INSTALL_DIR="$CONFIG_ROOT/modules/ii/bar"
    mkdir -p "$INSTALL_DIR"
    cp "$fixture/shell.qml" "$CONFIG_ROOT/shell.qml"
    cp "$fixture/modules/ii/bar/BarContent.qml" "$INSTALL_DIR/BarContent.qml"
    prepare_required_commands
    queue_http_text 401 '{"error":"unauthorized"}'
    set +e
    output="$(printf '%s\n' "$key" | env \
        PATH="$TEST_TMP_ROOT/bin:$PATH" \
        QUOTAS_CURL_BIN="$QUOTAS_CURL_BIN" \
        MOCK_CURL_QUEUE_DIR="$MOCK_CURL_QUEUE_DIR" \
        MOCK_CURL_LOG="$MOCK_CURL_LOG" \
        MOCK_CURL_HEADERS_LOG="$MOCK_CURL_HEADERS_LOG" \
        bash "$repo_root/install.sh" --api-url https://management.example \
            --management-key-stdin --install-dir "$INSTALL_DIR" 2>&1)"
    status=$?
    set -e
    [[ $status -ne 0 ]] || fail 'unauthorized stdin key validation must fail' || return 1
    [[ "$output" != *"$key"* ]] || fail 'stdin management key leaked into output' || return 1
    [[ "$(<"$MOCK_CURL_LOG")" != *"$key"* ]] || fail 'stdin management key leaked into curl arguments' || return 1
    [[ ! -e "$INSTALL_DIR/Quotas.qml" ]] || fail 'installer wrote payload before API validation'
}

test_rejects_empty_management_key_from_stdin() {
    reset_installer_state
    KEY_INPUT_MODE='stdin'
    local output status
    set +e
    output="$(read_management_key </dev/null 2>&1)"
    status=$?
    set -e
    [[ $status -ne 0 ]] || fail 'empty stdin key must fail' || return 1
    assert_contains "$output" 'empty'
}

test_reads_management_key_from_tty_file() {
    reset_installer_state
    local tty_file="$TEST_TMP_ROOT/tty" output
    printf 'tty-super-secret\n' >"$tty_file"
    QUOTAS_TTY_PATH="$tty_file"
    read_management_key || return 1
    assert_eq 'tty-super-secret' "$MANAGEMENT_KEY" || return 1
    output="$(<"$tty_file")"
    assert_contains "$output" 'Management key' || return 1
    assert_eq '1' "$(grep -o 'tty-super-secret' "$tty_file" | wc -l)" || return 1
}

test_validate_api_rejects_transport_failure() {
    prepare_remote_fixture
    queue_http_text 200 '{"files":[]}'
    MOCK_CURL_EXIT_CODE=7
    assert_remote_failure 'transport' validate_api
}

test_validate_api_rejects_401() {
    prepare_remote_fixture
    queue_http_text 401 '{"error":"unauthorized"}'
    assert_remote_failure '401' validate_api
}

test_validate_api_rejects_403() {
    prepare_remote_fixture
    queue_http_text 403 '{"error":"forbidden"}'
    assert_remote_failure '403' validate_api
}

test_validate_api_rejects_500() {
    prepare_remote_fixture
    queue_http_text 500 '{"error":"server"}'
    assert_remote_failure '500' validate_api
}

test_validate_api_rejects_malformed_json() {
    prepare_remote_fixture
    queue_http_text 200 'not-json'
    assert_remote_failure 'invalid JSON' validate_api
}

test_validate_api_rejects_multiple_json_documents() {
    prepare_remote_fixture
    queue_http_text 200 $'{"files":[]}\n{"files":[]}'
    assert_remote_failure 'single JSON document' validate_api
}

test_validate_api_rejects_missing_files() {
    prepare_remote_fixture
    queue_http_text 200 '{}'
    assert_remote_failure 'files array' validate_api
}

test_validate_api_rejects_non_array_files() {
    prepare_remote_fixture
    queue_http_text 200 '{"files":null}'
    assert_remote_failure 'files array' validate_api
}

test_validate_api_accepts_files_array_and_hides_key_from_argv() {
    prepare_remote_fixture
    queue_http_text 200 '{"files":[]}'
    run_with_mock_curl validate_api || return 1
    assert_contains "$(<"$MOCK_CURL_HEADERS_LOG")" 'Authorization: Bearer never-log-this-key' || return 1
    assert_eq '600' "$(<"$MOCK_CURL_HEADER_MODES_LOG")" || return 1
    [[ "$(<"$MOCK_CURL_LOG")" != *"$MANAGEMENT_KEY"* ]] || fail 'management key leaked into curl arguments'
}

test_every_curl_call_disables_curlrc_first() {
    prepare_remote_fixture
    create_release_archive "$TEST_TMP_ROOT/release.tar.gz"
    queue_http_text 200 '{"files":[]}'
    queue_latest_release '[{"name":"quickshell-quotas-widget-v1.0.0.tar.gz","browser_download_url":"https://download.example/release.tar.gz"}]'
    queue_http_file 200 "$TEST_TMP_ROOT/release.tar.gz"

    run_with_mock_curl validate_api || return 1
    run_with_mock_curl fetch_latest_release || return 1

    local line
    while IFS= read -r line; do
        [[ "$line" == 'curl --disable '* ]] || fail "curl must pass --disable first: $line" || return 1
    done <"$MOCK_CURL_LOG"
}

test_api_temporary_files_are_owned_by_global_cleanup() {
    prepare_remote_fixture
    queue_http_text 200 '{"files":[]}'

    run_with_mock_curl validate_api || return 1

    local path
    while IFS= read -r path; do
        [[ "$path" == "$WORK_DIR/"* ]] || fail "API temporary file escaped WORK_DIR: $path" || return 1
    done < <(cat "$MOCK_CURL_OUTPUTS_LOG" "$MOCK_CURL_HEADER_PATHS_LOG")
    printf 'leftover\n' >"$WORK_DIR/unexpected-termination-file"
    cleanup_work_dir || return 1
    [[ ! -e "$WORK_DIR" ]] || fail 'global cleanup must remove API temporary directory'
}

test_fetch_latest_release_rejects_missing_asset() {
    prepare_remote_fixture
    queue_latest_release '[]'
    assert_remote_failure 'exactly one' fetch_latest_release
}

test_fetch_latest_release_rejects_duplicate_assets() {
    prepare_remote_fixture
    queue_latest_release '[{"name":"quickshell-quotas-widget-v1.0.0.tar.gz","browser_download_url":"https://download.example/one"},{"name":"quickshell-quotas-widget-v2.0.0.tar.gz","browser_download_url":"https://download.example/two"}]'
    assert_remote_failure 'exactly one' fetch_latest_release
}

test_release_package_matches_archive_contract() {
    prepare_remote_fixture
    bash "$repo_root/scripts/package-release.sh" v1.0.0 "$TEST_TMP_ROOT/dist" || return 1
    ARCHIVE_PATH="$TEST_TMP_ROOT/dist/quickshell-quotas-widget-v1.0.0.tar.gz"

    validate_archive || return 1
    assert_eq $'Quotas.qml\nQuotasPopup.qml\nget-quotas.sh' "$(tar -tzf "$ARCHIVE_PATH")"
}

test_release_package_is_reproducible_across_filesystem_metadata() {
    local first_root="$TEST_TMP_ROOT/first" second_root="$TEST_TMP_ROOT/second" payload

    for payload in Quotas.qml QuotasPopup.qml get-quotas.sh; do
        mkdir -p "$first_root/scripts" "$second_root/scripts"
        cp "$repo_root/$payload" "$first_root/$payload"
        cp "$repo_root/$payload" "$second_root/$payload"
    done
    cp "$repo_root/scripts/package-release.sh" "$first_root/scripts/package-release.sh"
    cp "$repo_root/scripts/package-release.sh" "$second_root/scripts/package-release.sh"
    touch -t 202001010101 "$first_root" "$first_root/scripts" "$first_root"/*.*
    touch -t 203001010101 "$second_root" "$second_root/scripts" "$second_root"/*.*

    bash "$first_root/scripts/package-release.sh" v1.0.0 "$TEST_TMP_ROOT/first-dist" || return 1
    bash "$second_root/scripts/package-release.sh" v1.0.0 "$TEST_TMP_ROOT/second-dist" || return 1

    cmp -s \
        "$TEST_TMP_ROOT/first-dist/quickshell-quotas-widget-v1.0.0.tar.gz" \
        "$TEST_TMP_ROOT/second-dist/quickshell-quotas-widget-v1.0.0.tar.gz" \
        || fail 'equivalent payloads with different filesystem metadata must produce identical archives'
}

test_validate_archive_rejects_parent_entry() {
    prepare_remote_fixture
    local source_dir="$TEST_TMP_ROOT/archive-source"
    mkdir -p "$source_dir"
    printf 'unsafe\n' >"$source_dir/escape"
    tar -C "$source_dir" --transform='s|^|../|' -czf "$TEST_TMP_ROOT/unsafe.tar.gz" escape
    ARCHIVE_PATH="$TEST_TMP_ROOT/unsafe.tar.gz"
    assert_remote_failure 'unsafe archive' validate_archive
}

test_validate_archive_rejects_absolute_entry() {
    prepare_remote_fixture
    local absolute_file="$TEST_TMP_ROOT/absolute-entry"
    printf 'unsafe\n' >"$absolute_file"
    tar -P -czf "$TEST_TMP_ROOT/unsafe.tar.gz" "$absolute_file"
    ARCHIVE_PATH="$TEST_TMP_ROOT/unsafe.tar.gz"
    assert_remote_failure 'unsafe archive' validate_archive
}

test_validate_archive_rejects_missing_payload_file() {
    prepare_remote_fixture
    mkdir -p "$TEST_TMP_ROOT/payload"
    printf 'qml\n' >"$TEST_TMP_ROOT/payload/Quotas.qml"
    printf 'qml\n' >"$TEST_TMP_ROOT/payload/QuotasPopup.qml"
    tar -C "$TEST_TMP_ROOT/payload" -czf "$TEST_TMP_ROOT/incomplete.tar.gz" Quotas.qml QuotasPopup.qml
    ARCHIVE_PATH="$TEST_TMP_ROOT/incomplete.tar.gz"
    assert_remote_failure 'exactly once' validate_archive
}

test_validate_archive_rejects_duplicate_payload_file() {
    prepare_remote_fixture
    mkdir -p "$TEST_TMP_ROOT/payload"
    printf 'qml\n' >"$TEST_TMP_ROOT/payload/Quotas.qml"
    printf 'qml\n' >"$TEST_TMP_ROOT/payload/QuotasPopup.qml"
    printf '#!/usr/bin/env bash\nexit 0\n' >"$TEST_TMP_ROOT/payload/get-quotas.sh"
    tar -C "$TEST_TMP_ROOT/payload" -czf "$TEST_TMP_ROOT/duplicate.tar.gz" \
        Quotas.qml Quotas.qml QuotasPopup.qml get-quotas.sh
    ARCHIVE_PATH="$TEST_TMP_ROOT/duplicate.tar.gz"
    assert_remote_failure 'exactly once' validate_archive
}

test_validate_archive_rejects_extra_top_level_file() {
    prepare_remote_fixture
    create_release_archive "$TEST_TMP_ROOT/extra.tar.gz"
    printf 'extra\n' >"$TEST_TMP_ROOT/payload/README"
    tar -C "$TEST_TMP_ROOT/payload" -czf "$TEST_TMP_ROOT/extra.tar.gz" \
        Quotas.qml QuotasPopup.qml get-quotas.sh README
    ARCHIVE_PATH="$TEST_TMP_ROOT/extra.tar.gz"
    assert_remote_failure 'unexpected archive entry' validate_archive
}

test_validate_archive_rejects_nested_path() {
    prepare_remote_fixture
    mkdir -p "$TEST_TMP_ROOT/payload/nested"
    printf 'qml\n' >"$TEST_TMP_ROOT/payload/nested/Quotas.qml"
    printf 'qml\n' >"$TEST_TMP_ROOT/payload/QuotasPopup.qml"
    printf '#!/usr/bin/env bash\nexit 0\n' >"$TEST_TMP_ROOT/payload/get-quotas.sh"
    tar -C "$TEST_TMP_ROOT/payload" -czf "$TEST_TMP_ROOT/nested.tar.gz" \
        nested/Quotas.qml QuotasPopup.qml get-quotas.sh
    ARCHIVE_PATH="$TEST_TMP_ROOT/nested.tar.gz"
    assert_remote_failure 'unsafe archive' validate_archive
}

test_validate_archive_rejects_dot_component() {
    prepare_remote_fixture
    create_release_archive "$TEST_TMP_ROOT/dot.tar.gz"
    tar -C "$TEST_TMP_ROOT/payload" --transform='s|^Quotas.qml$|./Quotas.qml|' \
        -czf "$TEST_TMP_ROOT/dot.tar.gz" Quotas.qml QuotasPopup.qml get-quotas.sh
    ARCHIVE_PATH="$TEST_TMP_ROOT/dot.tar.gz"
    assert_remote_failure 'unsafe archive' validate_archive
}

test_validate_archive_rejects_symlink() {
    prepare_remote_fixture
    mkdir -p "$TEST_TMP_ROOT/payload"
    printf 'target\n' >"$TEST_TMP_ROOT/payload/target"
    ln -s target "$TEST_TMP_ROOT/payload/Quotas.qml"
    printf 'qml\n' >"$TEST_TMP_ROOT/payload/QuotasPopup.qml"
    printf '#!/usr/bin/env bash\nexit 0\n' >"$TEST_TMP_ROOT/payload/get-quotas.sh"
    tar -C "$TEST_TMP_ROOT/payload" -czf "$TEST_TMP_ROOT/symlink.tar.gz" \
        Quotas.qml QuotasPopup.qml get-quotas.sh
    ARCHIVE_PATH="$TEST_TMP_ROOT/symlink.tar.gz"
    assert_remote_failure 'regular files' validate_archive
}

test_validate_archive_rejects_hardlink() {
    prepare_remote_fixture
    mkdir -p "$TEST_TMP_ROOT/payload"
    printf 'qml\n' >"$TEST_TMP_ROOT/payload/Quotas.qml"
    ln "$TEST_TMP_ROOT/payload/Quotas.qml" "$TEST_TMP_ROOT/payload/QuotasPopup.qml"
    printf '#!/usr/bin/env bash\nexit 0\n' >"$TEST_TMP_ROOT/payload/get-quotas.sh"
    tar -C "$TEST_TMP_ROOT/payload" -czf "$TEST_TMP_ROOT/hardlink.tar.gz" \
        Quotas.qml QuotasPopup.qml get-quotas.sh
    ARCHIVE_PATH="$TEST_TMP_ROOT/hardlink.tar.gz"
    assert_remote_failure 'regular files' validate_archive
}

test_validate_archive_rejects_fifo() {
    prepare_remote_fixture
    mkdir -p "$TEST_TMP_ROOT/payload"
    mkfifo "$TEST_TMP_ROOT/payload/Quotas.qml"
    printf 'qml\n' >"$TEST_TMP_ROOT/payload/QuotasPopup.qml"
    printf '#!/usr/bin/env bash\nexit 0\n' >"$TEST_TMP_ROOT/payload/get-quotas.sh"
    tar -C "$TEST_TMP_ROOT/payload" -czf "$TEST_TMP_ROOT/fifo.tar.gz" \
        Quotas.qml QuotasPopup.qml get-quotas.sh
    ARCHIVE_PATH="$TEST_TMP_ROOT/fifo.tar.gz"
    assert_remote_failure 'regular files' validate_archive
}

# The generated tar mock must retain its shell expressions literally.
# shellcheck disable=SC2016
test_validate_archive_stops_when_verbose_listing_fails() {
    prepare_remote_fixture
    create_release_archive "$TEST_TMP_ROOT/release.tar.gz"
    local real_tar mock_tar="$TEST_TMP_ROOT/mock-tar" extract_log="$TEST_TMP_ROOT/extract.log"
    real_tar="$(command -v tar)"
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -euo pipefail' \
        'if [[ "$1" == "-tvzf" ]]; then' \
        '    "$REAL_TAR" "$@"' \
        '    exit 23' \
        'fi' \
        'if [[ "$1" == "-xzf" ]]; then' \
        '    : >"$MOCK_TAR_EXTRACT_LOG"' \
        'fi' \
        'exec "$REAL_TAR" "$@"' >"$mock_tar"
    chmod +x "$mock_tar"
    ARCHIVE_PATH="$TEST_TMP_ROOT/release.tar.gz"
    QUOTAS_TAR_BIN="$mock_tar"
    export REAL_TAR="$real_tar" MOCK_TAR_EXTRACT_LOG="$extract_log"

    assert_remote_failure 'cannot inspect release archive' validate_archive || return 1
    [[ ! -e "$extract_log" ]] || fail 'archive extraction must not run after verbose listing failure'
}

test_fetch_latest_release_downloads_and_extracts_valid_payload() {
    prepare_remote_fixture
    create_release_archive "$TEST_TMP_ROOT/release.tar.gz"
    queue_latest_release '[{"name":"quickshell-quotas-widget-v1.0.0.tar.gz","browser_download_url":"https://download.example/release.tar.gz"}]'
    queue_http_file 200 "$TEST_TMP_ROOT/release.tar.gz"
    run_with_mock_curl fetch_latest_release || return 1
    validate_archive || return 1
    assert_file_exists "$PAYLOAD_DIR/Quotas.qml" || return 1
    assert_file_exists "$PAYLOAD_DIR/QuotasPopup.qml" || return 1
    assert_file_exists "$PAYLOAD_DIR/get-quotas.sh"
}

test_stores_and_verifies_keyring_values() {
    prepare_installer_fixture
    store_credentials || return 1
    assert_eq 'keyring' "$CREDENTIAL_BACKEND" || return 1
    assert_eq "$API_URL" "$(<"$MOCK_SECRET_STORE_DIR/quotasApiUrl")" || return 1
    assert_eq "$MANAGEMENT_KEY" "$(<"$MOCK_SECRET_STORE_DIR/quotasManagementKey")" || return 1
    [[ ! -e "$INSTALL_DIR/quotas-widget.conf" ]] || fail 'fallback must be absent'
}

test_verifies_keyring_value_ending_in_newline() {
    prepare_installer_fixture
    MANAGEMENT_KEY=$'key-ending-in-newline\n'
    store_credentials || return 1
    assert_eq 'keyring' "$CREDENTIAL_BACKEND" || return 1
    [[ ! -e "$INSTALL_DIR/quotas-widget.conf" ]] || fail 'exact keyring match must not create fallback'
}

test_writes_json_fallback_with_mode_600() {
    prepare_installer_fixture
    QUOTAS_SECRET_TOOL_BIN="$TEST_TMP_ROOT/missing-secret-tool"
    store_credentials || return 1
    assert_eq 'file' "$CREDENTIAL_BACKEND" || return 1
    jq -e --arg url "$API_URL" --arg key "$MANAGEMENT_KEY" \
        '.apiUrl == $url and .managementKey == $key' \
        "$INSTALL_DIR/quotas-widget.conf" >/dev/null || return 1
    assert_file_mode 600 "$INSTALL_DIR/quotas-widget.conf"
}

test_falls_back_after_keyring_store_failure() {
    prepare_installer_fixture
    MOCK_SECRET_FAIL_STORE=23
    export MOCK_SECRET_FAIL_STORE
    store_credentials || return 1
    assert_eq 'file' "$CREDENTIAL_BACKEND" || return 1
    assert_file_exists "$INSTALL_DIR/quotas-widget.conf"
}

test_falls_back_after_keyring_lookup_failure() {
    prepare_installer_fixture
    MOCK_SECRET_FAIL_LOOKUP=24
    export MOCK_SECRET_FAIL_LOOKUP
    store_credentials || return 1
    assert_eq 'file' "$CREDENTIAL_BACKEND" || return 1
    assert_eq $'quotasApiUrl\nquotasManagementKey' "$(<"$MOCK_SECRET_LOOKUP_LOG")" || return 1
    assert_file_exists "$INSTALL_DIR/quotas-widget.conf"
}

test_falls_back_after_keyring_lookup_mismatch() {
    prepare_installer_fixture
    MOCK_SECRET_LOOKUP_OVERRIDE_KEY='quotasManagementKey'
    MOCK_SECRET_LOOKUP_OVERRIDE_VALUE='wrong-key'
    export MOCK_SECRET_LOOKUP_OVERRIDE_KEY MOCK_SECRET_LOOKUP_OVERRIDE_VALUE
    store_credentials || return 1
    assert_eq 'file' "$CREDENTIAL_BACKEND" || return 1
    assert_file_exists "$INSTALL_DIR/quotas-widget.conf"
}

test_falls_back_after_partial_keyring_write() {
    prepare_installer_fixture
    MOCK_SECRET_FAIL_STORE_KEY='quotasManagementKey'
    MOCK_SECRET_FAIL_STORE_KEY_CODE=25
    export MOCK_SECRET_FAIL_STORE_KEY MOCK_SECRET_FAIL_STORE_KEY_CODE
    store_credentials || return 1
    assert_eq 'file' "$CREDENTIAL_BACKEND" || return 1
    assert_file_exists "$MOCK_SECRET_STORE_DIR/quotasApiUrl" || return 1
    [[ ! -e "$MOCK_SECRET_STORE_DIR/quotasManagementKey" ]] || fail 'second keyring value must be absent' || return 1
    assert_file_exists "$INSTALL_DIR/quotas-widget.conf"
}

test_removes_existing_fallback_after_keyring_success() {
    prepare_installer_fixture
    printf '{"apiUrl":"stale","managementKey":"stale"}\n' >"$INSTALL_DIR/quotas-widget.conf"
    store_credentials || return 1
    assert_eq 'keyring' "$CREDENTIAL_BACKEND" || return 1
    [[ ! -e "$INSTALL_DIR/quotas-widget.conf" ]] || fail 'verified keyring must remove stale fallback'
}

test_preserves_special_characters_in_fallback_json() {
    prepare_installer_fixture
    MANAGEMENT_KEY=$'quotes " backslashes \\ spaces and\na newline'
    QUOTAS_SECRET_TOOL_BIN="$TEST_TMP_ROOT/missing-secret-tool"
    store_credentials || return 1
    jq -e --arg url "$API_URL" --arg key "$MANAGEMENT_KEY" \
        '.apiUrl == $url and .managementKey == $key' \
        "$INSTALL_DIR/quotas-widget.conf" >/dev/null
}

test_keeps_credentials_out_of_jq_argv() {
    prepare_installer_fixture
    local jq_argv jq_bin_dir="$TEST_TMP_ROOT/jq-bin"
    API_URL='https://management.example/path with spaces'
    MANAGEMENT_KEY=$'argv-secret-"-\\-with spaces\nand-newline'
    QUOTAS_SECRET_TOOL_BIN="$TEST_TMP_ROOT/missing-secret-tool"
    MOCK_JQ_ARGV_LOG="$TEST_TMP_ROOT/jq-argv.log"
    MOCK_JQ_STDIN_MODE_LOG="$TEST_TMP_ROOT/jq-stdin-mode.log"
    MOCK_JQ_STDIN_PATH_LOG="$TEST_TMP_ROOT/jq-stdin-path.log"
    REAL_JQ_BIN="$(command -v jq)"
    mkdir -p "$jq_bin_dir"
    cp "$JQ_MOCK" "$jq_bin_dir/jq"
    chmod +x "$jq_bin_dir/jq"
    export MOCK_JQ_ARGV_LOG MOCK_JQ_STDIN_MODE_LOG MOCK_JQ_STDIN_PATH_LOG REAL_JQ_BIN

    PATH="$jq_bin_dir:$PATH" store_credentials || return 1

    jq_argv="$(tr '\0' '\n' <"$MOCK_JQ_ARGV_LOG")"
    [[ "$jq_argv" != *"$API_URL"* ]] || fail 'API URL leaked into jq arguments' || return 1
    [[ "$jq_argv" != *"$MANAGEMENT_KEY"* ]] || fail 'management key leaked into jq arguments' || return 1
    assert_eq '600' "$(<"$MOCK_JQ_STDIN_MODE_LOG")" || return 1
    [[ "$(<"$MOCK_JQ_STDIN_PATH_LOG")" == "$WORK_DIR/"* ]] || fail 'jq input must be owned by WORK_DIR cleanup' || return 1
    jq -e --arg url "$API_URL" --arg key "$MANAGEMENT_KEY" \
        '.apiUrl == $url and .managementKey == $key' \
        "$FALLBACK_CONFIG" >/dev/null || return 1
    assert_file_mode 600 "$FALLBACK_CONFIG" || return 1
    [[ -z "$(find "$WORK_DIR" -maxdepth 1 -type f -print -quit)" ]] || fail 'credential input must be removed after fallback write'
}

test_never_logs_management_key() {
    prepare_installer_fixture
    local output
    MANAGEMENT_KEY=$'exact-secret-"-\\-with spaces\nand-newline'
    QUOTAS_SECRET_TOOL_BIN="$TEST_TMP_ROOT/missing-secret-tool"
    output="$(store_credentials 2>&1)" || return 1
    [[ "$output" != *"$MANAGEMENT_KEY"* ]] || fail 'management key leaked into credential storage output'
}

test_fallback_warning_is_bilingual() {
    prepare_installer_fixture
    local output russian_storage
    QUOTAS_SECRET_TOOL_BIN="$TEST_TMP_ROOT/missing-secret-tool"
    output="$(store_credentials 2>&1)" || return 1
    russian_storage="$(printf '%b' '\xD1\x85\xD1\x80\xD0\xB0\xD0\xBD\xD0\xB8\xD0\xBB\xD0\xB8\xD1\x89\xD0\xB0')"
    assert_contains "$output" 'Secret Service credential storage failed verification' || return 1
    assert_contains "$output" "$russian_storage"
}

test_inserts_managed_block_after_balanced_resources() {
    prepare_end4_fixture
    local bar_file="$CONFIG_ROOT/modules/ii/bar/BarContent.qml"
    local expected="$TEST_TMP_ROOT/expected.qml"

    cat >"$bar_file" <<'EOF'
import QtQuick

Item {
    Resources { objectName: "outside" }
    BarGroup {
        id: leftCenterGroup
        Resources {
            property var nested: ({ value: { enabled: true } }) // } ignored
            property string literal: "{not a brace} // not a comment"
        }
        Media {}
    }
}
EOF
    cat >"$expected" <<'EOF'
import QtQuick

Item {
    Resources { objectName: "outside" }
    BarGroup {
        id: leftCenterGroup
        Resources {
            property var nested: ({ value: { enabled: true } }) // } ignored
            property string literal: "{not a brace} // not a comment"
        }
        // quickshell-quotas-widget:start
        Quotas {
            visible: true
            Layout.fillWidth: false
        }
        // quickshell-quotas-widget:end
        Media {}
    }
}
EOF

    integrate_bar_content || return 1
    cmp -s "$expected" "$bar_file" || fail 'managed block was not inserted at the balanced Resources boundary'
}

test_preflight_accepts_braces_in_comments_and_strings() {
    prepare_end4_fixture
    local bar_file="$CONFIG_ROOT/modules/ii/bar/BarContent.qml"

    cat >"$bar_file" <<'EOF'
Item {
    BarGroup {
        id: leftCenterGroup
        Resources {
            property var nested: ({ value: { enabled: true } }) // } ignored
            property string literal: "} not a brace"
        }
        Media {}
    }
}
EOF
    validate_end4_layout
}

test_inserts_after_one_line_resources_component() {
    prepare_end4_fixture
    local bar_file="$CONFIG_ROOT/modules/ii/bar/BarContent.qml"

    cat >"$bar_file" <<'EOF'
Item {
    BarGroup {
        id: leftCenterGroup
        Resources {}
        Media {}
    }
}
EOF
    integrate_bar_content || return 1
    assert_contains "$(<"$bar_file")" $'        Resources {}\n        // quickshell-quotas-widget:start'
}

test_inserts_inside_fully_inline_left_center_group() {
    prepare_end4_fixture
    local bar_file="$CONFIG_ROOT/modules/ii/bar/BarContent.qml"

    printf '%s\n' 'Item { BarGroup { id: leftCenterGroup Resources {} Media {} } }' >"$bar_file"
    integrate_bar_content || return 1
    assert_contains "$(<"$bar_file")" $'Resources {}\n// quickshell-quotas-widget:start\nQuotas {\n    visible: true\n    Layout.fillWidth: false\n}\n// quickshell-quotas-widget:end\n Media {} }'
}

test_rejects_multiple_inline_resources_in_target_group() {
    prepare_end4_fixture
    local bar_file="$CONFIG_ROOT/modules/ii/bar/BarContent.qml"

    printf '%s\n' 'Item { BarGroup { id: leftCenterGroup Resources {} Resources {} Media {} } }' >"$bar_file"
    assert_bar_integration_failure 'exactly one'
}

test_rejects_multiple_inline_target_groups() {
    prepare_end4_fixture
    local bar_file="$CONFIG_ROOT/modules/ii/bar/BarContent.qml"

    printf '%s\n' 'Item { BarGroup { id: leftCenterGroup Resources {} Media {} } BarGroup { id: leftCenterGroup Resources {} Media {} } }' >"$bar_file"
    assert_bar_integration_failure 'exactly one'
}

test_preserves_unterminated_final_line() {
    prepare_end4_fixture
    local bar_file="$CONFIG_ROOT/modules/ii/bar/BarContent.qml"
    local expected="$TEST_TMP_ROOT/expected.qml" file_size last_byte

    printf '%s' $'Item {\n    BarGroup {\n        id: leftCenterGroup\n        Resources {}\n        Media {}\n    }\n}' >"$bar_file"
    printf '%s' $'Item {\n    BarGroup {\n        id: leftCenterGroup\n        Resources {}\n        // quickshell-quotas-widget:start\n        Quotas {\n            visible: true\n            Layout.fillWidth: false\n        }\n        // quickshell-quotas-widget:end\n        Media {}\n    }\n}' >"$expected"

    integrate_bar_content || return 1
    cmp -s "$expected" "$bar_file" || fail 'insertion changed unrelated bytes or final newline state' || return 1
    file_size="$(wc -c <"$bar_file")"
    last_byte="$(od -An -t u1 -j "$((file_size - 1))" -N 1 "$bar_file" | tr -d ' ')"
    [[ "$last_byte" != '10' ]] || fail 'unterminated input gained a final newline'
}

test_bar_integration_is_idempotent() {
    prepare_end4_fixture
    local bar_file="$CONFIG_ROOT/modules/ii/bar/BarContent.qml"

    integrate_bar_content || return 1
    integrate_bar_content || return 1
    assert_eq '1' "$(grep -c '^ *// quickshell-quotas-widget:start$' "$bar_file")" || return 1
    assert_eq '1' "$(grep -c '^ *// quickshell-quotas-widget:end$' "$bar_file")"
}

test_valid_managed_block_preserves_all_existing_bytes() {
    prepare_end4_fixture
    local bar_file="$CONFIG_ROOT/modules/ii/bar/BarContent.qml" before="$TEST_TMP_ROOT/before.qml"

    printf '%s' $'\nItem {\n    BarGroup {\n        id: leftCenterGroup\n        Resources {}\n        // quickshell-quotas-widget:start\n        Quotas {\n            visible: true\n            Layout.fillWidth: false\n        }\n        // quickshell-quotas-widget:end\n        Media {}\n    }\n}' >"$bar_file"
    cp "$bar_file" "$before"

    integrate_bar_content || return 1
    cmp -s "$before" "$bar_file" || fail 'valid managed block must remain byte-for-byte unchanged'
}

assert_bar_integration_failure() {
    local expected="$1" output status

    set +e
    output="$(integrate_bar_content 2>&1)"
    status=$?
    set -e
    [[ $status -ne 0 ]] || fail 'unsafe BarContent.qml integration must fail' || return 1
    assert_contains "$output" "$expected"
}

test_rejects_unbalanced_managed_markers() {
    prepare_end4_fixture
    printf '%s\n' '// quickshell-quotas-widget:start' >>"$CONFIG_ROOT/modules/ii/bar/BarContent.qml"
    assert_bar_integration_failure 'managed markers'
}

test_rejects_duplicate_managed_blocks() {
    prepare_end4_fixture
    local bar_file="$CONFIG_ROOT/modules/ii/bar/BarContent.qml"

    cat >>"$bar_file" <<'EOF'
// quickshell-quotas-widget:start
Quotas {}
// quickshell-quotas-widget:end
// quickshell-quotas-widget:start
Quotas {}
// quickshell-quotas-widget:end
EOF
    assert_bar_integration_failure 'managed markers'
}

test_rejects_reversed_managed_markers() {
    prepare_end4_fixture
    local bar_file="$CONFIG_ROOT/modules/ii/bar/BarContent.qml"

    cat >>"$bar_file" <<'EOF'
// quickshell-quotas-widget:end
Quotas {
    visible: true
    Layout.fillWidth: false
}
// quickshell-quotas-widget:start
EOF
    assert_bar_integration_failure 'managed block'
}

test_rejects_malformed_managed_block() {
    prepare_end4_fixture
    local bar_file="$CONFIG_ROOT/modules/ii/bar/BarContent.qml"

    cat >"$bar_file" <<'EOF'
Item {
    BarGroup {
        id: leftCenterGroup
        Resources {}
        // quickshell-quotas-widget:start
        Quotas {
            visible: false
            Layout.fillWidth: false
        }
        // quickshell-quotas-widget:end
        Media {}
    }
}
EOF
    assert_bar_integration_failure 'managed block'
}

test_rejects_misplaced_managed_block() {
    prepare_end4_fixture
    local bar_file="$CONFIG_ROOT/modules/ii/bar/BarContent.qml"

    cat >"$bar_file" <<'EOF'
Item {
    BarGroup {
        id: leftCenterGroup
        Resources {}
        Media {}
        // quickshell-quotas-widget:start
        Quotas {
            visible: true
            Layout.fillWidth: false
        }
        // quickshell-quotas-widget:end
    }
}
EOF
    assert_bar_integration_failure 'managed block'
}

test_rejects_missing_safe_bar_insertion_point() {
    prepare_end4_fixture
    printf 'Item { BarGroup { id: leftCenterGroup Media {} } }\n' \
        >"$CONFIG_ROOT/modules/ii/bar/BarContent.qml"
    assert_bar_integration_failure 'exactly one'
}

test_rejects_multiple_safe_bar_insertion_points() {
    prepare_end4_fixture
    local bar_file="$CONFIG_ROOT/modules/ii/bar/BarContent.qml"

    cat >"$bar_file" <<'EOF'
Item {
    BarGroup { id: leftCenterGroup Resources {} Media {} }
    BarGroup { id: leftCenterGroup Resources {} Media {} }
}
EOF
    assert_bar_integration_failure 'exactly one'
}

test_reports_unsafe_insertion_under_errexit() {
    prepare_end4_fixture
    printf 'Item { BarGroup { id: leftCenterGroup Media {} } }\n' \
        >"$CONFIG_ROOT/modules/ii/bar/BarContent.qml"
    local output status

    set +e
    output="$(bash -c '
        set -Eeuo pipefail
        QUOTAS_INSTALLER_SOURCE_ONLY=1 source "$1"
        CONFIG_ROOT="$2"
        WORK_DIR="$3"
        integrate_bar_content
    ' _ "$repo_root/install.sh" "$CONFIG_ROOT" "$WORK_DIR" 2>&1)"
    status=$?
    set -e
    [[ $status -ne 0 ]] || fail 'unsafe insertion must fail under errexit' || return 1
    assert_contains "$output" 'exactly one'
}

test_installs_payload_with_expected_modes_and_backups() {
    prepare_transaction_fixture
    printf 'old quotas qml\n' >"$INSTALL_DIR/Quotas.qml"
    printf 'new popup qml\n' >"$INSTALL_DIR/QuotasPopup.qml"
    chmod 644 "$INSTALL_DIR/QuotasPopup.qml"

    begin_transaction || return 1
    install_payload || return 1
    assert_file_mode 644 "$INSTALL_DIR/Quotas.qml" || return 1
    assert_file_mode 644 "$INSTALL_DIR/QuotasPopup.qml" || return 1
    assert_file_mode 700 "$INSTALL_DIR/get-quotas.sh" || return 1
    assert_file_exists "$INSTALL_DIR/Quotas.qml.backup.20260731-143000" || return 1
    [[ ! -e "$INSTALL_DIR/QuotasPopup.qml.backup.20260731-143000" ]] || fail 'identical payload must not receive a backup'
}

test_corrects_identical_payload_modes_transactionally() {
    prepare_transaction_fixture
    cp "$PAYLOAD_DIR/Quotas.qml" "$INSTALL_DIR/Quotas.qml"
    cp "$PAYLOAD_DIR/get-quotas.sh" "$INSTALL_DIR/get-quotas.sh"
    chmod 600 "$INSTALL_DIR/Quotas.qml"
    chmod 644 "$INSTALL_DIR/get-quotas.sh"
    touch -t 202001020304.05 "$INSTALL_DIR/get-quotas.sh"
    local original_mtime
    original_mtime="$(stat -c '%Y' "$INSTALL_DIR/get-quotas.sh")"

    begin_transaction || return 1
    install_payload || return 1
    assert_file_mode 644 "$INSTALL_DIR/Quotas.qml" || return 1
    assert_file_mode 700 "$INSTALL_DIR/get-quotas.sh" || return 1
    assert_file_mode 600 "$INSTALL_DIR/Quotas.qml.backup.20260731-143000" || return 1
    assert_file_mode 644 "$INSTALL_DIR/get-quotas.sh.backup.20260731-143000" || return 1
    rollback_transaction || return 1
    assert_file_mode 600 "$INSTALL_DIR/Quotas.qml" || return 1
    assert_file_mode 644 "$INSTALL_DIR/get-quotas.sh" || return 1
    assert_eq "$original_mtime" "$(stat -c '%Y' "$INSTALL_DIR/get-quotas.sh")"
}

test_corrects_identical_fallback_mode_transactionally() {
    prepare_installer_fixture
    QUOTAS_SECRET_TOOL_BIN="$TEST_TMP_ROOT/missing-secret-tool"
    QUOTAS_TIMESTAMP='20260731-143000'
    store_credentials >/dev/null 2>&1 || return 1
    chmod 644 "$FALLBACK_CONFIG"

    begin_transaction || return 1
    store_credentials >/dev/null 2>&1 || return 1
    assert_file_mode 600 "$FALLBACK_CONFIG" || return 1
    assert_file_mode 600 "$FALLBACK_CONFIG.backup.20260731-143000" || return 1
    rollback_transaction || return 1
    assert_file_mode 644 "$FALLBACK_CONFIG"
}

test_keyring_switch_secures_fallback_backup_and_restores_original_mode() {
    prepare_installer_fixture
    QUOTAS_TIMESTAMP='20260731-143000'
    FALLBACK_CONFIG="$INSTALL_DIR/quotas-widget.conf"
    printf '{"apiUrl":"old","managementKey":"old"}\n' >"$FALLBACK_CONFIG"
    chmod 644 "$FALLBACK_CONFIG"

    begin_transaction || return 1
    store_credentials || return 1
    [[ ! -e "$FALLBACK_CONFIG" ]] || fail 'keyring switch must remove active fallback' || return 1
    assert_file_mode 600 "$FALLBACK_CONFIG.backup.20260731-143000" || return 1
    rollback_transaction || return 1
    assert_eq '{"apiUrl":"old","managementKey":"old"}' "$(<"$FALLBACK_CONFIG")" || return 1
    assert_file_mode 644 "$FALLBACK_CONFIG"
}

test_writable_target_preflight_covers_every_persistent_destination() {
    local stage output status

    for stage in install-dir bar-content payload fallback; do
        prepare_transaction_fixture
        QUOTAS_WRITABLE_PROBE_FAIL="$stage"
        set +e
        output="$(validate_writable_targets 2>&1)"
        status=$?
        set -e
        [[ $status -ne 0 ]] || fail "forced $stage probe failure must fail" || return 1
        assert_contains "$output" "$stage" || return 1
        if compgen -G "$INSTALL_DIR/*.probe.*" >/dev/null \
            || compgen -G "$INSTALL_DIR/*.backup.20260731-143000" >/dev/null; then
            fail 'writable probe artifact remained' || return 1
        fi
    done
}

test_main_rejects_unwritable_target_before_keyring_writes() {
    local release_archive="$TEST_TMP_ROOT/release.tar.gz" output status
    create_release_archive "$release_archive"
    prepare_main_fixture "$release_archive"
    QUOTAS_WRITABLE_PROBE_FAIL='bar-content'
    export QUOTAS_WRITABLE_PROBE_FAIL

    set +e
    output="$(PATH="$TEST_TMP_ROOT/bin:$PATH" run_with_mock_curl main \
        --api-url "$API_URL" --management-key "$MANAGEMENT_KEY" --install-dir "$INSTALL_DIR" 2>&1)"
    status=$?
    set -e
    [[ $status -ne 0 ]] || fail 'unwritable destination must stop installation' || return 1
    assert_contains "$output" 'bar-content' || return 1
    [[ ! -e "$MOCK_SECRET_STORE_DIR/quotasApiUrl" ]] || fail 'preflight failure must precede keyring API URL write' || return 1
    [[ ! -e "$MOCK_SECRET_STORE_DIR/quotasManagementKey" ]] || fail 'preflight failure must precede keyring key write'
}

test_inserts_with_braces_in_block_comments_and_backtick_strings() {
    prepare_end4_fixture
    local bar_file="$CONFIG_ROOT/modules/ii/bar/BarContent.qml"

    cat >"$bar_file" <<'EOF'
Item {
    BarGroup {
        id: leftCenterGroup
        Resources {
            /* block comment with } and Resources { bogus } */
            property string templateValue: `literal } ${value} { tail`
        }
        Media {}
    }
}
EOF

    validate_end4_layout || return 1
    integrate_bar_content || return 1
    assert_contains "$(<"$bar_file")" $'        }\n        // quickshell-quotas-widget:start\n        Quotas {'
}

test_existing_marker_survives_block_comments_and_backtick_strings() {
    prepare_end4_fixture
    local bar_file="$CONFIG_ROOT/modules/ii/bar/BarContent.qml" before="$TEST_TMP_ROOT/before.qml"

    cat >"$bar_file" <<'EOF'
Item {
    BarGroup {
        id: leftCenterGroup
        Resources {
            /* } { */
            property string templateValue: `template { value }`
        }
        // quickshell-quotas-widget:start
        Quotas {
            visible: true
            Layout.fillWidth: false
        }
        // quickshell-quotas-widget:end
        Media {}
    }
}
EOF
    cp "$bar_file" "$before"

    validate_end4_layout || return 1
    integrate_bar_content || return 1
    cmp -s "$before" "$bar_file" || fail 'existing marker content changed around comments or backticks'
}

test_bar_integration_preserves_mode_600() {
    prepare_end4_fixture
    local bar_file="$CONFIG_ROOT/modules/ii/bar/BarContent.qml"
    chmod 600 "$bar_file"

    integrate_bar_content || return 1
    assert_file_mode 600 "$bar_file"
}

test_bar_integration_preserves_mode_664_and_rollback() {
    prepare_end4_fixture
    local bar_file="$CONFIG_ROOT/modules/ii/bar/BarContent.qml" original="$TEST_TMP_ROOT/original.qml"
    cp "$bar_file" "$original"
    chmod 664 "$bar_file"
    QUOTAS_TIMESTAMP='20260731-143000'

    begin_transaction || return 1
    integrate_bar_content || return 1
    assert_file_mode 664 "$bar_file" || return 1
    chmod 600 "$bar_file"
    rollback_transaction || return 1
    cmp -s "$original" "$bar_file" || fail 'rollback did not restore original BarContent.qml' || return 1
    assert_file_mode 664 "$bar_file"
}

test_ci_checks_release_packaging_script() {
    local workflow content

    for workflow in test.yml release.yml; do
        content="$(<"$repo_root/.github/workflows/$workflow")"
        assert_contains "$content" 'bash -n install.sh get-quotas.sh scripts/package-release.sh tests/*.bash tests/helpers/*.sh' || return 1
        assert_contains "$content" 'shellcheck install.sh get-quotas.sh scripts/package-release.sh tests/*.bash tests/helpers/*.sh' || return 1
    done
}

test_rolls_back_payload_when_bar_integration_fails() {
    prepare_transaction_fixture
    local bar_file="$CONFIG_ROOT/modules/ii/bar/BarContent.qml"
    printf 'old quotas qml\n' >"$INSTALL_DIR/Quotas.qml"
    printf 'Item { BarGroup { id: leftCenterGroup Media {} } }\n' >"$bar_file"

    begin_transaction || return 1
    install_payload || return 1
    if integrate_bar_content; then
        fail 'unsafe bar integration must fail' || return 1
    fi
    rollback_transaction || return 1
    assert_eq 'old quotas qml' "$(<"$INSTALL_DIR/Quotas.qml")" || return 1
    [[ ! -e "$INSTALL_DIR/QuotasPopup.qml" ]] || fail 'new popup must be removed by rollback' || return 1
    [[ ! -e "$INSTALL_DIR/get-quotas.sh" ]] || fail 'new fetcher must be removed by rollback' || return 1
    assert_file_exists "$INSTALL_DIR/Quotas.qml.backup.20260731-143000"
}

test_rejects_payload_symlink_destination() {
    prepare_transaction_fixture
    local outside="$TEST_TMP_ROOT/outside"
    printf 'outside\n' >"$outside"
    ln -s "$outside" "$INSTALL_DIR/Quotas.qml"

    begin_transaction || return 1
    if install_payload; then
        fail 'payload installation must reject symlink destinations' || return 1
    fi
    assert_eq 'outside' "$(<"$outside")"
}

test_smoke_failure_rolls_back_payload_bar_and_fallback() {
    prepare_transaction_fixture
    local bar_file="$CONFIG_ROOT/modules/ii/bar/BarContent.qml"
    local original_bar="$TEST_TMP_ROOT/original-bar.qml"
    cp "$bar_file" "$original_bar"
    printf 'old quotas qml\n' >"$INSTALL_DIR/Quotas.qml"
    FALLBACK_CONFIG="$INSTALL_DIR/quotas-widget.conf"
    printf '{"old":true}\n' >"$FALLBACK_CONFIG"

    begin_transaction || return 1
    backup_changed_file "$FALLBACK_CONFIG" || return 1
    printf '{"new":true}\n' >"$FALLBACK_CONFIG"
    install_payload || return 1
    integrate_bar_content || return 1
    printf '#!/usr/bin/env bash\nprintf '\''not-json\n'\''\n' >"$INSTALL_DIR/get-quotas.sh"
    chmod 700 "$INSTALL_DIR/get-quotas.sh"
    if run_smoke_test; then
        fail 'invalid smoke JSON must fail' || return 1
    fi
    rollback_transaction || return 1
    assert_eq 'old quotas qml' "$(<"$INSTALL_DIR/Quotas.qml")" || return 1
    cmp -s "$original_bar" "$bar_file" || fail 'BarContent.qml must be restored' || return 1
    assert_eq '{"old":true}' "$(<"$FALLBACK_CONFIG")" || return 1
    assert_file_exists "$FALLBACK_CONFIG.backup.20260731-143000"
}

test_rollback_keeps_keyring_mock_data() {
    prepare_installer_fixture
    QUOTAS_TIMESTAMP='20260731-143000'
    begin_transaction || return 1
    store_credentials || return 1
    rollback_transaction || return 1
    assert_eq "$API_URL" "$(<"$MOCK_SECRET_STORE_DIR/quotasApiUrl")" || return 1
    assert_eq "$MANAGEMENT_KEY" "$(<"$MOCK_SECRET_STORE_DIR/quotasManagementKey")"
}

test_signal_handler_rolls_back_and_exits_with_signal_status() {
    prepare_transaction_fixture
    printf 'old quotas qml\n' >"$INSTALL_DIR/Quotas.qml"
    begin_transaction || return 1
    install_payload || return 1
    local status

    set +e
    (handle_transaction_signal 130)
    status=$?
    set -e
    assert_eq '130' "$status" || return 1
    assert_eq 'old quotas qml' "$(<"$INSTALL_DIR/Quotas.qml")" || return 1
    [[ ! -e "$INSTALL_DIR/QuotasPopup.qml" ]] || fail 'signal rollback must remove created payload'
}

test_incomplete_rollback_remains_active_and_can_retry() {
    prepare_transaction_fixture
    printf 'old quotas qml\n' >"$INSTALL_DIR/Quotas.qml"
    chmod 640 "$INSTALL_DIR/Quotas.qml"

    begin_transaction || return 1
    install_payload || return 1
    rm -f "$INSTALL_DIR/Quotas.qml"
    mkdir "$INSTALL_DIR/Quotas.qml"
    if rollback_transaction; then
        fail 'rollback must fail rather than replace an unexpected directory' || return 1
    fi
    assert_eq '1' "$TX_ACTIVE" || return 1
    assert_file_exists "$INSTALL_DIR/Quotas.qml.backup.20260731-143000" || return 1
    rmdir "$INSTALL_DIR/Quotas.qml"
    rollback_transaction || return 1
    assert_eq '0' "$TX_ACTIVE" || return 1
    assert_eq 'old quotas qml' "$(<"$INSTALL_DIR/Quotas.qml")" || return 1
    assert_file_mode 640 "$INSTALL_DIR/Quotas.qml"
}

test_signal_during_rollback_is_deferred() {
    reset_installer_state
    TX_ACTIVE=1
    TX_ROLLING_BACK=1
    local status

    set +e
    (handle_transaction_signal 130)
    status=$?
    set -e
    assert_eq '0' "$status" || return 1
    assert_eq '1' "$TX_ACTIVE" || return 1
    assert_eq '1' "$TX_ROLLING_BACK"
}

assert_smoke_failure() {
    local stdout="$1" exit_code="${2:-0}" output status

    prepare_transaction_fixture
    write_smoke_fetcher "$stdout" "$exit_code"
    set +e
    output="$(run_smoke_test 2>&1)"
    status=$?
    set -e
    [[ $status -ne 0 ]] || fail 'invalid installed fetcher result must fail' || return 1
    assert_contains "$output" 'smoke test'
}

test_smoke_rejects_nonzero_fetcher_exit() {
    assert_smoke_failure '{"quotas":[],"minRemaining":1,"avgRemaining":2,"lastUpdated":"now"}' 23
}

test_smoke_rejects_invalid_json() {
    assert_smoke_failure 'not-json'
}

test_smoke_rejects_missing_quotas() {
    assert_smoke_failure '{"minRemaining":1,"avgRemaining":2,"lastUpdated":"now"}'
}

test_smoke_rejects_non_array_quotas() {
    assert_smoke_failure '{"quotas":{},"minRemaining":1,"avgRemaining":2,"lastUpdated":"now"}'
}

test_smoke_rejects_nonnumeric_minimum() {
    assert_smoke_failure '{"quotas":[],"minRemaining":"1","avgRemaining":2,"lastUpdated":"now"}'
}

test_smoke_rejects_nonnumeric_average() {
    assert_smoke_failure '{"quotas":[],"minRemaining":1,"avgRemaining":"2","lastUpdated":"now"}'
}

test_smoke_rejects_nonstring_timestamp() {
    assert_smoke_failure '{"quotas":[],"minRemaining":1,"avgRemaining":2,"lastUpdated":3}'
}

test_restart_warns_when_no_process_is_running() {
    prepare_end4_fixture
    make_qs_mock
    export MOCK_QS_LIST_JSON='[]'
    local output

    output="$(restart_quickshell 2>&1)" || return 1
    assert_eq "-p $CONFIG_ROOT list --json" "$(<"$MOCK_QS_LOG")" || return 1
    assert_contains "$output" 'not running'
}

test_restart_kills_and_daemonizes_running_process() {
    prepare_end4_fixture
    make_qs_mock
    export MOCK_QS_LIST_JSON='[{"name":"ii"}]'

    restart_quickshell || return 1
    assert_eq "$CONFIG_ROOT list --json" "$(sed -n 's/^-p //p' "$MOCK_QS_LOG" | sed -n '1p')" || return 1
    assert_contains "$(<"$MOCK_QS_LOG")" "-p $CONFIG_ROOT kill" || return 1
    assert_contains "$(<"$MOCK_QS_LOG")" "-p $CONFIG_ROOT --daemonize"
}

test_restart_failure_after_commit_does_not_roll_back() {
    prepare_transaction_fixture
    make_qs_mock
    export MOCK_QS_LIST_JSON='[{"name":"ii"}]'
    MOCK_QS_KILL_EXIT=9
    export MOCK_QS_KILL_EXIT
    printf 'old quotas qml\n' >"$INSTALL_DIR/Quotas.qml"

    begin_transaction || return 1
    install_payload || return 1
    integrate_bar_content || return 1
    run_smoke_test || return 1
    commit_transaction || return 1
    restart_quickshell >/dev/null 2>&1 || fail 'restart failure must be warning only' || return 1
    assert_eq 'new quotas qml' "$(<"$INSTALL_DIR/Quotas.qml")" || return 1
    assert_eq '0' "$TX_ACTIVE"
}

test_main_rejects_release_before_storing_credentials() {
    prepare_remote_fixture
    local fixture="$repo_root/tests/fixtures/end4-dots/ii"
    CONFIG_ROOT="$TEST_TMP_ROOT/config"
    INSTALL_DIR="$CONFIG_ROOT/modules/ii/bar"
    MOCK_SECRET_STORE_DIR="$TEST_TMP_ROOT/secrets"
    QUOTAS_SECRET_TOOL_BIN="$repo_root/tests/helpers/mock_secret_tool.sh"
    export QUOTAS_SECRET_TOOL_BIN MOCK_SECRET_STORE_DIR
    mkdir -p "$INSTALL_DIR" "$MOCK_SECRET_STORE_DIR"
    cp "$fixture/shell.qml" "$CONFIG_ROOT/shell.qml"
    cp "$fixture/modules/ii/bar/BarContent.qml" "$INSTALL_DIR/BarContent.qml"
    prepare_required_commands
    rm "$TEST_TMP_ROOT/bin/curl" "$TEST_TMP_ROOT/bin/jq" "$TEST_TMP_ROOT/bin/tar"
    queue_http_text 200 '{"files":[]}'
    queue_latest_release '[]'

    if PATH="$TEST_TMP_ROOT/bin:$PATH" run_with_mock_curl main \
        --api-url "$API_URL" --management-key "$MANAGEMENT_KEY" --install-dir "$INSTALL_DIR"; then
        fail 'main must reject an invalid release' || return 1
    fi
    [[ ! -e "$MOCK_SECRET_STORE_DIR/quotasApiUrl" ]] || fail 'credentials must not be stored before release validation' || return 1
    [[ ! -e "$INSTALL_DIR/quotas-widget.conf" ]] || fail 'fallback must not be written before release validation'
}

test_main_rolls_back_when_smoke_test_fails() {
    local release_archive="$TEST_TMP_ROOT/release.tar.gz"
    create_release_archive_with_fetcher "$release_archive" "printf 'not-json\\n'"
    prepare_main_fixture "$release_archive"
    local bar_file="$INSTALL_DIR/BarContent.qml" original_bar="$TEST_TMP_ROOT/original-bar.qml"
    cp "$bar_file" "$original_bar"
    printf 'old quotas qml\n' >"$INSTALL_DIR/Quotas.qml"
    printf '{"old":true}\n' >"$INSTALL_DIR/quotas-widget.conf"
    QUOTAS_SECRET_TOOL_BIN="$TEST_TMP_ROOT/missing-secret-tool"
    export QUOTAS_SECRET_TOOL_BIN

    if PATH="$TEST_TMP_ROOT/bin:$PATH" run_with_mock_curl main \
        --api-url "$API_URL" --management-key "$MANAGEMENT_KEY" --install-dir "$INSTALL_DIR"; then
        fail 'main must fail when installed fetcher smoke test fails' || return 1
    fi
    assert_eq 'old quotas qml' "$(<"$INSTALL_DIR/Quotas.qml")" || return 1
    cmp -s "$original_bar" "$bar_file" || fail 'main rollback must restore BarContent.qml' || return 1
    assert_eq '{"old":true}' "$(<"$INSTALL_DIR/quotas-widget.conf")"
}

test_main_stores_credentials_after_api_validation() {
    local release_archive="$TEST_TMP_ROOT/release.tar.gz"
    create_release_archive "$release_archive"
    prepare_main_fixture "$release_archive"

    PATH="$TEST_TMP_ROOT/bin:$PATH" run_with_mock_curl main \
        --api-url "$API_URL" --management-key "$MANAGEMENT_KEY" --install-dir "$INSTALL_DIR" || return 1
    assert_eq "$API_URL" "$(<"$MOCK_SECRET_STORE_DIR/quotasApiUrl")" || return 1
    assert_eq "$MANAGEMENT_KEY" "$(<"$MOCK_SECRET_STORE_DIR/quotasManagementKey")" || return 1
    assert_file_exists "$INSTALL_DIR/Quotas.qml" || return 1
    assert_contains "$(<"$INSTALL_DIR/BarContent.qml")" '// quickshell-quotas-widget:start'
}

run_test 'parses required API URL and management key' test_parse_required_api_url
run_test 'rejects conflicting management key modes' test_rejects_conflicting_key_modes
run_test 'rejects unsupported URL scheme' test_rejects_unsupported_url_scheme
run_test 'resolves default end4 layout' test_resolves_default_layout
run_test 'accepts compatible end4 layout' test_accepts_compatible_end4_layout
run_test 'help exits zero' test_help_exits_zero
run_test 'rejects unknown flag' test_rejects_unknown_flag
run_test 'rejects missing flag value' test_rejects_missing_flag_value
run_test 'rejects empty management key' test_rejects_empty_key
run_test 'rejects option as management key value' test_rejects_option_as_management_key_value
run_test 'usage remains bilingual' test_usage_remains_bilingual
run_test 'shell sources are ASCII' test_shell_sources_are_ascii
run_test 'accepts HTTP URL' test_accepts_http_url
run_test 'accepts HTTPS URL' test_accepts_https_url
run_test 'resolves custom install directory' test_resolves_custom_install_dir
run_test 'rejects Bash 3' test_rejects_bash_3
run_test 'accepts Bash 4' test_accepts_bash_4
run_test 'rejects missing BarContent.qml' test_rejects_missing_bar_content
run_test 'rejects missing shell.qml' test_rejects_missing_shell_qml
run_test 'rejects missing leftCenterGroup' test_rejects_missing_left_center_group
run_test 'rejects missing Resources' test_rejects_missing_resources
run_test 'reports missing hyprctl' test_reports_missing_hyprctl
run_test 'reports missing quickshell' test_reports_missing_quickshell
run_test 'reports missing curl' test_reports_missing_curl
run_test 'reports missing jq' test_reports_missing_jq
run_test 'reports missing tar' test_reports_missing_tar
run_test 'warns when notify-send is missing' test_warns_when_notify_send_is_missing
run_test 'reads management key from stdin without leaking it' test_reads_management_key_from_stdin_without_leaking_it
run_test 'rejects empty management key from stdin' test_rejects_empty_management_key_from_stdin
run_test 'reads management key from TTY file' test_reads_management_key_from_tty_file
run_test 'API validation rejects transport failure' test_validate_api_rejects_transport_failure
run_test 'API validation rejects HTTP 401' test_validate_api_rejects_401
run_test 'API validation rejects HTTP 403' test_validate_api_rejects_403
run_test 'API validation rejects HTTP 500' test_validate_api_rejects_500
run_test 'API validation rejects malformed JSON' test_validate_api_rejects_malformed_json
run_test 'API validation rejects multiple JSON documents' test_validate_api_rejects_multiple_json_documents
run_test 'API validation rejects missing files' test_validate_api_rejects_missing_files
run_test 'API validation rejects non-array files' test_validate_api_rejects_non_array_files
run_test 'API validation accepts files array securely' test_validate_api_accepts_files_array_and_hides_key_from_argv
run_test 'every curl call disables curlrc first' test_every_curl_call_disables_curlrc_first
run_test 'API temporary files are owned by global cleanup' test_api_temporary_files_are_owned_by_global_cleanup
run_test 'latest release rejects missing asset' test_fetch_latest_release_rejects_missing_asset
run_test 'latest release rejects duplicate assets' test_fetch_latest_release_rejects_duplicate_assets
run_test 'release package matches archive contract' test_release_package_matches_archive_contract
run_test 'release package is reproducible across filesystem metadata' test_release_package_is_reproducible_across_filesystem_metadata
run_test 'archive rejects parent entry' test_validate_archive_rejects_parent_entry
run_test 'archive rejects absolute entry' test_validate_archive_rejects_absolute_entry
run_test 'archive rejects missing payload file' test_validate_archive_rejects_missing_payload_file
run_test 'archive rejects duplicate payload file' test_validate_archive_rejects_duplicate_payload_file
run_test 'archive rejects extra top-level file' test_validate_archive_rejects_extra_top_level_file
run_test 'archive rejects nested path' test_validate_archive_rejects_nested_path
run_test 'archive rejects dot component' test_validate_archive_rejects_dot_component
run_test 'archive rejects symlink' test_validate_archive_rejects_symlink
run_test 'archive rejects hardlink' test_validate_archive_rejects_hardlink
run_test 'archive rejects FIFO' test_validate_archive_rejects_fifo
run_test 'archive stops when verbose listing fails' test_validate_archive_stops_when_verbose_listing_fails
run_test 'latest release downloads and extracts valid payload' test_fetch_latest_release_downloads_and_extracts_valid_payload
run_test 'stores and verifies keyring values' test_stores_and_verifies_keyring_values
run_test 'verifies keyring value ending in newline' test_verifies_keyring_value_ending_in_newline
run_test 'writes JSON fallback with mode 600' test_writes_json_fallback_with_mode_600
run_test 'falls back after keyring store failure' test_falls_back_after_keyring_store_failure
run_test 'falls back after keyring lookup failure' test_falls_back_after_keyring_lookup_failure
run_test 'falls back after keyring lookup mismatch' test_falls_back_after_keyring_lookup_mismatch
run_test 'falls back after partial keyring write' test_falls_back_after_partial_keyring_write
run_test 'removes existing fallback after keyring success' test_removes_existing_fallback_after_keyring_success
run_test 'preserves special characters in fallback JSON' test_preserves_special_characters_in_fallback_json
run_test 'keeps credentials out of jq arguments' test_keeps_credentials_out_of_jq_argv
run_test 'never logs management key while storing credentials' test_never_logs_management_key
run_test 'fallback warning is bilingual' test_fallback_warning_is_bilingual
run_test 'inserts managed block after balanced Resources' test_inserts_managed_block_after_balanced_resources
run_test 'preflight accepts braces in comments and strings' test_preflight_accepts_braces_in_comments_and_strings
run_test 'inserts after one-line Resources component' test_inserts_after_one_line_resources_component
run_test 'inserts inside fully inline leftCenterGroup' test_inserts_inside_fully_inline_left_center_group
run_test 'rejects multiple inline Resources in target group' test_rejects_multiple_inline_resources_in_target_group
run_test 'rejects multiple inline target groups' test_rejects_multiple_inline_target_groups
run_test 'preserves unterminated final line' test_preserves_unterminated_final_line
run_test 'bar integration is idempotent' test_bar_integration_is_idempotent
run_test 'valid managed block preserves all existing bytes' test_valid_managed_block_preserves_all_existing_bytes
run_test 'rejects unbalanced managed markers' test_rejects_unbalanced_managed_markers
run_test 'rejects duplicate managed blocks' test_rejects_duplicate_managed_blocks
run_test 'rejects reversed managed markers' test_rejects_reversed_managed_markers
run_test 'rejects malformed managed block' test_rejects_malformed_managed_block
run_test 'rejects misplaced managed block' test_rejects_misplaced_managed_block
run_test 'rejects missing safe bar insertion point' test_rejects_missing_safe_bar_insertion_point
run_test 'rejects multiple safe bar insertion points' test_rejects_multiple_safe_bar_insertion_points
run_test 'reports unsafe insertion under errexit' test_reports_unsafe_insertion_under_errexit
run_test 'installs payload with modes and backups' test_installs_payload_with_expected_modes_and_backups
run_test 'corrects identical payload modes transactionally' test_corrects_identical_payload_modes_transactionally
run_test 'corrects identical fallback mode transactionally' test_corrects_identical_fallback_mode_transactionally
run_test 'keyring switch secures fallback backup and restores original mode' test_keyring_switch_secures_fallback_backup_and_restores_original_mode
run_test 'writable-target preflight covers every persistent destination' test_writable_target_preflight_covers_every_persistent_destination
run_test 'main rejects unwritable target before keyring writes' test_main_rejects_unwritable_target_before_keyring_writes
run_test 'inserts with braces in block comments and backtick strings' test_inserts_with_braces_in_block_comments_and_backtick_strings
run_test 'existing marker survives block comments and backtick strings' test_existing_marker_survives_block_comments_and_backtick_strings
run_test 'bar integration preserves mode 600' test_bar_integration_preserves_mode_600
run_test 'bar integration preserves mode 664 and rollback' test_bar_integration_preserves_mode_664_and_rollback
run_test 'rolls back payload when bar integration fails' test_rolls_back_payload_when_bar_integration_fails
run_test 'rejects payload symlink destination' test_rejects_payload_symlink_destination
run_test 'smoke failure rolls back payload bar and fallback' test_smoke_failure_rolls_back_payload_bar_and_fallback
run_test 'rollback keeps keyring mock data' test_rollback_keeps_keyring_mock_data
run_test 'signal handler rolls back and exits with signal status' test_signal_handler_rolls_back_and_exits_with_signal_status
run_test 'incomplete rollback remains active and can retry' test_incomplete_rollback_remains_active_and_can_retry
run_test 'signal during rollback is deferred' test_signal_during_rollback_is_deferred
run_test 'smoke rejects nonzero fetcher exit' test_smoke_rejects_nonzero_fetcher_exit
run_test 'smoke rejects invalid JSON' test_smoke_rejects_invalid_json
run_test 'smoke rejects missing quotas' test_smoke_rejects_missing_quotas
run_test 'smoke rejects non-array quotas' test_smoke_rejects_non_array_quotas
run_test 'smoke rejects nonnumeric minimum' test_smoke_rejects_nonnumeric_minimum
run_test 'smoke rejects nonnumeric average' test_smoke_rejects_nonnumeric_average
run_test 'smoke rejects nonstring timestamp' test_smoke_rejects_nonstring_timestamp
run_test 'restart warns when no process is running' test_restart_warns_when_no_process_is_running
run_test 'restart kills and daemonizes running process' test_restart_kills_and_daemonizes_running_process
run_test 'restart failure after commit does not roll back' test_restart_failure_after_commit_does_not_roll_back
run_test 'main rejects release before storing credentials' test_main_rejects_release_before_storing_credentials
run_test 'main rolls back when smoke test fails' test_main_rolls_back_when_smoke_test_fails
run_test 'main stores credentials after API validation' test_main_stores_credentials_after_api_validation
run_test 'CI checks release packaging script' test_ci_checks_release_packaging_script

finish_tests
