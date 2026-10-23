# E-commerce SQL Analytics — Star Schema & Business Queries

![Python 3.9+](https://img.shields.io/badge/python-3.9+-blue.svg)
![SQLite](https://img.shields.io/badge/database-SQLite-003B57.svg)
![SQL](https://img.shields.io/badge/SQL-CTEs%20%7C%20Window%20Functions-green.svg)

> **Companion project:** [E-commerce Sales & Ad Spend Dashboard](https://github.com/MashhudFarah/ecommerce-sales-analytics) — same sample dataset, cleaned and visualized in Excel and Streamlit.
> 
> **Data Source:** This project uses a synthetic sample dataset to demonstrate SQL modeling and business analysis.

## Definitions

This project and the companion dashboard project analyze the same sample e-commerce dataset. 

- **Gross revenue** — sum of `revenue_usd` across all orders, including cancelled and returned. Total: **$1.39M**.
- **Fulfilled revenue** — sum of `revenue_usd` where `order_status = 'Delivered'`. Excludes cancelled and returned orders. Total: **$767K**.
- **Lost revenue** — sum of `revenue_usd` for cancelled and returned orders. Total: **$252K**.
- **Ad spend** — total advertising cost from the sample ad-spend file (~$375K).
- **ROAS** — fulfilled revenue ÷ ad spend. Uses fulfilled revenue so cancelled orders do not inflate return on ad spend.
- **Revenue after ad spend** — fulfilled revenue − ad spend (~$392K on the sample). This is **not profit**; it excludes cost of goods, shipping, and platform fees.

Cancelled and returned orders are counted in gross revenue but excluded from fulfilled revenue, ROAS, cohort retention, RFM, and repeat-purchase metrics.

## What it does

Takes 12,180 raw, genuinely messy order rows — five different date formats, 20 spellings of 6 payment methods, 24 spellings of 7 countries, 180 exact duplicates — and turns them into a clean star-schema warehouse in SQLite, then answers 11 business questions against it with SQL alone.

sql-project/
├── messy_data.csv        # raw orders export (source, untouched)
├── ad_spend.csv           # raw daily ad spend by category (source, untouched)
├── schema.sql              # star-schema DDL (3 dimensions, 2 facts)
├── etl.py                   # cleans the raw CSVs, loads ecommerce.db
├── queries.sql                # 11 documented analytical queries
├── run_queries.py              # executes queries.sql, prints results
├── query_results.md             # full output of every query
├── ecommerce.db                  # the built warehouse (tracked)
└── requirements.txt

## Data quality issues handled in the ETL

| Issue | Example | Fix |
|---|---|---|
| 5 date formats mixed in one column | `09-23-2025`, `2025/07/27`, `10 Apr 2026` | Multi-format parser, tries each format in priority order |
| 20 spellings of 6 payment methods | `NetBanking`, `net banking`, `Net Banking` | Lookup-table normalization |
| 24 spellings of 7 countries | `UK`, `U.K.`, `uk`, `United Kingdom` | Lookup-table normalization |
| 180 exact duplicate rows | same order appearing twice | Dropped before load |
| Nulls in discount / rating / city | ~6,150 missing ratings | Explicit fill rules, not silently dropped |

## Schema

Star schema: one grain-of-transaction fact table, one marketing fact table, three conformed dimensions so both facts join cleanly on `date_id`.

erDiagram
    dim_customers ||--o{ fact_orders : places
    dim_products  ||--o{ fact_orders : contains
    dim_date      ||--o{ fact_orders : "occurs on"
    dim_date      ||--o{ fact_ad_spend : "occurs on"

    dim_customers {
        string customer_id PK
        string country
        string city
        string first_order_date
    }
    dim_products {
        int product_id PK
        string category
        string product_name
    }
    dim_date {
        string date_id PK
        int year
        int month
        string year_month
    }
    fact_orders {
        string order_id PK
        string customer_id FK
        int product_id FK
        string date_id FK
        int quantity
        real revenue_usd
        string payment_method
        string order_status
    }
    fact_ad_spend {
        int ad_spend_id PK
        string date_id FK
        string category
        real ad_spend_usd
    }


## Business questions answered

1. Headline KPIs — total/fulfilled/lost revenue, AOV, cancel+return rate
2. Monthly revenue trend with month-over-month growth (`LAG`)
3. Running cumulative revenue (`SUM() OVER`)
4. Revenue, ad spend, and ROAS by category (two CTEs joined)
5. RFM segmentation — recency/frequency/monetary scored with `NTILE(4)`
6. Monthly cohort retention (month 0–3) per signup cohort
7. Repeat purchase rate
8. Top 10 customers by lifetime value (`DENSE_RANK`)
9. Revenue, AOV, and cancellation rate by country
10. Payment method mix and AOV
11. Cancellation/return rate by category

## Sample results

**Headline KPIs** — 12,000 clean orders, $1.39M total revenue, $767K fulfilled, $116 AOV, 18.4% cancel/return rate.

**RFM segments**
*(Note: Update these numbers after you push the fixed `NTILE` query)*

| Segment | Customers | Avg value | Avg recency (days) |
|---|---|---|---|
| Champions | 484 | $413.57 | ~50 |
| At Risk (high value) | 783 | $479.97 | ~115 |
| Needs Attention | 209 | $122.23 | ~212 |
| Lost / Churned | 549 | $114.24 | ~441 |
| New / Promising | 929 | $110.71 | ~560 |

**Category ROAS** — Electronics leads at 2.35x, Grocery trails at 1.72x. Full ranking in `query_results.md`.

**Retention** — every cohort loses roughly 90%+ of customers by month 1 and flattens out from there; repeat purchase rate across all customers is 66.8%, so the story isn't "no one comes back," it's "most who come back do so much later than 30 days" — worth checking against actual email/remarketing cadence.

**Country** — Australia leads on revenue ($367.8K); the US has the lowest cancel/return rate (17.6%) despite the smallest volume.

Full output for all 11 queries — every row, not just the highlights — is in [`query_results.md`](query_results.md).

## Run it yourself

pip install -r requirements.txt
python3 etl.py            # rebuilds ecommerce.db from the raw CSVs
python3 run_queries.py    # runs all 11 queries, regenerates query_results.md

Or open `ecommerce.db` directly in any SQLite browser (e.g. DB Browser for SQLite) and run `queries.sql` query-by-query.

## Notes

- All window functions and CTEs are standard ANSI SQL — they run unmodified on SQLite 3.25+, PostgreSQL, and MySQL 8+.
- Uses the same source data as the [E-commerce Sales & Ad Spend Dashboard](https://github.com/MashhudFarah/ecommerce-sales-analytics); this repo is the SQL/data-warehousing layer, that one is the pandas/Excel-dashboard layer.
