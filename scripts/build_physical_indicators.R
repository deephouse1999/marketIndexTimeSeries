#!/usr/bin/env Rscript

gate6_r_lib <- "C:/Users/yjh14/AppData/Local/R/win-library/4.5"
if (dir.exists(gate6_r_lib)) .libPaths(c(gate6_r_lib, .libPaths()))
suppressPackageStartupMessages({ library(dplyr); library(fst); library(lubridate); library(tibble); library(tidyr) })

repo_dir <- normalizePath(".", winslash = "/", mustWork = TRUE)
app_dir <- file.path(repo_dir, "apps", "timeseries")
gate_dir <- file.path(repo_dir, "docs", "gate4_5")
dir.create(gate_dir, recursive = TRUE, showWarnings = FALSE)

ecos <- read.fst(file.path(app_dir, "original_ts_ecos.fst"), as.data.table = FALSE) %>%
  as_tibble() %>% mutate(date = as.Date(date), observation_date = as.Date(observation_date))
yahoo <- read.fst(file.path(app_dir, "original_ts_yahoo.fst"), as.data.table = FALSE) %>%
  as_tibble() %>% mutate(date = as.Date(date))
components <- read.fst(file.path(app_dir, "original_ts_sox_components.fst"), as.data.table = FALSE) %>%
  as_tibble() %>% mutate(date = as.Date(date))

physical_ids <- c("KR_DRAM_PPI", "KR_FLASH_MEMORY_PPI")
streak_count <- function(x) {
  s <- sign(x)
  out <- integer(length(s))
  for (i in seq_along(s)) {
    if (is.na(s[i]) || s[i] == 0) out[i] <- 0L
    else if (i == 1L || is.na(s[i - 1L]) || s[i] != s[i - 1L]) out[i] <- s[i]
    else out[i] <- out[i - 1L] + s[i]
  }
  out
}

changes <- ecos %>%
  filter(series_id %in% physical_ids) %>%
  arrange(series_id, date) %>% group_by(series_id) %>%
  mutate(
    LEVEL = value,
    MOM = 100 * (value / lag(value, 1L) - 1),
    YOY = 100 * (value / lag(value, 12L) - 1),
    CHANGE_3M = 100 * (value / lag(value, 3L) - 1),
    CHANGE_6M = 100 * (value / lag(value, 6L) - 1),
    STREAK_MONTHS = streak_count(MOM)
  ) %>% ungroup() %>%
  pivot_longer(c(LEVEL, MOM, YOY, CHANGE_3M, CHANGE_6M, STREAK_MONTHS), names_to = "measure", values_to = "derived_value") %>%
  transmute(
    date, metric_group = "physical_change", metric_id = paste(series_id, measure, sep = "|"),
    series_id, measure, value = derived_value, aux_value = NA_real_, reference_date = date,
    available_at, source = "ECOS", unit = ifelse(measure == "LEVEL", "2020=100", ifelse(measure == "STREAK_MONTHS", "months", "%")),
    quality_status, calculation_version = "PHYSICAL_V1"
  )

market <- bind_rows(yahoo, components) %>%
  filter(series_id %in% c("^SOX", "MU", "000660.KS", "005930.KS")) %>%
  mutate(px = coalesce(adjusted_value, close_value), month = floor_date(date, "month")) %>%
  filter(is.finite(px), px > 0) %>%
  group_by(series_id, month) %>% arrange(date, .by_group = TRUE) %>%
  summarize(px = last(px), .groups = "drop") %>% group_by(series_id) %>% arrange(month) %>%
  mutate(market_return = px / lag(px) - 1) %>% ungroup()
ppi_mom <- changes %>% filter(measure == "MOM", is.finite(value)) %>% transmute(indicator_id = series_id, month = date, indicator_change = value / 100)

correlations <- bind_rows(lapply(physical_ids, function(pid) {
  bind_rows(lapply(unique(market$series_id), function(mid) {
    bind_rows(lapply(-6:6, function(lag_months) {
      m <- market %>% filter(series_id == mid) %>%
        transmute(indicator_month = month %m-% months(lag_months), market_month = month, market_return)
      z <- ppi_mom %>% filter(indicator_id == pid) %>% inner_join(m, by = c("month" = "indicator_month")) %>%
        filter(is.finite(indicator_change), is.finite(market_return))
      tibble(
        date = if (nrow(z)) max(z$month) else as.Date(NA), metric_group = "physical_reference_month_correlation",
        metric_id = paste(pid, mid, sprintf("LAG_%+d", lag_months), sep = "|"), series_id = pid,
        measure = "CORRELATION", value = if (nrow(z) >= 24L) cor(z$indicator_change, z$market_return) else NA_real_,
        aux_value = nrow(z), reference_date = if (nrow(z)) max(z$market_month) else as.Date(NA),
        available_at = if (nrow(z)) max(ecos$available_at[ecos$series_id == pid]) else NA_character_,
        source = "DERIVED", unit = "correlation", quality_status = ifelse(nrow(z) >= 24L, "REFERENCE_MONTH_ONLY", "INSUFFICIENT_HISTORY"),
        calculation_version = "PHYSICAL_V2_REFERENCE_MONTH"
      )
    }))
  }))
}))

