suppressPackageStartupMessages({ library(dplyr); library(readr) })
repo_dir <- normalizePath(".", winslash = "/", mustWork = TRUE)
app_dir <- file.path(repo_dir, "apps", "timeseries")
gate_dir <- file.path(repo_dir, "docs", "gate4")
path <- file.path(app_dir, "sox_constituents.csv")
x <- read_csv(path, show_col_types = FALSE)
if ("index_weight" %in% names(x) && !"proxy_weight_decimal" %in% names(x)) {
  x <- x %>% rename(proxy_weight_decimal = index_weight)
}
canonical <- c(
  "index_id", "ticker", "company_name", "official_name", "country", "value_chain",
  "core_products", "end_market", "korea_link", "effective_from", "effective_to",
  "membership_source", "membership_source_url", "membership_as_of",
  "proxy_weight_decimal", "weight_source", "weight_source_url", "weight_as_of",
  "quality_flag", "profile_source", "profile_updated_at"
)
stopifnot(setequal(names(x), canonical), nrow(x) == 30L, !anyDuplicated(x$ticker))
x <- x %>% select(all_of(canonical)) %>% arrange(ticker)
write_csv(x, path, na = "")
write_csv(x, file.path(gate_dir, "official_membership_snapshot.csv"), na = "")
write_csv(
  x %>% select(ticker, proxy_weight_decimal, weight_source, weight_as_of, weight_source_url, quality_flag),
  file.path(gate_dir, "weight_source_evidence.csv"), na = ""
)
cat("SOX metadata canonicalized: 30 rows\n")
