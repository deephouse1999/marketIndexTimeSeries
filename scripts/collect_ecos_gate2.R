suppressPackageStartupMessages({
  library(dplyr)
  library(fst)
  library(readr)
  library(tibble)
})

locale_result <- Sys.setlocale("LC_CTYPE", "Korean_Korea.utf8")
if (is.na(locale_result)) stop("UTF-8 Korean locale is required")

repo_dir <- normalizePath(".", winslash = "/", mustWork = TRUE)
app_dir <- file.path(repo_dir, "apps", "timeseries")
gate_dir <- file.path(repo_dir, "docs", "gate2")
source(file.path(app_dir, "ecos_adapter.R"), local = TRUE)

catalog_path <- file.path(app_dir, "series_catalog.csv")
snapshot_path <- file.path(app_dir, "ecos_item_snapshot.csv")
target_path <- file.path(app_dir, "original_ts_ecos.fst")
descriptor_path <- file.path(app_dir, "tab_stat_description_ecos.fst")
log_path <- file.path(app_dir, "ecos_update_log.csv")

catalog <- read_csv(catalog_path, col_types = cols(.default = col_character()), na = character()) %>%
  mutate(
    collect_flag = as.logical(collect_flag),
    default_visible = as.logical(default_visible),
    active = as.logical(active),
    display_order = as.integer(display_order)
  )
snapshot <- read_csv(snapshot_path, col_types = cols(.default = col_character()), na = character())
config <- catalog %>% filter(source == "ECOS", collect_flag, active)

contract_path <- file.path(gate_dir, "ecos_catalog_contract_validation.csv")
if (!file.exists(contract_path)) stop("CONFIG_CODE_MISMATCH: contract validation evidence is missing")
contract <- read_csv(contract_path, col_types = cols(.default = col_character()), na = character())
if (nrow(contract) != nrow(config) || any(contract$status != "VERIFIED") || !setequal(contract$series_id, config$series_id)) {
  stop("CONFIG_CODE_MISMATCH: catalog does not match official readback validation")
}

empty_ecos <- tibble(
  date = as.Date(character()), observation_date = as.Date(character()), value = numeric(), series_id = character(),
  source = character(), available_at = character(), collected_at = character(), source_updated_at = character(),
  vintage = character(), quality_status = character(), calculation_version = character()
)
existing <- if (file.exists(target_path)) {
  read.fst(target_path, as.data.table = FALSE) %>%
    normalize_ecos_storage_schema()
} else {
  empty_ecos
}

parse_snapshot_date <- function(value, cycle) {
  value <- as.character(value)
  switch(
    toupper(cycle),
    D = as.Date(value, format = "%Y%m%d"),
    M = as.Date(paste0(value, "01"), format = "%Y%m%d"),
    Q = parse_ecos_date(value, "Q"),
    A = as.Date(paste0(value, "0101"), format = "%Y%m%d"),
    stop("Unsupported cycle: ", cycle)
  )
}

batch_id <- paste0("ECOS_", format(Sys.time(), "%Y%m%dT%H%M%S"))
downloaded <- list()
log_rows <- list()

