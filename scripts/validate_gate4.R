suppressPackageStartupMessages({ library(dplyr); library(fst); library(readr); library(tibble) })
repo_dir <- normalizePath(".", winslash = "/", mustWork = TRUE)
app_dir <- file.path(repo_dir, "apps", "timeseries")
gate_dir <- file.path(repo_dir, "docs", "gate4")

cold <- bind_rows(lapply(1:5, function(i) read_csv(file.path(gate_dir, paste0("performance_cold_run_", i, ".csv")), show_col_types = FALSE)))
write_csv(cold, file.path(gate_dir, "performance_cold_runs.csv"))
warm <- read_csv(file.path(gate_dir, "performance_warm_runs.csv"), show_col_types = FALSE)
filter_runs <- read_csv(file.path(gate_dir, "performance_filter_runs.csv"), show_col_types = FALSE)
ui <- read_csv(file.path(gate_dir, "ui_smoke_metrics.csv"), show_col_types = FALSE)
members <- read_csv(file.path(app_dir, "sox_constituents.csv"), show_col_types = FALSE) %>% mutate(effective_from = as.Date(effective_from))
weight_history <- read_csv(file.path(app_dir, "sox_weight_history.csv"), show_col_types = FALSE) %>% mutate(weight_as_of = as.Date(weight_as_of))
contributions <- read_csv(file.path(gate_dir, "contribution_samples.csv"), show_col_types = FALSE) %>% mutate(date = as.Date(date), weight_as_of = as.Date(weight_as_of))
completeness <- read_csv(file.path(gate_dir, "member_date_completeness.csv"), show_col_types = FALSE) %>% mutate(date = as.Date(date))
overview <- read.fst(file.path(app_dir, "derived_sox_overview.fst"), as.data.table = FALSE) %>% as_tibble() %>% mutate(date = as.Date(date))
catalog <- read_csv(file.path(app_dir, "series_catalog.csv"), col_types = cols(.default = col_character()), na = character())
raw <- read.fst(file.path(app_dir, "original_ts_sox_components.fst"), as.data.table = FALSE) %>% as_tibble() %>% mutate(date = as.Date(date))
legacy <- read.fst(file.path(app_dir, "original_ts_yahoo.fst"), as.data.table = FALSE) %>% as_tibble()
derived <- read.fst(file.path(app_dir, "derived_sox_daily_summary.fst"), as.data.table = FALSE) %>% as_tibble() %>% mutate(date = as.Date(date))

