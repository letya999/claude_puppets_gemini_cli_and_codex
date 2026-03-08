# Claude Dispatcher v2: Setup & Architecture

Инструмент для оркестрации CLI-агентов (Claude Code, Gemini CLI, Codex CLI) в среде Windows 11. 

---

## 1. Режимы работы (Scope)

Режим определяет, **где хранятся настройки** и **на какие проекты** они влияют.

### Режим: Global (Глобальный)
Проект устанавливается в вашу домашнюю директорию и работает как «надстройка» над Claude Code для всех папок на компьютере.
- **Путь:** `%USERPROFILE%\.claude\`
- **Файлы:** Настройки и хуки применяются ко всем вызовам `claude`.

### Режим: Local (Проектный)
Настройки изолированы внутри конкретного Git-репозитория.
- **Путь:** `.claude\` в корне вашего проекта.
- **Файлы:** Позволяет создавать уникальные цепочки инструментов (Flows) для специфических задач проекта.

---

## 2. Типы интеграции (Formats)

Тип определяет, **как именно** Dispatcher встраивается в рабочий процесс Claude Code.

1.  **Directives (`directives`)**: Инструкции в файле `CLAUDE.md`. Claude Code читает их и понимает, что он — «Оркестратор», который должен вызывать `Invoke-Flow.ps1` вместо прямого редактирования файлов.
2.  **Hooks (`hooks`)**: Автоматический перехват ввода пользователя. Перед тем как Claude выполнит задачу, Dispatcher может вмешаться (только в Global режиме через `settings.json`).
3.  **Skills (`skills`)**: Добавление новых JavaScript-функций в Claude Code, которые вызывают PowerShell-скрипты Dispatcher.
4.  **Sub-agents (`subagents`)**: Использование набора системных промптов (roles) для разделения ответственности (например, один агент только пишет тесты, другой только рефакторит).

---

## 3. Управление настройками (`project.settings.json`)

Файл `project.settings.json` — это пульт управления Dispatcher. 

### Основные поля:
- `"mode"`: `"global"` или `"local"`.
- `"formats"`: Объект, где для каждого типа интеграции можно поставить `enabled: true` или `false`.

### Как переключать режимы (8 комбинаций):

Для быстрого переключения используйте скрипт `scripts\Switch-Mode.ps1`. Он автоматически копирует файлы и обновляет JSON.

| Задача | Команда PowerShell |
| :--- | :--- |
| **Local + Directives** | `.\scripts\Switch-Mode.ps1 -Mode Directives -Scope Local` |
| **Local + Skills** | `.\scripts\Switch-Mode.ps1 -Mode Skills -Scope Local` |
| **Local + Agents** | `.\scripts\Switch-Mode.ps1 -Mode Agents -Scope Local` |
| **Local + Hooks** | `.\scripts\Switch-Mode.ps1 -Mode Hooks -Scope Local` |
| **Global + Directives** | `.\scripts\Switch-Mode.ps1 -Mode Directives -Scope Global` |
| **Global + Skills** | `.\scripts\Switch-Mode.ps1 -Mode Skills -Scope Global` |
| **Global + Agents** | `.\scripts\Switch-Mode.ps1 -Mode Agents -Scope Global` |
| **Global + Hooks** | `.\scripts\Switch-Mode.ps1 -Mode Hooks -Scope Global` |

> **Важно:** Скрипт `Switch-Mode.ps1` работает по принципу XOR — он включает один выбранный формат и выключает остальные для чистоты эксперимента.

---

## 4. Настройка цепочек (`flow.config.json`)

Этот файл определяет, какие инструменты будут вызваны при выполнении задачи.

### Структура `flow.config.json`:
```json
{
  "defaultFlow": "standard",
  "flows": {
    "standard": {
      "steps": [
        { 
          "name": "research", 
          "tool": "gemini", 
          "role": "researcher", 
          "model": "gemini-2.0-flash" 
        },
        { 
          "name": "implement", 
          "tool": "codex", 
          "role": "implementer", 
          "yolo": true 
        }
      ]
    }
  },
  "tools": {
    "gemini": { "executable": "gemini" },
    "claude": { "executable": "claude" },
    "codex": { "executable": "codex" }
  }
}
```

### Параметры шага (Step):
- **`tool`**: `gemini`, `claude` или `codex`.
- **`role`**: Имя файла из папки `roles/` (без расширения .md). Это системный промпт для этого шага.
- **`model`**: (Опционально) Переопределение модели для конкретного шага.
- **`yolo`**: `true` — пропускать подтверждения безопасности (использовать с осторожностью!).

---

## 5. Полезные скрипты

1.  **`Invoke-Flow.ps1 -Task "текст задачи" -Flow "имя"`**
    Главный исполнитель. Вызывает цепочку инструментов, передавая контекст от одного к другому.
2.  **`Toggle-DispatcherMode.ps1 -Mode On/Off -TargetFile "путь"`**
    Включает/выключает блок инструкций Dispatcher в файле `CLAUDE.md`.
3.  **`Switch-Mode.ps1`**
    Комплексный переключатель между комбинациями (см. таблицу выше).
4.  **`Install-Dispatcher.ps1`**
    Начальная установка базовой инфраструктуры в Global или Local профиль.

---

## 6. Совместимость
- **OS:** Windows 10/11 (Native PowerShell).
- **Инструменты:** CLI-версии `claude`, `gemini`, `codex` должны быть в PATH.
