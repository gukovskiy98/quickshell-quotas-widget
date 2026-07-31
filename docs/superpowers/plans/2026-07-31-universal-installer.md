# Universal Installer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish an idempotent one-line installer for the end4-dots Quickshell quota widget, remove Bun and user-specific paths, and replace the TypeScript quota client with a Bash 4+ client using `curl` and `jq`.

**Architecture:** Keep `install.sh` self-contained so it works through `curl | bash`, while exposing internal functions under a source-only test seam. Install a release archive containing two QML files and `get-quotas.sh`; the runtime client reads either a local JSON credential file or Secret Service, and the installer modifies `BarContent.qml` transactionally with backups and rollback.

**Tech Stack:** Bash 4+, curl, jq, GNU/POSIX command-line utilities, tar, QML/Quickshell, GitHub Actions, ShellCheck, a repository-local Bash test harness.

## Global Constraints

- Support only Hyprland + Quickshell + compatible end4-dots installations; generic Quickshell configurations are out of scope.
- Require Bash 4+, `curl`, `jq`, and `tar`; do not require Bun or Node.js.
- Do not install packages, invoke `sudo`, or silently modify system configuration.
- Keep `secret-tool` and `notify-send` optional.
- Never print the management key to stdout or stderr.
- Prefer Secret Service; automatically fall back to `<install-dir>/quotas-widget.conf` with mode `600` and a visible warning.
- Preserve the current effective provider display support: Antigravity and Codex only.
- Keep stdout from `get-quotas.sh` to one JSON document; send diagnostics to stderr.
- Make repeat installation idempotent and never duplicate the managed QML block.
- Create timestamped backups only for files whose content changes.
- Roll back file changes and fallback credentials when installation fails after persistent writes begin; do not delete or restore keyring values automatically.
- Keep public documentation bilingual: complete English first, complete Russian second.
- Use ASCII in shell source and tests; retain the existing `•` character only in user-visible timestamp output and documentation examples.

## File Map

- Create `install.sh`: self-contained public bootstrap installer, argument parsing, preflight, API/release validation, credentials, transactional installation, bar integration, smoke test, and Quickshell restart.
- Create `get-quotas.sh`: runtime Management API client and Antigravity/Codex response transformer.
- Modify `Quotas.qml`: launch the neighboring shell client without Bun, preserve previous successful data on errors, and keep optional notifications.
- Keep `QuotasPopup.qml`: no functional redesign; only adjust if a test exposes compatibility issues.
- Delete `get-quotas.ts`: obsolete after the Bash client reaches parity.
- Create `tests/test_helper.bash`: minimal test runner and assertion helpers.
- Create `tests/run.sh`: execute every repository shell test.
- Create `tests/test_install.bash`: installer unit and integration tests.
- Create `tests/test_get_quotas.bash`: runtime client tests.
- Create `tests/test_qml.bash`: static QML portability assertions.
- Create `tests/test_docs.bash`: public documentation contract assertions.
- Create `tests/helpers/mock_curl.sh`: deterministic curl-compatible response queue for tests.
- Create `tests/helpers/mock_secret_tool.sh`: deterministic Secret Service mock.
- Create `tests/fixtures/end4-dots/ii/shell.qml`: compatible end4-dots fixture.
- Create `tests/fixtures/end4-dots/ii/modules/ii/bar/BarContent.qml`: compatible bar fixture.
- Create `tests/fixtures/api/*.json`: auth-file and provider response fixtures.
- Create `.github/workflows/test.yml`: test and ShellCheck workflow.
- Create `.github/workflows/release.yml`: tag-driven release archive workflow.
- Create `scripts/package-release.sh`: deterministic release archive builder shared by tests and GitHub Actions.
- Modify `.gitignore`: exclude generated plaintext credentials and local test artifacts only.
- Rewrite `README.md`: bilingual public installation, update, security, dependency, and recovery guide.

---

### Task 1: Shell Test Harness And Installer CLI

**Files:**
- Create: `tests/test_helper.bash`
- Create: `tests/run.sh`
- Create: `tests/test_install.bash`
- Create: `tests/fixtures/end4-dots/ii/shell.qml`
- Create: `tests/fixtures/end4-dots/ii/modules/ii/bar/BarContent.qml`
- Create: `install.sh`

**Interfaces:**
- Consumes: none.
- Produces: `install.sh` functions `usage()`, `die(message)`, `warn(message)`, `parse_args(args...)`, `normalize_api_url(url)`, `resolve_layout()`, `require_bash_version(major)`, `require_dependencies()`, and `validate_end4_layout()`.
- Produces test seam: setting `QUOTAS_INSTALLER_SOURCE_ONLY=1` before sourcing `install.sh` prevents `main` from running.
- Produces parsed globals: `API_URL`, `MANAGEMENT_KEY`, `KEY_INPUT_MODE`, `INSTALL_DIR`, `QS_BIN`, and `CONFIG_ROOT`.

- [ ] **Step 1: Add a minimal repository-local test harness**

Create `tests/test_helper.bash` with isolated temporary directories and explicit assertions:

```bash
#!/usr/bin/env bash
set -uo pipefail

TESTS_RUN=0
TESTS_FAILED=0
TEST_TMP_ROOT=""

setup_test_tmp() {
    TEST_TMP_ROOT="$(mktemp -d)"
}

cleanup_test_tmp() {
    [[ -z "${TEST_TMP_ROOT:-}" ]] || rm -rf -- "$TEST_TMP_ROOT"
}

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    return 1
}

assert_eq() {
    local expected="$1" actual="$2"
    [[ "$actual" == "$expected" ]] || fail "expected [$expected], got [$actual]"
}

assert_contains() {
    local haystack="$1" needle="$2"
    [[ "$haystack" == *"$needle"* ]] || fail "missing [$needle] in [$haystack]"
}

assert_file_exists() {
    [[ -f "$1" ]] || fail "expected file $1"
}

assert_file_mode() {
    local expected="$1" path="$2"
    assert_eq "$expected" "$(stat -c '%a' "$path")"
}

run_test() {
    local name="$1"
    shift
    TESTS_RUN=$((TESTS_RUN + 1))
    setup_test_tmp
    if ( "$@" ); then
        printf 'ok %d - %s\n' "$TESTS_RUN" "$name"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf 'not ok %d - %s\n' "$TESTS_RUN" "$name"
    fi
    cleanup_test_tmp
}

finish_tests() {
    printf '%d tests, %d failures\n' "$TESTS_RUN" "$TESTS_FAILED"
    (( TESTS_FAILED == 0 ))
}
```

