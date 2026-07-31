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
