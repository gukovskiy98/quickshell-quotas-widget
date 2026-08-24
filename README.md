# Quickshell Quotas Widget

Quickshell panel widget for viewing AI account quotas through a Management API.

[Русская версия](README_RU.md)

## What it does and compatibility

The widget adds a quota indicator and popup to the `leftCenterGroup` of the end4-dots Quickshell bar. It loads quota data at startup, shows the average remaining quota in the bar, and refreshes on right-click.

This project supports compatible Hyprland, Quickshell, and [end4-dots](https://github.com/end-4/dots-hyprland) configurations. It is not a generic installer for arbitrary Quickshell layouts: the installer validates the standard end4-dots `shell.qml` and `modules/ii/bar/BarContent.qml` structure before making persistent changes.

Only Antigravity and Codex quota providers are supported. Other provider records are skipped.

## Supported quota displays

- Antigravity account groups and buckets, including remaining percentages and reset times.
- Codex primary-window remaining percentage and reset time.
- Per-account details in the popup and the average remaining quota in the bar.
- Partial results when one supported account fails while other accounts remain available.

## Dependencies

Installation requires:

- Bash 4+.
- `hyprctl`.
- Quickshell as either `quickshell` or `qs`.
- `curl`, `jq`, and `tar`.
- An existing compatible end4-dots configuration.

`notify-send` and `secret-tool` are optional. Without `notify-send`, right-click refresh still works but no desktop notification is shown. Without a usable `secret-tool`, the installer uses the protected local credential fallback described below.

`tar` is required to validate and extract the release during installation; `tar` is not needed by the installed widget at runtime. Bun is not required.

## Recommended one-line installation

Replace the example Management API URL, then run:

```bash
curl -fsSL https://raw.githubusercontent.com/gukovskiy98/quickshell-quotas-widget/master/install.sh | bash -s -- --api-url "https://management.example"
```

The installer prompts for the management key through `/dev/tty` with input hidden. The prompt works even though the pipeline uses standard input for the script. The API URL must start with `http://` or `https://`.

Before downloading the release, the installer validates the management key and local end4-dots layout. After downloading, it validates the latest GitHub Release archive before making persistent changes.

## Automation flags and key exposure

`install.sh --help` documents the complete bilingual CLI. `--api-url URL` is required. If neither key flag is supplied, the hidden TTY prompt is used.

For a locally downloaded installer, `--management-key-stdin` reads one line from standard input. This mode is intended for local use because `curl | bash` already consumes standard input:

```bash
curl -fsSLO https://raw.githubusercontent.com/gukovskiy98/quickshell-quotas-widget/master/install.sh
chmod 700 install.sh
printf '%s\n' "$MANAGEMENT_KEY" | ./install.sh --api-url "https://management.example" --management-key-stdin
```

Automation can instead use `--management-key KEY`:

```bash
./install.sh --api-url "https://management.example" --management-key "$MANAGEMENT_KEY"
```

Warning: a value passed with `--management-key` may be exposed in shell history and process listings. Prefer the hidden TTY prompt for interactive installation or `--management-key-stdin` with a locally downloaded installer. The two key flags are mutually exclusive, and the installer never prints the management key in normal diagnostics.

## Custom installation directory

By default, files are installed in `${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/ii/modules/ii/bar`.

`--install-dir PATH` must point directly to the end4-dots bar modules directory, not to the Quickshell configuration root. The directory may be relative or absolute. The installer expects `BarContent.qml` there and derives the configuration root by walking up from the standard `modules/ii/bar` layout.

```bash
./install.sh --api-url "https://management.example" --install-dir "$HOME/.config/quickshell/ii/modules/ii/bar"
```

## Credential storage

Secret Service is preferred. When `secret-tool` is available, the installer stores and reads back both the API URL and management key, accepting the backend only after verification succeeds.

If Secret Service is missing, unavailable, fails to store a value, or fails verification, the installer prints a security warning and writes the plaintext fallback `<install-dir>/quotas-widget.conf`. The fallback is JSON, has mode `600`, and is read with `jq`; it is never sourced or evaluated as shell code. Protect this file because it contains the management key in plaintext.

If verified Secret Service storage later succeeds, a previous fallback file is removed transactionally. Keyring values are not deleted during rollback because they may have replaced credentials from an earlier working installation.

## Updating

To update, rerun the same installer command. It downloads the latest GitHub Release, validates it, replaces changed files, updates the managed `BarContent.qml` block without duplication, runs the installed fetcher as a smoke test, and keeps unchanged files untouched.

Use the same `--api-url`, key-input method, and `--install-dir` value as the original installation when they are still applicable.

## Applying or restarting Quickshell

After a successful committed installation, the installer checks for a Quickshell instance using this configuration. If one is running, it runs `kill` and then starts it with `--daemonize`. A restart failure is reported as a warning and does not roll back the committed installation.

If automatic restart was skipped or failed, restart manually. Set `INSTALL_DIR` to the same bar modules directory used for installation, including a custom `--install-dir`; the configuration root is three parent directories above it. Replace `qs` with `quickshell` if that is the executable installed on your system:

```bash
INSTALL_DIR="${INSTALL_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/ii/modules/ii/bar}"
CONFIG_ROOT="$(cd -- "$INSTALL_DIR/../../.." && pwd -P)"
qs -p "$CONFIG_ROOT" kill
qs -p "$CONFIG_ROOT" --daemonize
```

## Manual installation or recovery

The installer is recommended because it validates the API, layout, archive, credentials, integration, and final quota output. For recovery from a checked-out repository, copy the payload files with their required modes:

```bash
INSTALL_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/ii/modules/ii/bar"
install -d "$INSTALL_DIR"
install -m 644 Quotas.qml QuotasPopup.qml "$INSTALL_DIR/"
install -m 700 get-quotas.sh "$INSTALL_DIR/"
```

Then choose one credential backend. For Secret Service, read the key without echo and pipe values to `secret-tool` so the key is not placed in command arguments:

```bash
(
set -euo pipefail
API_URL="https://management.example"
IFS= read -r -s -p 'Management key: ' MANAGEMENT_KEY
printf '\n'
[[ -n "$MANAGEMENT_KEY" ]] || { printf 'Management key must not be empty\n' >&2; exit 1; }
printf '%s' "${API_URL%/}" | secret-tool store --label="Quotas API URL" application quotas key quotasApiUrl
printf '%s' "$MANAGEMENT_KEY" | secret-tool store --label="Quotas Management Key" application quotas key quotasManagementKey
unset MANAGEMENT_KEY
)
```

If Secret Service cannot be used, create the exact plaintext fallback JSON safely. Set `INSTALL_DIR` to the installed bar modules directory. The subshell uses a hidden prompt, restrictive creation permissions, `jq` stdin rather than key arguments, and an atomic final rename:

```bash
(
set -euo pipefail
INSTALL_DIR="${INSTALL_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/ii/modules/ii/bar}"
API_URL="https://management.example"
IFS= read -r -s -p 'Management key: ' MANAGEMENT_KEY
printf '\n'
[[ -n "$MANAGEMENT_KEY" ]] || { printf 'Management key must not be empty\n' >&2; exit 1; }
umask 077
tmp_config="$(mktemp "$INSTALL_DIR/quotas-widget.conf.XXXXXX")"
trap 'rm -f -- "$tmp_config"' EXIT
printf '%s\0%s' "${API_URL%/}" "$MANAGEMENT_KEY" \
  | jq -Rs 'split("\u0000") | {apiUrl:.[0], managementKey:.[1]}' >"$tmp_config"
chmod 600 "$tmp_config"
mv -f -- "$tmp_config" "$INSTALL_DIR/quotas-widget.conf"
trap - EXIT
unset MANAGEMENT_KEY
)
```

Finally, add this managed block immediately after the `Resources` component inside the single `BarGroup` with `id: leftCenterGroup`:

```qml
// quickshell-quotas-widget:start
Quotas {
    visible: true
    Layout.fillWidth: false
}
// quickshell-quotas-widget:end
```

Manual recovery bypasses installer validation and rollback. Prefer rerunning the installer once the layout or credentials are repaired.

## Backups and rollback

Before replacing a changed file, the installer creates timestamped backups beside it using the suffix `.backup.YYYYMMDD-HHMMSS`. This includes installed payload files, `BarContent.qml`, and an existing plaintext fallback when applicable. Identical files with correct modes do not receive unnecessary backups.

Credential storage, payload installation, bar integration, and the smoke test form one transaction. If a persistent step fails or the installer receives `INT` or `TERM`, it automatically rolls back replaced files and removes files newly created by that transaction. Backups are retained. If rollback itself is incomplete, the installer warns and preserves the backups for manual recovery.

## Development tests and releases

Run the complete Bash test suite before submitting changes:

```bash
bash tests/run.sh
```

Public releases use tags beginning with `v`. The release asset must be named `quickshell-quotas-widget-<tag>.tar.gz` and contain exactly these three regular files at archive top level: `Quotas.qml`, `QuotasPopup.qml`, and `get-quotas.sh`. The public installer queries the latest GitHub Release and rejects missing, duplicate, nested, extra, or unsafe payload entries.
