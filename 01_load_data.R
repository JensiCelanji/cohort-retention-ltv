library(readxl)
library(dplyr)
library(janitor)
library(DBI)
library(RPostgres)

con <- dbConnect(
  Postgres(),
  dbname   = "my_portfolio",
  host     = "localhost",
  port     = 5432,
  user     = "postgres",
  password = Sys.getenv("PG_PASSWORD"),
  bigint   = "numeric"
)

path <- "data/online_retail_II.xlsx"

col_types <- c("text", "text", "text", "numeric", "date",
               "numeric", "numeric", "text")

retail <- excel_sheets(path) |>
  lapply(\(s) read_excel(path, sheet = s, col_types = col_types)) |>
  bind_rows() |>
  clean_names()

cat("Rows loaded:", format(nrow(retail), big.mark = ","), "\n")
cat("Date range:", format(min(retail$invoice_date)), "to",
    format(max(retail$invoice_date)), "\n")

dbWriteTable(con, "retail_raw", as.data.frame(retail), overwrite = TRUE)
cat("Done! Table retail_raw written to PostgreSQL\n")

dbDisconnect(con)