Create `tests/run.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

for test_file in "$repo_root"/tests/test_*.bash; do
    bash "$test_file"
done
```

- [ ] **Step 2: Add representative compatible end4-dots fixtures**

Create `tests/fixtures/end4-dots/ii/shell.qml` containing `ShellRoot`, a `families: ["ii", "waffle"]` property, and `IllogicalImpulseFamily {}`. Create `BarContent.qml` containing a `BarGroup` with `id: leftCenterGroup`, a nested `Resources {}` block, and a following `Media {}` block. Keep enough nesting to exercise brace matching:

```qml
import QtQuick
import QtQuick.Layouts

Item {
    Row {
        BarGroup {
            id: leftCenterGroup

            Resources {
                alwaysShowAllResources: root.useShortenedForm === 2
                Layout.fillWidth: root.useShortenedForm === 2
            }

            Media {
                Layout.fillWidth: true
            }
        }
    }
}
```

- [ ] **Step 3: Write failing CLI and preflight tests**

Create `tests/test_install.bash`, source `install.sh` with `QUOTAS_INSTALLER_SOURCE_ONLY=1`, reset parsed globals before each case, and add these tests:

```bash
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
```

Add named test functions `test_help_exits_zero`, `test_rejects_unknown_flag`, `test_rejects_missing_flag_value`, `test_rejects_empty_key`, `test_accepts_http_url`, `test_accepts_https_url`, `test_resolves_custom_install_dir`, `test_rejects_bash_3`, `test_accepts_bash_4`, `test_rejects_missing_bar_content`, `test_rejects_missing_shell_qml`, `test_rejects_missing_left_center_group`, `test_rejects_missing_resources`, `test_reports_missing_hyprctl`, `test_reports_missing_quickshell`, `test_reports_missing_curl`, `test_reports_missing_jq`, `test_reports_missing_tar`, and `test_warns_when_notify_send_is_missing`. Each test must invoke one public function, assert nonzero status for invalid input, and assert the diagnostic names the missing flag, file, structure token, or command. The notification test must assert success plus a warning, not failure.

- [ ] **Step 4: Run the installer tests and verify they fail**

Run: `bash tests/test_install.bash`

Expected: FAIL because `install.sh` and its functions do not exist.

- [ ] **Step 5: Implement the minimal self-contained installer shell and CLI**

Create `install.sh` with `set -Eeuo pipefail`, English-first bilingual `usage`, `die`, and `warn`, and this execution guard:

```bash
if [[ "${QUOTAS_INSTALLER_SOURCE_ONLY:-0}" != "1" ]]; then
    main "$@"
fi
```

Implement argument parsing without `getopt`, because GNU `getopt` is not a declared dependency. Use a `while (($#)); do case "$1" in ... esac; done` loop. Use these defaults:

```bash
API_URL=""
MANAGEMENT_KEY=""
KEY_INPUT_MODE="tty"
INSTALL_DIR=""
QS_BIN=""
CONFIG_ROOT=""
```

`normalize_api_url` must accept only `http://` and `https://`, remove all trailing slashes after the authority/path, and reject an empty normalized value. `resolve_layout` must compute the default from `XDG_CONFIG_HOME` and derive `CONFIG_ROOT` as `INSTALL_DIR/../../..` using `pwd -P` only after confirming the path or nearest existing parent is valid.

`require_bash_version` must reject a supplied major version below `4`; `main` calls it with `${BASH_VERSINFO[0]}`. `require_dependencies` must aggregate missing commands instead of failing on the first one. Resolve Quickshell by preferring `quickshell`, then `qs`. Required commands are `hyprctl`, the selected Quickshell binary, `curl`, `jq`, and `tar`. Print package-manager hints for `pacman`, `apt-get`, `dnf`, and `zypper`, but do not run them. Missing `notify-send` emits a warning explaining that refresh still works without desktop notifications.

`validate_end4_layout` must verify both files and characteristic tokens. Do not accept a random QML file containing only one matching word.

- [ ] **Step 6: Run tests and verify the CLI/preflight slice passes**

Run: `bash tests/test_install.bash`

Expected: all Task 1 tests PASS.

- [ ] **Step 7: Commit the CLI and harness slice**

```bash
git add install.sh tests/test_helper.bash tests/run.sh tests/test_install.bash tests/fixtures/end4-dots
git commit -m "Add installer CLI and preflight checks"
```

---

### Task 2: Quota Client Credentials And Global API Request

**Files:**
- Create: `tests/helpers/mock_curl.sh`
- Create: `tests/helpers/mock_secret_tool.sh`
- Create: `tests/fixtures/api/auth-files-empty.json`
- Create: `tests/test_get_quotas.bash`
- Create: `get-quotas.sh`

**Interfaces:**
- Consumes: fallback config schema `{ "apiUrl": string, "managementKey": string }`.
- Produces: executable `get-quotas.sh` with functions `load_credentials()`, `curl_json(method, url, request_body?)`, `fetch_auth_files()`, and `main()`.
- Produces test seams: `QUOTAS_FETCHER_SOURCE_ONLY=1`, `QUOTAS_CONFIG_PATH`, `QUOTAS_CURL_BIN`, `QUOTAS_SECRET_TOOL_BIN`, and `QUOTAS_NOW`.
- Produces globals: `API_URL`, `MANAGEMENT_KEY`, `HTTP_STATUS`, and `HTTP_BODY`.

