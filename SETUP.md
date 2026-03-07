# SETUP — Как работает система и как настроить цепочку

---

## КАК ЭТО РАБОТАЕТ: один терминал, никаких доп. окон

```
Ты пишешь задачу в Claude Code
        │
        ▼
[ХOOK: UserPromptSubmit]  ← on-prompt.ps1 срабатывает ДО того как Claude отвечает
        │  Выводит в Claude: "ОБЯЗАТЕЛЬНО: напиши план, потом запусти цепочку"
        ▼
[Claude читает инструкцию → пишет план]
        │
        ▼
[Claude вызывает Bash tool]  ← Claude запускает subprocess из СВОЕГО же терминала
        │  pwsh -File scripts\Invoke-Chain.ps1 -Task "..."
        ▼
[ХOOK: PreToolUse / Bash]  ← pre-bash.ps1 проверяет что запускается перед выполнением
        │
        ▼
[Invoke-Chain.ps1 → Invoke-Agent.ps1 → Invoke-GeminiAgent.ps1]
        │  внутри: $prompt | gemini --model gemini-2.5-pro
        │  gemini отвечает → сохраняется в $env:TEMP\chain-XXXXXX\step-1-gemini.txt
        ▼
[Bash tool возвращает вывод Claude]
        │
        ▼
[Claude читает вывод → применяет изменения через Edit tool]
```

**Ключевое:** всё в одном терминале Claude Code. `gemini` и `codex` — это просто CLI-программы,
запускаемые как subprocess через `Bash` tool. Никаких дополнительных окон не нужно.

**Хуки — что они делают:**
- `UserPromptSubmit` → срабатывает перед каждым ответом Claude. Инжектирует инструкцию.
- `PreToolUse → Bash` → срабатывает перед каждым вызовом Bash tool. Проверяет/предупреждает.

---

## ПРОСТЕЙШАЯ ЦЕПОЧКА: Claude план → Gemini выполняет

### Шаг 1 — Установи Gemini CLI

```powershell
# Вариант A: через npm
npm install -g @google/generative-ai-cli

# Вариант B: через winget
winget install Google.GeminiCLI

# Проверка:
gemini --version
```

### Шаг 2 — Установи API ключ Gemini

```powershell
# На текущую сессию:
$env:GEMINI_API_KEY = "AIza..."

# Постоянно (в профиль PowerShell):
[System.Environment]::SetEnvironmentVariable("GEMINI_API_KEY", "AIza...", "User")

# Или через скрипт:
pwsh -File scripts\Set-DispatcherEnv.ps1 -Persist
```

### Шаг 3 — Настрой цепочку в конфиге

Открой `.claude/dispatcher.config.json` и поставь минимальную цепочку:

```json
{
  "chain": [
    {
      "agent": "gemini",
      "role": "implementer",
      "description": "Gemini implements what Claude planned"
    }
  ],

  "gemini": {
    "model": "gemini-2.5-pro",
    "retries": 1
  }
}
```

Или цепочку с исследованием → реализацией:

```json
{
  "chain": [
    { "agent": "gemini", "role": "researcher",  "description": "Research best practices" },
    { "agent": "gemini", "role": "implementer", "description": "Implement based on research" }
  ],
  "gemini": { "model": "gemini-2.5-pro" }
}
```

### Шаг 4 — Убедись что хуки включены

Файл `.claude/settings.json` уже настроен правильно:

```json
{
  "hooks": {
    "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "pwsh -NoProfile -NonInteractive -File .claude/hooks/on-prompt.ps1" }] }],
    "PreToolUse":       [{ "matcher": "Bash", "hooks": [{ "type": "command", "command": "pwsh -NoProfile -NonInteractive -File .claude/hooks/pre-bash.ps1" }] }]
  },
  "permissions": {
    "allow": ["Bash(pwsh*)", "Bash(gemini*)", "Bash(codex*)", "Bash(mods*)"]
  }
}
```

Если хуки не работают — убедись что `.claude/settings.json` в корне репозитория (где запущен `claude`).

### Шаг 5 — Проверь работоспособность

```powershell
# Полная диагностика (без API вызовов):
pwsh -File scripts\Test-Chain.ps1

# Dry-run цепочки (без API вызовов):
pwsh -File scripts\Invoke-Chain.ps1 -Task "напиши функцию hello world" -DryRun

# Реальный тест:
pwsh -File scripts\Invoke-Chain.ps1 -Task "напиши функцию для валидации email на Python"
```

### Шаг 6 — Запусти Claude Code и дай задачу

```bash
claude  # запускаешь из папки проекта (где лежит .claude/)
```

В Claude Code пишешь задачу обычным текстом. Хук сработает автоматически.

---

## ЧТО ПРОИСХОДИТ КОГДА ТЫ ПИШЕШЬ ЗАДАЧУ

