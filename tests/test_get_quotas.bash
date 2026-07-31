#!/usr/bin/env bash
set -uo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/test_helper.bash"

FIXTURES="$repo_root/tests/fixtures"
CURL_MOCK="$repo_root/tests/helpers/mock_curl.sh"
SECRET_MOCK="$repo_root/tests/helpers/mock_secret_tool.sh"
FETCHER="$repo_root/get-quotas.sh"

prepare_fetcher() {
    MOCK_CURL_QUEUE_DIR="$TEST_TMP_ROOT/curl-queue"
    MOCK_CURL_LOG="$TEST_TMP_ROOT/curl.log"
    MOCK_CURL_HEADERS_LOG="$TEST_TMP_ROOT/curl-headers.log"
    MOCK_SECRET_STORE_DIR="$TEST_TMP_ROOT/secrets"
    QUOTAS_CONFIG_PATH="$TEST_TMP_ROOT/quotas-widget.conf"
    mkdir -p "$MOCK_CURL_QUEUE_DIR" "$MOCK_SECRET_STORE_DIR"
    : >"$MOCK_CURL_LOG"
    : >"$MOCK_CURL_HEADERS_LOG"
}

write_config() {
    printf '%s\n' "$1" >"$QUOTAS_CONFIG_PATH"
    chmod 600 "$QUOTAS_CONFIG_PATH"
}

seed_secret_tool() {
    printf '%s' "$1" >"$MOCK_SECRET_STORE_DIR/quotasApiUrl"
    printf '%s' "$2" >"$MOCK_SECRET_STORE_DIR/quotasManagementKey"
}

queue_http() {
    local status="$1" fixture="$2" count
    count="$(find "$MOCK_CURL_QUEUE_DIR" -maxdepth 1 -type f ! -name '.counter' | wc -l)"
    {
        printf '%s\n' "$status"
        cat -- "$fixture"
    } >"$MOCK_CURL_QUEUE_DIR/$((count + 1))"
}

queue_http_text() {
    local status="$1" body="$2" count
    count="$(find "$MOCK_CURL_QUEUE_DIR" -maxdepth 1 -type f ! -name '.counter' | wc -l)"
    printf '%s\n%s\n' "$status" "$body" >"$MOCK_CURL_QUEUE_DIR/$((count + 1))"
}

run_fetcher() {
    env \
        QUOTAS_CONFIG_PATH="$QUOTAS_CONFIG_PATH" \
        QUOTAS_CURL_BIN="$CURL_MOCK" \
        QUOTAS_SECRET_TOOL_BIN="$SECRET_MOCK" \
        QUOTAS_NOW=$'12:34 \xE2\x80\xA2 31/07/2026' \
        MOCK_CURL_QUEUE_DIR="$MOCK_CURL_QUEUE_DIR" \
        MOCK_CURL_LOG="$MOCK_CURL_LOG" \
        MOCK_CURL_HEADERS_LOG="$MOCK_CURL_HEADERS_LOG" \
        MOCK_SECRET_STORE_DIR="$MOCK_SECRET_STORE_DIR" \
        MOCK_SECRET_FAIL_STORE="${MOCK_SECRET_FAIL_STORE:-0}" \
        MOCK_SECRET_FAIL_LOOKUP="${MOCK_SECRET_FAIL_LOOKUP:-0}" \
        MOCK_CURL_EXIT_CODE="${MOCK_CURL_EXIT_CODE:-0}" \
        bash "$FETCHER"
}

run_fetcher_without_now() {
    env \
        PATH="$TEST_TMP_ROOT/bin:$PATH" \
        QUOTAS_CONFIG_PATH="$QUOTAS_CONFIG_PATH" \
        QUOTAS_CURL_BIN="$CURL_MOCK" \
        QUOTAS_SECRET_TOOL_BIN="$SECRET_MOCK" \
        MOCK_CURL_QUEUE_DIR="$MOCK_CURL_QUEUE_DIR" \
        MOCK_CURL_LOG="$MOCK_CURL_LOG" \
        MOCK_CURL_HEADERS_LOG="$MOCK_CURL_HEADERS_LOG" \
        MOCK_SECRET_STORE_DIR="$MOCK_SECRET_STORE_DIR" \
        MOCK_SECRET_FAIL_STORE="${MOCK_SECRET_FAIL_STORE:-0}" \
        MOCK_SECRET_FAIL_LOOKUP="${MOCK_SECRET_FAIL_LOOKUP:-0}" \
        MOCK_CURL_EXIT_CODE="${MOCK_CURL_EXIT_CODE:-0}" \
        bash "$FETCHER"
}

