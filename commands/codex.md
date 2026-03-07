Пользователь явно вызвал `/codex`. Делегируй реализацию Codex CLI.

Задача: $ARGUMENTS

## ДЕЙСТВИЕ

1. Определи язык программирования из задачи (по умолчанию: python)
2. Выполни через Bash:

```powershell
powershell -NoProfile -File scripts\Invoke-CodexDelegate.ps1 `
    -Task "$ARGUMENTS" `
    -Language "python"
```

3. После получения вывода — запусти автоматическое ревью:

```powershell
# Путь к файлу вывода Codex берём из предыдущего шага
powershell -NoProfile -File scripts\Invoke-ModsReview.ps1 `
    -InputFile "<путь-из-вывода-codex>" `
    -ApplyFixes
```

4. Прочитай файл ревью и предложи применить через Edit tool

## КОГДА CODEX ЛУЧШЕ ВСЕГО

- Точная генерация кода (алгоритмы, классы, API)
- Python, JavaScript, TypeScript, Go
- Когда нужен предсказуемый, строго структурированный вывод
- Реализация по чёткому ТЗ

## ВАЖНО

НЕ пиши код сам — только делегируй в Codex, потом в Mods для ревью.
