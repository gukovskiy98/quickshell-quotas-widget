# Universal Installer Design

## Summary

Quickshell Quotas Widget currently requires manual file copying, manual changes to end4-dots, a hard-coded user path, and Bun. The public version will provide an idempotent Bash installer that can be run from GitHub, replace the TypeScript quota client with Bash, and remove all user-specific paths.

This project remains an end4-dots widget rather than a generic Quickshell widget. Universal installation means that any user with a compatible Hyprland, Quickshell, and end4-dots installation can install it without manually editing files.

Provider behavior is not expanded in this change. The new quota client preserves the current effective display support for Antigravity and Codex. Claude, Kimi, and xAI quota parsing are outside this scope.

## Distribution

The repository is published at `gukovskiy98/quickshell-quotas-widget`.

Each tagged GitHub release contains:

```text
quickshell-quotas-widget-<version>.tar.gz
├── Quotas.qml
├── QuotasPopup.qml
└── get-quotas.sh
```

`install.sh` remains available at a stable raw GitHub URL. It discovers and downloads the latest GitHub Release instead of installing files from the moving `master` branch. A GitHub Actions workflow triggered by tags matching `v*` builds the archive. CI also runs ShellCheck and the automated test suite.

The primary installation command is:

```bash
curl -fsSL https://raw.githubusercontent.com/gukovskiy98/quickshell-quotas-widget/master/install.sh \
  | bash -s -- --api-url "http://localhost:8080"
```

When the management key is omitted, the installer reads it without echo from `/dev/tty`. This works even when standard input is occupied by the `curl | bash` pipeline.

For automation, `--management-key VALUE` remains available, with documentation warning that command arguments may appear in shell history and process listings. A locally downloaded installer additionally supports `--management-key-stdin`.

## Installer Interface

`install.sh` requires Bash 4 or newer and supports:

```text
--api-url URL                 Required Management API base URL
--management-key KEY          Optional key argument for automation
--management-key-stdin        Read the key from standard input
--install-dir DIR             Destination bar modules directory
--help                        Print usage
```

`--management-key` and `--management-key-stdin` are mutually exclusive. If neither is supplied, the installer prompts through `/dev/tty`.

The default installation directory is:

```text
${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/ii/modules/ii/bar
```

`--install-dir` refers directly to the bar modules directory. The installer expects `BarContent.qml` in that directory and derives the end4-dots configuration root from its standard relative location.

The API URL must use `http://` or `https://`. The installer removes trailing slashes before storing or using it. Unknown arguments, missing values, conflicting key-input modes, empty credentials, and unsupported URL schemes are fatal errors.

## Preflight Validation

The installer makes no persistent changes until all preflight checks pass.

It verifies:

- Bash 4 or newer.
- `hyprctl` is available.
- `quickshell` or `qs` is available.
- `curl` and `jq` are available.
- The selected installation directory and its parent are writable or creatable.
- `BarContent.qml` exists at the selected destination.
- The corresponding end4-dots `shell.qml` exists.
- `shell.qml` contains characteristic end4-dots structure, including the panel family setup.
- `BarContent.qml` contains the expected end4-dots bar structure, including `leftCenterGroup` and a `Resources` component.

The checks establish that the software and compatible configuration are installed. They do not require an active Hyprland or Quickshell process.

If required commands are missing, the installer does not invoke `sudo` or install packages automatically. It reports all missing commands and, for recognized distributions/package managers, prints a suitable installation command.

`notify-send` and `secret-tool` are optional. Their absence produces warnings or activates fallback behavior rather than failing preflight.

## API Validation

Before downloading or modifying widget files, the installer validates the supplied credentials with:

```text
GET <api-url>/v0/management/auth-files
Authorization: Bearer <management-key>
```

Validation requires:

- A successful network request.
- A successful HTTP status.
- Valid JSON.
- A top-level `files` array.

Authentication, network, HTTP, or schema errors stop installation before persistent changes. The management key is never printed in diagnostics.

## Release Download

The installer requests the latest release metadata from the GitHub API and downloads the expected versioned archive into a temporary directory. The temporary directory is removed through a `trap` on success, error, or interruption.

Before installing, it verifies that the archive contains exactly the expected widget payload files at its top level and rejects missing files, unexpected path traversal entries, or unsafe archive paths. Downloaded scripts are not executed during archive validation.

The GitHub owner and repository are constants in the installer:

```text
owner: gukovskiy98
repository: quickshell-quotas-widget
```

