#!/usr/bin/env bash
set -uo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/test_helper.bash"

README_FILE="$repo_root/README.md"

read_readme() {
    REPLY="$(<"$README_FILE")"
}

decode_utf8_hex() {
    local hex="$1" escaped=""

    while [[ -n "$hex" ]]; do
        escaped+="\\x${hex:0:2}"
        hex="${hex:2}"
    done
    printf '%b' "$escaped"
}

read_guides() {
    local content russian_heading
    read_readme
    content="$REPLY"
    russian_heading="$(decode_utf8_hex '232320d0a0d183d181d181d0bad0b8d0b9')"
    ENGLISH_GUIDE="${content#*'## English'}"
    ENGLISH_GUIDE="${ENGLISH_GUIDE%%"$russian_heading"*}"
    RUSSIAN_GUIDE="${content#*"$russian_heading"}"
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
    assert_contains "$content" 'CONFIG_ROOT="$(cd -- "$INSTALL_DIR/../../.." && pwd -P)"' || return 1
    assert_contains "$content" 'qs -p "$CONFIG_ROOT" kill' || return 1
    assert_contains "$content" 'qs -p "$CONFIG_ROOT" --daemonize' || return 1
    assert_contains "$content" 'timestamped backups' || return 1
    assert_contains "$content" 'automatically rolls back'
}

test_documents_safe_plaintext_recovery() {
    local content
    read_readme
    content="$REPLY"

    assert_contains "$content" "IFS= read -r -s -p 'Management key: ' MANAGEMENT_KEY" || return 1
    assert_contains "$content" 'umask 077' || return 1
    assert_contains "$content" 'printf '\''%s\0%s'\'' "${API_URL%/}" "$MANAGEMENT_KEY"' || return 1
    assert_contains "$content" "jq -Rs 'split(\"\\u0000\") | {apiUrl:.[0], managementKey:.[1]}'" || return 1
    assert_contains "$content" 'chmod 600 "$tmp_config"' || return 1
    assert_contains "$content" 'mv -f -- "$tmp_config" "$INSTALL_DIR/quotas-widget.conf"'
}

