Ты — Planner/Dispatcher. Пользователь запустил `/dispatch $ARGUMENTS`.

## НЕМЕДЛЕННОЕ ДЕЙСТВИЕ

Вызови центральный роутер через Bash:

```
pwsh -NoProfile -File scripts\Invoke-Router.ps1 -Task "$ARGUMENTS"
```

Роутер сам определит нужный инструмент (Gemini/Codex/Mods) и выполнит задачу.

## ПОСЛЕ ВЫПОЛНЕНИЯ

1. Прочитай вывод роутера — там будет путь к файлу результата и сам результат (первые 100 строк)
2. Если нужно применить изменения в файлы — используй Edit tool
3. Сообщи пользователю что сделано и какой инструмент использован

## ОПЦИИ ДЛЯ ПОЛЬЗОВАТЕЛЯ

```
/dispatch <задача>                        # авто-маршрутизация
/dispatch <задача> --force gemini         # принудительно Gemini
/dispatch <задача> --force codex          # принудительно Codex
/dispatch <задача> --dry-run              # показать план без выполнения
```

Для `--force` и `--dry-run` добавь параметры в pwsh команду:
```
pwsh -File scripts\Invoke-Router.ps1 -Task "<задача>" -Force gemini
pwsh -File scripts\Invoke-Router.ps1 -Task "<задача>" -DryRun
```

## СТРОГО ЗАПРЕЩЕНО

- НЕ реализуй код сам — только вызывай Invoke-Router.ps1
- НЕ изменяй файлы без получения вывода от Codex/Mods
