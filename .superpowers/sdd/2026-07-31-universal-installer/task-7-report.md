# Task 7 Report

Status: Complete

Implementation commit: `157bda4 Add transactional widget installation`

Implemented:

- Transaction journal for replaced and created files with deterministic timestamped backups, reverse-order rollback, preserved backup copies, and signal/error handling.
- Atomic payload installation with modes `644`, `644`, and `700`, content comparison, destination-local temporary files, and symlink rejection.
- Journal-aware fallback credential creation, replacement, and removal while leaving Secret Service writes outside rollback.
- Balanced `BarContent.qml` insertion after the unique `Resources` component inside the unique `leftCenterGroup` `BarGroup`, ignoring braces in line comments and quoted strings.
- Managed marker validation, idempotent reinvocation, and rejection of partial, duplicate, missing, or ambiguous insertion points.
- Installed-fetcher smoke testing with separate stdout/stderr capture and strict quota JSON schema checks.
- Configuration-scoped Quickshell detection, kill, and daemonized restart with warning-only post-commit failures.
- Full orchestration order: credentials are stored only after API and release validation; all persistent changes are committed only after the smoke test.

Tests: `bash tests/run.sh` -> 142 tests, 0 failures (`39 + 95 + 8`); `bash -n install.sh get-quotas.sh tests/*.bash tests/helpers/*.sh`, ASCII scan, `git diff --check`, and ShellCheck all passed.

Security review:

- Management credentials are not placed in curl or jq arguments and are not printed in completion, warning, or error output.
- Release extraction constraints remain unchanged.
- Payload and fallback destinations reject symlinks.
- Smoke-test stderr is kept in a protected temporary work directory and is referenced by path rather than copied into installer output.

Concerns: Secret Service writes are intentionally not rolled back, as required. Timestamped backups intentionally remain after successful installation and rollback. No live user configuration was touched; tests used fixtures and temporary directories only.