- [ ] **Step 1: Add deterministic command mocks**

Create `tests/helpers/mock_curl.sh`. It must emulate the subset of curl used by both scripts: parse `--output PATH`, append the complete argument vector to `$MOCK_CURL_LOG`, copy the contents of any `--header @FILE` argument to `$MOCK_CURL_HEADERS_LOG`, consume the next numbered file from `$MOCK_CURL_QUEUE_DIR`, write all lines after the first to the output path, print the first line as the HTTP status, and exit with `${MOCK_CURL_EXIT_CODE:-0}`. The argument log must contain only the `@FILE` path, never expanded header content.

Queue file format:

```text
200
{"files":[]}
```

Create `tests/helpers/mock_secret_tool.sh` with `store` and `lookup` behavior backed by `$MOCK_SECRET_STORE_DIR`. Read the stored secret from stdin for `store`; map the final lookup key (`quotasApiUrl` or `quotasManagementKey`) to a file. Support `${MOCK_SECRET_FAIL_STORE:-0}` and `${MOCK_SECRET_FAIL_LOOKUP:-0}`.

- [ ] **Step 2: Write failing credential and global-request tests**

Create `tests/fixtures/api/auth-files-empty.json`:

```json
{"files":[]}
```

Add tests that execute `get-quotas.sh` as a process, not only sourced functions:

```bash
test_reads_fallback_json_without_eval() {
    write_config '{"apiUrl":"http://proxy:8317","managementKey":"$(touch /tmp/must-not-run)"}'
    queue_http 200 "$FIXTURES/api/auth-files-empty.json"

    output="$(run_fetcher)"

    jq -e '.quotas == [] and .minRemaining == 1 and .avgRemaining == 1' <<<"$output" >/dev/null
    [[ ! -e /tmp/must-not-run ]] || fail 'config content was executed'
}

test_prefers_fallback_when_file_exists() {
    write_config '{"apiUrl":"http://fallback","managementKey":"fallback-key"}'
    seed_secret_tool 'http://keyring' 'keyring-key'
    queue_http 200 "$FIXTURES/api/auth-files-empty.json"
    run_fetcher >/dev/null
    assert_contains "$(<"$MOCK_CURL_LOG")" 'http://fallback/v0/management/auth-files'
}

test_uses_keyring_without_fallback_file() {
    seed_secret_tool 'http://keyring' 'keyring-key'
    queue_http 200 "$FIXTURES/api/auth-files-empty.json"
    run_fetcher >/dev/null
    assert_contains "$(<"$MOCK_CURL_HEADERS_LOG")" 'Authorization: Bearer keyring-key'
    [[ "$(<"$MOCK_CURL_LOG")" != *'keyring-key'* ]] || fail 'key leaked into curl arguments'
}
```

Add named test functions `test_rejects_invalid_fallback_json`, `test_rejects_incomplete_fallback_json`, `test_rejects_absent_secret_service_without_fallback`, `test_rejects_incomplete_keyring_pair`, `test_reports_curl_transport_failure`, `test_rejects_non_2xx_auth_files_response`, `test_rejects_invalid_auth_files_json`, `test_rejects_missing_files_array`, and `test_keeps_stdout_json_only`. For the last test, capture stdout and stderr separately, validate stdout with `jq -e`, and assert the progress message appears only in stderr.

- [ ] **Step 3: Run the quota tests and verify they fail**

Run: `bash tests/test_get_quotas.bash`

Expected: FAIL because `get-quotas.sh` does not exist.

- [ ] **Step 4: Implement credential loading and the global API request**

Create `get-quotas.sh` with `set -Eeuo pipefail` and a source-only guard matching the installer pattern. Determine the default config path from the script directory:

```bash
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="${QUOTAS_CONFIG_PATH:-$SCRIPT_DIR/quotas-widget.conf}"
```

If `CONFIG_PATH` exists, require mode `600` or stricter, parse both strings with `jq -er`, and never query Secret Service. Otherwise, query both keyring attributes. Reject incomplete pairs.

Implement `curl_json` with a temporary response file so HTTP status and response body cannot mix:

```bash
HTTP_STATUS="$($curl_bin --silent --show-error --location \
    --output "$response_file" --write-out '%{http_code}' \
    --request "$method" "$@" "$url")"
HTTP_BODY="$(<"$response_file")"
```

The displayed snippet is structural pseudocode. The real implementation must write `Authorization: Bearer $MANAGEMENT_KEY` and `Content-Type: application/json` to a mode-`600` temporary header file and pass it as `--header @<path>`, so the key does not appear in curl's argument list. Add a bounded connect timeout and total timeout. Reject non-2xx status and invalid JSON without printing headers or credentials, and delete the header file through a function-local trap or explicit cleanup on every return path.

For an empty account list, output:

```json
{"quotas":[],"minRemaining":1,"avgRemaining":1,"lastUpdated":"<formatted time>"}
```

Use `${QUOTAS_NOW:-}` only in tests; production uses `date '+%H:%M • %d/%m/%Y'`.

- [ ] **Step 5: Run quota tests and verify the foundation passes**

Run: `bash tests/test_get_quotas.bash`

Expected: all Task 2 tests PASS.

- [ ] **Step 6: Commit the quota-client foundation**

```bash
git add get-quotas.sh tests/test_get_quotas.bash tests/helpers tests/fixtures/api/auth-files-empty.json
git commit -m "Add Bash quota client foundation"
```

---

### Task 3: Antigravity And Codex Quota Transformation

**Files:**
- Modify: `get-quotas.sh`
- Modify: `tests/test_get_quotas.bash`
- Create: `tests/fixtures/api/auth-files-mixed.json`
- Create: `tests/fixtures/api/codex-response.json`
- Create: `tests/fixtures/api/antigravity-response.json`
- Create: `tests/fixtures/api/antigravity-auth-file.json`
- Delete: `get-quotas.ts`

