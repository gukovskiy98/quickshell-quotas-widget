/**
 * Скрипт для получения текущих квот по всем аккаунтам через Management API.
 * 
 * Запуск через Bun:
 * API_URL=http://localhost:8080 MANAGEMENT_KEY=ваш_ключ bun run scripts/get-quotas.ts
 * 
 * Запуск через Node (18+):
 * API_URL=http://localhost:8080 MANAGEMENT_KEY=ваш_ключ node scripts/get-quotas.ts
 */

const API_URL = process.env.API_URL || 'http://localhost:8080';
const MANAGEMENT_KEY = process.env.MANAGEMENT_KEY;

if (!MANAGEMENT_KEY) {
  console.error('Ошибка: Не задана переменная окружения MANAGEMENT_KEY.');
  process.exit(1);
}

const headers = {
  Authorization: `Bearer ${MANAGEMENT_KEY}`,
  'Content-Type': 'application/json',
};

async function apiCall(authIndex, method, url, requestHeader = {}, data = undefined) {
  const payload = {
    authIndex,
    method,
    url,
    header: requestHeader,
  };
  if (data) {
    payload.data = data;
  }

  const res = await fetch(`${API_URL}/v0/management/api-call`, {
    method: 'POST',
    headers,
    body: JSON.stringify(payload),
  });

  if (!res.ok) {
    throw new Error(`API Call failed: ${res.status} ${await res.text()}`);
  }

  const result = await res.json();
  if (result.status_code >= 400) {
    throw new Error(`Upstream API failed: ${result.status_code} ${result.bodyText}`);
  }

  let body = result.body;
  if (typeof body === 'string') {
    try {
      body = JSON.parse(body);
    } catch (e) {
      // Игнорируем, если это не JSON
    }
  }
  return body;
}

// Функции для каждого провайдера
async function getCodexQuota(authIndex) {
  return apiCall(authIndex, 'GET', 'https://chatgpt.com/backend-api/wham/usage', {
    Authorization: 'Bearer $TOKEN$',
    'User-Agent': 'codex_cli_rs/0.76.0 (Debian 13.0.0; x86_64) WindowsTerminal',
    Accept: 'application/json',
  });
}

async function getClaudeQuota(authIndex) {
  return apiCall(authIndex, 'GET', 'https://api.anthropic.com/api/oauth/usage', {
    Authorization: 'Bearer $TOKEN$',
    'anthropic-beta': 'oauth-2025-04-20',
    Accept: 'application/json',
  });
}

async function getKimiQuota(authIndex) {
  return apiCall(authIndex, 'GET', 'https://api.kimi.com/coding/v1/usages', {
    Authorization: 'Bearer $TOKEN$',
  });
}

async function getXaiQuota(authIndex) {
  return apiCall(authIndex, 'GET', 'https://cli-chat-proxy.grok.com/v1/billing', {
    Authorization: 'Bearer $TOKEN$',
    'x-xai-token-auth': 'xai-grok-cli',
    'x-grok-client-version': '0.2.91',
    'user-agent': 'grok-pager/0.2.91 grok-shell/0.2.91 (macos; aarch64)',
  });
}

async function getAntigravityQuota(file, authIndex) {
  let projectId =
    file.project_id ||
    file.projectId ||
    file.metadata?.project_id ||
    file.metadata?.projectId ||
    file.attributes?.project_id ||
    file.attributes?.projectId ||
    file.attributes?.gemini_virtual_project;

  if (!projectId) {
    // Если проект не найден в метаданных, скачиваем сам файл
    const res = await fetch(
      `${API_URL}/v0/management/auth-files/download?name=${encodeURIComponent(file.name)}`,
      { headers }
    );
    if (res.ok) {
      const fileContent = await res.json();
      projectId =
        fileContent.project_id ||
        fileContent.projectId ||
        fileContent.installed?.project_id ||
        fileContent.web?.project_id;
    }
  }

  if (!projectId) {
    throw new Error('Не удалось найти Project ID для Antigravity');
  }

  return apiCall(
    authIndex,
    'POST',
    'https://daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary',
    {
      Authorization: 'Bearer $TOKEN$',
      'User-Agent': 'antigravity/cli/1.0.13 (aidev_client; os_type=darwin; arch=arm64)',
    },
    JSON.stringify({ project: projectId })
  );
}

