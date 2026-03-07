Пользователь вызвал `/review`. Запусти Mods для ревью кода.

Аргументы: $ARGUMENTS

## ДЕЙСТВИЕ

Аргумент может быть путём к файлу или описанием. Определи:

**Если это путь к файлу** (заканчивается на .py, .ps1, .js, .ts, .go, etc.):
```powershell
pwsh -NoProfile -File scripts\Invoke-ModsReview.ps1 `
    -InputFile "$ARGUMENTS" `
    -ReviewType "full" `
    -ApplyFixes
```

**Если это описание задачи** — сначала спроси пользователя про целевой файл:
"Какой файл нужно проверить? Укажи путь."

## ТИПЫ РЕВЬЮ

Пользователь может указать тип через пробел: `/review src\auth.py security`

| Тип | Описание |
|-----|---------|
| `full` | Полное ревью (дефолт) |
| `security` | Только уязвимости |
| `bugs` | Только ошибки логики |
| `style` | Стиль и читаемость |
| `refactor` | Предложения по рефакторингу |

Пример с типом:
```powershell
pwsh -NoProfile -File scripts\Invoke-ModsReview.ps1 `
    -InputFile "src\auth.py" `
    -ReviewType "security" `
    -ApplyFixes
```

## ПОСЛЕ РЕВЬЮ

Прочитай вывод Mods и предложи применить исправления через Edit tool.
Если Mods недоступен — выполни ревью inline сам.
