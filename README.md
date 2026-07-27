# Quickshell Quotas Widget (Виджет Квот)

Автономный виджет для панели **Quickshell** (illogical-impulse / end4 dots), отображающий текущий остаток квот AI-аккаунтов (Antigravity, Codex и др.) с автоматическим и ручным обновлением.

---

## 📁 Структура файлов икуда их копировать

При переустановке или обновлении точек (end4 dots / Quickshell), скопируйте файлы из этой папки по следующим путям:

| Файл в репозитории | Целевой путь в системе |
| :--- | :--- |
| `Quotas.qml` | `~/.config/quickshell/ii/modules/ii/bar/Quotas.qml` |
| `QuotasPopup.qml` | `~/.config/quickshell/ii/modules/ii/bar/QuotasPopup.qml` |
| `get-quotas.ts` | `~/.config/quickshell/ii/modules/ii/bar/get-quotas.ts` |

---

## 🔑 Необходимые переменные и секреты (`gnome-keyring`)

Виджет использует `secret-tool` для безопасного считывания URL API и ключа управления из связки ключей GNOME без хранения секретов в конфигурациях.

Если секреты не заданы (или после чистой установки системы), выполните в терминале команды:

```bash
# 1. Сохранить API URL Management API
secret-tool store --label="Quotas API URL" application quotas key quotasApiUrl

# 2. Сохранить Management Key
secret-tool store --label="Quotas Management Key" application quotas key quotasManagementKey
```

> **Проверка наличия секретов в keyring:**
> ```bash
> secret-tool lookup application quotas key quotasApiUrl
> secret-tool lookup application quotas key quotasManagementKey
> ```

---

## 🔌 Подключение виджета на панель

В файле `~/.config/quickshell/ii/modules/ii/bar/BarContent.qml` добавьте вызов виджета `Quotas` (например, рядом с `Resources` или `Media`):

```qml
Resources {
    alwaysShowAllResources: root.useShortenedForm === 2
    Layout.fillWidth: root.useShortenedForm === 2
}

// === Виджет Квот ===
Quotas {
    visible: true
    Layout.fillWidth: false
}
```

---

## 🛠️ Зависимости

- **Bun**: должен быть установлен по пути `~/.bun/bin/bun`
- **libsecret / secret-tool**: пакетом `libsecret` в Linux
- **notify-send**: для всплывающего уведомления при ручном обновлении (по правому клику)
