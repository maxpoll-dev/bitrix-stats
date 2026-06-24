# bitrix-stats

Аналитический контур поверх выгрузки из CRM: `CSV → raw → нормализованный слой
(main) → SQL-отчёты`. Пайплайн загрузки/чистки — в `db/init/` (raw-схема, загрузка
CSV, нормализованная схема, нормализация с журналом отбраковки `main.rejects`).

## Проверка

### Вариант 1 — Docker (полный пайплайн с нуля)

Init-скрипты `db/init/01..04` применяются автоматически при первом старте
(raw → загрузка CSV → схема main → нормализация).

```bash
make up        # или: docker compose up -d
make down      # остановить и очистить данные (down -v)
```

Запустить отчёты:

```bash
docker exec -i postgres psql -U postgres -d crm < reports.sql
```

Подключение: БД `crm`, пользователь/пароль `postgres`, порт `5432`.

### Вариант 2 — Импорт готового дампа

Самодостаточный дамп `db/dump.sql` (схемы `raw` + `main`, данные, типы, функции,
индексы; данные как `INSERT` — подходит и для Supabase). Импорт в любой PostgreSQL 16:

```bash
psql -d <database> -f db/dump.sql
psql -d <database> -f reports.sql
```

## Диаграммы

- [ERD — нормализованный слой](ERD.md)
- [Процесс сделки: FSM + BPM](PROCESS.md)

## Артефакты

- `db/init/` — схемы и нормализация (raw → main)
- `reports.sql` — 7 аналитических отчётов
- `db/dump.sql` — полный дамп базы
- `ai-log/` - лог работы с ии