**Interfaces:**
- Consumes: `curl_json()` and credential globals from Task 2.
- Produces: `api_call(auth_index, method, upstream_url, headers_json, data?)`, `get_codex_quota(auth_index)`, `get_antigravity_quota(file_json, auth_index)`, `format_refresh_in(value)`, and `fetch_all_quotas()`.
- Produces output account shape: `{name, type, groups, minRemaining}`.

- [ ] **Step 1: Add realistic provider fixtures**

Create `auth-files-mixed.json` containing an enabled Codex account, enabled Antigravity account, disabled account, runtime-only account, unsupported Claude account, and malformed account without `auth_index`.

Create a Codex wrapper response:

```json
{
  "status_code": 200,
  "body": "{\"rate_limit\":{\"primary_window\":{\"used_percent\":25,\"reset_at\":1893456000}}}"
}
```

Create an Antigravity wrapper response with two groups and multiple buckets using `remainingFraction` and `resetTime`. Create `antigravity-auth-file.json` for the fallback project-ID download path.

- [ ] **Step 2: Write failing transformation tests**

Add these provider tests:

```bash
test_transforms_codex_primary_window() {
    queue_http 200 "$FIXTURES/api/auth-files-codex.json"
    queue_http 200 "$FIXTURES/api/codex-response.json"
    output="$(run_fetcher)"
    jq -e '
      .quotas[0].type == "codex" and
      .quotas[0].groups[0].name == "Codex Limit" and
      .quotas[0].groups[0].items[0].val == "75.00%" and
      .minRemaining == 0.75 and
      .avgRemaining == 0.75
    ' <<<"$output" >/dev/null
}

test_transforms_antigravity_groups() {
    queue_http 200 "$FIXTURES/api/auth-files-antigravity.json"
    queue_http 200 "$FIXTURES/api/antigravity-response.json"
    output="$(run_fetcher)"
    jq -e '
      .quotas[0].type == "antigravity" and
      (.quotas[0].groups | length) == 2 and
      .quotas[0].minRemaining == 0.2
    ' <<<"$output" >/dev/null
}
```

Add named test functions `test_reads_antigravity_project_id_from_metadata`, `test_downloads_antigravity_auth_file_for_project_id`, `test_rejects_upstream_error_status`, `test_accepts_string_wrapper_body`, `test_accepts_object_wrapper_body`, `test_returns_partial_result_after_account_failure`, `test_computes_global_average_from_displayed_limits`, `test_skips_disabled_and_runtime_only_accounts`, `test_logs_unsupported_provider`, `test_formats_epoch_seconds_reset`, `test_formats_epoch_milliseconds_reset`, and `test_formats_iso_reset`. Each test queues the exact auth-files and proxy responses it needs and asserts the resulting JSON field or stderr diagnostic.

- [ ] **Step 3: Run transformation tests and verify they fail**

Run: `bash tests/test_get_quotas.bash`

Expected: new provider tests FAIL while Task 2 tests remain passing.

- [ ] **Step 4: Implement Management API proxy calls**

Build request JSON only through `jq -cn --arg/--argjson`; never interpolate JSON manually. `api_call` posts to `/v0/management/api-call`, verifies the wrapper `status_code`, parses `.body` with `fromjson? // .`, and returns the decoded upstream body.

Keep the existing upstream URLs and headers from `get-quotas.ts` for Codex and Antigravity. For Antigravity, first inspect all existing project-ID field variants; if absent, GET `/v0/management/auth-files/download?name=<urlencoded name>` and inspect the documented fallback fields.

- [ ] **Step 5: Implement account aggregation in jq-backed Bash**

Use temporary newline-delimited JSON files for accounts and remaining fractions instead of building shell-escaped JSON arrays. For each successful account, append one compact JSON object. At the end, use `jq -s` to create `quotas` and compute minimum/average fractions.

Codex output must use:

```json
{
  "name": "Codex Limit",
  "items": [{"label":"Primary Window","val":"75.00%","resetTime":"..."}]
}
```

Antigravity must preserve group display names, bucket display names or IDs, two-decimal percentages, and reset text. If an account has no displayable groups, include the account with an empty `groups` array and `minRemaining: null`, matching the current data contract.

- [ ] **Step 6: Run the complete quota-client tests**

Run: `bash tests/test_get_quotas.bash`

Expected: all quota-client tests PASS, including partial failures.

- [ ] **Step 7: Delete the obsolete TypeScript implementation**

Delete `get-quotas.ts` only after the Bash parity tests pass. Run `grep -R "get-quotas.ts\|bun" README.md Quotas.qml get-quotas.sh tests` and confirm remaining matches are only intentional failing-test fixtures or documentation being replaced later.

- [ ] **Step 8: Commit provider parity**

```bash
git add get-quotas.sh tests/test_get_quotas.bash tests/fixtures/api
git rm get-quotas.ts
git commit -m "Replace TypeScript quota fetcher with Bash"
```

---

### Task 4: Portable QML Process Integration

**Files:**
- Modify: `Quotas.qml:1-95`
- Create: `tests/test_qml.bash`

**Interfaces:**
- Consumes: installed neighboring executable `get-quotas.sh` from Tasks 2-3.
- Produces: `readonly property string quotaScriptPath` and direct `Process.command: [root.quotaScriptPath]`.

- [ ] **Step 1: Write failing static QML portability tests**

Create `tests/test_qml.bash` using the shared harness. Assert:

```bash
test_uses_relative_shell_fetcher() {
    content="$(<"$REPO_ROOT/Quotas.qml")"
    assert_contains "$content" 'Qt.resolvedUrl("get-quotas.sh")'
    assert_contains "$content" 'command: [root.quotaScriptPath]'
}

test_has_no_user_or_bun_paths() {
    content="$(<"$REPO_ROOT/Quotas.qml")"
    [[ "$content" != *'/home/ngukovskiy'* ]] || fail 'hard-coded home remains'
    [[ "$content" != *'.bun/bin/bun'* ]] || fail 'Bun path remains'
    [[ "$content" != *'secret-tool lookup'* ]] || fail 'QML must not load credentials'
}
```

