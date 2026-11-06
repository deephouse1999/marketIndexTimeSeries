suppressPackageStartupMessages({
  library(dplyr); library(fst); library(ggplot2); library(readr); library(tibble); library(tidyr); library(zoo)
})

repo_dir <- normalizePath(".", winslash = "/", mustWork = TRUE)
app_dir <- file.path(repo_dir, "apps", "timeseries")
gate_dir <- file.path(repo_dir, "docs", "gate4")
members <- read_csv(file.path(app_dir, "sox_constituents.csv"), show_col_types = FALSE) %>%
  mutate(effective_from = as.Date(effective_from), effective_to = as.Date(effective_to), weight_as_of = as.Date(weight_as_of))
weight_history <- read_csv(file.path(app_dir, "sox_weight_history.csv"), show_col_types = FALSE) %>%
  mutate(weight_as_of = as.Date(weight_as_of))

normalize_prices <- function(path) {
  read.fst(path, as.data.table = FALSE) %>% as_tibble() %>%
    transmute(date = as.Date(date), series_id = as.character(series_id),
              adjusted = as.numeric(dplyr::coalesce(adjusted_value, close_value)))
}
raw_prices <- bind_rows(
  normalize_prices(file.path(app_dir, "original_ts_yahoo.fst")),
  normalize_prices(file.path(app_dir, "original_ts_sox_components.fst"))
) %>% arrange(series_id, date) %>% distinct(series_id, date, .keep_all = TRUE)
prices <- raw_prices %>%
  group_by(series_id) %>%
  mutate(
    prior_adjusted = lag(adjusted),
    return = ifelse(
      is.finite(adjusted) & adjusted > 0 & is.finite(prior_adjusted) & prior_adjusted > 0,
      adjusted / prior_adjusted - 1,
      NA_real_
    ),
    return = ifelse(is.finite(return) & abs(return) <= 1, return, NA_real_)
  ) %>%
  select(-prior_adjusted) %>% ungroup()

member_candidates <- prices %>%
  filter(series_id %in% members$ticker) %>%
  left_join(members %>% select(ticker, effective_from, effective_to, value_chain, company_name), by = c("series_id" = "ticker")) %>%
  filter(date >= effective_from, is.na(effective_to) | date <= effective_to) %>%
  left_join(weight_history, by = c("series_id" = "ticker"), relationship = "many-to-many") %>%
  filter(weight_as_of < date) %>%
  group_by(date, series_id) %>% slice_max(weight_as_of, n = 1, with_ties = FALSE) %>% ungroup()

expected_by_date <- tidyr::crossing(
  date = sort(unique(member_candidates$date)),
  series_id = members$ticker
) %>%
  left_join(weight_history, by = c("series_id" = "ticker"), relationship = "many-to-many") %>%
  filter(weight_as_of < date) %>%
  group_by(date, series_id) %>% slice_max(weight_as_of, n = 1, with_ties = FALSE) %>% ungroup() %>%
  group_by(date) %>% summarize(expected_members = n(), expected_weight_total = sum(proxy_weight_decimal), .groups = "drop")
date_completeness <- member_candidates %>%
  group_by(date) %>%
  summarize(
    available_members = n_distinct(series_id[!is.na(return)]),
    available_weight = sum(proxy_weight_decimal[!is.na(return)]),
    .groups = "drop"
  ) %>%
  left_join(expected_by_date, by = "date") %>%
  mutate(
    weight_coverage = available_weight / expected_weight_total,
    complete = expected_members == nrow(members) & available_members == nrow(members) & abs(weight_coverage - 1) < 1e-10
  ) %>%
  select(date, expected_members, available_members, expected_weight_total, available_weight, weight_coverage, complete)
complete_dates <- date_completeness %>% filter(complete) %>% select(date)
member_daily <- member_candidates %>%
  semi_join(complete_dates, by = "date") %>%
  group_by(date) %>%
  mutate(
    normalized_proxy_weight = proxy_weight_decimal / sum(proxy_weight_decimal),
    contribution = normalized_proxy_weight * return
  ) %>% ungroup()

