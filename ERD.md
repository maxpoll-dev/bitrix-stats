# ERD — нормализованный слой `main`

Диаграмма «сущность-связь» по схеме из `db/init/03_schema.sql`. Центральная
сущность — `deals`; справочники (`sources`, `users`, `pipeline_stages`,
`companies`, `products`) и дочерние таблицы сделки вокруг неё.

Служебная таблица `main.rejects` (журнал отбраковки нормализации) в ERD не
показана — она не связана FK с бизнес-моделью.

```mermaid
erDiagram
    sources ||--o{ deals : "источник"
    sources ||--o{ marketing_costs : "затраты"
    users ||--o{ deals : "менеджер"
    users ||--o{ activities : "ответственный"
    users ||--o{ stage_history : "автор изменения"
    pipeline_stages ||--o{ deals : "текущая стадия"
    pipeline_stages ||--o{ stage_history : "old/new стадия"
    companies ||--o{ contacts : "сотрудники"
    companies ||--o{ deals : "клиент-компания"
    contacts ||--o{ deals : "контакт"
    deals ||--o{ deal_products : "позиции"
    products ||--o{ deal_products : "товар"
    deals ||--o{ payments : "оплаты"
    deals ||--o{ activities : "активности"
    deals ||--o{ stage_history : "история стадий"
    deals ||--o{ production_orders : "производство"
    deals ||--o{ shipments : "отгрузки"

    sources {
        text source_id PK "канонический ключ (avito, website…)"
        text name
    }
    users {
        text user_id PK
        text name
        role_enum role
        boolean active
        text department
        text email
    }
    pipeline_stages {
        text stage_id PK
        text pipeline_id
        text stage_name
        smallint sort_order
        boolean is_final
        boolean is_success
    }
    companies {
        text company_id PK
        text name
        text inn
        text city
        text industry
        timestamptz created_at
    }
    contacts {
        text contact_id PK
        text company_id FK
        text name
        text phone
        text email
        timestamptz created_at
    }
    products {
        text product_id PK
        text sku
        text name
        text category
        numeric cost_price
        boolean is_active
    }
    deals {
        text deal_id PK
        text title
        timestamptz created_at
        timestamptz updated_at
        text stage_id FK
        text manager_id FK
        text company_id FK
        text contact_id FK
        text source_id FK
        numeric expected_amount
        text currency
        timestamptz closed_at
        text lost_reason
        date custom_deadline
    }
    deal_products {
        text deal_id PK,FK
        text product_id PK,FK
        smallint quantity
        numeric unit_price
        numeric discount
    }
    payments {
        text payment_id PK
        text deal_id FK
        date payment_date
        numeric amount
        text payment_type
        text status
    }
    activities {
        text activity_id PK
        text deal_id FK
        text activity_type
        text direction
        text subject
        text responsible_user_id FK
        boolean completed
        timestamptz deadline_at
        timestamptz completed_at
    }
    stage_history {
        text event_id PK
        text deal_id FK
        text old_stage_id FK
        text new_stage_id FK
        timestamptz changed_at
        text changed_by_id FK
    }
    production_orders {
        text production_order_id PK
        text deal_id FK
        timestamptz created_at
        date planned_finish_at
        date actual_finish_at
        text status
        text workshop
    }
    shipments {
        text shipment_id PK
        text deal_id FK
        date planned_date
        date actual_date
        text status
    }
    marketing_costs {
        bigint cost_id PK
        date cost_date
        text source_id FK
        text campaign
        numeric cost_amount
        text currency
    }
```

## Замечания по связям

- `marketing_costs` связан со сделками **не напрямую**, а только через общий
  `source_id` (+ дату) — в исходных данных FK на сделку нет.
- `deal_products` — связь M:N между `deals` и `products` с составным PK
  `(deal_id, product_id)`.
- `stage_history.old_stage_id` / `new_stage_id` — обе ссылки на `pipeline_stages`
  (история переходов по воронке).
- Все FK нормализованного слоя жёсткие; битые ссылки из raw отсеяны на этапе
  `04_normalize.sql` (см. `main.rejects`).