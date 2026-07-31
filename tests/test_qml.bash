#!/usr/bin/env bash
set -uo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/test_helper.bash"

QML_FILE="$repo_root/Quotas.qml"

test_uses_relative_shell_fetcher() {
    local content
    content="$(<"$QML_FILE")"

    assert_contains "$content" 'Qt.resolvedUrl("get-quotas.sh")' || return 1
    assert_contains "$content" 'command: [root.quotaScriptPath]'
}

test_has_no_user_or_bun_paths() {
    local content
    content="$(<"$QML_FILE")"

    [[ "$content" != *'/home/ngukovskiy'* ]] || fail 'hard-coded home remains' || return 1
    [[ "$content" != *'.bun/bin/bun'* ]] || fail 'Bun path remains' || return 1
    [[ "$content" != *'secret-tool lookup'* ]] || fail 'QML must not load credentials'
}

test_parses_stdout_only_after_successful_exit() {
    local content stdout_handler exit_handler
    content="$(<"$QML_FILE")"
    stdout_handler="${content#*stdout: StdioCollector}"
    stdout_handler="${stdout_handler%%stderr: StdioCollector*}"
    exit_handler="${content#*onExited:}"
    exit_handler="${exit_handler%%onPressed:*}"

    [[ "$stdout_handler" != *'JSON.parse'* ]] || fail 'stdout collector parses before process exit' || return 1
    assert_contains "$stdout_handler" 'root.pendingStdout = text' || return 1
    assert_contains "$exit_handler" 'exitCode === 0' || return 1
    assert_contains "$exit_handler" 'JSON.parse(root.pendingStdout)'
}

test_declares_process_exit_parameters() {
    local content
    content="$(<"$QML_FILE")"

    assert_contains "$content" 'onExited: function(exitCode, exitStatus)'
}

test_clears_process_state_for_every_exit() {
    local content exit_handler
    content="$(<"$QML_FILE")"
    exit_handler="${content#*onExited:}"
    exit_handler="${exit_handler%%onPressed:*}"

    assert_contains "$content" 'property string pendingStdout: ""' || return 1
    assert_contains "$content" 'property string pendingStderr: ""' || return 1
    assert_contains "$exit_handler" 'finally' || return 1
    assert_contains "$exit_handler" 'root.pendingStdout = ""' || return 1
    assert_contains "$exit_handler" 'root.pendingStderr = ""' || return 1
    assert_contains "$exit_handler" 'root.isFetching = false'
}

test_failure_preserves_previous_quota_data() {
    local content exit_handler failure_handler
    content="$(<"$QML_FILE")"
    exit_handler="${content#*onExited:}"
    exit_handler="${exit_handler%%onPressed:*}"
    failure_handler="${exit_handler#*else}"

    assert_contains "$failure_handler" 'root.pendingStderr' || return 1
    [[ "$failure_handler" != *'root.quotasData = null'* ]] || fail 'failure clears previous quota data'
}

run_test 'uses relative shell fetcher' test_uses_relative_shell_fetcher
run_test 'has no user or Bun paths' test_has_no_user_or_bun_paths
run_test 'parses stdout only after successful exit' test_parses_stdout_only_after_successful_exit
run_test 'declares process exit parameters' test_declares_process_exit_parameters
run_test 'clears process state for every exit' test_clears_process_state_for_every_exit
run_test 'failure preserves previous quota data' test_failure_preserves_previous_quota_data

finish_tests
