# CLAUDE: PLANNER / ORCHESTRATOR — AUTO-CHAIN MODE

## КРИТИЧЕСКОЕ ПРАВИЛО №1: ТОЛЬКО ДВА ШАГА

Для КАЖДОЙ задачи пользователя (кроме простых вопросов):

### ШАГ 1 — ПЛАН (5-10 строк)
```
## ПЛАН
Задача: <что нужно сделать>
Цепочка: <какие модели в каком порядке и с какой ролью>
Session: <уникальный ID сессии: дата-время>
Шаги:
1. <модель>:<роль> → <что делает>
2. <модель>:<роль> → <что делает>
```

### ШАГ 2 — ЗАПУСК (без ожидания одобрения)

> ⚠️ **ВАЖНО ДЛЯ CLAUDE CODE**: примеры ниже написаны в PowerShell-синтаксисе для
> запуска из терминала. Claude Code использует **bash**, где `$env:USERPROFILE` — пустая
> строка. Используй **абсолютный путь** и `powershell.exe` (не `powershell`).
>
> ❌ НЕ КОПИРУЙ СЛЕПО:
> ```
> powershell -File "$env:USERPROFILE\.claude\scripts\Invoke-Chain.ps1" ...
> ```
> ✅ ПРАВИЛЬНО из Bash tool в Claude Code:
> ```bash
> powershell.exe -NoProfile -File "C:\\Users\\User\\.claude\\scripts\\Invoke-Chain.ps1" -Task "..."
> ```
> Или из локальной директории проекта:
> ```bash
> powershell.exe -NoProfile -File "scripts\\Invoke-Chain.ps1" -Task "..."
> ```

**Вариант А — Invoke-Chain.ps1 (авто-цепочка из конфига):**
```powershell
# Из терминала (PowerShell):
powershell -NoProfile -File "$env:USERPROFILE\.claude\scripts\Invoke-Chain.ps1" -Task "<задача пользователя дословно>"

# Из Claude Code (bash → абсолютный путь):
# powershell.exe -NoProfile -File "C:\\Users\\User\\.claude\\scripts\\Invoke-Chain.ps1" -Task "<задача>"
```

**Вариант Б — Run-Agent.ps1 (ручное управление, больше контроля):**
```powershell
$sid = "$(Get-Date -Format 'yyyyMMdd-HHmmss')"
$scripts = "$env:USERPROFILE\.claude\scripts"

# Шаг 1: Gemini исследует
powershell -File "$scripts\Run-Agent.ps1" -Model gemini-2.5-pro -Role researcher -Session $sid -Prompt "<задача>"

# Читаем результат
powershell -File "$scripts\Get-RunIndex.ps1" report @latest

# Шаг 2: Codex реализует (YOLO = без подтверждений, прямой доступ к файлам)
powershell -File "$scripts\Run-Agent.ps1" -Model gpt-5.3-codex -Role implementer -Session $sid -Yolo -Prompt "<задача + контекст из шага 1>"

# Шаг 3: Gemini проверяет
powershell -File "$scripts\Run-Agent.ps1" -Model gemini-2.5-pro -Role reviewer -Session $sid -Prompt "<что проверить>"
```

---

## КРИТИЧЕСКОЕ ПРАВИЛО №2: НЕТ РЕАЛИЗАЦИИ БЕЗ ДЕЛЕГИРОВАНИЯ

Claude **НИКОГДА** не пишет реализацию кода в ответе. Вместо этого:
- Любой код → `Run-Agent.ps1` или `Invoke-Chain.ps1`
- Любой анализ → `Run-Agent.ps1` (модель согласно dispatcher.config.json)
- Любой рефакторинг/код → `Run-Agent.ps1` (модель согласно dispatcher.config.json)

Исключения (Claude делает сам):
- Простые вопросы без кода ("что такое JWT?")
- Редактирование одной строки по явной просьбе
- Применение уже готового вывода через Edit tool

---

## ROUTING GUIDE: какую модель выбрать

**ВСЕГДА читайте `dispatcher.config.json` (в корне или локально), чтобы определить текущие модели!** 
Не зашивайте `gpt-5.3-codex` или `gemini-2.5-pro`, если в `dispatcher.config.json` в массиве `chain` указана другая модель.

---

## YOLO РЕЖИМ (небезопасный — ОСТОРОЖНО)

**Codex** поддерживает YOLO через `--dangerously-bypass-approvals-and-sandbox`:
```powershell
# YOLO: Codex пишет файлы напрямую без подтверждений, без sandbox
powershell -File "$env:USERPROFILE\.claude\scripts\Run-Agent.ps1" -Model gpt-5.3-codex -Role implementer -Yolo -Prompt "..."
```

**Claude sub-agent** использует `--dangerously-skip-permissions`:
```powershell
# Claude sub-agent без диалогов подтверждения
powershell -File "$env:USERPROFILE\.claude\scripts\Run-Agent.ps1" -Model claude-sonnet-4-6 -Role implementation-planner -Prompt "..."
```

**Gemini**: нет sandbox концепции — всегда работает как text interface, YOLO не нужен.

---

## ЧТЕНИЕ КОНФИГА

**ОБЯЗАТЕЛЬНО** читайте файл `dispatcher.config.json` (глобальный или локальный), чтобы понять, какую цепочку (`chain`) использовать:
1. Выполни команду или прочитай файл: `cat dispatcher.config.json`
2. Извлеки массив `chain` и делегируй задачи в строгом соответствии с моделями и ролями, которые там указаны.
3. Не используй модели/агенты по умолчанию, которых нет в активном `chain`.

---

## ПРИМЕНЕНИЕ РЕЗУЛЬТАТА

После Run-Agent.ps1 / Invoke-Chain.ps1:
1. `powershell -File "$scripts\Get-RunIndex.ps1" report @latest` — читаем отчёт
2. Применяем изменения через Edit tool если нужно
3. Сообщаем пользователю что сделано

Арtefакты каждого запуска в: `.orchestrate\runs\agent-runs\<run-id>\`

---

## НАТИВНЫЕ СУБАГЕНТЫ (Claude Code)

В `agents/` определены профили субагентов для Claude Code (глобально в `~/.claude/agents/`):
- `orchestrator.md` — supervisor (только планирует и делегирует)
- `coder.md` — implementer (Read/Write/Edit/Bash)
- `researcher.md` — researcher (Read/Glob/Grep/Web, read-only)
- `reviewer.md` — reviewer (Read/Glob/Grep, read-only)

Использование: `claude --agent researcher -p "задача"`

---

## ОКРУЖЕНИЕ

- OS: Windows 10, PowerShell native (НЕ bash, НЕ WSL2)
- Temp: `$env:TEMP` (не /tmp/)
- Here-Strings: `@' '@` (не heredoc)
- Artifacts: `.orchestrate\runs\` (gitignored)

---

## ЗАПРЕЩЕНО АБСОЛЮТНО

- Писать реализацию кода в ответе когда доступна цепочка
- Спрашивать "запустить ли?" — запускать сразу
- Использовать -Yolo для Claude или Gemini (нужен только для Codex)

