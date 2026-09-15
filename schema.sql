-- ============================================================
-- E-commerce Analytics Warehouse — Star Schema
-- ============================================================
-- One fact table for transactions, one for marketing spend,
-- three conformed dimensions. Classic dimensional model so
-- the same date/customer/product keys join across both facts.
-- ============================================================

PRAGMA foreign_keys = ON;

DROP TABLE IF EXISTS fact_ad_spend;
DROP TABLE IF EXISTS fact_orders;
DROP TABLE IF EXISTS dim_customers;
DROP TABLE IF EXISTS dim_products;
DROP TABLE IF EXISTS dim_date;

-- ---------------------------------------------------------
-- Dimensions
-- ---------------------------------------------------------

CREATE TABLE dim_date (
    date_id      TEXT PRIMARY KEY,   -- 'YYYY-MM-DD'
    full_date    DATE NOT NULL,
    year         INTEGER NOT NULL,
    quarter      INTEGER NOT NULL,
    month        INTEGER NOT NULL,
    month_name   TEXT NOT NULL,
    year_month   TEXT NOT NULL,      -- 'YYYY-MM', convenient for GROUP BY
    day_of_week  TEXT NOT NULL
);

CREATE TABLE dim_customers (
    customer_id     TEXT PRIMARY KEY,
    country         TEXT NOT NULL,
    city            TEXT,
    first_order_date TEXT NOT NULL
);

CREATE TABLE dim_products (
    product_id      INTEGER PRIMARY KEY,
    category        TEXT NOT NULL,
    product_name    TEXT NOT NULL,
    UNIQUE(category, product_name)
);

-- ---------------------------------------------------------
-- Facts
-- ---------------------------------------------------------

CREATE TABLE fact_orders (
    order_id          TEXT PRIMARY KEY,
    customer_id       TEXT NOT NULL REFERENCES dim_customers(customer_id),
    product_id        INTEGER NOT NULL REFERENCES dim_products(product_id),
    date_id           TEXT NOT NULL REFERENCES dim_date(date_id),
    quantity          INTEGER NOT NULL,
    unit_price_usd    REAL NOT NULL,
    discount_percent  REAL NOT NULL DEFAULT 0,
    revenue_usd       REAL NOT NULL,     -- quantity * unit_price * (1 - discount/100)
    payment_method    TEXT NOT NULL,
    order_status      TEXT NOT NULL,
    customer_rating   REAL
);

CREATE TABLE fact_ad_spend (
    ad_spend_id  INTEGER PRIMARY KEY AUTOINCREMENT,
    date_id      TEXT NOT NULL REFERENCES dim_date(date_id),
    category     TEXT NOT NULL,
    ad_spend_usd REAL NOT NULL
);

CREATE INDEX idx_orders_customer ON fact_orders(customer_id);
CREATE INDEX idx_orders_product  ON fact_orders(product_id);
CREATE INDEX idx_orders_date     ON fact_orders(date_id);
CREATE INDEX idx_adspend_date    ON fact_ad_spend(date_id);
CREATE INDEX idx_adspend_cat     ON fact_ad_spend(category);
