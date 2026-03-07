Пользователь явно вызвал `/gemini`. Делегируй задачу Gemini CLI.

Задача: $ARGUMENTS

## ДЕЙСТВИЕ

Немедленно выполни через Bash:

```powershell
pwsh -NoProfile -File scripts\Invoke-GeminiDelegate.ps1 -Task "$ARGUMENTS"
```

Затем:
1. Прочитай файл вывода (путь будет в выводе скрипта, строка "Output saved to:")
2. Представь результат пользователю
3. Спроси: "Применить изменения через Edit tool?"

## КОГДА GEMINI ЛУЧШЕ ВСЕГО

- Контекст файлов > 50k токенов
- Анализ больших логов или кодовой базы
- Творческий поиск / brainstorm
- Веб-поиск и агрегация информации
- Сравнение множества подходов

## FALLBACK

Если Gemini недоступен (нет в PATH или нет API ключа):
```powershell
pwsh -NoProfile -File scripts\Invoke-CodexDelegate.ps1 -Task "$ARGUMENTS"
```