```
Ты: "напиши FastAPI endpoint для регистрации пользователя"

  [on-prompt.ps1 срабатывает]
  Выводит Claude:
    ┌─────────────────────────────────────────────────────────────┐
    │ DISPATCHER - MANDATORY INSTRUCTION                          │
    │ Active chain: gemini:researcher -> gemini:implementer       │
    │                                                             │
    │ STEP 1 - Write PLAN                                         │
    │ STEP 2 - Run: pwsh -File scripts\Invoke-Chain.ps1 -Task ... │
    └─────────────────────────────────────────────────────────────┘

Claude пишет:
  ## ПЛАН
  Задача: FastAPI endpoint для регистрации
  Цепочка: gemini:researcher → gemini:implementer
  Шаги:
  1. Gemini исследует best practices FastAPI регистрации → researcher
  2. Gemini реализует endpoint → implementer

  [Claude вызывает Bash tool]:
  pwsh -NoProfile -File scripts\Invoke-Chain.ps1 -Task "напиши FastAPI endpoint..."

  [Invoke-Chain.ps1 запускает Gemini]:
  $prompt | gemini --model gemini-2.5-pro

  [Gemini возвращает код → сохраняется в temp файл]
  [Bash tool показывает вывод Claude]

Claude применяет: Edit tool → создаёт/изменяет файлы
```

---

## ПРЯМОЕ ДЕЛЕГИРОВАНИЕ (без скриптов цепочки)

Можно делегировать и напрямую, без всей системы скриптов.
Claude Code делает это через Bash tool так же как в твоём примере:

**PowerShell Here-String (эквивалент bash heredoc):**
```powershell
# В Bash tool Claude пишет:
$prompt = @"
Task: implement a FastAPI endpoint for user registration
Requirements:
- JWT authentication
- Pydantic validation
- Return user object without password

Output only the Python code.
"@

$prompt | gemini --model gemini-2.5-pro | Tee-Object -FilePath $env:TEMP\gemini-out.txt
Get-Content $env:TEMP\gemini-out.txt
```

**Для этого паттерна** (без хуков и цепочки) просто напиши в `CLAUDE.md`:
```markdown
Всегда делегируй реализацию через Bash tool:
- Анализ/research → gemini <<'эот'
- Код → codex exec "..."
Никогда не пиши код сам.
```

---

## ТАБЛИЦА: какой подход когда использовать

| Подход | Когда | Команда |
|--------|-------|---------|
| **Автоматическая цепочка** (текущая система) | Стандартные задачи, конфигурируется в json | Хуки делают это сами |
| **Ручной запуск цепочки** | Один конкретный шаг | `pwsh -File scripts\Invoke-Chain.ps1 -Task "..."` |
| **Прямой вызов агента** | Только Gemini или только Codex | `pwsh -File scripts\agents\Invoke-GeminiAgent.ps1 ...` |
| **Прямой Bash вызов** | Без скриптов, минималистично | `$prompt \| gemini` в Bash tool |

---

## ПЕРЕКЛЮЧЕНИЕ ЦЕПОЧКИ

Весь смысл системы — менять цепочку только в `dispatcher.config.json`:

```json
// Только Gemini (исследование + реализация):
"chain": [
  { "agent": "gemini", "role": "researcher" },
  { "agent": "gemini", "role": "implementer" }
]

// Claude план → Gemini реализует:
"chain": [
  { "agent": "gemini", "role": "implementer" }
]
// (Claude ВСЕГДА пишет план сам — это до запуска цепочки)

// Полный pipeline:
"chain": [
  { "agent": "gemini", "role": "researcher" },
  { "agent": "claude", "role": "implementation-planner" },
  { "agent": "codex",  "role": "implementer" },
  { "agent": "gemini", "role": "reviewer" }
]

// Codex + проверка Mods:
"chain": [
  { "agent": "codex", "role": "implementer" },
  { "agent": "mods",  "role": "reviewer" }
]
```

---

## ДОБАВИТЬ НОВЫЙ АГЕНТ (расширение)

1. Создай файл `scripts/agents/Invoke-<Имя>Agent.ps1` (скопируй `Invoke-GeminiAgent.ps1` как шаблон)
2. Измени внутри: имя CLI-команды, параметры, способ передачи промпта
3. Используй в конфиге: `{ "agent": "<имя>", "role": "..." }`

Никаких изменений в `Invoke-Chain.ps1` или `Invoke-Agent.ps1` не нужно.

---

## ДОБАВИТЬ НОВУЮ РОЛЬ

1. Создай файл `.claude/roles/<роль>.md`
2. Напиши в нём системный промпт для этой роли
3. Используй в конфиге: `{ "agent": "gemini", "role": "<роль>" }`

---

## БЫСТРАЯ ДИАГНОСТИКА ПРОБЛЕМ

```powershell
# Хук не срабатывает?
# Проверь: claude запущен из папки где лежит .claude/settings.json
ls .claude\settings.json

# gemini не найден?
npm install -g @google/generative-ai-cli
# или добавь node_modules/.bin в PATH

# Нет прав на .ps1?
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned

# Посмотреть вывод последней сессии:
Get-ChildItem $env:TEMP\chain-* | Sort-Object LastWriteTime -Descending | Select-Object -First 1 | Get-ChildItem

# Полная диагностика:
pwsh -File scripts\Test-Chain.ps1
```
