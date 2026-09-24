# Customer Cohort Retention & Lifetime Value

I wanted to figure out how quickly new customers stop buying, what early behavior predicts that they'll stick around, and how much a customer is actually worth. So I built a cohort analysis on over a million real transactions and turned it into a dashboard.

![Dashboard](output/dashboard.png)

## The Question
Most customers buy once and never come back. If you can spot the ones who will stay early on, you know where to focus. I wanted to answer three things: how many new customers churn, what separates the ones who stay, and how concentrated revenue is across customers.

## What I Used
- **PostgreSQL** to clean the transactions and build the cohort tables
- **R** to calculate lifetime value and run a logistic regression
- **Power BI** for the dashboard

## The Data
I used the Online Retail II dataset from the [UCI Machine Learning Repository](https://archive.ics.uci.edu/dataset/502/online+retail+ii). It has **1,067,371 transactions** from a UK online retailer between December 2009 and December 2011. All amounts are in British pounds (£).

After removing cancelled orders, returns, and transactions with no customer ID, I was left with **779,425 transactions**, **36,969 orders**, and **5,878 customers** across **25 monthly cohorts**.

## How I Built It
1. **Loaded the data into PostgreSQL with R.** The Excel file has two sheets, so I combined them and made sure cancelled invoices (which start with a "C") didn't get read as missing values.
2. **Cleaned and reshaped it in SQL.** I went from individual transaction lines to one row per order and then one row per customer, using window functions to find each customer's first order and group them into monthly cohorts.
3. **Built a cohort retention table** showing what percent of each cohort came back in each month after their first purchase.
4. **Ran analysis queries** to measure 90-day churn, compare early buyers, and see how revenue is split across customers.
5. **Calculated 12-month lifetime value in R** and ran a logistic regression to see which early behaviors predict a customer coming back.
6. **Built a dashboard in Power BI** with the retention heatmap as the centerpiece.

## What I Found
- **53% of new customers didn't come back within 90 days.** The first few months are when you either keep someone or lose them.
- **Early repeat buyers are way more valuable.** Customers who ordered twice in their first 30 days retained at **79% vs. 63%** for everyone else, and their average 12-month LTV was **£5,359 vs. £1,351**, about 4x higher.
- The logistic regression backed this up: ordering twice in the first month gave customers **2.2x the odds** of coming back. A bigger first order also helped, but being in the UK vs. international didn't make a significant difference.
- **Revenue is super concentrated.** The top 20% of customers brought in **77% of total revenue**, while the bottom 20% brought in about 1%.
- The average 12-month LTV was **£2,294**, but the median was only **£854**. A small group of big spenders pulls the average way up.

## Why This Matters for Fintech
This is the same analysis neobanks, payment apps, and investing apps run to measure activation. Swap "orders" for "transactions" or "deposits," and a finding like "users who transact twice in their first month are worth 4x more" is exactly what shapes onboarding campaigns and referral bonuses.

## Things I'd Improve
- The **December 2009 cohort** looks way more loyal than the others. That's because the data starts that month, so it includes customers who were already shopping there before, not just new ones. I'd exclude it or flag it in a more formal analysis.
- About **23% of transactions had no customer ID** (probably guest checkouts), so they couldn't be tracked. The results only reflect customers who had accounts.
- The data only has revenue, not profit, so LTV here is revenue-based. With margin data I could calculate true customer profitability.
- I'd like to try a probabilistic model like BG/NBD to predict *future* LTV instead of just measuring the past.

## Files
| File | What it does |
|---|---|
| `01_load_data.R` | Loads the Excel data into PostgreSQL |
| `02_cohort_analysis.sql` | Cleans the data and builds the order, customer, and cohort tables |
| `03_analysis_queries.sql` | Churn, retention by first-month behavior, and revenue concentration |
| `04_ltv_analysis.R` | Calculates lifetime value, runs the logistic regression, and makes charts |
| `cohort_ltv_dashboard.pbix` | The Power BI dashboard |
| `output/` | Charts and dashboard screenshot |

## Running It Yourself
1. Download the data from UCI and put `online_retail_II.xlsx` in a `data/` folder.
2. Create a PostgreSQL database called `my_portfolio`.
3. Run `01_load_data.R`, then `02_cohort_analysis.sql` in pgAdmin, then `04_ltv_analysis.R`.
4. Run the queries in `03_analysis_queries.sql` one at a time to see the key numbers.
5. Open the `.pbix` file in Power BI Desktop.