index_ret <- prices %>% filter(series_id == "^SOX") %>% select(date, sox_return = return)
daily <- member_daily %>% group_by(date) %>%
  summarize(
    member_count = sum(!is.na(return)), advancing = sum(return > 0, na.rm = TRUE), declining = sum(return < 0, na.rm = TRUE),
    unchanged = sum(return == 0, na.rm = TRUE), breadth_pct = mean(return > 0, na.rm = TRUE) * 100,
    equal_weight_return = mean(return, na.rm = TRUE), proxy_weighted_return = sum(proxy_weight_decimal * return, na.rm = TRUE) / sum(proxy_weight_decimal[!is.na(return)], na.rm = TRUE),
    top5_concentration = sum(head(sort(unique(proxy_weight_decimal), decreasing = TRUE), 5L), na.rm = TRUE),
    top10_concentration = sum(head(sort(unique(proxy_weight_decimal), decreasing = TRUE), 10L), na.rm = TRUE),
    .groups = "drop"
  ) %>% left_join(index_ret, by = "date") %>%
  mutate(residual_return = sox_return - proxy_weighted_return, quality_flag = "SOXQ_PROXY_COMPLETE_PREVIOUS_SNAPSHOT")

chain <- member_daily %>% group_by(date, value_chain) %>%
  summarize(value = weighted.mean(return, proxy_weight_decimal, na.rm = TRUE), member_count = sum(!is.na(return)), .groups = "drop") %>%
  transmute(date, metric_group = "value_chain_return", metric_id = value_chain, value, aux_value = as.numeric(member_count), quality_flag = "SOXQ_PROXY_COMPLETE_PREVIOUS_SNAPSHOT")

contrib <- member_daily %>%
  transmute(date, metric_group = "constituent_contribution", metric_id = series_id,
            value = contribution, aux_value = return, quality_flag = "SOXQ_PROXY_COMPLETE_PREVIOUS_SNAPSHOT")

daily_long <- daily %>%
  pivot_longer(cols = c(member_count, advancing, declining, unchanged, breadth_pct, equal_weight_return,
                        proxy_weighted_return, top5_concentration, top10_concentration, sox_return, residual_return),
               names_to = "metric_id", values_to = "value") %>%
  transmute(date, metric_group = "daily_summary", metric_id, value, aux_value = NA_real_, quality_flag)

bench_ids <- c("^SOX", "SOXX", "XSD", "SOXQ", "^KS11")
benchmark <- prices %>% filter(series_id %in% bench_ids, is.finite(adjusted), adjusted > 0) %>%
  transmute(date, metric_group = "benchmark_return", metric_id = series_id, value = return,
            aux_value = adjusted, quality_flag = "ADJUSTED_CLOSE_QUALITY_GUARDED")

next_kr <- function(us_id, kr_id) {
  us <- prices %>% filter(series_id == us_id, !is.na(return)) %>% select(us_date = date, us_return = return)
  kr <- prices %>% filter(series_id == kr_id, !is.na(return)) %>% select(kr_date = date, kr_return = return)
  if (!nrow(us) || !nrow(kr)) return(tibble())
  next_index <- findInterval(us$us_date, kr$kr_date) + 1L
  keep <- next_index <= nrow(kr)
  mapped <- tibble(
    date = kr$kr_date[next_index[keep]], us_date = us$us_date[keep],
    us_return = us$us_return[keep], kr_return = kr$kr_return[next_index[keep]]
  ) %>% arrange(date, desc(us_date)) %>% distinct(date, .keep_all = TRUE) %>% arrange(date)
  bind_rows(lapply(c(20L, 60L, 120L), function(w) {
    mapped %>% mutate(value = zoo::rollapplyr(cbind(us_return, kr_return), w, function(z) cor(z[, 1], z[, 2], use = "complete.obs"), by.column = FALSE, fill = NA_real_)) %>%
      transmute(date, metric_group = "us_next_korea", metric_id = paste(us_id, kr_id, paste0(w, "D_CORR"), sep = "|"),
                value, aux_value = kr_return, quality_flag = ifelse(is.na(value), "INSUFFICIENT_HISTORY", "NEXT_KR_TRADING_DAY_LATEST_US_CLOSE"))
  }))
}
link <- bind_rows(lapply(c("^SOX", "SOXX", "XSD", "SOXQ"), next_kr, kr_id = "^KS11"))

