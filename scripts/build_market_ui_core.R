suppressPackageStartupMessages({
  library(dplyr)
  library(fst)
  library(readr)
  library(tibble)
})

repo_dir <- normalizePath(".", winslash = "/", mustWork = TRUE)
app_dir <- file.path(repo_dir, "apps", "timeseries")
catalog <- read_csv(file.path(app_dir, "series_catalog.csv"), show_col_types = FALSE)
yahoo <- read.fst(file.path(app_dir, "original_ts_yahoo.fst"), as.data.table = FALSE) %>% as_tibble()

core_catalog <- catalog %>%
  mutate(
    active = as.logical(active),
    analysis_group = sub(".*(?:^|;)analysis_group=([^;]+).*", "\\1", ifelse(is.na(notes), "", notes), perl = TRUE),
    analysis_group = ifelse(grepl("(?:^|;)analysis_group=", ifelse(is.na(notes), "", notes)), analysis_group, NA_character_)
  ) %>%
  filter(
    source == "YAHOO", active,
    series_cls == "sector_etf" | analysis_group == "semiconductor_korea"
  )
core_ids <- unique(c(core_catalog$series_id, na.omit(core_catalog$benchmark_series)))
core <- yahoo %>%
  filter(series_id %in% core_ids) %>%
  arrange(source, series_id, date) %>%
  distinct(source, series_id, date, .keep_all = TRUE)

target <- file.path(app_dir, "derived_market_ui_core.fst")
staging <- paste0(target, ".staging")
last_good <- paste0(target, ".last_good")
on.exit(if (file.exists(staging)) unlink(staging), add = TRUE)
write.fst(core, staging, compress = 50)
readback <- read.fst(staging, as.data.table = FALSE)
if (nrow(readback) != nrow(core) || !setequal(unique(readback$series_id), unique(core$series_id))) {
  stop("MARKET_UI_CORE_READBACK_FAILED")
}
if (file.exists(last_good)) unlink(last_good)
if (file.exists(target) && !file.rename(target, last_good)) stop("MARKET_UI_CORE_BACKUP_FAILED")
if (!file.rename(staging, target)) {
  if (file.exists(last_good)) file.rename(last_good, target)
  stop("MARKET_UI_CORE_PUBLICATION_FAILED")
}

cat("Market UI core: PASS (", nrow(core), " rows, ", n_distinct(core$series_id), " series)\n", sep = "")
