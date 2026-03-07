Пользователь вызвал `/pipeline`. Запусти полный автоматический конвейер.

Задача: $ARGUMENTS

## ДЕЙСТВИЕ — ОДНА КОМАНДА

```powershell
powershell -NoProfile -File scripts\Invoke-Pipeline.ps1 -Task "$ARGUMENTS"
```

Pipeline автоматически:
1. **Проверит** доступность инструментов (`Test-Tools.ps1`)
2. **Определит режим** (research/code/review) по ключевым словам задачи
3. **Gemini** → исследование / анализ контекста (если нужен)
4. **Codex** → имплементация кода
5. **Mods** → ревью и исправление
6. Сохранит все промежуточные результаты в `$env:TEMP\pipeline-<timestamp>\`

## ПОСЛЕ PIPELINE

Прочитай итоговый файл (путь будет в строке "FINAL OUTPUT:") и примени через Edit tool.

## ОПЦИИ

```powershell
# Принудительный режим
powershell -File scripts\Invoke-Pipeline.ps1 -Task "$ARGUMENTS" -Mode research
powershell -File scripts\Invoke-Pipeline.ps1 -Task "$ARGUMENTS" -Mode code
powershell -File scripts\Invoke-Pipeline.ps1 -Task "$ARGUMENTS" -Mode review

# С файлом контекста
powershell -File scripts\Invoke-Pipeline.ps1 -Task "$ARGUMENTS" -ContextFile ".\src\main.py"

# Без ревью (быстрее)
powershell -File scripts\Invoke-Pipeline.ps1 -Task "$ARGUMENTS" -SkipReview
```
