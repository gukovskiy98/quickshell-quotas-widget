#!/usr/bin/env bash
set -uo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/test_helper.bash"

QML_FILE="$repo_root/Quotas.qml"

test_uses_relative_shell_fetcher() {
    local content
    content="$(<"$QML_FILE")"

    assert_contains "$content" 'Qt.resolvedUrl("get-quotas.sh")' || return 1
    assert_contains "$content" 'command: [root.quotaScriptPath]' || return 1
    [[ "$content" != *'bash", "-c'* ]] || fail 'QML must not use bash -c'
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

test_cleans_up_failed_process_launch() {
    local content running_handler
    content="$(<"$QML_FILE")"
    running_handler="${content#*onRunningChanged:}"
    running_handler="${running_handler%%onExited:*}"

    assert_contains "$content" 'property bool processStarted: false' || return 1
    assert_contains "$content" 'onStarted: root.processStarted = true' || return 1
    assert_contains "$running_handler" '!running' || return 1
    assert_contains "$running_handler" 'root.isFetching' || return 1
    assert_contains "$running_handler" '!root.processStarted' || return 1
    assert_contains "$running_handler" 'root.pendingStderr' || return 1
    assert_contains "$running_handler" 'root.pendingStdout = ""' || return 1
    assert_contains "$running_handler" 'root.pendingStderr = ""' || return 1
    assert_contains "$running_handler" 'root.isFetching = false'
}

test_validates_success_payload_before_atomic_update() {
    local content success_handler validation_prefix
    content="$(<"$QML_FILE")"
    success_handler="${content#*if (exitCode === 0)}"
    success_handler="${success_handler%%} else {*}}"
    validation_prefix="${success_handler%%root.quotasData = parsed*}"

    assert_contains "$validation_prefix" 'parsed !== null' || return 1
    assert_contains "$validation_prefix" 'typeof parsed === "object"' || return 1
    assert_contains "$validation_prefix" '!Array.isArray(parsed)' || return 1
    assert_contains "$validation_prefix" 'Array.isArray(parsed.quotas)' || return 1
    assert_contains "$validation_prefix" 'typeof parsed.avgRemaining === "number"' || return 1
    assert_contains "$validation_prefix" 'Number.isFinite(parsed.avgRemaining)' || return 1
    assert_contains "$success_handler" 'root.quotasData = parsed' || return 1
    assert_contains "$success_handler" 'root.avgRemaining = parsed.avgRemaining'
}

run_test 'uses relative shell fetcher' test_uses_relative_shell_fetcher
run_test 'has no user or Bun paths' test_has_no_user_or_bun_paths
run_test 'parses stdout only after successful exit' test_parses_stdout_only_after_successful_exit
run_test 'declares process exit parameters' test_declares_process_exit_parameters
run_test 'clears process state for every exit' test_clears_process_state_for_every_exit
run_test 'failure preserves previous quota data' test_failure_preserves_previous_quota_data
run_test 'cleans up failed process launch' test_cleans_up_failed_process_launch
run_test 'validates success payload before atomic update' test_validates_success_payload_before_atomic_update

finish_tests
