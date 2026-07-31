#!/usr/bin/env bash
set -uo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/test_helper.bash"

README_FILE="$repo_root/README.md"

read_readme() {
    REPLY="$(<"$README_FILE")"
}

test_documents_public_installer_and_cli() {
    local content
    read_readme
    content="$REPLY"

    assert_contains "$content" 'curl -fsSL https://raw.githubusercontent.com/gukovskiy98/quickshell-quotas-widget/master/install.sh | bash -s -- --api-url' || return 1
    assert_contains "$content" '--api-url' || return 1
    assert_contains "$content" '--management-key' || return 1
    assert_contains "$content" 'shell history and process listings' || return 1
    assert_contains "$content" '--management-key-stdin' || return 1
    assert_contains "$content" 'locally downloaded installer' || return 1
    assert_contains "$content" '--install-dir' || return 1
    assert_contains "$content" 'bar modules directory'
}

test_documents_dependencies_and_credentials() {
    local content
    read_readme
    content="$REPLY"

    assert_contains "$content" 'Bash 4+' || return 1
    assert_contains "$content" '`curl`' || return 1
    assert_contains "$content" '`jq`' || return 1
    assert_contains "$content" '`tar`' || return 1
    assert_contains "$content" '`notify-send` and `secret-tool` are optional' || return 1
    assert_contains "$content" '`tar` is not needed by the installed widget at runtime' || return 1
    assert_contains "$content" 'Secret Service is preferred' || return 1
    assert_contains "$content" 'plaintext fallback' || return 1
    assert_contains "$content" 'mode `600`'
}

test_documents_updates_restart_and_recovery() {
    local content
    read_readme
    content="$REPLY"

    assert_contains "$content" 'rerun the same installer command' || return 1
    assert_contains "$content" 'qs -p "${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/ii" kill' || return 1
    assert_contains "$content" 'qs -p "${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/ii" --daemonize' || return 1
    assert_contains "$content" 'timestamped backups' || return 1
    assert_contains "$content" 'automatically rolls back'
}

test_documents_exact_provider_scope() {
    local content
    read_readme
    content="$REPLY"

    assert_contains "$content" 'Only Antigravity and Codex quota providers are supported.'
}

test_has_english_and_russian_guides() {
    local content russian_heading
    read_readme
    content="$REPLY"
    russian_heading="$(printf '%b' '## \xD0\xA0\xD1\x83\xD1\x81\xD1\x81\xD0\xBA\xD0\xB8\xD0\xB9')"

    assert_contains "$content" '## English' || return 1
    assert_contains "$content" "$russian_heading"
}

extract_bash_blocks() {
    awk '
        /^```bash$/ { in_block = 1; print; next }
        /^```$/ && in_block { in_block = 0; print; next }
        in_block { print }
    '
}

test_translations_use_identical_commands() {
    local content english russian russian_heading english_commands russian_commands
    read_readme
    content="$REPLY"
    russian_heading="$(printf '%b' '## \xD0\xA0\xD1\x83\xD1\x81\xD1\x81\xD0\xBA\xD0\xB8\xD0\xB9')"

    assert_contains "$content" '## English' || return 1
    assert_contains "$content" "$russian_heading" || return 1
    english="${content#*'## English'}"
    english="${english%%"$russian_heading"*}"
    russian="${content#*"$russian_heading"}"
    english_commands="$(extract_bash_blocks <<<"$english")"
    russian_commands="$(extract_bash_blocks <<<"$russian")"

    [[ -n "$english_commands" ]] || fail 'English guide has no shell commands' || return 1
    assert_eq "$english_commands" "$russian_commands"
}

test_removes_legacy_machine_requirements() {
    local content
    read_readme
    content="$REPLY"

    assert_contains "$content" 'Bun is not required' || return 1
    [[ "$content" != *'.bun/bin/bun'* ]] || fail 'README still requires the legacy Bun path' || return 1
    [[ "$content" != *'/home/ngukovskiy'* ]] || fail 'README contains a developer-specific home path'
}

test_documentation_test_source_is_ascii() {
    if LC_ALL=C grep -n '[^ -~[:space:]]' "$repo_root/tests/test_docs.bash" >/dev/null 2>&1; then
        fail 'documentation test source must remain ASCII'
    fi
}

run_test 'documents public installer and CLI' test_documents_public_installer_and_cli
run_test 'documents dependencies and credentials' test_documents_dependencies_and_credentials
run_test 'documents updates restart and recovery' test_documents_updates_restart_and_recovery
run_test 'documents exact provider scope' test_documents_exact_provider_scope
run_test 'has English and Russian guides' test_has_english_and_russian_guides
run_test 'translations use identical commands' test_translations_use_identical_commands
run_test 'removes legacy machine requirements' test_removes_legacy_machine_requirements
run_test 'documentation test source is ASCII' test_documentation_test_source_is_ascii

finish_tests
