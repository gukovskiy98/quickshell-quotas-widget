# Quickshell Quotas Widget

Quickshell panel widget for viewing AI account quotas through a Management API.

## English

### What it does and compatibility

The widget adds a quota indicator and popup to the `leftCenterGroup` of the end4-dots Quickshell bar. It loads quota data at startup, shows the average remaining quota in the bar, and refreshes on right-click.

This project supports compatible Hyprland, Quickshell, and [end4-dots](https://github.com/end-4/dots-hyprland) configurations. It is not a generic installer for arbitrary Quickshell layouts: the installer validates the standard end4-dots `shell.qml` and `modules/ii/bar/BarContent.qml` structure before making persistent changes.

Only Antigravity and Codex quota providers are supported. Other provider records are skipped.

### Supported quota displays

- Antigravity account groups and buckets, including remaining percentages and reset times.
- Codex primary-window remaining percentage and reset time.
- Per-account details in the popup and the average remaining quota in the bar.
- Partial results when one supported account fails while other accounts remain available.

### Dependencies

Installation requires:

- Bash 4+.
- `hyprctl`.
- Quickshell as either `quickshell` or `qs`.
- `curl`, `jq`, and `tar`.
- An existing compatible end4-dots configuration.

`notify-send` and `secret-tool` are optional. Without `notify-send`, right-click refresh still works but no desktop notification is shown. Without a usable `secret-tool`, the installer uses the protected local credential fallback described below.

`tar` is required to validate and extract the release during installation; `tar` is not needed by the installed widget at runtime. Bun is not required.

### Recommended one-line installation

Replace the example Management API URL, then run:

```bash
curl -fsSL https://raw.githubusercontent.com/gukovskiy98/quickshell-quotas-widget/master/install.sh | bash -s -- --api-url "https://management.example"
```

The installer prompts for the management key through `/dev/tty` with input hidden. The prompt works even though the pipeline uses standard input for the script. The API URL must start with `http://` or `https://`.

Before downloading or changing files, the installer validates the key against `<api-url>/v0/management/auth-files`, validates the local end4-dots layout, and validates the latest GitHub Release archive.

### Automation flags and key exposure

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

### Custom installation directory

By default, files are installed in `${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/ii/modules/ii/bar`.

`--install-dir PATH` must point directly to the end4-dots bar modules directory, not to the Quickshell configuration root. The directory may be relative or absolute. The installer expects `BarContent.qml` there and derives the configuration root by walking up from the standard `modules/ii/bar` layout.

```bash
./install.sh --api-url "https://management.example" --install-dir "$HOME/.config/quickshell/ii/modules/ii/bar"
```

### Credential storage

Secret Service is preferred. When `secret-tool` is available, the installer stores and reads back both the API URL and management key, accepting the backend only after verification succeeds.

If Secret Service is missing, unavailable, fails to store a value, or fails verification, the installer prints a security warning and writes the plaintext fallback `<install-dir>/quotas-widget.conf`. The fallback is JSON, has mode `600`, and is read with `jq`; it is never sourced or evaluated as shell code. Protect this file because it contains the management key in plaintext.

If verified Secret Service storage later succeeds, a previous fallback file is removed transactionally. Keyring values are not deleted during rollback because they may have replaced credentials from an earlier working installation.

### Updating

To update, rerun the same installer command. It downloads the latest GitHub Release, validates it, replaces changed files, updates the managed `BarContent.qml` block without duplication, runs the installed fetcher as a smoke test, and keeps unchanged files untouched.

Use the same `--api-url`, key-input method, and `--install-dir` value as the original installation when they are still applicable.

### Applying or restarting Quickshell

After a successful committed installation, the installer checks for a Quickshell instance using this configuration. If one is running, it runs `kill` and then starts it with `--daemonize`. A restart failure is reported as a warning and does not roll back the committed installation.

If automatic restart was skipped or failed, restart manually. Replace `qs` with `quickshell` if that is the executable installed on your system:

```bash
qs -p "${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/ii" kill
qs -p "${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/ii" --daemonize
```

### Manual installation or recovery

The installer is recommended because it validates the API, layout, archive, credentials, integration, and final quota output. For recovery from a checked-out repository, copy the payload files with their required modes:

```bash
INSTALL_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/ii/modules/ii/bar"
install -d "$INSTALL_DIR"
install -m 644 Quotas.qml QuotasPopup.qml "$INSTALL_DIR/"
install -m 700 get-quotas.sh "$INSTALL_DIR/"
```

Then ensure credentials exist through Secret Service or a mode-`600` `quotas-widget.conf`, and add this managed block immediately after the `Resources` component inside the single `BarGroup` with `id: leftCenterGroup`:

```bash
printf '%s' "https://management.example" | secret-tool store --label="Quotas API URL" application quotas key quotasApiUrl
printf '%s' "$MANAGEMENT_KEY" | secret-tool store --label="Quotas Management Key" application quotas key quotasManagementKey
```

```qml
// quickshell-quotas-widget:start
Quotas {
    visible: true
    Layout.fillWidth: false
}
// quickshell-quotas-widget:end
```

Manual recovery bypasses installer validation and rollback. Prefer rerunning the installer once the layout or credentials are repaired.

### Backups and rollback

Before replacing a changed file, the installer creates timestamped backups beside it using the suffix `.backup.YYYYMMDD-HHMMSS`. This includes installed payload files, `BarContent.qml`, and an existing plaintext fallback when applicable. Identical files with correct modes do not receive unnecessary backups.

Credential storage, payload installation, bar integration, and the smoke test form one transaction. If a persistent step fails or the installer receives `INT` or `TERM`, it automatically rolls back replaced files and removes files newly created by that transaction. Backups are retained. If rollback itself is incomplete, the installer warns and preserves the backups for manual recovery.

### Development tests and releases

Run the complete Bash test suite before submitting changes:

```bash
bash tests/run.sh
```

Public releases use tags beginning with `v`. The release asset must be named `quickshell-quotas-widget-<tag>.tar.gz` and contain exactly these three regular files at archive top level: `Quotas.qml`, `QuotasPopup.qml`, and `get-quotas.sh`. The public installer queries the latest GitHub Release and rejects missing, duplicate, nested, extra, or unsafe payload entries.

## Русский

### Назначение и совместимость

Виджет добавляет индикатор квот и всплывающее окно в группу `leftCenterGroup` панели end4-dots Quickshell. Он загружает данные при запуске, показывает средний остаток квот на панели и обновляет данные по правому клику.

Проект поддерживает совместимые конфигурации Hyprland, Quickshell и [end4-dots](https://github.com/end-4/dots-hyprland). Это не универсальный установщик для произвольных конфигураций Quickshell: перед постоянными изменениями установщик проверяет стандартную структуру end4-dots в `shell.qml` и `modules/ii/bar/BarContent.qml`.

Поддерживаются только провайдеры квот Antigravity и Codex. Записи других провайдеров пропускаются.

### Отображаемые квоты

- Группы и лимиты аккаунтов Antigravity, включая оставшиеся проценты и время сброса.
- Оставшийся процент и время сброса основного окна Codex.
- Подробности по аккаунтам во всплывающем окне и средний остаток квот на панели.
- Частичный результат, если один поддерживаемый аккаунт завершился ошибкой, а данные остальных доступны.

### Зависимости

Для установки необходимы:

- Bash 4+.
- `hyprctl`.
- Quickshell с исполняемым файлом `quickshell` или `qs`.
- `curl`, `jq` и `tar`.
- Существующая совместимая конфигурация end4-dots.

`notify-send` и `secret-tool` необязательны. Без `notify-send` обновление по правому клику работает, но уведомление рабочего стола не показывается. Без рабочего `secret-tool` установщик использует защищенный локальный файл учетных данных, описанный ниже.

`tar` нужен для проверки и распаковки релиза во время установки; установленному виджету `tar` во время работы не нужен. Bun не требуется.

### Рекомендуемая установка одной командой

Замените пример URL Management API и выполните:

```bash
curl -fsSL https://raw.githubusercontent.com/gukovskiy98/quickshell-quotas-widget/master/install.sh | bash -s -- --api-url "https://management.example"
```

Установщик запрашивает ключ управления через `/dev/tty` и скрывает ввод. Запрос работает, даже когда стандартный ввод занят конвейером со скриптом. URL API должен начинаться с `http://` или `https://`.

До загрузки или изменения файлов установщик проверяет ключ через `<api-url>/v0/management/auth-files`, локальную структуру end4-dots и архив последнего GitHub Release.

### Флаги автоматизации и раскрытие ключа

Команда `install.sh --help` выводит полную двуязычную справку CLI. Флаг `--api-url URL` обязателен. Если флаг способа передачи ключа не указан, используется скрытый запрос через TTY.

Для локально загруженного установщика `--management-key-stdin` читает одну строку из стандартного ввода. Этот режим предназначен для локального использования, потому что в `curl | bash` стандартный ввод уже занят:

```bash
curl -fsSLO https://raw.githubusercontent.com/gukovskiy98/quickshell-quotas-widget/master/install.sh
chmod 700 install.sh
printf '%s\n' "$MANAGEMENT_KEY" | ./install.sh --api-url "https://management.example" --management-key-stdin
```

Для автоматизации также доступен `--management-key KEY`:

```bash
./install.sh --api-url "https://management.example" --management-key "$MANAGEMENT_KEY"
```

Предупреждение: значение `--management-key` может попасть в историю оболочки и список процессов. Для интерактивной установки предпочтителен скрытый запрос через TTY, а для локально загруженного установщика - `--management-key-stdin`. Эти два флага взаимоисключающие; установщик не печатает ключ управления в обычной диагностике.

### Другой каталог установки

По умолчанию файлы устанавливаются в `${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/ii/modules/ii/bar`.

Путь `--install-dir PATH` должен указывать непосредственно на каталог модулей панели end4-dots, а не на корень конфигурации Quickshell. Путь может быть относительным или абсолютным. Установщик ожидает там `BarContent.qml` и определяет корень конфигурации по стандартной структуре `modules/ii/bar`.

```bash
./install.sh --api-url "https://management.example" --install-dir "$HOME/.config/quickshell/ii/modules/ii/bar"
```

### Хранение учетных данных

Предпочтительно хранилище Secret Service. Если доступен `secret-tool`, установщик сохраняет и считывает обратно URL API и ключ управления и принимает это хранилище только после успешной проверки значений.

Если Secret Service отсутствует или недоступен либо сохранение или проверка не удались, установщик выводит предупреждение безопасности и записывает открытые данные в резервный файл `<install-dir>/quotas-widget.conf`. Это JSON-файл с правами `600`, который читается через `jq` и никогда не подключается и не выполняется как shell-код. Защитите этот файл: ключ управления хранится в нем открытым текстом.

Если позднее проверенное сохранение в Secret Service пройдет успешно, прежний резервный файл будет удален в рамках транзакции. Значения в связке ключей не удаляются при откате, потому что они могли заменить учетные данные предыдущей рабочей установки.

### Обновление

Для обновления повторно выполните ту же команду установщика. Он загрузит последний GitHub Release, проверит его, заменит изменившиеся файлы, обновит управляемый блок в `BarContent.qml` без дублирования, запустит установленный загрузчик квот для проверки и не будет трогать неизменившиеся файлы.

Используйте те же `--api-url`, способ передачи ключа и значение `--install-dir`, что и при первой установке, если они по-прежнему актуальны.

### Применение изменений или перезапуск Quickshell

После успешной фиксации установки установщик проверяет экземпляр Quickshell с этой конфигурацией. Если он запущен, установщик выполняет `kill`, а затем запускает его с `--daemonize`. Ошибка перезапуска выводится как предупреждение и не откатывает уже зафиксированную установку.

Если автоматический перезапуск пропущен или завершился ошибкой, перезапустите Quickshell вручную. Замените `qs` на `quickshell`, если в вашей системе установлен исполняемый файл с этим именем:

```bash
qs -p "${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/ii" kill
qs -p "${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/ii" --daemonize
```

### Ручная установка или восстановление

Рекомендуется установщик: он проверяет API, структуру каталогов, архив, учетные данные, интеграцию и итоговые данные квот. Для восстановления из локальной копии репозитория скопируйте файлы с необходимыми правами:

```bash
INSTALL_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/ii/modules/ii/bar"
install -d "$INSTALL_DIR"
install -m 644 Quotas.qml QuotasPopup.qml "$INSTALL_DIR/"
install -m 700 get-quotas.sh "$INSTALL_DIR/"
```

Затем настройте учетные данные в Secret Service или файле `quotas-widget.conf` с правами `600` и добавьте следующий управляемый блок сразу после компонента `Resources` внутри единственного `BarGroup` с `id: leftCenterGroup`:

```bash
printf '%s' "https://management.example" | secret-tool store --label="Quotas API URL" application quotas key quotasApiUrl
printf '%s' "$MANAGEMENT_KEY" | secret-tool store --label="Quotas Management Key" application quotas key quotasManagementKey
```

```qml
// quickshell-quotas-widget:start
Quotas {
    visible: true
    Layout.fillWidth: false
}
// quickshell-quotas-widget:end
```

При ручном восстановлении проверки и откат установщика не выполняются. После исправления структуры или учетных данных предпочтительно снова запустить установщик.

### Резервные копии и откат

Перед заменой изменившегося файла установщик создает рядом резервную копию с меткой времени и суффиксом `.backup.YYYYMMDD-HHMMSS`. Это относится к файлам виджета, `BarContent.qml` и существующему открытому резервному файлу учетных данных, когда он используется. Для одинаковых файлов с правильными правами лишние резервные копии не создаются.

Хранение учетных данных, установка файлов, интеграция с панелью и проверочный запуск образуют одну транзакцию. Если постоянный шаг завершился ошибкой или установщик получил `INT` или `TERM`, он автоматически откатывает замененные файлы и удаляет файлы, созданные этой транзакцией. Резервные копии сохраняются. Если сам откат не завершен полностью, установщик выводит предупреждение и сохраняет копии для ручного восстановления.

### Тесты разработки и релизы

Перед отправкой изменений запустите полный набор Bash-тестов:

```bash
bash tests/run.sh
```

Публичные релизы используют теги, начинающиеся с `v`. Релиз должен содержать архив `quickshell-quotas-widget-<tag>.tar.gz` ровно с тремя обычными файлами верхнего уровня: `Quotas.qml`, `QuotasPopup.qml` и `get-quotas.sh`. Публичный установщик запрашивает последний GitHub Release и отклоняет отсутствующие, дублирующиеся, вложенные, лишние или небезопасные элементы архива.