Also assert that stdout is parsed only after a zero exit, `isFetching` is cleared for all exits, and an error path does not assign `quotasData = null`.

- [ ] **Step 2: Run QML tests and verify they fail**

Run: `bash tests/test_qml.bash`

Expected: FAIL on the current Bun command and hard-coded home path.

- [ ] **Step 3: Replace the QML command and tighten process state handling**

Add `import qs.modules.common.functions`. Resolve the script path with:

```qml
readonly property string quotaScriptPath: FileUtils.trimFileProtocol(`${Qt.resolvedUrl("get-quotas.sh")}`)
property string pendingStdout: ""
property string pendingStderr: ""
```

Set `command: [root.quotaScriptPath]`. Collect stdout/stderr into pending properties. Parse and assign data in `onExited` only when `exitCode === 0`; on failures, log stderr and retain prior data. Always clear pending buffers and `isFetching` after handling exit.

Keep right-click refresh. Continue using `Quickshell.execDetached(["notify-send", ...])`; failure to launch notification must not affect the already-started quota process.

- [ ] **Step 4: Run static tests and a real QML smoke check**

Run: `bash tests/test_qml.bash`

Expected: all static QML tests PASS.

Check for a graphical session with `[[ -n "${WAYLAND_DISPLAY:-}" ]]`. If present, run: `timeout 10s qs -p "$HOME/.config/quickshell/ii" --no-duplicate --verbose`

Expected: no new QML syntax/type error referencing `Quotas.qml`. If the current user configuration already has a running instance or unrelated errors, capture that limitation and use `qs log` plus the static checks as evidence instead of changing the live configuration.

- [ ] **Step 5: Commit portable QML execution**

```bash
git add Quotas.qml tests/test_qml.bash tests/run.sh
git commit -m "Make quota widget runtime portable"
```

---

### Task 5: Installer API Validation And Release Acquisition

**Files:**
- Modify: `install.sh`
- Modify: `tests/test_install.bash`
- Reuse: `tests/helpers/mock_curl.sh`

**Interfaces:**
- Consumes: parsed `API_URL`, `MANAGEMENT_KEY`, and required tools from Task 1.
- Produces: `read_management_key()`, `validate_api()`, `fetch_latest_release()`, `validate_archive()`, and globals `WORK_DIR`, `ARCHIVE_PATH`, `PAYLOAD_DIR`.
- Produces test seams: `QUOTAS_GITHUB_API_BASE`, `QUOTAS_CURL_BIN`, and `QUOTAS_TAR_BIN`.

- [ ] **Step 1: Write failing key-input and API-validation tests**

Add process-level tests for `--management-key-stdin` and function-level tests for TTY fallback by setting `QUOTAS_TTY_PATH` to a temporary file in tests. Verify that the captured installer output never contains the key.

Add API tests covering transport failure, 401/403, 500, malformed JSON, missing/non-array `files`, and success. Confirm the first persistent file does not exist after any validation failure.

- [ ] **Step 2: Write failing release acquisition tests**

Generate a valid test archive dynamically:

```bash
mkdir -p "$TEST_TMP_ROOT/payload"
printf 'qml\n' >"$TEST_TMP_ROOT/payload/Quotas.qml"
printf 'qml\n' >"$TEST_TMP_ROOT/payload/QuotasPopup.qml"
printf '#!/usr/bin/env bash\nexit 0\n' >"$TEST_TMP_ROOT/payload/get-quotas.sh"
tar -C "$TEST_TMP_ROOT/payload" -czf "$TEST_TMP_ROOT/release.tar.gz" \
    Quotas.qml QuotasPopup.qml get-quotas.sh
```

Mock latest-release JSON with one asset named `quickshell-quotas-widget-v1.0.0.tar.gz`. Test missing asset, duplicate matching assets, unsafe `../` archive entry, absolute archive entry, missing payload file, extra top-level file, and valid extraction.

- [ ] **Step 3: Run installer tests and verify the new cases fail**

Run: `bash tests/test_install.bash`

Expected: key/API/release tests FAIL while Task 1 tests remain passing.

- [ ] **Step 4: Implement secure key input and API validation**

`read_management_key` behavior:

- Keep `--management-key` value already parsed.
- For stdin mode, use `IFS= read -r MANAGEMENT_KEY` and reject empty input.
- For TTY mode, open `${QUOTAS_TTY_PATH:-/dev/tty}`, print the bilingual prompt there, use `IFS= read -r -s MANAGEMENT_KEY`, then print a newline to the TTY.
- Do not enable `set -x` and do not include the key in any failure message.

`validate_api` must use a temporary body file and explicit status handling, then require `jq -e '.files | type == "array"'`. Like the runtime client, it passes the bearer token through a mode-`600` temporary header file rather than a command-line header value.

- [ ] **Step 5: Implement latest-release download and archive validation**

Use `${QUOTAS_GITHUB_API_BASE:-https://api.github.com}` and request `/repos/gukovskiy98/quickshell-quotas-widget/releases/latest`. Select exactly one asset whose name matches `^quickshell-quotas-widget-v[^/]+\.tar\.gz$`.

Before extraction, read `tar -tzf` output and reject entries that:

- Start with `/`.
- Contain an empty component, `.` component, or `..` component.
- Contain `/` at all, because the payload is required at archive top level.
- Are not exactly `Quotas.qml`, `QuotasPopup.qml`, or `get-quotas.sh`.

Require each expected name exactly once. Extract into `$PAYLOAD_DIR` only after validation.

- [ ] **Step 6: Run installer tests and verify API/release behavior passes**

Run: `bash tests/test_install.bash`

Expected: all tests through Task 5 PASS.

- [ ] **Step 7: Commit remote validation and download**