for (i in seq_len(nrow(config))) {
  row <- config[i, ]
  prior <- existing %>% filter(series_id == row$series_id[[1]])
  official <- snapshot %>%
    filter(stat_code == row$stat_code[[1]], cycle == row$cycle[[1]], item_code == row$item_code1[[1]])
  if (nrow(official) != 1L) stop("CONFIG_CODE_MISMATCH: snapshot row missing for ", row$series_id[[1]])

  if (nrow(prior) > 0L) {
    if (toupper(row$cycle[[1]]) == "M") {
      prior_dates <- sort(unique(prior$date), decreasing = TRUE)
      start_date <- prior_dates[min(5L, length(prior_dates))]
      mode <- "INCREMENTAL_OVERLAP_5_OBSERVATIONS"
    } else {
      start_date <- previous_business_date(max(prior$date), ECOS_OVERLAP_BUSINESS_DAYS)
      mode <- "INCREMENTAL_OVERLAP_5BD"
    }
  } else {
    start_date <- parse_snapshot_date(official$start_date[[1]], row$cycle[[1]])
    mode <- "FULL_HISTORY"
  }
  official_end <- parse_snapshot_date(official$end_date[[1]], row$cycle[[1]])
  end_date <- max(Sys.Date(), official_end, na.rm = TRUE)

  started_at <- Sys.time()
  result <- ecos_collect_one_safe(row, start_date, end_date)
  completed_at <- Sys.time()
  if (startsWith(result$status, "SUCCESS")) downloaded[[length(downloaded) + 1L]] <- result$data

  log_rows[[length(log_rows) + 1L]] <- tibble(
    batch_id = batch_id,
    series_id = row$series_id[[1]],
    stat_code = row$stat_code[[1]],
    item_code1 = row$item_code1[[1]],
    mode = mode,
    request_start = as.character(start_date),
    request_end = as.character(end_date),
    status = result$status,
    rows_received = nrow(result$data),
    observation_start = if (nrow(result$data)) as.character(min(result$data$date)) else NA_character_,
    observation_end = if (nrow(result$data)) as.character(max(result$data$date)) else NA_character_,
    started_at = format(started_at, tz = "Asia/Seoul", usetz = TRUE),
    completed_at = format(completed_at, tz = "Asia/Seoul", usetz = TRUE),
    error = result$error
  )
}

batch_log <- bind_rows(log_rows)
write_csv(batch_log, file.path(gate_dir, paste0(tolower(batch_id), "_run_log.csv")))
if (file.exists(log_path)) {
  historical_log <- read_csv(
    log_path,
    col_types = cols(.default = col_character()),
    show_col_types = FALSE
  )
  write_csv(
    bind_rows(historical_log, batch_log %>% mutate(across(everything(), as.character))),
    log_path
  )
} else {
  write_csv(batch_log, log_path)
}

hard_failures <- batch_log %>% filter(status %in% c("ERROR", "SKIPPED_NO_KEY", "NO_DATA"))
if (nrow(hard_failures) > 0L) {
  stop("ECOS_COLLECTION_FAILED: ", paste(paste0(hard_failures$series_id, "=", hard_failures$status), collapse = ", "))
}

new_data <- bind_rows(downloaded)
combined <- bind_rows(existing, new_data) %>%
  arrange(source, series_id, date, desc(collected_at)) %>%
  distinct(source, series_id, date, .keep_all = TRUE) %>%
  arrange(series_id, date)

publication <- atomic_publish_ecos_fst(combined, target_path)
readback <- read.fst(target_path, as.data.table = FALSE) %>% as_tibble() %>% mutate(date = as.Date(date))
readback_check <- validate_ecos_dataset(readback)
if (!readback_check$valid || readback_check$rows != nrow(combined)) {
  stop("ECOS_INDEPENDENT_READBACK_FAILED")
}

descriptor <- readback %>%
  group_by(series_id) %>%
  summarize(
    observation_start = min(date), observation_end = max(date), n_obs = n(),
    last_value = value[which.max(date)], .groups = "drop"
  ) %>%
  right_join(config, by = "series_id") %>%
  arrange(display_order, series_id)
descriptor_staging <- paste0(descriptor_path, ".staging")
write.fst(descriptor, descriptor_staging, compress = 50)
if (file.exists(descriptor_path)) file.remove(descriptor_path)
if (!file.rename(descriptor_staging, descriptor_path)) stop("ECOS_DESCRIPTOR_PUBLICATION_FAILED")

write_csv(
  tibble(
    batch_id = batch_id,
    status = "PASS",
    configured_series = nrow(config),
    published_series = n_distinct(readback$series_id),
    rows = nrow(readback),
    duplicate_keys = readback_check$duplicate_keys,
    start_date = min(readback$date),
    end_date = max(readback$date),
    pending_source = sum(grepl("PENDING_SOURCE", batch_log$status, fixed = TRUE)),
    published = TRUE,
    completed_at = format(Sys.time(), tz = "Asia/Seoul", usetz = TRUE)
  ),
  file.path(gate_dir, "ecos_latest_publication.csv")
)

cat("ECOS collection and atomic publication: PASS (", nrow(readback), " rows, ", n_distinct(readback$series_id), " series)\n", sep = "")

