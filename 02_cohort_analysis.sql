-- 1. Clean transactions
DROP TABLE IF EXISTS transactions_clean;

CREATE TABLE transactions_clean AS
SELECT DISTINCT
    invoice,
    stock_code,
    description,
    quantity,
    invoice_date,
    price,
    CAST(customer_id AS INT) AS customer_id,
    country,
    quantity * price         AS revenue
FROM retail_raw
WHERE customer_id IS NOT NULL
  AND invoice NOT LIKE 'C%'
  AND quantity > 0
  AND price > 0;

-- 2. One row per order
DROP TABLE IF EXISTS orders;

CREATE TABLE orders AS
SELECT
    invoice,
    customer_id,
    MIN(invoice_date) AS order_date,
    MAX(country)      AS country,
    SUM(revenue)      AS order_revenue
FROM transactions_clean
GROUP BY invoice, customer_id;

-- 3. One row per customer
DROP TABLE IF EXISTS customers;

CREATE TABLE customers AS
WITH ranked AS (
    SELECT
        o.*,
        ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date) AS order_num,
        MIN(order_date) OVER (PARTITION BY customer_id)                 AS first_order_date
    FROM orders o
)
SELECT
    customer_id,
    DATE_TRUNC('month', MIN(first_order_date))::DATE AS cohort_month,
    MIN(first_order_date)                            AS first_order_date,
    MAX(country)       FILTER (WHERE order_num = 1)  AS country,
    MAX(order_revenue) FILTER (WHERE order_num = 1)  AS first_order_revenue,
    COUNT(*) FILTER (WHERE order_date < first_order_date + INTERVAL '30 days') AS orders_first_30d,
    COUNT(*)                                         AS total_orders,
    SUM(order_revenue)                               AS total_revenue
FROM ranked
GROUP BY customer_id;

-- 4. Cohort retention table
DROP TABLE IF EXISTS cohort_retention;

CREATE TABLE cohort_retention AS
WITH activity AS (
    SELECT DISTINCT
        o.customer_id,
        c.cohort_month,
        DATE_TRUNC('month', o.order_date)::DATE AS activity_month
    FROM orders o
    JOIN customers c USING (customer_id)
),
indexed AS (
    SELECT
        cohort_month,
        customer_id,
        (EXTRACT(YEAR  FROM AGE(activity_month, cohort_month)) * 12 +
         EXTRACT(MONTH FROM AGE(activity_month, cohort_month)))::INT AS months_since_first
    FROM activity
),
counts AS (
    SELECT cohort_month, months_since_first, COUNT(DISTINCT customer_id) AS active_customers
    FROM indexed
    GROUP BY cohort_month, months_since_first
)
SELECT
    cohort_month,
    months_since_first,
    active_customers,
    FIRST_VALUE(active_customers) OVER w AS cohort_size,
    ROUND(active_customers::NUMERIC / FIRST_VALUE(active_customers) OVER w, 4) AS retention_rate
FROM counts
WINDOW w AS (PARTITION BY cohort_month ORDER BY months_since_first);

-- 5. Cumulative revenue per customer by cohort
DROP TABLE IF EXISTS cohort_ltv_curve;

CREATE TABLE cohort_ltv_curve AS
WITH monthly AS (
    SELECT
        c.cohort_month,
        (EXTRACT(YEAR  FROM AGE(DATE_TRUNC('month', o.order_date)::DATE, c.cohort_month)) * 12 +
         EXTRACT(MONTH FROM AGE(DATE_TRUNC('month', o.order_date)::DATE, c.cohort_month)))::INT
                             AS months_since_first,
        SUM(o.order_revenue) AS revenue
    FROM orders o
    JOIN customers c USING (customer_id)
    GROUP BY 1, 2
),
sizes AS (
    SELECT cohort_month, COUNT(*) AS cohort_size
    FROM customers
    GROUP BY cohort_month
)
SELECT
    m.cohort_month,
    m.months_since_first,
    s.cohort_size,
    ROUND((SUM(m.revenue) OVER (PARTITION BY m.cohort_month ORDER BY m.months_since_first)
           / s.cohort_size)::NUMERIC, 2) AS cumulative_revenue_per_customer
FROM monthly m
JOIN sizes s USING (cohort_month);

-- Quick check
SELECT
    (SELECT COUNT(*) FROM retail_raw)          AS raw_rows,
    (SELECT COUNT(*) FROM transactions_clean)  AS clean_rows,
    (SELECT COUNT(*) FROM orders)              AS orders,
    (SELECT COUNT(*) FROM customers)           AS customers,
    (SELECT COUNT(DISTINCT cohort_month) FROM customers) AS cohorts;