```bash
git add install.sh tests/test_install.bash tests/helpers/mock_curl.sh
git commit -m "Add installer API and release validation"
```

---

### Task 6: Credential Storage Backends

**Files:**
- Modify: `install.sh`
- Modify: `tests/test_install.bash`
- Reuse: `tests/helpers/mock_secret_tool.sh`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: validated `API_URL`, `MANAGEMENT_KEY`, and resolved `INSTALL_DIR`.
- Produces: `store_credentials()`, `store_keyring_credentials()`, `write_fallback_config()`, and `FALLBACK_CONFIG="$INSTALL_DIR/quotas-widget.conf"`.
- Produces backend result: `CREDENTIAL_BACKEND` equals `keyring` or `file`.

- [ ] **Step 1: Write failing keyring and fallback tests**

Add these credential-storage tests:

```bash
test_stores_and_verifies_keyring_values() {
    prepare_installer_fixture
    QUOTAS_SECRET_TOOL_BIN="$REPO_ROOT/tests/helpers/mock_secret_tool.sh"
    store_credentials
    assert_eq 'keyring' "$CREDENTIAL_BACKEND"
    [[ ! -e "$INSTALL_DIR/quotas-widget.conf" ]] || fail 'fallback must be absent'
}

test_writes_json_fallback_with_mode_600() {
    prepare_installer_fixture
    QUOTAS_SECRET_TOOL_BIN="$TEST_TMP_ROOT/missing-secret-tool"
    store_credentials
    assert_eq 'file' "$CREDENTIAL_BACKEND"
    jq -e --arg url "$API_URL" --arg key "$MANAGEMENT_KEY" \
      '.apiUrl == $url and .managementKey == $key' \
      "$INSTALL_DIR/quotas-widget.conf" >/dev/null
    assert_file_mode 600 "$INSTALL_DIR/quotas-widget.conf"
}
```

Add named test functions `test_falls_back_after_keyring_store_failure`, `test_falls_back_after_keyring_lookup_failure`, `test_falls_back_after_keyring_lookup_mismatch`, `test_falls_back_after_partial_keyring_write`, `test_removes_existing_fallback_after_keyring_success`, `test_preserves_special_characters_in_fallback_json`, and `test_never_logs_management_key`. The special-character test must include quotes, backslashes, spaces, and a newline in the key and compare values through `jq --arg`; the leakage test captures both output streams and asserts the exact key is absent.

- [ ] **Step 2: Run installer tests and verify credential cases fail**

Run: `bash tests/test_install.bash`

Expected: new credential tests FAIL.

- [ ] **Step 3: Implement complete-pair keyring verification and fallback**

Write each key through stdin:

```bash
printf '%s' "$API_URL" | "$secret_tool" store \
    --label='Quotas API URL' application quotas key quotasApiUrl
```

Perform both lookups and require exact string equality. Only select `keyring` if the complete pair verifies. Otherwise write one complete JSON file atomically with:

```bash
jq -n --arg apiUrl "$API_URL" --arg managementKey "$MANAGEMENT_KEY" \
    '{apiUrl:$apiUrl, managementKey:$managementKey}' >"$tmp_config"
chmod 600 "$tmp_config"
mv -f -- "$tmp_config" "$FALLBACK_CONFIG"
```

Do not attempt to delete partially written keyring values. Emit an English/Russian plaintext warning without including values.

- [ ] **Step 4: Add generated credential files to `.gitignore`**

Add only patterns relevant to this repository:

```gitignore
quotas-widget.conf
```

Do not ignore `.codebase-memory/` or `.serena/` as part of this feature unless the user separately requests it.

- [ ] **Step 5: Run installer and quota credential tests**

Run: `bash tests/test_install.bash && bash tests/test_get_quotas.bash`

Expected: all credential backend tests PASS and the fetcher reads the generated JSON schema.

- [ ] **Step 6: Commit credential storage**

```bash
git add install.sh tests/test_install.bash tests/helpers/mock_secret_tool.sh .gitignore
git commit -m "Add secure credential storage fallback"
```

---

### Task 7: Transactional Installation, Bar Integration, Smoke Test, And Restart

**Files:**
- Modify: `install.sh`
- Modify: `tests/test_install.bash`

**Interfaces:**
- Consumes: validated payload in `PAYLOAD_DIR`, selected credential backend, and end4 layout.
- Produces: `begin_transaction()`, `backup_changed_file(path)`, `track_created_file(path)`, `rollback_transaction()`, `commit_transaction()`, `install_payload()`, `integrate_bar_content()`, `run_smoke_test()`, `restart_quickshell()`, and complete `main()` orchestration.
- Produces managed markers: `// quickshell-quotas-widget:start` and `// quickshell-quotas-widget:end`.
- Produces test seams: `QUOTAS_TIMESTAMP`, `QUOTAS_SKIP_RESTART`, and `QUOTAS_QS_BIN`.

- [ ] **Step 1: Write failing managed-block insertion tests**

Add tests that copy the fixture to a temporary config and assert:

- A new block is inserted immediately after the balanced `Resources { ... }` component inside `leftCenterGroup`.
- Nested braces inside `Resources` do not truncate the match.
- A `Resources` component elsewhere in the file is ignored.
- A second run does not duplicate markers.
- One start marker without an end marker fails.
- Duplicate complete marker blocks fail.
- Missing or multiple safe insertion points fail.
- Existing unrelated formatting and content remain byte-for-byte unchanged outside the insertion.

The expected inserted block is exactly:

```qml
// quickshell-quotas-widget:start
Quotas {
    visible: true
    Layout.fillWidth: false
}
// quickshell-quotas-widget:end
```

- [ ] **Step 2: Write failing transaction and rollback tests**

Cover:

- New payload files receive modes `644`, `644`, and `700`.
- Changed existing files receive `<name>.backup.<timestamp>` backups.
- Identical files do not receive backups.
- Failure during bar integration restores all replaced files and removes newly created files.
- Smoke-test failure restores payload, `BarContent.qml`, and pre-existing fallback config.
- Backup files remain after rollback.
- Keyring mock data remains after rollback.