## Credential Storage

The preferred storage backend is Secret Service through `secret-tool`. The installer writes:

```text
application=quotas, key=quotasApiUrl
application=quotas, key=quotasManagementKey
```

After each write, it performs a lookup and verifies that the stored value matches the input. The key itself is not printed.

If `secret-tool` is absent, Secret Service is unavailable, storage fails, or verification fails, installation continues with an explicit security warning and writes:

```text
<install-dir>/quotas-widget.conf
```

The fallback file has mode `600` and contains JSON generated with `jq`, not shell syntax:

```json
{
  "apiUrl": "http://localhost:8080",
  "managementKey": "..."
}
```

`get-quotas.sh` parses it with `jq` and never uses `source` or `eval`.

The configuration file is generated during installation and is never included in source control or release archives.

Credential rollback is intentionally conservative. If installation later fails, newly written keyring values are not automatically deleted because they may have replaced valid values from an earlier installation. Existing fallback configuration is backed up and restored like other replaced files.

The fallback file also acts as an explicit backend selector through its presence. If Secret Service storage and verification succeed, the installer removes an existing fallback file as a tracked transactional change. If either keyring write or verification fails, the installer writes a complete fallback file. This prevents a partially updated keyring pair from being mixed with older values.

## Installed Files

The installer places these files in the selected bar modules directory:

```text
Quotas.qml
QuotasPopup.qml
get-quotas.sh
quotas-widget.conf    # present only when plaintext fallback is active
```

Modes are:

```text
Quotas.qml:           644
QuotasPopup.qml:      644
get-quotas.sh:        700
quotas-widget.conf:   600
```

Files are first copied to temporary names in the destination and then renamed into place. Existing files that will change are backed up before replacement. Unchanged files do not produce unnecessary backups.

## BarContent Integration

The installer automatically adds the widget to `BarContent.qml` and creates a timestamped backup before modifying the file.

The managed block is:

```qml
// quickshell-quotas-widget:start
Quotas {
    visible: true
    Layout.fillWidth: false
}
// quickshell-quotas-widget:end
```

If exactly one complete managed block already exists, it is left in place and no duplicate is added. Partial or duplicate markers are treated as an error requiring manual cleanup.

For a new installation, the installer locates the `Resources` component within `leftCenterGroup` and inserts the managed block immediately after it. Matching is limited to the expected end4-dots structure rather than the first `Resources` token in the file.

If a unique safe insertion point cannot be identified, the installer does not guess. It rolls back files changed during the current run, preserves the backup, and prints the exact block and target file for manual insertion.

## Transaction And Rollback

Installation is idempotent. Re-running it:

- Updates widget files from the latest release.
- Updates credentials.
- Does not duplicate the `BarContent.qml` block.
- Preserves unrelated user modifications.
- Creates backups only for content that changes.

Once persistent changes begin, the installer tracks every created or replaced file. A failure during file installation, bar integration, permissions, or smoke testing restores replaced files and removes files newly created by that run.

The original `BarContent.qml` is restored on failure. Timestamped backups are retained for user recovery and inspection.

Rollback does not remove keyring values. It restores a pre-existing fallback config file or removes one created by the failed run.

## Quota Fetcher

`get-quotas.sh` replaces `get-quotas.ts` and requires Bash 4+, `curl`, and `jq`.

It determines its own directory from `BASH_SOURCE`, so it does not depend on `$HOME`, a username, Bun, Node.js, or the current working directory.

Credential lookup order is:

1. If the local fallback configuration exists, read both values from it.
2. Otherwise, read both values through `secret-tool` when available.
3. Fail with a diagnostic if no complete credential pair is available.

The script preserves the current provider request behavior and output contract. It fetches the auth file list, skips disabled, runtime-only, or malformed entries, and processes accounts sequentially.

Antigravity and Codex responses are converted to display groups as in the current implementation. Claude, Kimi, xAI, and unknown or currently unsupported response formats are reported to stderr and do not terminate processing of other accounts.

Failure to fetch or parse the global auth file list is fatal. Failure for one account is non-fatal and produces a partial result.

Stdout contains exactly one JSON document. All progress and diagnostics go to stderr. The output remains compatible with the QML components:

```json
{
  "quotas": [],
  "minRemaining": 1,
  "avgRemaining": 1,
  "lastUpdated": "14:30 • 31/07/2026"
}
```