assert_fetcher_fails_with() {
    local expected="$1" output status
    if output="$(run_fetcher 2>&1)"; then
        status=0
    else
        status=$?
    fi
    [[ $status -ne 0 ]] || fail 'fetcher must fail' || return 1
    assert_contains "$output" "$expected"
}

assert_single_json_document() {
    jq -e -s 'length == 1' "$1" >/dev/null
}

test_assert_fetcher_failure_preserves_errexit_state() {
    prepare_fetcher
    write_config '{invalid'
    [[ "$-" != *e* ]] || fail 'test requires errexit to start disabled' || return 1

    assert_fetcher_fails_with 'invalid fallback configuration' || return 1

    [[ "$-" != *e* ]] || fail 'assert_fetcher_fails_with enabled errexit'
}

test_reads_fallback_json_without_eval() {
    prepare_fetcher
    rm -f /tmp/must-not-run
    write_config '{"apiUrl":"http://proxy:8317","managementKey":"$(touch /tmp/must-not-run)"}'
    queue_http 200 "$FIXTURES/api/auth-files-empty.json"

    local output
    output="$(run_fetcher)" || return 1

    jq -e '.quotas == [] and .minRemaining == 1 and .avgRemaining == 1' <<<"$output" >/dev/null || return 1
    [[ ! -e /tmp/must-not-run ]] || fail 'config content was executed'
}

test_prefers_fallback_when_file_exists() {
    prepare_fetcher
    write_config '{"apiUrl":"http://fallback","managementKey":"fallback-key"}'
    seed_secret_tool 'http://keyring' 'keyring-key'
    local secret_probe="$TEST_TMP_ROOT/secret-probe"
    printf '#!/usr/bin/env bash\ntouch %q\nexit 23\n' "$TEST_TMP_ROOT/secret-was-called" >"$secret_probe"
    chmod +x "$secret_probe"
    SECRET_MOCK="$secret_probe"
    queue_http 200 "$FIXTURES/api/auth-files-empty.json"
    run_fetcher >/dev/null || return 1
    assert_contains "$(<"$MOCK_CURL_LOG")" 'http://fallback/v0/management/auth-files' || return 1
    [[ ! -e "$TEST_TMP_ROOT/secret-was-called" ]] || fail 'fallback must not query Secret Service'
}

test_uses_keyring_without_fallback_file() {
    prepare_fetcher
    seed_secret_tool 'http://keyring' 'keyring-key'
    queue_http 200 "$FIXTURES/api/auth-files-empty.json"
    run_fetcher >/dev/null || return 1
    assert_contains "$(<"$MOCK_CURL_HEADERS_LOG")" 'Authorization: Bearer keyring-key' || return 1
    [[ "$(<"$MOCK_CURL_LOG")" != *'keyring-key'* ]] || fail 'key leaked into curl arguments'
}

test_rejects_invalid_fallback_json() {
    prepare_fetcher
    write_config '{invalid'
    assert_fetcher_fails_with 'invalid fallback configuration'
}

test_rejects_incomplete_fallback_json() {
    prepare_fetcher
    write_config '{"apiUrl":"http://fallback"}'
    assert_fetcher_fails_with 'invalid fallback configuration'
}

test_rejects_insecure_fallback_permissions() {
    prepare_fetcher
    write_config '{"apiUrl":"http://fallback","managementKey":"fallback-key"}'
    chmod 644 "$QUOTAS_CONFIG_PATH"
    assert_fetcher_fails_with 'permissions'
}

test_rejects_absent_secret_service_without_fallback() {
    prepare_fetcher
    QUOTAS_SECRET_TOOL_BIN="$TEST_TMP_ROOT/missing-secret-tool"
    local output status
    if output="$(env \
            QUOTAS_CONFIG_PATH="$QUOTAS_CONFIG_PATH" \
            QUOTAS_CURL_BIN="$CURL_MOCK" \
            QUOTAS_SECRET_TOOL_BIN="$QUOTAS_SECRET_TOOL_BIN" \
            bash "$FETCHER" 2>&1)"; then
        status=0
    else
        status=$?
    fi
    [[ $status -ne 0 ]] || fail 'missing Secret Service must fail' || return 1
    assert_contains "$output" 'Secret Service'
}

