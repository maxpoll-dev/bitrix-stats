-- Импорт CSV из папки data в raw-слой.
-- Предполагается, что ./data смонтирована в контейнер как /data
-- (docker-compose: volumes: ./data:/data:ro). Имена таблиц = имена файлов.

COPY raw.deals             FROM '/data/deals.csv'             WITH (FORMAT csv, HEADER true);
COPY raw.deal_products     FROM '/data/deal_products.csv'     WITH (FORMAT csv, HEADER true);
COPY raw.products          FROM '/data/products.csv'          WITH (FORMAT csv, HEADER true);
COPY raw.payments          FROM '/data/payments.csv'          WITH (FORMAT csv, HEADER true);
COPY raw.companies         FROM '/data/companies.csv'         WITH (FORMAT csv, HEADER true);
COPY raw.contacts          FROM '/data/contacts.csv'          WITH (FORMAT csv, HEADER true);
COPY raw.users             FROM '/data/users.csv'             WITH (FORMAT csv, HEADER true);
COPY raw.pipeline_stages   FROM '/data/pipeline_stages.csv'   WITH (FORMAT csv, HEADER true);
COPY raw.stage_history     FROM '/data/stage_history.csv'     WITH (FORMAT csv, HEADER true);
COPY raw.activities        FROM '/data/activities.csv'        WITH (FORMAT csv, HEADER true);
COPY raw.production_orders FROM '/data/production_orders.csv' WITH (FORMAT csv, HEADER true);
COPY raw.shipments         FROM '/data/shipments.csv'         WITH (FORMAT csv, HEADER true);
COPY raw.marketing_costs   FROM '/data/marketing_costs.csv'   WITH (FORMAT csv, HEADER true);