#!/usr/bin/env bash
set -uo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/test_helper.bash"
QUOTAS_INSTALLER_SOURCE_ONLY=1 source "$repo_root/install.sh"

reset_installer_state() {
    API_URL=""
    MANAGEMENT_KEY=""
    KEY_INPUT_MODE="tty"
    INSTALL_DIR=""
    QS_BIN=""
    CONFIG_ROOT=""
}

prepare_end4_fixture() {
    reset_installer_state
    local fixture="$repo_root/tests/fixtures/end4-dots/ii"
    CONFIG_ROOT="$TEST_TMP_ROOT/config"
    mkdir -p "$CONFIG_ROOT/modules/ii/bar"
    cp "$fixture/shell.qml" "$CONFIG_ROOT/shell.qml"
    cp "$fixture/modules/ii/bar/BarContent.qml" "$CONFIG_ROOT/modules/ii/bar/BarContent.qml"
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
    parse_args --api-url 'http://localhost:8080/' --management-key 'secret'
    assert_eq 'http://localhost:8080' "$API_URL"
    assert_eq 'secret' "$MANAGEMENT_KEY"
    assert_eq 'argument' "$KEY_INPUT_MODE"
}

test_rejects_conflicting_key_modes() {
    reset_installer_state
    local output status
    set +e
    output="$(parse_args --api-url http://localhost --management-key secret --management-key-stdin 2>&1)"
    status=$?
    set -e
    [[ $status -ne 0 ]] || fail 'conflicting modes must fail'
    assert_contains "$output" 'mutually exclusive'
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
    resolve_layout
    assert_eq "$TEST_TMP_ROOT/config/quickshell/ii/modules/ii/bar" "$INSTALL_DIR"
    assert_eq "$TEST_TMP_ROOT/config/quickshell/ii" "$CONFIG_ROOT"
}

test_accepts_compatible_end4_layout() {
    prepare_end4_fixture
    validate_end4_layout
}

test_help_exits_zero() {
    reset_installer_state
    local output status
    set +e
    output="$(parse_args --help 2>&1)"
    status=$?
    set -e
    assert_eq '0' "$status"
    assert_contains "$output" 'Usage:'
}

test_rejects_unknown_flag() {
    reset_installer_state
    local output status
    set +e
    output="$(parse_args --unknown 2>&1)"
    status=$?
    set -e
    [[ $status -ne 0 ]] || fail 'unknown flag must fail'
    assert_contains "$output" '--unknown'
}

test_rejects_missing_flag_value() {
    reset_installer_state
    local output status
    set +e
    output="$(parse_args --api-url 2>&1)"
    status=$?
    set -e
    [[ $status -ne 0 ]] || fail 'missing flag value must fail'
    assert_contains "$output" '--api-url'
}

test_rejects_empty_key() {
    reset_installer_state
    local output status
    set +e
    output="$(parse_args --management-key '' 2>&1)"
    status=$?
    set -e
    [[ $status -ne 0 ]] || fail 'empty key must fail'
    assert_contains "$output" '--management-key'
}

test_accepts_http_url() {
    reset_installer_state
    assert_eq 'http://example.com/api' "$(normalize_api_url 'http://example.com/api///')"
}

test_accepts_https_url() {
    reset_installer_state
    assert_eq 'https://example.com' "$(normalize_api_url 'https://example.com/')"
}

test_resolves_custom_install_dir() {
    reset_installer_state
    INSTALL_DIR="$TEST_TMP_ROOT/custom/modules/ii/bar"
    mkdir -p "$INSTALL_DIR"
    resolve_layout
    assert_eq "$TEST_TMP_ROOT/custom/modules/ii/bar" "$INSTALL_DIR"
    assert_eq "$TEST_TMP_ROOT/custom" "$CONFIG_ROOT"
}

test_rejects_bash_3() {
    local output status
    set +e
    output="$(require_bash_version 3 2>&1)"
    status=$?
    set -e
    [[ $status -ne 0 ]] || fail 'Bash 3 must fail'
    assert_contains "$output" 'Bash 3'
}

test_accepts_bash_4() {
    require_bash_version 4
}

test_rejects_missing_bar_content() {
    prepare_end4_fixture
    rm "$CONFIG_ROOT/modules/ii/bar/BarContent.qml"
    local output status
    set +e
    output="$(validate_end4_layout 2>&1)"
    status=$?
    set -e
    [[ $status -ne 0 ]] || fail 'missing BarContent.qml must fail'
    assert_contains "$output" 'BarContent.qml'
}

test_rejects_missing_shell_qml() {
    prepare_end4_fixture
    rm "$CONFIG_ROOT/shell.qml"
    local output status
    set +e
    output="$(validate_end4_layout 2>&1)"
    status=$?
    set -e
    [[ $status -ne 0 ]] || fail 'missing shell.qml must fail'
    assert_contains "$output" 'shell.qml'
}

test_rejects_missing_left_center_group() {
    prepare_end4_fixture
    printf 'import QtQuick\nItem { Resources {} Media {} }\n' >"$CONFIG_ROOT/modules/ii/bar/BarContent.qml"
    local output status
    set +e
    output="$(validate_end4_layout 2>&1)"
    status=$?
    set -e
    [[ $status -ne 0 ]] || fail 'missing leftCenterGroup must fail'
    assert_contains "$output" 'leftCenterGroup'
}

test_rejects_missing_resources() {
    prepare_end4_fixture
    printf 'import QtQuick\nItem { BarGroup { id: leftCenterGroup Media {} } }\n' >"$CONFIG_ROOT/modules/ii/bar/BarContent.qml"
    local output status
    set +e
    output="$(validate_end4_layout 2>&1)"
    status=$?
    set -e
    [[ $status -ne 0 ]] || fail 'missing Resources must fail'
    assert_contains "$output" 'Resources'
}

assert_missing_dependency() {
    local missing="$1"
    prepare_required_commands
    rm "$TEST_TMP_ROOT/bin/$missing"
    reset_installer_state
    local output status
    set +e
    output="$(PATH="$TEST_TMP_ROOT/bin" require_dependencies 2>&1)"
    status=$?
    set -e
    [[ $status -ne 0 ]] || fail "missing $missing must fail"
    assert_contains "$output" "$missing"
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
    assert_eq '0' "$status"
    assert_contains "$output" 'notify-send'
    assert_contains "$output" 'refresh still works'
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

finish_tests
