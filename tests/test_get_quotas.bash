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
    MOCK_CURL_OUTPUTS_LOG="$TEST_TMP_ROOT/curl-outputs.log"
    MOCK_CURL_HEADER_PATHS_LOG="$TEST_TMP_ROOT/curl-header-paths.log"
    MOCK_SECRET_STORE_DIR="$TEST_TMP_ROOT/secrets"
    QUOTAS_CONFIG_PATH="$TEST_TMP_ROOT/quotas-widget.conf"
    mkdir -p "$MOCK_CURL_QUEUE_DIR" "$MOCK_SECRET_STORE_DIR"
    : >"$MOCK_CURL_LOG"
    : >"$MOCK_CURL_HEADERS_LOG"
    : >"$MOCK_CURL_OUTPUTS_LOG"
    : >"$MOCK_CURL_HEADER_PATHS_LOG"
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
        MOCK_CURL_OUTPUTS_LOG="$MOCK_CURL_OUTPUTS_LOG" \
        MOCK_CURL_HEADER_PATHS_LOG="$MOCK_CURL_HEADER_PATHS_LOG" \
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

# The management key is deliberately an inert command-substitution string.
# shellcheck disable=SC2016
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

test_rejects_multiple_auth_files_json_documents() {
    prepare_fetcher
    write_config '{"apiUrl":"http://fallback","managementKey":"fallback-key"}'
    queue_http_text 200 $'{"files":[]}\n{"files":[]}'
    assert_fetcher_fails_with 'single JSON document'
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
    # FETCHER is the repository get-quotas.sh path configured above.
    # shellcheck source=../get-quotas.sh
    # shellcheck disable=SC1091
    QUOTAS_FETCHER_SOURCE_ONLY=1 QUOTAS_CONFIG_PATH="$QUOTAS_CONFIG_PATH" source "$FETCHER"

    declare -F \
        load_credentials \
        curl_json \
        fetch_auth_files \
        api_call \
        get_codex_quota \
        get_antigravity_quota \
        format_refresh_in \
        fetch_all_quotas \
        main >/dev/null || return 1
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

test_transforms_codex_primary_window() {
    prepare_fetcher
    write_config '{"apiUrl":"http://fallback","managementKey":"fallback-key"}'
    queue_http_text 200 '{"files":[{"name":"codex.json","type":"codex","auth_index":11}]}'
    queue_http 200 "$FIXTURES/api/codex-response.json"

    local output
    output="$(QUOTAS_EPOCH_NOW=1893369600 run_fetcher)" || return 1

    jq -e '
      .quotas[0].type == "codex" and
      .quotas[0].groups[0].name == "Codex Limit" and
      .quotas[0].groups[0].items[0].val == "75.00%" and
      .quotas[0].groups[0].items[0].resetTime == "1 day, 0 hours" and
      .quotas[0].minRemaining == 0.75 and
      .minRemaining == 0.75 and
      .avgRemaining == 0.75
    ' <<<"$output" >/dev/null
    assert_contains "$(<"$MOCK_CURL_LOG")" 'https://chatgpt.com/backend-api/wham/usage' || return 1
    assert_contains "$(<"$MOCK_CURL_LOG")" 'codex_cli_rs/0.76.0' || return 1
    [[ "$(<"$MOCK_CURL_LOG")" != *'fallback-key'* ]] || fail 'management key leaked into provider curl arguments'
}

test_transforms_antigravity_groups() {
    prepare_fetcher
    write_config '{"apiUrl":"http://fallback","managementKey":"fallback-key"}'
    queue_http_text 200 '{"files":[{"name":"antigravity.json","type":"antigravity","auth_index":22,"project_id":"project-direct"}]}'
    queue_http 200 "$FIXTURES/api/antigravity-response.json"

    local output
    output="$(QUOTAS_EPOCH_NOW=1893369600 run_fetcher)" || return 1

    jq -e '
      .quotas[0].type == "antigravity" and
      (.quotas[0].groups | length) == 2 and
      .quotas[0].groups[0].name == "Gemini Models" and
      .quotas[0].groups[0].items[0].label == "Gemini Pro" and
      .quotas[0].groups[0].items[1].label == "gemini-flash" and
      .quotas[0].groups[0].items[1].val == "20.00%" and
      .quotas[0].minRemaining == 0.2 and
      .minRemaining == 0.2
    ' <<<"$output" >/dev/null
}

test_reads_antigravity_project_id_from_metadata() {
    prepare_fetcher
    write_config '{"apiUrl":"http://fallback","managementKey":"fallback-key"}'
    queue_http_text 200 '{"files":[{"name":"metadata.json","type":"antigravity","auth_index":22,"attributes":{"gemini_virtual_project":"metadata-project"}}]}'
    queue_http 200 "$FIXTURES/api/antigravity-response.json"

    run_fetcher >/dev/null || return 1

    [[ "$(<"$MOCK_CURL_LOG")" != *'/auth-files/download?'* ]] || fail 'metadata project ID must avoid auth-file download' || return 1
    assert_contains "$(<"$MOCK_CURL_LOG")" 'retrieveUserQuotaSummary' || return 1
    assert_contains "$(<"$MOCK_CURL_LOG")" 'antigravity/cli/1.0.13' || return 1
    [[ "$(<"$MOCK_CURL_LOG")" != *'fallback-key'* ]] || fail 'management key leaked into provider curl arguments'
}

test_downloads_antigravity_auth_file_for_project_id() {
    prepare_fetcher
    write_config '{"apiUrl":"http://fallback","managementKey":"fallback-key"}'
    queue_http_text 200 '{"files":[{"name":"antigravity account.json","type":"antigravity","auth_index":22}]}'
    queue_http 200 "$FIXTURES/api/antigravity-auth-file.json"
    queue_http 200 "$FIXTURES/api/antigravity-response.json"

    local output
    output="$(run_fetcher)" || return 1

    jq -e '.quotas[0].name == "antigravity account.json" and .quotas[0].minRemaining == 0.2' <<<"$output" >/dev/null || return 1
    assert_contains "$(<"$MOCK_CURL_LOG")" 'download\?name=antigravity%20account.json'
}

test_rejects_upstream_error_status() {
    prepare_fetcher
    write_config '{"apiUrl":"http://fallback","managementKey":"fallback-key"}'
    queue_http_text 200 '{"files":[{"name":"codex.json","type":"codex","auth_index":11}]}'
    queue_http_text 200 '{"status_code":429,"body":{"error":"rate limited"}}'
    local stdout_file="$TEST_TMP_ROOT/stdout" stderr_file="$TEST_TMP_ROOT/stderr"

    run_fetcher >"$stdout_file" 2>"$stderr_file" || return 1

    jq -e '.quotas == [] and .minRemaining == 1 and .avgRemaining == 1' "$stdout_file" >/dev/null || return 1
    assert_contains "$(<"$stderr_file")" 'Upstream API returned status 429'
}

test_accepts_string_wrapper_body() {
    prepare_fetcher
    write_config '{"apiUrl":"http://fallback","managementKey":"fallback-key"}'
    queue_http_text 200 '{"files":[{"name":"codex.json","type":"codex","auth_index":11}]}'
    queue_http 200 "$FIXTURES/api/codex-response.json"

    local output
    output="$(run_fetcher)" || return 1

    jq -e '.quotas[0].groups[0].items[0].val == "75.00%"' <<<"$output" >/dev/null
}

test_accepts_object_wrapper_body() {
    prepare_fetcher
    write_config '{"apiUrl":"http://fallback","managementKey":"fallback-key"}'
    queue_http_text 200 '{"files":[{"name":"codex.json","type":"codex","auth_index":11}]}'
    queue_http_text 200 '{"status_code":200,"body":{"rate_limit":{"primary_window":{"used_percent":40,"reset_at":1893456000}}}}'

    local output
    output="$(run_fetcher)" || return 1

    jq -e '.quotas[0].groups[0].items[0].val == "60.00%"' <<<"$output" >/dev/null
}

test_rejects_multiple_proxy_json_documents() {
    prepare_fetcher
    write_config '{"apiUrl":"http://fallback","managementKey":"fallback-key"}'
    queue_http_text 200 '{"files":[{"name":"codex.json","type":"codex","auth_index":11}]}'
    queue_http_text 200 $'{"status_code":200,"body":{}}\n{"status_code":200,"body":{}}'
    local stdout_file="$TEST_TMP_ROOT/stdout" stderr_file="$TEST_TMP_ROOT/stderr"

    run_fetcher >"$stdout_file" 2>"$stderr_file" || return 1

    jq -e '.quotas == []' "$stdout_file" >/dev/null || return 1
    assert_contains "$(<"$stderr_file")" 'single JSON document'
}

test_skips_non_object_auth_file_members_and_continues() {
    prepare_fetcher
    write_config '{"apiUrl":"http://fallback","managementKey":"fallback-key"}'
    queue_http_text 200 '{"files":[null,"bad",[],17,{"name":"codex.json","type":"codex","auth_index":11}]}'
    queue_http 200 "$FIXTURES/api/codex-response.json"

    local output
    output="$(run_fetcher)" || return 1

    jq -e '.quotas | length == 1 and .[0].name == "codex.json"' <<<"$output" >/dev/null
}

test_cleans_request_temp_directory_on_term() {
    prepare_fetcher
    write_config '{"apiUrl":"http://fallback","managementKey":"fallback-key"}'
    queue_http 200 "$FIXTURES/api/auth-files-empty.json"
    local ready="$TEST_TMP_ROOT/curl-ready" request_parent="$TEST_TMP_ROOT/request-tmp"
    local stdout_file="$TEST_TMP_ROOT/stdout" stderr_file="$TEST_TMP_ROOT/stderr" pid status path request_dir index
    mkdir -p "$request_parent"

    setsid env \
        QUOTAS_CONFIG_PATH="$QUOTAS_CONFIG_PATH" \
        QUOTAS_CURL_BIN="$CURL_MOCK" \
        QUOTAS_SECRET_TOOL_BIN="$SECRET_MOCK" \
        QUOTAS_REQUEST_TMP_PARENT="$request_parent" \
        MOCK_CURL_QUEUE_DIR="$MOCK_CURL_QUEUE_DIR" \
        MOCK_CURL_LOG="$MOCK_CURL_LOG" \
        MOCK_CURL_HEADERS_LOG="$MOCK_CURL_HEADERS_LOG" \
        MOCK_CURL_OUTPUTS_LOG="$MOCK_CURL_OUTPUTS_LOG" \
        MOCK_CURL_HEADER_PATHS_LOG="$MOCK_CURL_HEADER_PATHS_LOG" \
        MOCK_CURL_BLOCK_READY="$ready" \
        MOCK_SECRET_STORE_DIR="$MOCK_SECRET_STORE_DIR" \
        bash "$FETCHER" >"$stdout_file" 2>"$stderr_file" &
    pid=$!

    for ((index = 0; index < 200; index++)); do
        [[ ! -e "$ready" ]] || break
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.01
    done
    [[ -e "$ready" ]] || {
        kill -TERM -- "-$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
        fail 'mock curl did not reach interruption point' || return 1
    }
    path="$(<"$MOCK_CURL_HEADER_PATHS_LOG")"
    request_dir="${path%/*}"
    assert_file_mode 700 "$request_dir" || return 1

    kill -TERM -- "-$pid"
    set +e
    wait "$pid"
    status=$?
    set -e
    [[ $status -ne 0 ]] || fail 'TERM must stop the fetcher' || return 1
    [[ ! -e "$request_dir" ]] || fail "request temp directory remained after TERM: $request_dir"
}

test_formats_percentages_with_dot_under_comma_locale() {
    prepare_fetcher
    write_config '{"apiUrl":"http://fallback","managementKey":"fallback-key"}'
    queue_http_text 200 '{"files":[{"name":"codex.json","type":"codex","auth_index":11},{"name":"antigravity.json","type":"antigravity","auth_index":22,"project_id":"project-direct"}]}'
    queue_http 200 "$FIXTURES/api/codex-response.json"
    queue_http 200 "$FIXTURES/api/antigravity-response.json"

    local output
    output="$(LC_NUMERIC=ru_RU.utf8 run_fetcher)" || return 1

    jq -e '
      .quotas[0].groups[0].items[0].val == "75.00%" and
      .quotas[1].groups[0].items[0].val == "60.00%" and
      .quotas[1].groups[0].items[1].val == "20.00%"
    ' <<<"$output" >/dev/null
}

# Generated helper scripts and bash -c input must retain their shell expressions literally.
# shellcheck disable=SC2016
test_cleans_aggregation_temp_files_after_unexpected_failure() {
    prepare_fetcher
    mkdir -p "$TEST_TMP_ROOT/bin"
    printf '#!/usr/bin/env bash\nset -euo pipefail\ncounter_file=%q\ncounter=0\n[[ ! -f "$counter_file" ]] || counter="$(<"$counter_file")"\ncounter=$((counter + 1))\nprintf '\''%%s\\n'\'' "$counter" >"$counter_file"\npath=%q/mktemp-$counter\n: >"$path"\nprintf '\''%%s\\n'\'' "$path"\n' \
        "$TEST_TMP_ROOT/mktemp-counter" "$TEST_TMP_ROOT" >"$TEST_TMP_ROOT/bin/mktemp"
    printf '#!/usr/bin/env bash\nset -euo pipefail\nfor arg in "$@"; do\n    [[ "$arg" != "-s" ]] || exit 23\ndone\nexec /usr/bin/jq "$@"\n' >"$TEST_TMP_ROOT/bin/jq"
    chmod +x "$TEST_TMP_ROOT/bin/mktemp" "$TEST_TMP_ROOT/bin/jq"

    local status
    if env PATH="$TEST_TMP_ROOT/bin:$PATH" \
            QUOTAS_FETCHER_SOURCE_ONLY=1 \
            QUOTAS_NOW='12:34 fixed' \
            bash -c 'source "$1"; HTTP_BODY='\''{"files":[]}'\''; fetch_all_quotas' _ "$FETCHER" \
            >/dev/null 2>&1; then
        status=0
    else
        status=$?
    fi

    [[ $status -ne 0 ]] || fail 'forced aggregation failure must fail the fetcher' || return 1
    assert_eq '2' "$(<"$TEST_TMP_ROOT/mktemp-counter")" || return 1
    [[ ! -e "$TEST_TMP_ROOT/mktemp-1" ]] || fail 'account aggregation temp file remained after failure' || return 1
    [[ ! -e "$TEST_TMP_ROOT/mktemp-2" ]] || fail 'remaining-fraction temp file remained after failure'
}

test_falls_back_from_empty_antigravity_display_names() {
    prepare_fetcher
    write_config '{"apiUrl":"http://fallback","managementKey":"fallback-key"}'
    queue_http_text 200 '{"files":[{"name":"unnamed-limits.json","type":"antigravity","auth_index":22,"project_id":"project-direct"}]}'
    queue_http_text 200 '{"status_code":200,"body":{"groups":[{"displayName":"","buckets":[{"bucketId":"fallback-bucket","displayName":"","remainingFraction":0.5}]}]}}'

    local output
    output="$(run_fetcher)" || return 1

    jq -e '
      .quotas[0].groups[0].name == "Limits" and
      .quotas[0].groups[0].items[0].label == "fallback-bucket"
    ' <<<"$output" >/dev/null
}

test_keeps_antigravity_account_without_displayable_groups() {
    prepare_fetcher
    write_config '{"apiUrl":"http://fallback","managementKey":"fallback-key"}'
    queue_http_text 200 '{"files":[{"name":"empty-antigravity.json","type":"antigravity","auth_index":22,"project_id":"project-direct"}]}'
    queue_http_text 200 '{"status_code":200,"body":{"groups":[{"displayName":"Empty","buckets":[{"bucketId":"no-fraction"}]}]}}'

    local output
    output="$(run_fetcher)" || return 1

    jq -e '
      .quotas[0].name == "empty-antigravity.json" and
      .quotas[0].groups == [] and
      .quotas[0].minRemaining == null and
      .minRemaining == 1 and
      .avgRemaining == 1
    ' <<<"$output" >/dev/null
}

test_returns_partial_result_after_account_failure() {
    prepare_fetcher
    write_config '{"apiUrl":"http://fallback","managementKey":"fallback-key"}'
    queue_http 200 "$FIXTURES/api/auth-files-mixed.json"
    queue_http_text 200 '{"status_code":500,"body":{"error":"codex unavailable"}}'
    queue_http 200 "$FIXTURES/api/antigravity-response.json"

    local output
    output="$(run_fetcher 2>"$TEST_TMP_ROOT/stderr")" || return 1

    jq -e '.quotas | length == 1 and .[0].type == "antigravity"' <<<"$output" >/dev/null || return 1
    assert_contains "$(<"$TEST_TMP_ROOT/stderr")" 'codex-primary.json'
}

test_computes_global_average_from_displayed_limits() {
    prepare_fetcher
    write_config '{"apiUrl":"http://fallback","managementKey":"fallback-key"}'
    queue_http 200 "$FIXTURES/api/auth-files-mixed.json"
    queue_http 200 "$FIXTURES/api/codex-response.json"
    queue_http 200 "$FIXTURES/api/antigravity-response.json"

    local output
    output="$(run_fetcher)" || return 1

    jq -e '.avgRemaining == 0.6125 and .minRemaining == 0.2 and (.quotas | length) == 2' <<<"$output" >/dev/null
}

test_skips_disabled_and_runtime_only_accounts() {
    prepare_fetcher
    write_config '{"apiUrl":"http://fallback","managementKey":"fallback-key"}'
    queue_http 200 "$FIXTURES/api/auth-files-mixed.json"
    queue_http 200 "$FIXTURES/api/codex-response.json"
    queue_http 200 "$FIXTURES/api/antigravity-response.json"

    local output
    output="$(run_fetcher)" || return 1

    jq -e '
      [.quotas[].name] == ["codex-primary.json", "antigravity-main.json"] and
      ([.quotas[].name] | index("disabled-codex.json")) == null and
      ([.quotas[].name] | index("runtime-antigravity.json")) == null
    ' <<<"$output" >/dev/null
}

test_logs_unsupported_provider() {
    prepare_fetcher
    write_config '{"apiUrl":"http://fallback","managementKey":"fallback-key"}'
    queue_http 200 "$FIXTURES/api/auth-files-mixed.json"
    queue_http 200 "$FIXTURES/api/codex-response.json"
    queue_http 200 "$FIXTURES/api/antigravity-response.json"
    local stderr_file="$TEST_TMP_ROOT/stderr"

    run_fetcher >/dev/null 2>"$stderr_file" || return 1

    assert_contains "$(<"$stderr_file")" 'unsupported-claude.json' || return 1
    assert_contains "$(<"$stderr_file")" 'unsupported provider claude'
}

test_formats_epoch_seconds_reset() {
    # FETCHER is the repository get-quotas.sh path configured above.
    # shellcheck source=../get-quotas.sh
    # shellcheck disable=SC1091
    QUOTAS_FETCHER_SOURCE_ONLY=1 source "$FETCHER"
    export QUOTAS_EPOCH_NOW=1893369600
    assert_eq '1 day, 0 hours' "$(format_refresh_in 1893456000)"
}

test_formats_epoch_milliseconds_reset() {
    # FETCHER is the repository get-quotas.sh path configured above.
    # shellcheck source=../get-quotas.sh
    # shellcheck disable=SC1091
    QUOTAS_FETCHER_SOURCE_ONLY=1 source "$FETCHER"
    export QUOTAS_EPOCH_NOW=1893369600
    assert_eq '1 day, 0 hours' "$(format_refresh_in 1893456000000)"
}

test_formats_iso_reset() {
    # FETCHER is the repository get-quotas.sh path configured above.
    # shellcheck source=../get-quotas.sh
    # shellcheck disable=SC1091
    QUOTAS_FETCHER_SOURCE_ONLY=1 source "$FETCHER"
    export QUOTAS_EPOCH_NOW=1893369600
    assert_eq '1 day, 0 hours' "$(format_refresh_in '2030-01-01T00:00:00Z')"
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
run_test 'rejects multiple auth-files JSON documents' test_rejects_multiple_auth_files_json_documents
run_test 'rejects missing files array' test_rejects_missing_files_array
run_test 'keeps stdout JSON only' test_keeps_stdout_json_only
run_test 'single JSON validator rejects JSON streams' test_single_json_validator_rejects_json_stream
run_test 'Task 2 shell sources are ASCII' test_task2_shell_sources_are_ascii
run_test 'formats production time with runtime bullet' test_formats_production_time_with_runtime_bullet
run_test 'exposes source-only interface' test_exposes_source_only_interface
run_test 'mock curl separates header path from contents' test_mock_curl_logs_header_path_separately_from_contents
run_test 'mock curl expands every header file' test_mock_curl_expands_every_header_file
run_test 'transforms Codex primary window' test_transforms_codex_primary_window
run_test 'transforms Antigravity groups' test_transforms_antigravity_groups
run_test 'reads Antigravity project ID from metadata' test_reads_antigravity_project_id_from_metadata
run_test 'downloads Antigravity auth file for project ID' test_downloads_antigravity_auth_file_for_project_id
run_test 'rejects upstream error status' test_rejects_upstream_error_status
run_test 'accepts string wrapper body' test_accepts_string_wrapper_body
run_test 'accepts object wrapper body' test_accepts_object_wrapper_body
run_test 'rejects multiple proxy JSON documents' test_rejects_multiple_proxy_json_documents
run_test 'skips non-object auth-file members and continues' test_skips_non_object_auth_file_members_and_continues
run_test 'cleans request temp directory on TERM' test_cleans_request_temp_directory_on_term
run_test 'formats percentages with dot under comma locale' test_formats_percentages_with_dot_under_comma_locale
run_test 'cleans aggregation temp files after unexpected failure' test_cleans_aggregation_temp_files_after_unexpected_failure
run_test 'falls back from empty Antigravity display names' test_falls_back_from_empty_antigravity_display_names
run_test 'keeps Antigravity account without displayable groups' test_keeps_antigravity_account_without_displayable_groups
run_test 'returns partial result after account failure' test_returns_partial_result_after_account_failure
run_test 'computes global average from displayed limits' test_computes_global_average_from_displayed_limits
run_test 'skips disabled and runtime-only accounts' test_skips_disabled_and_runtime_only_accounts
run_test 'logs unsupported provider' test_logs_unsupported_provider
run_test 'formats epoch-seconds reset' test_formats_epoch_seconds_reset
run_test 'formats epoch-milliseconds reset' test_formats_epoch_milliseconds_reset
run_test 'formats ISO reset' test_formats_iso_reset

finish_tests