// Основная функция
async function fetchAllQuotas() {
  console.error(`Подключение к ${API_URL}...`);
  const authFilesRes = await fetch(`${API_URL}/v0/management/auth-files`, { headers });
  
  if (!authFilesRes.ok) {
    throw new Error(`Не удалось получить список аккаунтов: ${authFilesRes.status}`);
  }

  const authFilesData = await authFilesRes.json();
  const files = authFilesData.files || [];

  console.error(`Найдено ${files.length} файлов авторизации.\n`);

  const results = [];
  let globalMinRemaining = 1.0;
  const allRemainingFractions = [];

  function formatRefreshIn(dateStrOrSecs) {
    if (!dateStrOrSecs) return "";
    let resetDate = new Date(dateStrOrSecs);
    if (typeof dateStrOrSecs === 'number') {
      resetDate = new Date(dateStrOrSecs < 10000000000 ? dateStrOrSecs * 1000 : dateStrOrSecs);
    }
    const resetMs = resetDate.getTime();
    if (isNaN(resetMs)) return "";

    const nowMs = Date.now();
    const diffSecs = Math.max(0, Math.floor((resetMs - nowMs) / 1000));

    const days = Math.floor(diffSecs / 86400);
    const hours = Math.floor((diffSecs % 86400) / 3600);
    const minutes = Math.floor((diffSecs % 3600) / 60);

    if (days > 0) {
      const dayStr = `${days} ${days === 1 ? 'day' : 'days'}`;
      const hourStr = `${hours} ${hours === 1 ? 'hour' : 'hours'}`;
      return `${dayStr}, ${hourStr}`;
    } else {
      const hourStr = `${hours} ${hours === 1 ? 'hour' : 'hours'}`;
      const minStr = `${minutes} ${minutes === 1 ? 'minute' : 'minutes'}`;
      return `${hourStr}, ${minStr}`;
    }
  }

  for (const file of files) {
    const type = file.type || file.provider;
    const authIndex = file.auth_index || file.authIndex;

    // Пропускаем выключенные или неактуальные файлы
    if (file.disabled || file.runtime_only || file.runtimeOnly || !authIndex) {
      continue;
    }

    try {
      let quotaInfo = null;

      if (type === 'codex') {
        quotaInfo = await getCodexQuota(authIndex);
      } else if (type === 'claude') {
        quotaInfo = await getClaudeQuota(authIndex);
      } else if (type === 'antigravity') {
        quotaInfo = await getAntigravityQuota(file, authIndex);
      } else if (type === 'kimi') {
        quotaInfo = await getKimiQuota(authIndex);
      } else if (type === 'xai') {
        quotaInfo = await getXaiQuota(authIndex);
      } else {
        console.error(`[ПРОПУСК] ${file.name} (провайдер ${type} не поддерживается скриптом)`);
        continue;
      }

      let localMinRemaining = null;
      let accountGroups = [];
      try {
        if (type === 'antigravity' && quotaInfo.groups) {
          let min = 1.0;
          for (const group of quotaInfo.groups) {
            let items = [];
            for (const bucket of group.buckets || []) {
              if (typeof bucket.remainingFraction === 'number') {
                allRemainingFractions.push(bucket.remainingFraction);
                if (bucket.remainingFraction < min) min = bucket.remainingFraction;
                items.push({
                  label: bucket.displayName || bucket.bucketId,
                  val: (bucket.remainingFraction * 100).toFixed(2) + '%',
                  resetTime: formatRefreshIn(bucket.resetTime)
                });
              }
            }
            if (items.length > 0) {
              accountGroups.push({ name: group.displayName || 'Limits', items });
            }
          }
          localMinRemaining = min;
        } else if (type === 'codex' && quotaInfo.rate_limit?.primary_window) {
          const used = quotaInfo.rate_limit.primary_window.used_percent;
          if (typeof used === 'number') {
            localMinRemaining = Math.max(0, 1 - (used / 100));
            allRemainingFractions.push(localMinRemaining);
            accountGroups.push({
              name: 'Codex Limit',
              items: [{
                label: 'Primary Window',
                val: (localMinRemaining * 100).toFixed(2) + '%',
                resetTime: formatRefreshIn(quotaInfo.rate_limit.primary_window.reset_at)
              }]
            });
          }
        }
      } catch (e) {}

      if (localMinRemaining !== null && localMinRemaining < globalMinRemaining) {
        globalMinRemaining = localMinRemaining;
      }

      results.push({
        name: file.name,
        type,
        groups: accountGroups,
        minRemaining: localMinRemaining
      });
      console.error(`[УСПЕХ] ${file.name} (${type})`);
    } catch (err) {
      console.error(`[ОШИБКА] ${file.name} (${type}):`, err.message);
    }
  }

  // Вывод чистого JSON в stdout
  const globalAvgRemaining = allRemainingFractions.length > 0
    ? allRemainingFractions.reduce((sum, val) => sum + val, 0) / allRemainingFractions.length
    : 1.0;

  const now = new Date();
  const timeString = now.toLocaleTimeString('ru-RU', { hour: '2-digit', minute: '2-digit' });
  const day = String(now.getDate()).padStart(2, '0');
  const month = String(now.getMonth() + 1).padStart(2, '0');
  const year = now.getFullYear();
  const dateString = `${day}/${month}/${year}`;

  const output = {
    quotas: results,
    minRemaining: globalMinRemaining,
    avgRemaining: globalAvgRemaining,
    lastUpdated: `${timeString} • ${dateString}`
  };
  console.log(JSON.stringify(output));
}

fetchAllQuotas().catch((err) => {
  console.error('Критическая ошибка:', err.message);
  process.exit(1);
});