checks <- list()
add <- function(id, observed, expected, pass) checks[[length(checks) + 1L]] <<- tibble(check = id, observed = as.character(observed), expected = as.character(expected), status = ifelse(pass, "PASS", "FAIL"))
add("official_membership_count", nrow(members), 30, nrow(members) == 30L && n_distinct(members$ticker) == 30L)
add("membership_source", paste(unique(members$membership_source), collapse = ";"), "NASDAQ_OFFICIAL", all(members$membership_source == "NASDAQ_OFFICIAL"))
add("weight_source", paste(unique(members$weight_source), collapse = ";"), "SOXQ_PROXY", all(members$weight_source == "SOXQ_PROXY"))
add("proxy_weight_sum", sum(members$proxy_weight_decimal), "0.99 to 1.01", between(sum(members$proxy_weight_decimal), .99, 1.01))
add("weight_snapshot_history", paste(sort(unique(weight_history$weight_as_of)), collapse = ";"), "2026-11-03;2026-11-04", nrow(weight_history) == 60L && n_distinct(weight_history$ticker) == 30L)
add("strict_prior_weight_usage", sum(contributions$weight_as_of >= contributions$date), 0, all(contributions$weight_as_of < contributions$date))
add("raw_rows", nrow(raw), "> 0", nrow(raw) > 0)
add("raw_series", n_distinct(raw$series_id), 30, n_distinct(raw$series_id) == 30L)
add("raw_duplicate_keys", nrow(raw %>% count(source, series_id, date) %>% filter(n > 1)), 0, !anyDuplicated(paste(raw$source, raw$series_id, raw$date)))
add("required_series_coverage", n_distinct(c(intersect(members$ticker, legacy$series_id), raw$series_id)), 32, all(c(members$ticker, "SOXQ", "005930.KS") %in% c(legacy$series_id, raw$series_id)))
add("derived_rows", nrow(derived), "> 0", nrow(derived) > 0)
add("derived_duplicate_keys", nrow(derived %>% count(date, metric_group, metric_id) %>% filter(n > 1)), 0, !anyDuplicated(paste(derived$date, derived$metric_group, derived$metric_id)))
member_metrics <- derived %>% filter(metric_group %in% c("daily_summary", "value_chain_return", "constituent_contribution"))
add("no_membership_lookahead", if (nrow(member_metrics)) as.character(min(member_metrics$date)) else NA_character_, as.character(min(members$effective_from)), nrow(member_metrics) > 0 && min(member_metrics$date) >= min(members$effective_from))
add("adjusted_close_policy", sum(is.na(raw$adjusted_value) | raw$adjusted_value <= 0), 0, sum(is.na(raw$adjusted_value) | raw$adjusted_value <= 0) == 0)
gate4_owned <- setdiff(c(members$ticker, "SOXQ", "005930.KS"), c("NVDA", "MU"))
owned_catalog <- catalog %>% filter(source == "YAHOO", series_id %in% gate4_owned)
add("collector_ownership_gate4_only", paste(unique(owned_catalog$collect_flag), collapse = ";"), "FALSE", nrow(owned_catalog) == length(gate4_owned) && all(owned_catalog$collect_flag == "FALSE"))
write_csv(
  catalog %>%
    filter(source == "YAHOO", series_id %in% c(members$ticker, "SOXQ", "005930.KS")) %>%
    transmute(source, series_id, collect_flag, collector_owner = ifelse(series_id %in% c("NVDA", "MU"), "LEGACY_YAHOO", "GATE4_SOX")),
  file.path(gate_dir, "collector_ownership_validation.csv")
)
published_bad_prices <- derived %>% filter(metric_group == "benchmark_return", !is.na(aux_value), (!is.finite(aux_value) | aux_value <= 0))
add("published_nonpositive_adjusted_prices", nrow(published_bad_prices), 0, nrow(published_bad_prices) == 0L)
published_extreme_returns <- derived %>% filter(metric_group == "benchmark_return", !is.na(value), abs(value) > 1)
add("published_extreme_daily_returns", nrow(published_extreme_returns), 0, nrow(published_extreme_returns) == 0L)
add("latest_us_close_alignment_policy", sum(derived$quality_flag == "NEXT_KR_TRADING_DAY_LATEST_US_CLOSE", na.rm = TRUE), "> 0", any(derived$quality_flag == "NEXT_KR_TRADING_DAY_LATEST_US_CLOSE", na.rm = TRUE))
daily_member_count <- derived %>% filter(metric_group == "daily_summary", metric_id == "member_count")
add("complete_member_aggregate_only", paste(unique(daily_member_count$value), collapse = ";"), 30, nrow(daily_member_count) > 0L && all(daily_member_count$value == 30))
incomplete_dates <- completeness$date[!completeness$complete]
add("incomplete_dates_not_published", sum(member_metrics$date %in% incomplete_dates), 0, !any(member_metrics$date %in% incomplete_dates))
overview_bounds <- overview %>% group_by(metric_id) %>% summarize(first_date = min(date), last_date = max(date), first_value = first(value[order(date)]), .groups = "drop")
add("overview_common_period", n_distinct(paste(overview_bounds$first_date, overview_bounds$last_date)), 1, n_distinct(overview_bounds$first_date) == 1L && n_distinct(overview_bounds$last_date) == 1L)
add("overview_exact_100_baseline", max(abs(overview_bounds$first_value - 100)), 0, all(abs(overview_bounds$first_value - 100) < 1e-10))
add("cold_render_max_seconds", max(cold$elapsed_seconds), "<= 2", max(cold$elapsed_seconds) <= 2)
add("warm_render_p95_seconds", quantile(warm$elapsed_seconds, .95), "<= 2", quantile(warm$elapsed_seconds, .95) <= 2)
add("filter_response_p95_seconds", quantile(filter_runs$elapsed_seconds, .95), "<= 2", quantile(filter_runs$elapsed_seconds, .95) <= 2)
add("app_startup_max_seconds", max(c(cold$app_startup_seconds, warm$app_startup_seconds, filter_runs$app_startup_seconds)), "<= 5", max(c(cold$app_startup_seconds, warm$app_startup_seconds, filter_runs$app_startup_seconds)) <= 5)
memory <- as.numeric(ui$value[ui$check == "session_memory_mb"])
add("session_memory_mb", memory, "<= 500", memory <= 500)
add("app_time_api_calls", 0, 0, !any(grepl("indexes.nasdaqomx.com|dng-api.invesco.com|getSymbols\\(", readLines(file.path(app_dir, "app.R")))))
checks <- bind_rows(checks)
write_csv(checks, file.path(gate_dir, "gate4_validation.csv"))

