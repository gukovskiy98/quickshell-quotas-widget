#!/usr/bin/env bash
set -uo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/test_helper.bash"
QUOTAS_UNINSTALLER_SOURCE_ONLY=1 source "$repo_root/uninstall.sh"

reset_uninstaller_state() {
    INSTALL_DIR=""
    CONFIG_ROOT=""
    BAR_FILE=""
    QS_BIN=""
    WORK_DIR=""
    HELP_REQUESTED=0
    UNINSTALL_CHANGED=0
    QUOTAS_SKIP_RESTART=1
    QUOTAS_TIMESTAMP=20260824-200000
    TMPDIR="$TEST_TMP_ROOT"
    export QUOTAS_SKIP_RESTART QUOTAS_TIMESTAMP TMPDIR
}

write_bar_fixture() {
    cat >"$INSTALL_DIR/BarContent.qml" <<'EOF'
BarGroup {
    id: leftCenterGroup
    Resources {
        visible: true
    }
    // quickshell-quotas-widget:start
    Quotas {
        visible: true
        Layout.fillWidth: false
    }
    // quickshell-quotas-widget:end

    Media {
        visible: true
    }
}
EOF
}

prepare_uninstall_fixture() {
    reset_uninstaller_state
    INSTALL_DIR="$TEST_TMP_ROOT/quickshell/ii/modules/ii/bar"
    mkdir -p "$INSTALL_DIR"
    write_bar_fixture
    printf 'widget\n' >"$INSTALL_DIR/Quotas.qml"
    printf 'popup\n' >"$INSTALL_DIR/QuotasPopup.qml"
    printf '#!/usr/bin/env bash\n' >"$INSTALL_DIR/get-quotas.sh"
    chmod 700 "$INSTALL_DIR/get-quotas.sh"
    printf '{"apiUrl":"kept","managementKey":"kept"}\n' >"$INSTALL_DIR/quotas-widget.conf"
    chmod 600 "$INSTALL_DIR/quotas-widget.conf"
}

test_removes_managed_block_and_payload() {
    prepare_uninstall_fixture
    local original output backup="$INSTALL_DIR/BarContent.qml.backup.$QUOTAS_TIMESTAMP"
    original="$(<"$INSTALL_DIR/BarContent.qml")"

    output="$(uninstall_main --install-dir "$INSTALL_DIR" 2>&1)" || return 1

    [[ ! -e "$INSTALL_DIR/Quotas.qml" ]] || fail 'Quotas.qml was not removed' || return 1
    [[ ! -e "$INSTALL_DIR/QuotasPopup.qml" ]] || fail 'QuotasPopup.qml was not removed' || return 1
    [[ ! -e "$INSTALL_DIR/get-quotas.sh" ]] || fail 'get-quotas.sh was not removed' || return 1
    [[ "$(<"$INSTALL_DIR/BarContent.qml")" != *'quickshell-quotas-widget'* ]] || fail 'managed block remains' || return 1
    assert_contains "$(<"$INSTALL_DIR/BarContent.qml")" 'Media {' || return 1
    assert_file_exists "$backup" || return 1
    assert_eq "$original" "$(<"$backup")" || return 1
    assert_contains "$output" 'Credentials were preserved.'
}

test_preserves_credentials_and_bar_mode() {
    prepare_uninstall_fixture
    chmod 600 "$INSTALL_DIR/BarContent.qml"

    uninstall_main --install-dir "$INSTALL_DIR" >/dev/null 2>&1 || return 1

    assert_file_exists "$INSTALL_DIR/quotas-widget.conf" || return 1
    assert_file_mode 600 "$INSTALL_DIR/quotas-widget.conf" || return 1
    assert_file_mode 600 "$INSTALL_DIR/BarContent.qml"
}

test_is_idempotent_without_extra_backup() {
    prepare_uninstall_fixture
    uninstall_main --install-dir "$INSTALL_DIR" >/dev/null 2>&1 || return 1
    UNINSTALL_CHANGED=0
    WORK_DIR=""

    uninstall_main --install-dir "$INSTALL_DIR" >/dev/null 2>&1 || return 1

    [[ "$(find "$INSTALL_DIR" -maxdepth 1 -name 'BarContent.qml.backup.*' | wc -l)" == '1' ]] ||
        fail 'idempotent uninstall created another backup'
}