test_documents_validation_sequence() {
    local content pre_download post_download
    read_readme
    content="$REPLY"
    pre_download='Before downloading the release, the installer validates the management key and local end4-dots layout.'
    post_download='After downloading, it validates the latest GitHub Release archive before making persistent changes.'

    assert_contains "$content" "$pre_download" || return 1
    assert_contains "$content" "$post_download" || return 1
    [[ "${content%%"$pre_download"*}" != "$content" ]] || return 1
    content="${content#*"$pre_download"}"
    [[ "${content%%"$post_download"*}" != "$content" ]] || fail 'archive validation must follow pre-download checks'
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

russian_section_headings() {
    local -a headings=(
        '23232320d09dd0b0d0b7d0bdd0b0d187d0b5d0bdd0b8d0b520d0b820d181d0bed0b2d0bcd0b5d181d182d0b8d0bcd0bed181d182d18c'
        '23232320d09ed182d0bed0b1d180d0b0d0b6d0b0d0b5d0bcd18bd0b520d0bad0b2d0bed182d18b'
        '23232320d097d0b0d0b2d0b8d181d0b8d0bcd0bed181d182d0b8'
        '23232320d0a0d0b5d0bad0bed0bcd0b5d0bdd0b4d183d0b5d0bcd0b0d18f20d183d181d182d0b0d0bdd0bed0b2d0bad0b020d0bed0b4d0bdd0bed0b920d0bad0bed0bcd0b0d0bdd0b4d0bed0b9'
        '23232320d0a4d0bbd0b0d0b3d0b820d0b0d0b2d182d0bed0bcd0b0d182d0b8d0b7d0b0d186d0b8d0b820d0b820d180d0b0d181d0bad180d18bd182d0b8d0b520d0bad0bbd18ed187d0b0'
        '23232320d094d180d183d0b3d0bed0b920d0bad0b0d182d0b0d0bbd0bed0b320d183d181d182d0b0d0bdd0bed0b2d0bad0b8'
        '23232320d0a5d180d0b0d0bdd0b5d0bdd0b8d0b520d183d187d0b5d182d0bdd18bd18520d0b4d0b0d0bdd0bdd18bd185'
        '23232320d09ed0b1d0bdd0bed0b2d0bbd0b5d0bdd0b8d0b5'
        '23232320d09fd180d0b8d0bcd0b5d0bdd0b5d0bdd0b8d0b520d0b8d0b7d0bcd0b5d0bdd0b5d0bdd0b8d0b920d0b8d0bbd0b820d0bfd0b5d180d0b5d0b7d0b0d0bfd183d181d0ba20517569636b7368656c6c'
        '23232320d0a0d183d187d0bdd0b0d18f20d183d181d182d0b0d0bdd0bed0b2d0bad0b020d0b8d0bbd0b820d0b2d0bed181d181d182d0b0d0bdd0bed0b2d0bbd0b5d0bdd0b8d0b5'
        '23232320d0a0d0b5d0b7d0b5d180d0b2d0bdd18bd0b520d0bad0bed0bfd0b8d0b820d0b820d0bed182d0bad0b0d182'
        '23232320d0a2d0b5d181d182d18b20d180d0b0d0b7d180d0b0d0b1d0bed182d0bad0b820d0b820d180d0b5d0bbd0b8d0b7d18b'
    )
    local hex

    for hex in "${headings[@]}"; do
        decode_utf8_hex "$hex"
        printf '\n'
    done
}

russian_contract_anchors() {
    russian_section_headings
    decode_utf8_hex 'd0add182d0be20d0bdd0b520d183d0bdd0b8d0b2d0b5d180d181d0b0d0bbd18cd0bdd18bd0b920d183d181d182d0b0d0bdd0bed0b2d189d0b8d0ba'; printf '\n'
    decode_utf8_hex 'd09fd0bed0b4d0b4d0b5d180d0b6d0b8d0b2d0b0d18ed182d181d18f20d182d0bed0bbd18cd0bad0be20d0bfd180d0bed0b2d0b0d0b9d0b4d0b5d180d18b20d0bad0b2d0bed18220416e74696772617669747920d0b820436f6465782e'; printf '\n'
    printf '%s\n' 'Bash 4+' '`curl`' '`jq`' '`tar`'
    decode_utf8_hex 'd0bdd0b5d0bed0b1d18fd0b7d0b0d182d0b5d0bbd18cd0bdd18b'; printf '\n'
    printf '%s\n' 'notify-send' 'secret-tool'
    printf '%s\n' 'curl -fsSL https://raw.githubusercontent.com/gukovskiy98/quickshell-quotas-widget/master/install.sh'
    decode_utf8_hex 'd181d0bad180d18bd0b2d0b0d0b5d18220d0b2d0b2d0bed0b4'; printf '\n'
    printf '%s\n' '/dev/tty' '--management-key' '--management-key-stdin'
    decode_utf8_hex 'd0b8d181d182d0bed180d0b8d18e20d0bed0b1d0bed0bbd0bed187d0bad0b820d0b820d181d0bfd0b8d181d0bed0ba20d0bfd180d0bed186d0b5d181d181d0bed0b2'; printf '\n'
    printf '%s\n' '--install-dir' 'CONFIG_ROOT'
    decode_utf8_hex 'd0bad0b0d182d0b0d0bbd0bed0b320d0bcd0bed0b4d183d0bbd0b5d0b920d0bfd0b0d0bdd0b5d0bbd0b820656e64342d646f7473'; printf '\n'
    decode_utf8_hex 'd09fd180d0b5d0b4d0bfd0bed187d182d0b8d182d0b5d0bbd18cd0bdd0be20d185d180d0b0d0bdd0b8d0bbd0b8d189d0b5205365637265742053657276696365'; printf '\n'
    printf '%s\n' 'quotas-widget.conf' 'jq -Rs'
    decode_utf8_hex '4a534f4e2dd184d0b0d0b9d0bb20d18120d0bfd180d0b0d0b2d0b0d0bcd0b8206036303060'; printf '\n'
    decode_utf8_hex 'd0bed182d0bad180d18bd182d18bd0bc20d182d0b5d0bad181d182d0bed0bc'; printf '\n'
    decode_utf8_hex 'd0bfd0bed0b2d182d0bed180d0bdd0be20d0b2d18bd0bfd0bed0bbd0bdd0b8d182d0b520d182d18320d0b6d0b520d0bad0bed0bcd0b0d0bdd0b4d18320d183d181d182d0b0d0bdd0bed0b2d189d0b8d0bad0b0'; printf '\n'
    printf '%s\n' 'qs -p "$CONFIG_ROOT" kill' 'qs -p "$CONFIG_ROOT" --daemonize'
    printf '%s\n' 'install -m 644 Quotas.qml QuotasPopup.qml' 'install -m 700 get-quotas.sh' "IFS= read -r -s -p 'Management key: ' MANAGEMENT_KEY"
    decode_utf8_hex 'd180d0b5d0b7d0b5d180d0b2d0bdd183d18e20d0bad0bed0bfd0b8d18e20d18120d0bcd0b5d182d0bad0bed0b920d0b2d180d0b5d0bcd0b5d0bdd0b8'; printf '\n'
    decode_utf8_hex 'd0b0d0b2d182d0bed0bcd0b0d182d0b8d187d0b5d181d0bad0b820d0bed182d0bad0b0d182d18bd0b2d0b0d0b5d182'; printf '\n'
    printf '%s\n' 'bash tests/run.sh' 'quickshell-quotas-widget-<tag>.tar.gz'
    decode_utf8_hex 'd09fd183d0b1d0bbd0b8d187d0bdd18bd0b520d180d0b5d0bbd0b8d0b7d18b20d0b8d181d0bfd0bed0bbd18cd0b7d183d18ed18220d182d0b5d0b3d0b8'; printf '\n'
}

validate_russian_contract() {
    local guide="$1" anchor heading remainder="$1"

    while IFS= read -r anchor; do
        [[ -n "$anchor" ]] || continue
        assert_contains "$guide" "$anchor" || return 1
    done < <(russian_contract_anchors)

    while IFS= read -r heading; do
        [[ -n "$heading" ]] || continue
        [[ "$remainder" == *"$heading"* ]] || fail "missing ordered Russian section [$heading]" || return 1
        remainder="${remainder#*"$heading"}"
    done < <(russian_section_headings)
}

test_russian_guide_covers_public_contract() {
    read_guides
    validate_russian_contract "$RUSSIAN_GUIDE"
}

test_russian_contract_rejects_each_removed_anchor() {
    local anchor mutated count=0
    read_guides

    validate_russian_contract "$RUSSIAN_GUIDE" || return 1
    while IFS= read -r anchor; do
        [[ -n "$anchor" ]] || continue
        count=$((count + 1))
        mutated="${RUSSIAN_GUIDE//"$anchor"/}"
        if validate_russian_contract "$mutated" >/dev/null 2>&1; then
            fail "Russian contract accepted removal of required anchor $count" || return 1
        fi
    done < <(russian_contract_anchors)

    ((count > 12)) || fail 'Russian contract must include section headings and detail anchors'
}

test_russian_guide_documents_validation_sequence() {
    local pre_download post_download russian
    pre_download="$(decode_utf8_hex 'd094d0be20d0b7d0b0d0b3d180d183d0b7d0bad0b820d180d0b5d0bbd0b8d0b7d0b0')"
    post_download="$(decode_utf8_hex 'd09fd0bed181d0bbd0b520d0b7d0b0d0b3d180d183d0b7d0bad0b820d183d181d182d0b0d0bdd0bed0b2d189d0b8d0ba20d0bfd180d0bed0b2d0b5d180d18fd0b5d18220d0b0d180d185d0b8d0b220d0b4d0be20d0bfd0bed181d182d0bed18fd0bdd0bdd18bd18520d0b8d0b7d0bcd0b5d0bdd0b5d0bdd0b8d0b9')"
    read_guides
    russian="$RUSSIAN_GUIDE"

    assert_contains "$russian" "$pre_download" || return 1
    assert_contains "$russian" "$post_download" || return 1
    russian="${russian#*"$pre_download"}"
    [[ "${russian%%"$post_download"*}" != "$russian" ]] || fail 'Russian archive validation must follow pre-download checks'
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
run_test 'documents safe plaintext recovery' test_documents_safe_plaintext_recovery
run_test 'documents validation sequence' test_documents_validation_sequence
run_test 'documents exact provider scope' test_documents_exact_provider_scope
run_test 'has English and Russian guides' test_has_english_and_russian_guides
run_test 'Russian guide covers public contract' test_russian_guide_covers_public_contract
run_test 'Russian contract rejects each removed anchor' test_russian_contract_rejects_each_removed_anchor
run_test 'Russian guide documents validation sequence' test_russian_guide_documents_validation_sequence
run_test 'translations use identical commands' test_translations_use_identical_commands
run_test 'removes legacy machine requirements' test_removes_legacy_machine_requirements
run_test 'documentation test source is ASCII' test_documentation_test_source_is_ascii

finish_tests