bwet <- yahoo %>% filter(series_id == "BWET_VLCC_PROXY") %>% arrange(date) %>%
  mutate(px = coalesce(adjusted_value, close_value), ret = px / lag(px) - 1)
last_px <- tail(bwet$px[is.finite(bwet$px)], 1L)
period_return <- function(n) if (nrow(bwet) > n) 100 * (last_px / bwet$px[nrow(bwet) - n] - 1) else NA_real_
drawdown <- 100 * (bwet$px / cummax(bwet$px) - 1)
bwet_metrics <- tibble(
  measure = c("RETURN_1D", "RETURN_1W", "RETURN_1M", "RETURN_3M", "VOL_20D", "MAX_DRAWDOWN"),
  value = c(100 * tail(bwet$ret[is.finite(bwet$ret)], 1L), period_return(5L), period_return(21L), period_return(63L),
            sd(tail(bwet$ret[is.finite(bwet$ret)], 20L)) * sqrt(252) * 100, min(drawdown, na.rm = TRUE))
)

drivers <- yahoo %>% filter(series_id %in% c("CL=F", "XLE", "XOP")) %>%
  mutate(px = coalesce(adjusted_value, close_value)) %>% group_by(series_id) %>% arrange(date) %>%
  mutate(ret = px / lag(px) - 1) %>% ungroup()
bwet_corr <- bind_rows(lapply(c("CL=F", "XLE", "XOP"), function(id) {
  z <- inner_join(bwet %>% select(date, bwet_ret = ret), drivers %>% filter(series_id == id) %>% select(date, driver_ret = ret), by = "date") %>%
    filter(is.finite(bwet_ret), is.finite(driver_ret)) %>% tail(252)
  tibble(measure = paste0("CORR_252D_", id), value = if (nrow(z) >= 60L) cor(z$bwet_ret, z$driver_ret) else NA_real_)
}))
wti_regime <- bwet %>% select(date, bwet_ret = ret) %>%
  inner_join(drivers %>% filter(series_id == "CL=F") %>% select(date, wti_ret = ret), by = "date") %>%
  inner_join(drivers %>% filter(series_id == "XLE") %>% select(date, xle_ret = ret), by = "date") %>%
  filter(is.finite(bwet_ret), is.finite(wti_ret), is.finite(xle_ret)) %>%
  mutate(excess_vs_xle = bwet_ret - xle_ret) %>%
  summarize(UP = 100 * mean(excess_vs_xle[wti_ret > 0]), DOWN = 100 * mean(excess_vs_xle[wti_ret < 0])) %>%
  pivot_longer(everything(), names_to = "regime", values_to = "value") %>%
  transmute(measure = paste0("WTI_", regime, "_EXCESS_VS_XLE"), value)
bwet_summary <- bind_rows(bwet_metrics, bwet_corr, wti_regime) %>%
  transmute(
    date = max(bwet$date), metric_group = "bwet_summary", metric_id = paste("BWET_VLCC_PROXY", measure, sep = "|"),
    series_id = "BWET_VLCC_PROXY", measure, value, aux_value = NA_real_, reference_date = max(bwet$date),
    available_at = max(bwet$available_at), source = "YAHOO", unit = ifelse(grepl("CORR", measure), "correlation", "%"),
    quality_status = "ETF_PROXY_NOT_SPOT_RATE", calculation_version = "PHYSICAL_V2"
  )

derived <- bind_rows(changes, correlations, bwet_summary) %>% arrange(metric_group, metric_id, date)
target <- file.path(app_dir, "derived_physical_indicators.fst")
staging <- paste0(target, ".staging"); last_good <- paste0(target, ".last_good")
on.exit(if (file.exists(staging)) unlink(staging), add = TRUE)
write.fst(derived, staging, compress = 50)
readback <- read.fst(staging, as.data.table = FALSE)
dups <- sum(duplicated(readback[c("metric_group", "metric_id", "date")]))
if (nrow(readback) != nrow(derived) || dups != 0L) stop("PHYSICAL_DERIVED_READBACK_FAILED")
if (file.exists(last_good)) unlink(last_good)
if (file.exists(target) && !file.rename(target, last_good)) stop("PHYSICAL_BACKUP_FAILED")
if (!file.rename(staging, target)) stop("PHYSICAL_ATOMIC_PUBLICATION_FAILED")

write.csv(tibble(rows = nrow(derived), duplicate_keys = dups, min_date = min(derived$date, na.rm = TRUE), max_date = max(derived$date, na.rm = TRUE)),
          file.path(gate_dir, "physical_derived_summary.csv"), row.names = FALSE)
cat("Physical indicators derived: PASS (", nrow(derived), " rows)\n", sep = "")