Use `QUOTAS_TIMESTAMP=20260731-143000` for deterministic backup names.

- [ ] **Step 3: Write failing smoke-test and restart tests**

Smoke tests must reject nonzero fetcher exit, invalid JSON, missing `quotas`, non-array `quotas`, nonnumeric averages/minimums, and nonstring timestamp.

Quickshell tests must verify:

- `qs -p "$CONFIG_ROOT" list --json` is used to detect the relevant instance.
- No process means installation succeeds with a warning.
- A running process triggers `qs -p "$CONFIG_ROOT" kill`, then `qs -p "$CONFIG_ROOT" --daemonize`.
- Restart failure warns but does not invoke rollback after a successful smoke test.

- [ ] **Step 4: Run installer tests and verify transaction cases fail**

Run: `bash tests/test_install.bash`

Expected: new integration and rollback tests FAIL.

- [ ] **Step 5: Implement balanced QML insertion**

Use an `awk` state machine rather than a broad regular-expression replacement. The state machine must:

- Locate exactly one `BarGroup {` whose balanced body contains `id: leftCenterGroup`.
- Within that balanced body, locate exactly one `Resources {` component.
- Count braces after removing `//` comments and quoted string contents from each line.
- Record the closing line of that `Resources` component.
- Insert the managed block using the same indentation as the `Resources` line.

Write the transformed content to a temporary file and validate marker counts before replacing `BarContent.qml`.

- [ ] **Step 6: Implement the transaction journal**

Use arrays for tracked paths:

```bash
declare -a TX_REPLACED_PATHS=()
declare -a TX_BACKUP_PATHS=()
declare -a TX_CREATED_PATHS=()
TX_ACTIVE=0
```

Before replacing an existing changed file, copy it with `cp -p` to the deterministic timestamped backup and append both paths to aligned arrays. Before creating a new destination, append it to `TX_CREATED_PATHS`. Rollback iterates in reverse order, restores replacements, and removes new files. Keep timestamped backup copies after restoration.

Install each payload through a destination-local temporary file followed by `chmod` and `mv`. Compare with `cmp -s` first to avoid unnecessary writes/backups.

- [ ] **Step 7: Implement smoke test, activation, and complete orchestration**

Run the installed fetcher while capturing stdout and stderr separately. Validate with:

```bash
jq -e '
  (.quotas | type == "array") and
  (.minRemaining | type == "number") and
  (.avgRemaining | type == "number") and
  (.lastUpdated | type == "string")
' "$smoke_stdout"
```

`main` order must be:

1. Parse arguments and read key.
2. Resolve paths and run preflight.
3. Validate API.
4. Download and validate release.
5. Begin transaction.
6. Store credentials.
7. Install payload.
8. Integrate `BarContent.qml`.
9. Run smoke test.
10. Commit transaction.
11. Attempt Quickshell restart.
12. Print completion summary without secrets.

Set an `ERR`, `INT`, and `TERM` trap that rolls back only while `TX_ACTIVE=1`; always clean the temporary work directory.

- [ ] **Step 8: Run the complete shell test suite**

Run: `bash tests/run.sh`

Expected: all installer, quota-client, and QML tests PASS.

- [ ] **Step 9: Run syntax checks**

Run: `bash -n install.sh get-quotas.sh tests/*.bash tests/helpers/*.sh`

Expected: exit 0 and no output.

- [ ] **Step 10: Commit complete installer behavior**

```bash
git add install.sh tests/test_install.bash
git commit -m "Add transactional widget installation"
```

---

### Task 8: Bilingual Public Documentation

**Files:**
- Modify: `README.md:1-64`
- Modify: `tests/test_qml.bash`

**Interfaces:**
- Consumes: final CLI, dependencies, paths, credential behavior, and release process.
- Produces: complete English and Russian user guides with matching commands and warnings.

- [ ] **Step 1: Add failing documentation consistency checks**

Create `tests/test_docs.bash` with the shared harness. Assert README contains:

- The one-line raw GitHub installer URL.
- `--api-url`.
- `--management-key` exposure warning.
- `--management-key-stdin` local-use explanation.
- `--install-dir` semantics.
- `curl`, `jq`, and `tar` dependencies.
- Secret Service preferred storage and mode-`600` plaintext fallback.
- Update-by-rerun instructions.
- Manual restart command using `qs -p` or `quickshell -p`.
- Explicit support wording for Antigravity and Codex.
- English and Russian top-level sections.
- No Bun installation requirement and no `/home/ngukovskiy` path.

- [ ] **Step 2: Run documentation tests and verify they fail**

Run: `bash tests/run.sh`

Expected: documentation checks FAIL against the current README.

- [ ] **Step 3: Rewrite README in English and Russian**

Use this section order in each language:

1. What the widget does and exact compatibility scope.
2. Supported quota displays.
3. Dependencies.
4. Recommended one-line installation with hidden TTY key prompt.
5. Automation flags and key exposure warning.
6. Custom installation directory.
7. Credential storage and plaintext fallback.
8. Updating by rerunning the installer.
9. Applying/restarting Quickshell.
10. Manual installation/recovery.
11. Backup and rollback behavior.
12. Development tests and release process.

Keep commands identical between translations. State that `notify-send` and `secret-tool` are optional; Bash 4+, `curl`, `jq`, and `tar` are required for installation, while `tar` is not needed by the installed widget at runtime.

- [ ] **Step 4: Run all documentation and shell tests**

Run: `bash tests/run.sh`

Expected: all tests PASS.

- [ ] **Step 5: Commit public documentation**

```bash
git add README.md tests/test_docs.bash tests/run.sh
git commit -m "Document public widget installation"
```

---

### Task 9: CI, Release Packaging, And Final Verification

**Files:**
- Create: `.github/workflows/test.yml`
- Create: `.github/workflows/release.yml`
- Create: `scripts/package-release.sh`
- Modify: `tests/test_install.bash`