test_rejects_malformed_managed_block_before_removing_payload() {
    prepare_uninstall_fixture
    local original
    original="$(<"$INSTALL_DIR/BarContent.qml")"
    sed -i '/Layout.fillWidth/d' "$INSTALL_DIR/BarContent.qml"
    original="$(<"$INSTALL_DIR/BarContent.qml")"

    if uninstall_main --install-dir "$INSTALL_DIR" >/dev/null 2>&1; then
        fail 'malformed managed block was accepted' || return 1
    fi

    assert_eq "$original" "$(<"$INSTALL_DIR/BarContent.qml")" || return 1
    assert_file_exists "$INSTALL_DIR/Quotas.qml"
}

test_rejects_unsafe_install_directory_scope() {
    reset_uninstaller_state
    mkdir -p "$TEST_TMP_ROOT/arbitrary"

    if uninstall_main --install-dir "$TEST_TMP_ROOT/arbitrary" >/dev/null 2>&1; then
        fail 'unsafe install directory was accepted'
    fi
}

test_rejects_symlink_escape_after_canonicalization() {
    reset_uninstaller_state
    local scoped_root="$TEST_TMP_ROOT/scoped/modules/ii" outside="$TEST_TMP_ROOT/outside"
    mkdir -p "$scoped_root" "$outside"
    ln -s "$outside" "$scoped_root/bar"

    if uninstall_main --install-dir "$scoped_root/bar" >/dev/null 2>&1; then
        fail 'symlink escape was accepted'
    fi
}

test_validates_all_payload_targets_before_bar_change() {
    prepare_uninstall_fixture
    local original
    original="$(<"$INSTALL_DIR/BarContent.qml")"
    rm -f -- "$INSTALL_DIR/QuotasPopup.qml"
    mkdir "$INSTALL_DIR/QuotasPopup.qml"

    if uninstall_main --install-dir "$INSTALL_DIR" >/dev/null 2>&1; then
        fail 'payload directory was accepted' || return 1
    fi

    assert_eq "$original" "$(<"$INSTALL_DIR/BarContent.qml")" || return 1
    [[ ! -e "$INSTALL_DIR/BarContent.qml.backup.$QUOTAS_TIMESTAMP" ]] ||
        fail 'bar backup was created before payload validation'
}

test_keeps_unmanaged_quotas_reference_and_warns() {
    reset_uninstaller_state
    INSTALL_DIR="$TEST_TMP_ROOT/quickshell/ii/modules/ii/bar"
    mkdir -p "$INSTALL_DIR"
    printf 'Quotas { visible: true }\n' >"$INSTALL_DIR/BarContent.qml"
    printf 'widget\n' >"$INSTALL_DIR/Quotas.qml"
    local output

    output="$(uninstall_main --install-dir "$INSTALL_DIR" 2>&1)" || return 1

    assert_contains "$(<"$INSTALL_DIR/BarContent.qml")" 'Quotas {' || return 1
    assert_contains "$output" 'unmanaged Quotas component'
}

test_help_documents_custom_directory() {
    reset_uninstaller_state
    local output
    output="$(uninstall_main --help)" || return 1
    assert_contains "$output" '--install-dir'
}

run_test 'removes managed block and payload' test_removes_managed_block_and_payload
run_test 'preserves credentials and bar mode' test_preserves_credentials_and_bar_mode
run_test 'is idempotent without extra backup' test_is_idempotent_without_extra_backup
run_test 'rejects malformed managed block before payload removal' test_rejects_malformed_managed_block_before_removing_payload
run_test 'rejects unsafe install directory scope' test_rejects_unsafe_install_directory_scope
run_test 'rejects symlink escape after canonicalization' test_rejects_symlink_escape_after_canonicalization
run_test 'validates payload targets before bar change' test_validates_all_payload_targets_before_bar_change
run_test 'keeps unmanaged Quotas reference and warns' test_keeps_unmanaged_quotas_reference_and_warns
run_test 'help documents custom directory' test_help_documents_custom_directory

finish_tests
