suppressPackageStartupMessages({ library(dplyr); library(fst); library(readr); library(tibble) })

repo_dir <- normalizePath(".", winslash = "/", mustWork = TRUE)
app_dir <- file.path(repo_dir, "apps", "timeseries")
gate_dir <- file.path(repo_dir, "docs", "gate4")
members <- read_csv(file.path(app_dir, "sox_constituents.csv"), show_col_types = FALSE) %>%
  mutate(weight_as_of = as.Date(weight_as_of))
snapshot_date <- unique(members$weight_as_of)
if (length(snapshot_date) != 1L || snapshot_date != as.Date("2026-11-04")) stop("EXPECTED_2026_11_04_EOD_SNAPSHOT")

normalize_prices <- function(path) {
  read.fst(path, as.data.table = FALSE) %>% as_tibble() %>%
    transmute(date = as.Date(date), ticker = as.character(series_id), adjusted = as.numeric(adjusted_value))
}
prices <- bind_rows(
  normalize_prices(file.path(app_dir, "original_ts_yahoo.fst")),
  normalize_prices(file.path(app_dir, "original_ts_sox_components.fst"))
) %>% filter(ticker %in% members$ticker, date %in% as.Date(c("2026-11-03", "2026-11-04"))) %>%
  distinct(ticker, date, .keep_all = TRUE) %>%
  tidyr::pivot_wider(names_from = date, values_from = adjusted, names_prefix = "px_") %>%
  mutate(return_2026_11_04 = `px_2026-11-04` / `px_2026-11-03` - 1)
if (nrow(prices) != 30L || any(!is.finite(prices$return_2026_11_04))) stop("WEIGHT_RECONSTRUCTION_PRICE_GAP")

current <- members %>%
  select(ticker, proxy_weight_decimal, weight_source, weight_source_url, weight_as_of) %>%
  mutate(
    snapshot_type = "OFFICIAL_SOXQ_EOD",
    quality_flag = "PROXY_WEIGHT_NOT_OFFICIAL_INDEX_WEIGHT",
    reconstruction_basis = NA_character_
  )
prior <- current %>%
  left_join(prices %>% select(ticker, return_2026_11_04), by = "ticker") %>%
  mutate(proxy_weight_decimal = proxy_weight_decimal / (1 + return_2026_11_04)) %>%
  mutate(proxy_weight_decimal = proxy_weight_decimal / sum(proxy_weight_decimal) * sum(current$proxy_weight_decimal)) %>%
  transmute(
    ticker, proxy_weight_decimal, weight_source, weight_source_url,
    weight_as_of = as.Date("2026-11-03"),
    snapshot_type = "RECONSTRUCTED_PRE_EOD",
    quality_flag = "RECONSTRUCTED_FROM_2026_11_04_EOD_PRICE_DRIFT",
    reconstruction_basis = "w_t_minus_1 proportional to w_t divided by (1 + adjusted_return_t); normalized to observed proxy total"
  )
history <- bind_rows(prior, current) %>% arrange(weight_as_of, ticker)
write_csv(history, file.path(app_dir, "sox_weight_history.csv"), na = "")
write_csv(history, file.path(gate_dir, "sox_weight_history_evidence.csv"), na = "")
write_csv(
  prices %>% select(ticker, starts_with("px_"), return_2026_11_04) %>%
    left_join(prior %>% select(ticker, reconstructed_weight = proxy_weight_decimal), by = "ticker") %>%
    left_join(current %>% select(ticker, eod_weight = proxy_weight_decimal), by = "ticker"),
  file.path(gate_dir, "weight_reconstruction_evidence.csv"), na = ""
)
cat("SOX weight history: 2 snapshots x 30 members\n")
