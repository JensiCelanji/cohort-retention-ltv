# Customer lifetime value analysis
# Run after the SQL scripts

library(DBI)
library(RPostgres)
library(tidyverse)
library(scales)

con <- dbConnect(
  Postgres(),
  dbname   = "my_portfolio",
  host     = "localhost",
  port     = 5432,
  user     = "postgres",
  password = Sys.getenv("PG_PASSWORD"),
  bigint   = "numeric"
)

customers <- dbGetQuery(con, "SELECT * FROM customers") |> as_tibble()
orders    <- dbGetQuery(con, "SELECT customer_id, order_date, order_revenue FROM orders") |> as_tibble()
retention <- dbGetQuery(con, "SELECT * FROM cohort_retention") |> as_tibble()

data_end <- max(orders$order_date)

# Only look at customers with a full year of history so everyone is compared fairly
eligible <- customers |>
  filter(first_order_date <= data_end - days(365))

# 12-month lifetime value for each customer
ltv <- orders |>
  inner_join(eligible |> select(customer_id, first_order_date, cohort_month,
                                country, orders_first_30d, first_order_revenue),
             by = "customer_id") |>
  filter(order_date <= first_order_date + days(365)) |>
  group_by(customer_id, cohort_month, country, orders_first_30d, first_order_revenue) |>
  summarise(
    ltv_12m    = sum(order_revenue),
    orders_12m = n(),
    retained   = as.integer(any(order_date > first_order_date + days(90))),
    .groups = "drop"
  ) |>
  mutate(
    first_month_segment = if_else(orders_first_30d >= 2,
                                  "2+ orders in first 30 days",
                                  "1 order in first 30 days"),
    region = if_else(country == "United Kingdom", "UK", "International")
  )

cat("Customers with 12 months of history:", nrow(ltv), "\n")
cat("Average 12-month LTV:", dollar(mean(ltv$ltv_12m)), "\n")
cat("Median 12-month LTV:", dollar(median(ltv$ltv_12m)), "\n")

# How does LTV compare between the two first-month groups?
ltv_by_segment <- ltv |>
  group_by(first_month_segment) |>
  summarise(customers = n(),
            avg_ltv_12m = mean(ltv_12m),
            retention_rate = mean(retained),
            .groups = "drop")
print(ltv_by_segment)

# UK vs international customers
ltv_by_region <- ltv |>
  group_by(region) |>
  summarise(customers = n(), avg_ltv_12m = mean(ltv_12m), .groups = "drop")
print(ltv_by_region)

# Logistic regression: what early behaviors predict a customer coming back?
ret_model <- glm(
  retained ~ I(orders_first_30d >= 2) + log1p(first_order_revenue) + region,
  data = ltv, family = binomial
)

cat("\nOdds ratios (above 1 = more likely to come back):\n")
print(broom::tidy(ret_model, exponentiate = TRUE, conf.int = TRUE))

# Pareto curve data
pareto <- customers |>
  arrange(desc(total_revenue)) |>
  mutate(customer_pct = row_number() / n(),
         revenue_pct  = cumsum(total_revenue) / sum(total_revenue))

# Charts
dir.create("output", showWarnings = FALSE)

heatmap <- retention |>
  filter(months_since_first <= 12) |>
  ggplot(aes(months_since_first, factor(cohort_month), fill = retention_rate)) +
  geom_tile(color = "white") +
  geom_text(aes(label = percent(retention_rate, 1)), size = 2.5) +
  scale_fill_gradient(low = "#f7fbff", high = "#08519c", labels = percent) +
  scale_y_discrete(limits = rev) +
  labs(title = "Monthly Cohort Retention", x = "Months since first purchase",
       y = "Cohort (first purchase month)", fill = "Retention")
ggsave("output/cohort_heatmap.png", heatmap, width = 10, height = 7)

pareto_plot <- ggplot(pareto, aes(customer_pct, revenue_pct)) +
  geom_line(linewidth = 1) +
  geom_vline(xintercept = 0.2, linetype = "dashed") +
  scale_x_continuous(labels = percent) +
  scale_y_continuous(labels = percent) +
  labs(title = "Revenue Concentration",
       x = "Share of customers (highest spenders first)", y = "Share of revenue")
ggsave("output/pareto_curve.png", pareto_plot, width = 7, height = 5)

ltv_plot <- ltv_by_segment |>
  ggplot(aes(first_month_segment, avg_ltv_12m)) +
  geom_col() +
  scale_y_continuous(labels = dollar) +
  labs(title = "12-Month LTV by First-Month Behavior", x = NULL, y = "Average LTV")
ggsave("output/ltv_by_segment.png", ltv_plot, width = 7, height = 5)

# Save results for Power BI
dbWriteTable(con, "customer_ltv", ltv, overwrite = TRUE)
cat("\nDone! Table customer_ltv written to PostgreSQL.\n")

dbDisconnect(con)