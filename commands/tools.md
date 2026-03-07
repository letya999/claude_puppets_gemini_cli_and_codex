Пользователь вызвал `/tools`. Проверь доступность всех CLI инструментов.

## ДЕЙСТВИЕ

Выполни немедленно:

```powershell
powershell -NoProfile -File scripts\Test-Tools.ps1
```

Затем выведи итог в формате:

```
## Статус инструментов

| Инструмент | Статус | Путь |
|-----------|--------|------|
| Gemini CLI | ✓ / ✗ | путь или "не найден" |
| Codex CLI  | ✓ / ✗ | путь или "не найден" |
| Mods CLI   | ✓ / ✗ | путь или "не найден" |

## API Ключи
- GEMINI_API_KEY: установлен / НЕ установлен
- OPENAI_API_KEY: установлен / НЕ установлен

## Рекомендации
[инструкции по установке для недостающих инструментов]
```

## УСТАНОВКА НЕДОСТАЮЩИХ ИНСТРУМЕНТОВ

Если инструменты не найдены, предложи пользователю:

```powershell
# Gemini CLI
npm install -g @google/generative-ai-cli

# Codex CLI
npm install -g @openai/codex

# Mods CLI
winget install charmbracelet.mods

# Настройка ключей
powershell -NoProfile -File scripts\Set-DispatcherEnv.ps1 -Persist
```