test_absent_secret_check_preserves_errexit_state() {
    [[ "$-" != *e* ]] || fail 'test requires errexit to start disabled' || return 1

    test_rejects_absent_secret_service_without_fallback || return 1

    [[ "$-" != *e* ]] || fail 'absent Secret Service check enabled errexit'
}

test_rejects_incomplete_keyring_pair() {
    prepare_fetcher
    printf '%s' 'http://keyring' >"$MOCK_SECRET_STORE_DIR/quotasApiUrl"
    assert_fetcher_fails_with 'incomplete credentials'
}

test_reports_curl_transport_failure() {
    prepare_fetcher
    write_config '{"apiUrl":"http://fallback","managementKey":"fallback-key"}'
    queue_http 200 "$FIXTURES/api/auth-files-empty.json"
    MOCK_CURL_EXIT_CODE=7
    assert_fetcher_fails_with 'transport failure'
}

test_rejects_non_2xx_auth_files_response() {
    prepare_fetcher
    write_config '{"apiUrl":"http://fallback","managementKey":"fallback-key"}'
    queue_http_text 401 '{"error":"unauthorized"}'
    assert_fetcher_fails_with 'HTTP 401'
}

test_rejects_invalid_auth_files_json() {
    prepare_fetcher
    write_config '{"apiUrl":"http://fallback","managementKey":"fallback-key"}'
    queue_http_text 200 'not-json'
    assert_fetcher_fails_with 'invalid JSON'
}

test_rejects_missing_files_array() {
    prepare_fetcher
    write_config '{"apiUrl":"http://fallback","managementKey":"fallback-key"}'
    queue_http_text 200 '{"files":null}'
    assert_fetcher_fails_with 'files array'
}

test_keeps_stdout_json_only() {
    prepare_fetcher
    write_config '{"apiUrl":"http://fallback","managementKey":"fallback-key"}'
    queue_http 200 "$FIXTURES/api/auth-files-empty.json"
    local stdout_file="$TEST_TMP_ROOT/stdout" stderr_file="$TEST_TMP_ROOT/stderr"

    run_fetcher >"$stdout_file" 2>"$stderr_file" || return 1

    assert_single_json_document "$stdout_file" || return 1
    jq -e '.lastUpdated == "12:34 \u2022 31/07/2026"' "$stdout_file" >/dev/null || return 1
    assert_contains "$(<"$stderr_file")" 'Connecting to http://fallback' || return 1
    [[ "$(<"$stdout_file")" != *'Connecting to'* ]] || fail 'progress leaked to stdout'
}

test_single_json_validator_rejects_json_stream() {
    local one_document="$TEST_TMP_ROOT/one-document" json_stream="$TEST_TMP_ROOT/json-stream"
    printf '{"ok":true}\n' >"$one_document"
    printf '{"ok":true}\n{"extra":true}\n' >"$json_stream"

    assert_single_json_document "$one_document" || return 1
    if assert_single_json_document "$json_stream"; then
        fail 'multiple JSON documents must be rejected'
    fi
}

test_task2_shell_sources_are_ascii() {
    local output status
    if output="$(LC_ALL=C grep -n '[^ -~]' \
        "$repo_root/get-quotas.sh" \
        "$repo_root/tests/test_get_quotas.bash" \
        "$repo_root"/tests/helpers/*.sh 2>&1)"; then
        status=0
    else
        status=$?
    fi
    [[ $status -eq 1 ]] || fail "non-ASCII Task 2 shell source: $output"
}

test_formats_production_time_with_runtime_bullet() {
    prepare_fetcher
    write_config '{"apiUrl":"http://fallback","managementKey":"fallback-key"}'
    queue_http 200 "$FIXTURES/api/auth-files-empty.json"
    mkdir -p "$TEST_TMP_ROOT/bin"
    printf '#!/usr/bin/env bash\nprintf '\''09:08 31/07/2026\\n'\''\n' >"$TEST_TMP_ROOT/bin/date"
    chmod +x "$TEST_TMP_ROOT/bin/date"

    local output
    output="$(run_fetcher_without_now)" || return 1

    jq -e '.lastUpdated == "09:08 \u2022 31/07/2026"' <<<"$output" >/dev/null
}