summary <- bind_rows(daily_long, chain, contrib, benchmark, link) %>% arrange(metric_group, metric_id, date)
target <- file.path(app_dir, "derived_sox_daily_summary.fst")
staging <- paste0(target, ".staging"); last_good <- paste0(target, ".last_good")
on.exit(if (file.exists(staging)) unlink(staging), add = TRUE)
write.fst(summary, staging, compress = 50)
rb <- read.fst(staging, as.data.table = FALSE) %>% as_tibble()
dups <- rb %>% count(date, metric_group, metric_id) %>% filter(n > 1L)
if (nrow(rb) != nrow(summary) || nrow(dups)) stop("SOX_DERIVED_READBACK_FAILED")
if (file.exists(last_good)) unlink(last_good)
if (file.exists(target) && !file.rename(target, last_good)) stop("SOX_DERIVED_BACKUP_FAILED")
if (!file.rename(staging, target)) { if (file.exists(last_good)) file.rename(last_good, target); stop("SOX_DERIVED_PUBLICATION_FAILED") }

latest <- summary %>% group_by(metric_group, metric_id) %>% slice_max(date, n = 1, with_ties = FALSE) %>% ungroup()
write.fst(latest, file.path(app_dir, "derived_sox_latest.fst"), compress = 50)
overview_ids <- c("^SOX", "SOXX", "XSD", "SOXQ")
overview_source <- benchmark %>% filter(metric_id %in% overview_ids, is.finite(aux_value), aux_value > 0)
shared_dates <- Reduce(intersect, split(overview_source$date, overview_source$metric_id))
shared_dates <- sort(shared_dates[shared_dates >= max(shared_dates) - 365L * 5L])
if (!length(shared_dates)) stop("SOX_OVERVIEW_COMMON_PERIOD_NOT_AVAILABLE")
overview_daily <- overview_source %>%
  filter(date %in% shared_dates) %>%
  group_by(metric_id) %>% arrange(date) %>%
  mutate(value = 100 * aux_value / first(aux_value), metric_group = "benchmark_index",
         quality_flag = "COMMON_DATE_ADJUSTED_CLOSE_INDEX") %>% ungroup()
overview_baseline <- overview_daily %>% filter(date == min(shared_dates))
overview <- overview_daily %>%
  mutate(month = format(date, "%Y-%m")) %>%
  group_by(metric_id, month) %>% slice_max(date, n = 1, with_ties = FALSE) %>% ungroup() %>%
  bind_rows(overview_baseline) %>%
  distinct(metric_id, date, .keep_all = TRUE) %>%
  arrange(metric_id, date) %>%
  select(date, metric_group, metric_id, value, aux_value, quality_flag)
write.fst(overview, file.path(app_dir, "derived_sox_overview.fst"), compress = 50)
overview_plot <- ggplot(overview, aes(x = date, y = value, color = metric_id)) +
  geom_line(linewidth = 0.8, na.rm = TRUE) +
  labs(x = "Date", y = "Adjusted Close return index (common start = 100)", color = NULL) +
  theme_minimal(base_size = 12) + theme(legend.position = "bottom")
ggsave(file.path(app_dir, "derived_sox_overview.png"), overview_plot, width = 12, height = 4.5, dpi = 120)
write_csv(daily, file.path(gate_dir, "daily_replication_evidence.csv"))
write_csv(member_daily %>% select(date, series_id, return, proxy_weight_decimal, normalized_proxy_weight, contribution, value_chain, weight_as_of, snapshot_type, quality_flag), file.path(gate_dir, "contribution_samples.csv"))
write_csv(date_completeness, file.path(gate_dir, "member_date_completeness.csv"))
write_csv(
  raw_prices %>%
    mutate(exclusion_reason = case_when(
      is.na(adjusted) ~ "MISSING_ADJUSTED_CLOSE",
      !is.finite(adjusted) ~ "NONFINITE_ADJUSTED_CLOSE",
      adjusted <= 0 ~ "NONPOSITIVE_ADJUSTED_CLOSE",
      TRUE ~ NA_character_
    )) %>%
    filter(!is.na(exclusion_reason)) %>%
    count(series_id, exclusion_reason, name = "excluded_rows"),
  file.path(gate_dir, "price_quality_exclusions.csv")
)
write_csv(tibble(rows = nrow(summary), metrics = n_distinct(paste(summary$metric_group, summary$metric_id)), duplicate_keys = nrow(dups), min_date = min(summary$date), max_date = max(summary$date)), file.path(gate_dir, "derived_build_summary.csv"))
cat("SOX derived summary:", nrow(summary), "rows\n")