The fetcher exits nonzero for global failures and zero when it can produce a structurally valid result, including a partial result with individual account failures.

## QML Behavior

`Quotas.qml` launches the neighboring `get-quotas.sh` directly through Quickshell `Process`; it does not use `bash -c`, retrieve credentials, or construct environment variables.

The script path is resolved relative to `Quotas.qml`, removing the current hard-coded `/home/ngukovskiy` and `~/.bun/bin/bun` paths.

On successful output, QML parses the JSON and updates the displayed quotas. On a nonzero exit or invalid JSON, it clears the fetching state, retains the previous successful data, and logs a useful diagnostic without exposing credentials.

Right-click continues to trigger a manual refresh. If `notify-send` is available, it displays the refresh notification. Its absence does not prevent refresh.

`QuotasPopup.qml` keeps its current user-facing behavior. Provider expansion and UI redesign are not included.

## Smoke Test And Activation

After files and bar integration are in place, the installer runs the installed `get-quotas.sh` and requires:

- Exit status zero.
- Valid JSON.
- A `quotas` array.
- Numeric `minRemaining` and `avgRemaining` fields.
- A string `lastUpdated` field.

Smoke-test failure triggers rollback.

After successful installation, the installer detects whether the relevant Quickshell configuration is running. If possible, it uses the supported Quickshell CLI to stop the existing instance and starts the `ii` configuration again. Inability to restart is a warning, not an installation failure, and the installer prints a manual restart command.

An active Hyprland or Quickshell session is never required to install.

## Error Classification

Fatal errors include:

- Missing Hyprland, Quickshell, Bash 4+, `curl`, or `jq`.
- Missing or incompatible end4-dots files.
- Invalid arguments or API URL.
- Unreachable API, rejected credentials, invalid API JSON, or an invalid auth-files schema.
- Release metadata or archive download failure.
- Unsafe or incomplete release archive.
- Ambiguous or unsafe `BarContent.qml` integration.
- File installation, permission, or smoke-test failure.

Warnings include:

- Secret Service is unavailable and plaintext fallback is used.
- `notify-send` is unavailable.
- Quickshell is not running.
- Automatic Quickshell restart fails.
- An individual AI account or unsupported provider response cannot be processed.

CLI messages are English-first with concise Russian translations for user-facing errors, warnings, prompts, and completion instructions.

## Testing

Automated tests run against temporary fixture directories and never modify the real user configuration.

Installer coverage includes:

- Required and optional argument parsing.
- TTY prompt behavior and stdin key mode.
- Invalid and unsupported URLs.
- Missing dependency diagnostics.
- Compatible and incompatible end4-dots fixtures.
- API authentication, HTTP, JSON, and schema failures.
- Release archive validation.
- Safe insertion after `Resources` in `leftCenterGroup`.
- Repeated installation without duplicate blocks.
- Detection of partial or duplicate managed markers.
- Backup creation and preservation.
- Rollback after failures at each persistent stage.
- Secret Service success and fallback behavior.
- Fallback config permissions and safe parsing.
- Verification that credentials never appear in output.

Quota fetcher tests use fixture responses and mocked transport to cover:

- Antigravity output.
- Codex output.
- Mixed accounts.
- Disabled and runtime-only accounts.
- Individual account failure with a partial result.
- Global API failure.
- Structurally valid JSON output and exit statuses.

Internal environment variables may replace GitHub endpoints, API transport, command paths, and configuration roots during tests. They are test seams, not documented public interfaces.

Manual release validation covers installation in a real end4-dots environment, visible bar integration, popup behavior, right-click refresh, keyring storage, plaintext fallback, repeat installation, and Quickshell restart behavior.

## Documentation

`README.md` becomes bilingual. It contains a complete English guide followed by a complete Russian guide.

Both guides document:

- Supported environment and providers.
- Required dependencies.
- One-line installation.
- Secure hidden key prompt.
- Automation with `--management-key` and its exposure risk.
- Local `--management-key-stdin` usage.
- Custom `--install-dir` behavior.
- Secret Service and plaintext fallback behavior.
- Updating by re-running the installer.
- Manual Quickshell restart.
- Manual installation as a recovery path.
- Backup and rollback behavior.

## Out Of Scope

- Generic support for Quickshell configurations other than end4-dots.
- Automatic package installation or use of `sudo`.
- New quota provider parsers.
- Popup redesign or broader widget customization.
- Uninstaller implementation.
- Automatic deletion of credentials during rollback.
