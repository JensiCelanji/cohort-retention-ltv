-- Analysis queries for the cohort retention project
-- Run each query on its own (highlight it, then press F5)


-- How many new customers never came back within 90 days?
WITH first_two AS (
    SELECT
        customer_id,
        order_date,
        LEAD(order_date) OVER (PARTITION BY customer_id ORDER BY order_date) AS next_order_date,
        ROW_NUMBER()     OVER (PARTITION BY customer_id ORDER BY order_date) AS order_num
    FROM orders
)
SELECT
    COUNT(*) AS customers_evaluated,
    ROUND(AVG(CASE WHEN next_order_date IS NULL
                     OR next_order_date > order_date + INTERVAL '90 days'
                   THEN 1 ELSE 0 END) * 100, 1) AS churn_90d_pct
FROM first_two
WHERE order_num = 1
  AND order_date <= (SELECT MAX(order_date) FROM orders) - INTERVAL '90 days';


-- Do customers who buy twice in their first month stick around longer?
-- Only includes customers with a full year of history
WITH eligible AS (
    SELECT *
    FROM customers
    WHERE first_order_date <= (SELECT MAX(order_date) FROM orders) - INTERVAL '365 days'
),
flags AS (
    SELECT
        e.customer_id,
        CASE WHEN e.orders_first_30d >= 2 THEN '2+ orders in first 30 days'
             ELSE '1 order in first 30 days' END AS first_month_segment,
        MAX(CASE WHEN o.order_date >  e.first_order_date + INTERVAL '90 days'
                  AND o.order_date <= e.first_order_date + INTERVAL '365 days'
                 THEN 1 ELSE 0 END) AS retained
    FROM eligible e
    JOIN orders o USING (customer_id)
    GROUP BY e.customer_id, first_month_segment
)
SELECT
    first_month_segment,
    COUNT(*)                      AS customers,
    ROUND(AVG(retained) * 100, 1) AS retention_pct
FROM flags
GROUP BY first_month_segment;


-- How much of total revenue comes from the top 20% of customers?
-- Quintile 1 = top spenders
WITH ranked AS (
    SELECT
        customer_id,
        total_revenue,
        NTILE(5) OVER (ORDER BY total_revenue DESC) AS revenue_quintile
    FROM customers
)
SELECT
    revenue_quintile,
    COUNT(*) AS customers,
    ROUND(SUM(total_revenue)::NUMERIC, 0) AS revenue,
    ROUND((SUM(total_revenue) * 100.0 / SUM(SUM(total_revenue)) OVER ())::NUMERIC, 1)
        AS pct_of_total_revenue
FROM ranked
GROUP BY revenue_quintile
ORDER BY revenue_quintile;