**Interfaces:**
- Consumes: final payload files and `tests/run.sh`.
- Produces: CI validation on pushes/PRs and a GitHub Release asset named `quickshell-quotas-widget-<tag>.tar.gz` for tags `v*`.

- [ ] **Step 1: Add a failing archive-contract test**

Add a test that invokes a repository packaging script which does not exist yet:

```bash
bash "$REPO_ROOT/scripts/package-release.sh" v1.0.0 "$TEST_TMP_ROOT/dist"
```

Pass `$TEST_TMP_ROOT/dist/quickshell-quotas-widget-v1.0.0.tar.gz` to the installer's `validate_archive` and assert success. Also assert `tar -tzf` returns exactly the three top-level names. This test ties workflow packaging to installer expectations.

- [ ] **Step 2: Run the archive-contract test and verify it fails if workflow helpers are absent**

Run: `bash tests/test_install.bash`

Expected: FAIL because `scripts/package-release.sh` does not exist.

- [ ] **Step 3: Implement deterministic release packaging**

Create `scripts/package-release.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

tag="${1:?usage: package-release.sh TAG OUTPUT_DIR}"
output_dir="${2:?usage: package-release.sh TAG OUTPUT_DIR}"
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
archive="$output_dir/quickshell-quotas-widget-$tag.tar.gz"

mkdir -p -- "$output_dir"
tar -C "$repo_root" -czf "$archive" Quotas.qml QuotasPopup.qml get-quotas.sh
printf '%s\n' "$archive"
```

Run: `bash tests/test_install.bash`

Expected: the release-contract test PASS.

- [ ] **Step 4: Add the test workflow**

Create `.github/workflows/test.yml` triggered on `push` and `pull_request`. Use `ubuntu-latest`, `actions/checkout`, install `shellcheck jq`, then run:

```yaml
- name: Syntax check
  run: bash -n install.sh get-quotas.sh tests/*.bash tests/helpers/*.sh
- name: ShellCheck
  run: shellcheck install.sh get-quotas.sh tests/*.bash tests/helpers/*.sh
- name: Tests
  run: bash tests/run.sh
```

Do not globally disable ShellCheck rules. Resolve findings in the shell source. If ShellCheck cannot infer a sourced test helper, use one narrow inline directive adjacent to that `source` statement and include the reason.

- [ ] **Step 5: Add the tag-driven release workflow**

Create `.github/workflows/release.yml` triggered on `push.tags: ['v*']`, with `permissions.contents: write`. It must:

1. Check out the tagged commit.
2. Install test dependencies.
3. Run syntax, ShellCheck, and tests.
4. Run `bash scripts/package-release.sh "$GITHUB_REF_NAME" dist`.
5. Publish the archive using `gh release create "$GITHUB_REF_NAME" ... --generate-notes` with `GH_TOKEN: ${{ github.token }}`.

Use a noninteractive command and fail if the release already exists instead of overwriting assets silently.

- [ ] **Step 6: Run local ShellCheck or install it only in an approved disposable environment**

If `shellcheck` is available locally, run:

```bash
shellcheck install.sh get-quotas.sh tests/*.bash tests/helpers/*.sh
```

Expected: exit 0.

If it is unavailable, do not install packages with `sudo`; report that CI will provide this verification and run all remaining local checks.

- [ ] **Step 7: Run complete final verification**

Run:

```bash
bash -n install.sh get-quotas.sh tests/*.bash tests/helpers/*.sh
bash tests/run.sh
tmp_dist="$(mktemp -d)"
bash scripts/package-release.sh v0.0.0-test "$tmp_dist"
tar -tzf "$tmp_dist/quickshell-quotas-widget-v0.0.0-test.tar.gz"
rm -rf -- "$tmp_dist"
git diff --check
git status --short
```

Expected:

- Syntax check exits 0.
- All tests report zero failures.
- Archive lists exactly `Quotas.qml`, `QuotasPopup.qml`, and `get-quotas.sh` at top level.
- `git diff --check` reports no whitespace errors.
- Status contains only intended implementation files plus unrelated pre-existing `.codebase-memory/` and `.serena/` entries.

- [ ] **Step 8: Perform a controlled live smoke test**

Do not run the public installer against the user's real configuration without explicit confirmation because it changes `BarContent.qml` and credentials. Instead, run it against a temporary copy using mocked API/GitHub endpoints and `--install-dir`:

```bash
bash install.sh \
  --api-url http://mock-api \
  --management-key test-key \
  --install-dir "$temporary_end4_root/modules/ii/bar"
```

Expected: payload installed, one managed block inserted, fallback/keyring mock selected as configured, smoke test passes, and repeat execution makes no duplicate block.

- [ ] **Step 9: Commit CI and release automation**

```bash
git add .github/workflows/test.yml .github/workflows/release.yml scripts/package-release.sh tests/test_install.bash
git commit -m "Add CI and release packaging"
```

## Completion Criteria

- `install.sh` works both as a downloaded file and through `curl | bash`.
- The key can be entered through hidden `/dev/tty`, stdin for local use, or the explicit automation flag.
- Preflight rejects missing Hyprland, Quickshell, end4-dots, Bash 4+, `curl`, `jq`, or `tar` before persistent writes.
- API credentials are validated before release download or installation.
- Release archives are validated against path traversal and exact payload membership.
- Secret Service is verified as a complete pair; fallback JSON is mode `600` and selected explicitly by file presence.
- `get-quotas.sh` produces compatible Antigravity/Codex JSON without Bun or Node.js.
- `Quotas.qml` contains no hard-coded home path, Bun command, or credential lookup.
- `BarContent.qml` integration is safe, idempotent, backed up, and rolled back on failure.
- Smoke-test failure rolls back file changes; restart failure only warns.
- README is complete in English and Russian.
- CI runs syntax checks, ShellCheck, and tests.
- Tag workflow publishes the exact archive expected by the installer.