test_exposes_source_only_interface() {
    prepare_fetcher
    QUOTAS_FETCHER_SOURCE_ONLY=1 QUOTAS_CONFIG_PATH="$QUOTAS_CONFIG_PATH" source "$FETCHER"

    declare -F load_credentials curl_json fetch_auth_files main >/dev/null || return 1
    assert_eq '' "$API_URL" || return 1
    assert_eq '' "$MANAGEMENT_KEY" || return 1
    assert_eq '' "$HTTP_STATUS" || return 1
    assert_eq '' "$HTTP_BODY"
}

test_mock_curl_logs_header_path_separately_from_contents() {
    prepare_fetcher
    write_config '{"apiUrl":"http://fallback","managementKey":"never-log-this-key"}'
    queue_http 200 "$FIXTURES/api/auth-files-empty.json"

    run_fetcher >/dev/null || return 1

    assert_contains "$(<"$MOCK_CURL_LOG")" '--header' || return 1
    assert_contains "$(<"$MOCK_CURL_LOG")" '@' || return 1
    [[ "$(<"$MOCK_CURL_LOG")" != *'never-log-this-key'* ]] || fail 'key leaked into curl arguments' || return 1
    assert_contains "$(<"$MOCK_CURL_HEADERS_LOG")" 'Authorization: Bearer never-log-this-key'
}

test_mock_curl_expands_every_header_file() {
    prepare_fetcher
    local first_header="$TEST_TMP_ROOT/first-header" second_header="$TEST_TMP_ROOT/second-header"
    printf 'First: alpha\n' >"$first_header"
    printf 'Second: beta\n' >"$second_header"
    queue_http 200 "$FIXTURES/api/auth-files-empty.json"

    MOCK_CURL_QUEUE_DIR="$MOCK_CURL_QUEUE_DIR" \
        MOCK_CURL_LOG="$MOCK_CURL_LOG" \
        MOCK_CURL_HEADERS_LOG="$MOCK_CURL_HEADERS_LOG" \
        "$CURL_MOCK" --output "$TEST_TMP_ROOT/body" \
        --header "@$first_header" --header "@$second_header" >/dev/null || return 1

    assert_contains "$(<"$MOCK_CURL_HEADERS_LOG")" 'First: alpha' || return 1
    assert_contains "$(<"$MOCK_CURL_HEADERS_LOG")" 'Second: beta' || return 1
    [[ "$(<"$MOCK_CURL_LOG")" != *'First: alpha'* ]] || fail 'first header leaked into curl arguments' || return 1
    [[ "$(<"$MOCK_CURL_LOG")" != *'Second: beta'* ]] || fail 'second header leaked into curl arguments'
}

run_test 'reads fallback JSON without eval' test_reads_fallback_json_without_eval
run_test 'failure assertion preserves errexit state' test_assert_fetcher_failure_preserves_errexit_state
run_test 'prefers fallback when file exists' test_prefers_fallback_when_file_exists
run_test 'uses keyring without fallback file' test_uses_keyring_without_fallback_file
run_test 'rejects invalid fallback JSON' test_rejects_invalid_fallback_json
run_test 'rejects incomplete fallback JSON' test_rejects_incomplete_fallback_json
run_test 'rejects insecure fallback permissions' test_rejects_insecure_fallback_permissions
run_test 'rejects absent Secret Service without fallback' test_rejects_absent_secret_service_without_fallback
run_test 'absent Secret Service check preserves errexit state' test_absent_secret_check_preserves_errexit_state
run_test 'rejects incomplete keyring pair' test_rejects_incomplete_keyring_pair
run_test 'reports curl transport failure' test_reports_curl_transport_failure
run_test 'rejects non-2xx auth-files response' test_rejects_non_2xx_auth_files_response
run_test 'rejects invalid auth-files JSON' test_rejects_invalid_auth_files_json
run_test 'rejects missing files array' test_rejects_missing_files_array
run_test 'keeps stdout JSON only' test_keeps_stdout_json_only
run_test 'single JSON validator rejects JSON streams' test_single_json_validator_rejects_json_stream
run_test 'Task 2 shell sources are ASCII' test_task2_shell_sources_are_ascii
run_test 'formats production time with runtime bullet' test_formats_production_time_with_runtime_bullet
run_test 'exposes source-only interface' test_exposes_source_only_interface
run_test 'mock curl separates header path from contents' test_mock_curl_logs_header_path_separately_from_contents
run_test 'mock curl expands every header file' test_mock_curl_expands_every_header_file

finish_tests
