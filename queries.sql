-- ============================================================
-- E-commerce Analytics — Business Question Queries
-- Run against ecommerce.db (built by etl.py from schema.sql)
-- Standard ANSI SQL — window functions & CTEs run unmodified
-- on SQLite 3.25+, PostgreSQL, and MySQL 8+.
-- ============================================================


-- ------------------------------------------------------------
-- 1. Headline KPIs
-- ------------------------------------------------------------
SELECT
    COUNT(*)                                                  AS total_orders,
    ROUND(SUM(revenue_usd), 2)                                AS total_revenue_usd,
    ROUND(SUM(CASE WHEN order_status = 'Delivered'
              THEN revenue_usd ELSE 0 END), 2)                AS fulfilled_revenue_usd,
    ROUND(SUM(CASE WHEN order_status IN ('Cancelled','Returned')
              THEN revenue_usd ELSE 0 END), 2)                AS lost_revenue_usd,
    ROUND(AVG(revenue_usd), 2)                                AS avg_order_value_usd,
    ROUND(100.0 * SUM(CASE WHEN order_status IN ('Cancelled','Returned') THEN 1 ELSE 0 END)
          / COUNT(*), 2)                                      AS cancel_return_rate_pct
FROM fact_orders;


-- ------------------------------------------------------------
-- 2. Monthly revenue trend with month-over-month growth %
--    (window function: LAG)
-- ------------------------------------------------------------
WITH monthly AS (
    SELECT d.year_month,
           SUM(f.revenue_usd) AS revenue_usd
    FROM fact_orders f
    JOIN dim_date d ON f.date_id = d.date_id
    WHERE f.order_status = 'Delivered'
    GROUP BY d.year_month
)
SELECT
    year_month,
    ROUND(revenue_usd, 2) AS revenue_usd,
    ROUND(100.0 * (revenue_usd - LAG(revenue_usd) OVER (ORDER BY year_month))
          / LAG(revenue_usd) OVER (ORDER BY year_month), 2)   AS mom_growth_pct
FROM monthly
ORDER BY year_month;


-- ------------------------------------------------------------
-- 3. Running cumulative revenue by month
--    (window function: SUM() OVER with a frame)
-- ------------------------------------------------------------
WITH monthly AS (
    SELECT d.year_month, SUM(f.revenue_usd) AS revenue_usd
    FROM fact_orders f
    JOIN dim_date d ON f.date_id = d.date_id
    WHERE f.order_status = 'Delivered'
    GROUP BY d.year_month
)
SELECT
    year_month,
    ROUND(revenue_usd, 2) AS revenue_usd,
    ROUND(SUM(revenue_usd) OVER (ORDER BY year_month
          ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW), 2) AS cumulative_revenue_usd
FROM monthly
ORDER BY year_month;


-- ------------------------------------------------------------
-- 4. Category performance: revenue, ad spend, and ROAS
--    (two CTEs joined on category)
-- ------------------------------------------------------------
WITH category_revenue AS (
    SELECT p.category,
           SUM(f.revenue_usd) AS revenue_usd
    FROM fact_orders f
    JOIN dim_products p ON f.product_id = p.product_id
    WHERE f.order_status = 'Delivered'
    GROUP BY p.category
),
category_spend AS (
    SELECT category, SUM(ad_spend_usd) AS ad_spend_usd
    FROM fact_ad_spend
    GROUP BY category
)
SELECT
    r.category,
    ROUND(r.revenue_usd, 2) AS revenue_usd,
    ROUND(s.ad_spend_usd, 2) AS ad_spend_usd,
    ROUND(r.revenue_usd / s.ad_spend_usd, 2) AS roas
FROM category_revenue r
JOIN category_spend s ON r.category = s.category
ORDER BY roas DESC;


-- ------------------------------------------------------------
-- 5. RFM customer segmentation
--    (CTEs + NTILE window function to score each dimension)
-- ------------------------------------------------------------
WITH customer_orders AS (
    SELECT customer_id,
           MAX(date_id)          AS last_order_date,
           COUNT(*)              AS frequency,
           SUM(revenue_usd)      AS monetary
    FROM fact_orders
    WHERE order_status = 'Delivered'
    GROUP BY customer_id
),
scored AS (
    SELECT
        customer_id,
        CAST(julianday((SELECT MAX(date_id) FROM fact_orders)) - julianday(last_order_date) AS INT) AS recency_days,
        frequency,
        ROUND(monetary, 2) AS monetary,
        NTILE(4) OVER (ORDER BY julianday(last_order_date) ASC) AS r_score,  -- 4 = most recent
        NTILE(4) OVER (ORDER BY frequency ASC)                   AS f_score,
        NTILE(4) OVER (ORDER BY monetary ASC)                    AS m_score
    FROM customer_orders
)
SELECT
    CASE
        WHEN r_score >= 3 AND f_score >= 3 AND m_score >= 3 THEN 'Champions'
        WHEN r_score >= 3 AND f_score <= 2                  THEN 'New / Promising'
        WHEN r_score <= 2 AND f_score >= 3 AND m_score >= 3 THEN 'At Risk (high value)'
        WHEN r_score <= 2 AND f_score <= 2                  THEN 'Lost / Churned'
        ELSE 'Needs Attention'
    END AS rfm_segment,
    COUNT(*)                    AS customers,
    ROUND(AVG(monetary), 2)     AS avg_monetary_usd,
    ROUND(AVG(recency_days), 1) AS avg_recency_days