write_csv(
  tibble(
    required_series = n_distinct(c(members$ticker, "SOXQ", "005930.KS")),
    existing_reused = 2L,
    newly_collected = n_distinct(raw$series_id),
    rows = nrow(raw), duplicate_keys = nrow(raw %>% count(source, series_id, date) %>% filter(n > 1L)),
    collection_mode = "INDEPENDENT_READBACK_AFTER_REMEDIATION",
    first_date = min(as.Date(raw$date)), last_date = max(as.Date(raw$date)),
    membership_effective_from = min(members$effective_from),
    historical_membership_before_effective_from = "NOT_AVAILABLE"
  ),
  file.path(gate_dir, "collection_summary.csv")
)

sha256_file <- function(path) {
  output <- system2("certutil", c("-hashfile", shQuote(path), "SHA256"), stdout = TRUE, stderr = TRUE)
  candidates <- gsub(" ", "", output)
  candidates <- candidates[grepl("^[0-9A-Fa-f]{64}$", candidates)]
  if (length(candidates) != 1L) stop("SHA256_FAILED: ", path)
  toupper(candidates[[1]])
}
hashes <- tibble(
  file = c("original_ts_fred.fst", "original_ts_yahoo.fst", "original_ts_ecos.fst",
           "original_ts_sox_components.fst", "original_ts_sox_components.fst.last_good",
           "derived_sox_daily_summary.fst", "derived_sox_daily_summary.fst.last_good"),
  sha256 = vapply(file.path(app_dir, file), sha256_file, character(1)),
  algorithm = "SHA256"
)
write_csv(hashes, file.path(gate_dir, "file_integrity_inventory.csv"))

summary <- tibble(
  test = c("cold_max", "warm_p50", "warm_p95", "warm_max", "filter_p50", "filter_p95", "filter_max", "startup_max", "session_rss_mb"),
  seconds_or_mb = c(max(cold$elapsed_seconds), median(warm$elapsed_seconds), quantile(warm$elapsed_seconds, .95), max(warm$elapsed_seconds), median(filter_runs$elapsed_seconds), quantile(filter_runs$elapsed_seconds, .95), max(filter_runs$elapsed_seconds), max(c(cold$app_startup_seconds, warm$app_startup_seconds, filter_runs$app_startup_seconds)), memory)
)
write_csv(summary, file.path(gate_dir, "performance_summary.csv"))
if (any(checks$status != "PASS")) stop("GATE4_VALIDATION_FAILED: ", paste(checks$check[checks$status != "PASS"], collapse = ", "))
cat("Gate 4 validation: PASS (", nrow(checks), "/", nrow(checks), ")\n", sep = "")
