# Процесс сделки — FSM и BPM

Модель жизненного цикла сделки (`deals` + `pipeline_stages` + `stage_history`).
Стадии и флаги взяты из `pipeline_stages` (`sort_order`, `is_final`, `is_success`).

## 1. FSM — конечный автомат стадий сделки

Состояния = стадии воронки. Терминальные (`is_final`): `WON` (успех,
`is_success=true`) и `LOST`. `UNKNOWN` — служебное «карантинное» состояние для
сделок с битой/неизвестной стадией (паттерн unknown-member).

Канонический путь — линейный по `sort_order`, но в данных встречаются «перескоки»
(напр. D1001: `QUALIFICATION → PRODUCTION`), поэтому переход возможен на любую
следующую стадию, а `LOST` достижим практически из любой рабочей.

```mermaid
stateDiagram-v2
    [*] --> NEW

    NEW --> QUALIFICATION
    QUALIFICATION --> CALCULATION
    CALCULATION --> PROPOSAL
    PROPOSAL --> CONTRACT
    CONTRACT --> PRODUCTION
    PRODUCTION --> SHIPPED
    SHIPPED --> WON

    NEW --> LOST
    QUALIFICATION --> LOST
    CALCULATION --> LOST
    PROPOSAL --> LOST
    CONTRACT --> LOST
    PRODUCTION --> LOST
    SHIPPED --> LOST

    WON --> [*]
    LOST --> [*]

    state "UNKNOWN (карантин)" as UNKNOWN
    UNKNOWN --> QUALIFICATION : ручная разметка

    note right of WON
        is_final=true, is_success=true
        ожидается closed_at
    end note
    note right of LOST
        is_final=true, is_success=false
        ожидается lost_reason
    end note
```

**Инварианты (контролируются качеством данных):**
- В `WON`/`LOST` ожидается `closed_at`; нарушение (D1009 — WON без даты) пишется
  в `rejects` как warning.
- Каждый переход фиксируется строкой в `stage_history` (`old → new`, кто и когда).
- Стадия вне справочника (`WAIT_CLIENT`) → `UNKNOWN`, исходное значение в логе.

## 2. BPM — сквозной процесс обработки сделки

Дорожки: **Продажи → Производство → Логистика → Финансы**. Показаны ключевые
шаги и шлюзы решений; точки, где формируются связанные записи (`activities`,
`deal_products`, `production_orders`, `shipments`, `payments`).

```mermaid
flowchart TD
    start([Заявка из источника]) --> lead[Создание сделки: source, manager]

    subgraph SALES[Продажи]
        lead --> qual{Квалифицирована?}
        qual -- нет --> lost[(LOST: lost_reason)]
        qual -- да --> calc[Расчёт: позиции deal_products]
        calc --> prop[КП отправлено]
        prop --> deal{Согласовано?}
        deal -- нет --> lost
        deal -- да --> contract[Договор]
    end

    subgraph PROD[Производство]
        contract --> po[production_orders: план/факт]
        po --> delay{Срок > план + 5д?}
        delay -- да --> escalate[[Эскалация: задержка]]
        delay -- нет --> ready[Готово к отгрузке]
        escalate --> ready
    end

    subgraph LOG[Логистика]
        ready --> ship[shipments: planned/actual]
    end

    subgraph FIN[Финансы]
        contract -.-> prepay[Предоплата]
        ship --> invoice{Оплачено полностью?}
        prepay -.-> invoice
        invoice -- нет --> ar[(Дебиторка: остаток)]
        invoice -- да --> won[(WON: closed_at)]
        ar --> won
    end

    won --> done([Сделка закрыта])
    lost --> done

    activities[[activities: звонки/задачи/письма]] -. сопровождают .-> SALES
```

**Связь с отчётами (`reports.sql`):**
- Воронка — распределение сделок по состояниям FSM.
- Дебиторка — узел «Оплачено полностью?» (сумма − оплаты = остаток).
- Задержка производства — шлюз «Срок > план + 5д».
- Без активности N дней — отсутствие свежих `activities` на дорожке Продажи.