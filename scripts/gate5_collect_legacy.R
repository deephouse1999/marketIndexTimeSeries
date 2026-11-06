#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
scope <- tolower(if (length(args)) args[[1]] else "")
if (!scope %in% c("us", "kr")) stop("Usage: gate5_collect_legacy.R <us|kr>")

options(market_ts.skip_autorun = TRUE)
source(file.path("apps", "timeseries", "dataExtract_fredyahoo.R"), local = TRUE)
catalog <- read_series_catalog(catalog_path)
log_rows_before <- if (file.exists(update_log_path)) nrow(readr::read_csv(update_log_path, show_col_types = FALSE)) else 0L

if (scope == "us") {
  if (!nzchar(get_fred_api_key())) stop("FRED_API_KEY_NOT_BOUND")
  run_market_data_update(update_fred = TRUE, update_yahoo = TRUE)
} else {
  kr_ids <- unique(c(
    "^KS11", "000660.KS", "USDKRW=X",
    catalog$series_id[catalog$source == "YAHOO" & catalog$region %in% c("Korea", "South Korea")]
  ))
  config <- catalog[catalog$source == "YAHOO" & catalog$series_id %in% kr_ids, , drop = FALSE]
  config$collect_flag <- TRUE
  config$active <- TRUE
  updated <- update_series(config, yahoo_ts_path, safe_yahoo_series, "YAHOO", as.Date("1976-01-01"))
  write.fst(build_descriptor(updated, catalog[catalog$source == "YAHOO", , drop = FALSE]), yahoo_desc_path, compress = 50)

  component_id <- "005930.KS"
  component_config <- catalog[catalog$source == "YAHOO" & catalog$series_id == component_id, , drop = FALSE]
  if (!nrow(component_config)) stop("KR_CRITICAL_SERIES_NOT_IN_CATALOG: ", component_id)
  component_config$collect_flag <- TRUE
  component_config$active <- TRUE
  component_path <- file.path(data_dir, "original_ts_sox_components.fst")
  update_series(component_config, component_path, safe_yahoo_series, "YAHOO", as.Date("1976-01-01"))
}

all_log <- readr::read_csv(update_log_path, show_col_types = FALSE)
run_log <- if (nrow(all_log) > log_rows_before) all_log[(log_rows_before + 1L):nrow(all_log), , drop = FALSE] else all_log[0, , drop = FALSE]
hard_fail <- run_log$status %in% c("error", "empty_new_series")
readr::write_csv(
  run_log %>%
    mutate(scope = scope, gate5_result = ifelse(hard_fail, "FAIL", "PASS")) %>%
    select(scope, everything()),
  file.path(data_dir, "gate5_legacy_result.csv")
)
if (any(hard_fail)) {
  failures <- run_log[hard_fail, , drop = FALSE]
  stop("LEGACY_COLLECTION_PARTIAL_FAILURE: ", paste(paste0(failures$series_id, "=", failures$status), collapse = ","))
}