FROM scored
GROUP BY rfm_segment
ORDER BY avg_monetary_usd DESC;


-- ------------------------------------------------------------
-- 6. Monthly cohort retention
--    (CTEs: assign each customer a cohort month, measure which
--    later months they were still active in)
-- ------------------------------------------------------------
WITH first_order AS (
    SELECT customer_id, MIN(year_month) AS cohort_month
    FROM fact_orders f
    JOIN dim_date d ON f.date_id = d.date_id
    WHERE f.order_status = 'Delivered'
    GROUP BY customer_id
),
activity AS (
    SELECT DISTINCT f.customer_id, d.year_month AS order_month
    FROM fact_orders f
    JOIN dim_date d ON f.date_id = d.date_id
    WHERE f.order_status = 'Delivered'
),
cohort_activity AS (
    SELECT
        fo.cohort_month,
        (CAST(strftime('%Y', a.order_month || '-01') AS INT) - CAST(strftime('%Y', fo.cohort_month || '-01') AS INT)) * 12
        + (CAST(strftime('%m', a.order_month || '-01') AS INT) - CAST(strftime('%m', fo.cohort_month || '-01') AS INT))
            AS month_number,
        a.customer_id
    FROM first_order fo
    JOIN activity a ON fo.customer_id = a.customer_id
)
SELECT
    cohort_month,
    month_number,
    COUNT(DISTINCT customer_id) AS active_customers,
    ROUND(100.0 * COUNT(DISTINCT customer_id) /
        FIRST_VALUE(COUNT(DISTINCT customer_id)) OVER (PARTITION BY cohort_month ORDER BY month_number), 1)
        AS retention_pct
FROM cohort_activity
WHERE month_number BETWEEN 0 AND 3
GROUP BY cohort_month, month_number
ORDER BY cohort_month, month_number;


-- ------------------------------------------------------------
-- 7. Repeat purchase rate
-- ------------------------------------------------------------
WITH per_customer AS (
    SELECT customer_id, COUNT(*) AS orders
    FROM fact_orders
    WHERE order_status = 'Delivered'
    GROUP BY customer_id
)
SELECT
    COUNT(*)                                             AS total_customers,
    SUM(CASE WHEN orders > 1 THEN 1 ELSE 0 END)           AS repeat_customers,
    ROUND(100.0 * SUM(CASE WHEN orders > 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS repeat_purchase_rate_pct
FROM per_customer;


-- ------------------------------------------------------------
-- 8. Top 10 customers by lifetime value
--    (window function: DENSE_RANK)
-- ------------------------------------------------------------
WITH ltv AS (
    SELECT customer_id, SUM(revenue_usd) AS lifetime_value_usd, COUNT(*) AS orders
    FROM fact_orders
    WHERE order_status = 'Delivered'
    GROUP BY customer_id
)
SELECT
    DENSE_RANK() OVER (ORDER BY lifetime_value_usd DESC) AS ltv_rank,
    customer_id,
    orders,
    ROUND(lifetime_value_usd, 2) AS lifetime_value_usd
FROM ltv
ORDER BY ltv_rank
LIMIT 10;


-- ------------------------------------------------------------
-- 9. Country performance: revenue, AOV, cancellation rate
-- ------------------------------------------------------------
SELECT
    c.country,
    COUNT(*)                                                              AS orders,
    ROUND(SUM(f.revenue_usd), 2)                                          AS total_revenue_usd,
    ROUND(AVG(f.revenue_usd), 2)                                          AS avg_order_value_usd,
    ROUND(100.0 * SUM(CASE WHEN f.order_status IN ('Cancelled','Returned') THEN 1 ELSE 0 END)
          / COUNT(*), 2)                                                  AS cancel_return_rate_pct
FROM fact_orders f
JOIN dim_customers c ON f.customer_id = c.customer_id
GROUP BY c.country
ORDER BY total_revenue_usd DESC;


-- ------------------------------------------------------------
-- 10. Payment method mix
-- ------------------------------------------------------------
SELECT
    payment_method,
    COUNT(*)                                          AS orders,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_orders,
    ROUND(AVG(revenue_usd), 2)                         AS avg_order_value_usd
FROM fact_orders
GROUP BY payment_method
ORDER BY orders DESC;


-- ------------------------------------------------------------
-- 11. Categories with the highest cancellation / return rate
--    (an ops / product-quality signal, not just a sales one)
-- ------------------------------------------------------------
SELECT
    p.category,
    COUNT(*)                                                              AS orders,
    ROUND(100.0 * SUM(CASE WHEN f.order_status IN ('Cancelled','Returned') THEN 1 ELSE 0 END)
          / COUNT(*), 2)                                                  AS cancel_return_rate_pct
FROM fact_orders f
JOIN dim_products p ON f.product_id = p.product_id
GROUP BY p.category
ORDER BY cancel_return_rate_pct DESC;
