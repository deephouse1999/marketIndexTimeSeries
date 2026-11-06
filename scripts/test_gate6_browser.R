#!/usr/bin/env Rscript

gate6_r_lib <- "C:/Users/yjh14/AppData/Local/R/win-library/4.5"
if (dir.exists(gate6_r_lib)) .libPaths(c(gate6_r_lib, .libPaths()))
Sys.setenv(NOT_CRAN = "true")
suppressPackageStartupMessages({
  library(readr)
  library(shinytest2)
})

repo_dir <- normalizePath(Sys.getenv("MARKET_TS_REPO", unset = "."), winslash = "/", mustWork = TRUE)
app_dir <- file.path(repo_dir, "apps", "timeseries")
gate_dir <- file.path(repo_dir, "docs", "gate6")
download_dir <- file.path(gate_dir, "downloads")
dir.create(download_dir, recursive = TRUE, showWarnings = FALSE)
unlink(list.files(download_dir, full.names = TRUE), force = TRUE)

app <- AppDriver$new(
  app_dir = app_dir,
  name = "gate6_final_browser",
  seed = 20261106,
  load_timeout = 120000,
  timeout = 60000
)
on.exit(app$stop(), add = TRUE)
app$wait_for_idle(timeout = 60000)

checks <- data.frame(screen = character(), check = character(), actual = character(), result = character())
record <- function(screen, check, actual, pass) {
  checks <<- rbind(checks, data.frame(screen = screen, check = check, actual = as.character(actual), result = if (isTRUE(pass)) "PASS" else "FAIL"))
}
has_output <- function(id) {
  value <- tryCatch(app$get_value(output = id), error = function(e) NULL)
  if (!is.null(value) && length(value) > 0L) return(TRUE)
  tryCatch(
    isTRUE(app$get_js(sprintf("(() => { const x=document.getElementById('%s'); return !!x && x.childElementCount > 0; })()", id))),
    error = function(e) FALSE
  )
}
select_tab <- function(label) {
  started <- Sys.time()
  app$set_inputs(main_tab = label, wait_ = FALSE, timeout_ = 60000)
  app$wait_for_idle(timeout = 60000)
  as.numeric(difftime(Sys.time(), started, units = "secs"))
}

tab_times <- numeric()
tab_times["Sector Rotation"] <- select_tab("Sector Rotation")
for (id in c("sector_beating", "sector_latest", "sector_excess_plot", "sector_table")) record("Sector Rotation", id, has_output(id), has_output(id))

tab_times["Series Explorer"] <- select_tab("Series Explorer")
app$set_inputs(
  date_range = c(as.character(Sys.Date() - 365L), as.character(Sys.Date())),
  f_class = "All", f_group = "All", f_sector = "All", f_region = "All", f_search = "",
  corr_mode = "Daily Return", benchmark = "SPY", beta_min_obs = 20,
  wait_ = FALSE,
  timeout_ = 60000,
  allow_no_input_binding_ = TRUE
)
app$click(selector = "#currentChangeTable table.dataTable tbody tr:first-child td:first-child")
app$wait_for_idle(timeout = 60000)
app$set_inputs(currentChangeTable_rows_selected = 1L, wait_ = FALSE, timeout_ = 60000, allow_no_input_binding_ = TRUE)
app$wait_for_idle(timeout = 60000)
try(app$wait_for_js("document.querySelector('#download_selected_csv') !== null", timeout = 10000), silent = TRUE)
for (id in c("currentChangeTable", "corr_note", "download_selected_ui")) record("Series Explorer", id, has_output(id), has_output(id))

series_download <- tryCatch(app$get_download("download_selected_csv", filename = file.path(download_dir, "selected_market_series.csv")), error = identity)
series_ok <- !inherits(series_download, "error") && file.exists(file.path(download_dir, "selected_market_series.csv"))
if (series_ok) {
  series_csv <- read_csv(file.path(download_dir, "selected_market_series.csv"), show_col_types = FALSE)
  series_ok <- nrow(series_csv) > 0L && all(c("date", "series_id", "effective_value", "source") %in% names(series_csv))
}
series_actual <- if (series_ok) nrow(series_csv) else if (inherits(series_download, "error")) conditionMessage(series_download) else "FILE_NOT_CREATED"
record("Series Explorer", "csv_download", series_actual, series_ok)

tab_times["Korea Rates & Funding"] <- select_tab("Korea Rates & Funding")
app$set_inputs(kr_subtab = "Yield Curve", wait_ = FALSE, timeout_ = 60000, allow_no_input_binding_ = TRUE)
app$wait_for_idle(timeout = 60000)
for (id in c("kr_status_text", "kr_curve_plot", "kr_rate_summary_table", "kr_spread_summary_table")) record("Korea Rates & Funding", id, has_output(id), has_output(id))
app$set_inputs(kr_subtab = "Data Quality", wait_ = FALSE, timeout_ = 60000)
app$wait_for_idle(timeout = 60000)
app$set_inputs(kr_download_group = "all", wait_ = FALSE, timeout_ = 60000)
app$wait_for_idle(timeout = 60000)
kr_download <- tryCatch(app$get_download("download_korea_rates", filename = file.path(download_dir, "korea_rates.csv")), error = identity)
kr_ok <- !inherits(kr_download, "error") && file.exists(file.path(download_dir, "korea_rates.csv"))
if (kr_ok) {
  kr_csv <- read_csv(file.path(download_dir, "korea_rates.csv"), show_col_types = FALSE)
  kr_ok <- nrow(kr_csv) > 0L && all(c("metric_id", "metric_group", "observation_date", "value") %in% names(kr_csv))
}
kr_actual <- if (kr_ok) nrow(kr_csv) else if (inherits(kr_download, "error")) conditionMessage(kr_download) else "FILE_NOT_CREATED"
record("Korea Rates & Funding", "csv_download", kr_actual, kr_ok)

tab_times["SOX Constituents"] <- select_tab("SOX Constituents")
app$set_inputs(sox_subtab = "Overview", wait_ = FALSE, timeout_ = 60000, allow_no_input_binding_ = TRUE)
app$wait_for_idle(timeout = 60000)
for (id in c("sox_status", "sox_benchmark_plot")) record("SOX Constituents", id, has_output(id), has_output(id))
for (subtab in c("Breadth", "Contribution", "Value Chain", "Korea Link", "Constituents", "Data Quality")) {
  app$set_inputs(sox_subtab = subtab, wait_ = FALSE, timeout_ = 60000)
  app$wait_for_idle(timeout = 60000)
}
for (id in c("sox_breadth_plot", "sox_daily_table", "sox_contribution_plot", "sox_chain_plot", "sox_korea_plot", "sox_constituents_table", "sox_quality_table")) record("SOX Constituents", id, has_output(id), has_output(id))
sox_download <- tryCatch(app$get_download("download_sox_data", filename = file.path(download_dir, "derived_sox_daily_summary.csv")), error = identity)
sox_ok <- !inherits(sox_download, "error") && file.exists(file.path(download_dir, "derived_sox_daily_summary.csv"))
if (sox_ok) {
  sox_csv <- read_csv(file.path(download_dir, "derived_sox_daily_summary.csv"), show_col_types = FALSE)
  sox_ok <- nrow(sox_csv) > 0L && all(c("date", "metric_group", "metric_id", "value") %in% names(sox_csv))
}
sox_actual <- if (sox_ok) nrow(sox_csv) else if (inherits(sox_download, "error")) conditionMessage(sox_download) else "FILE_NOT_CREATED"
record("SOX Constituents", "csv_download", sox_actual, sox_ok)

tab_times["Semiconductor & Korea Link"] <- select_tab("Semiconductor & Korea Link")
for (id in c("link_performance", "link_cumulative_plot", "link_spread_plot", "link_relation_table", "link_rolling_plot")) record("Semiconductor & Korea Link", id, has_output(id), has_output(id))

app$set_inputs(main_tab = "SOX Constituents", sox_subtab = "Overview", wait_ = FALSE, timeout_ = 60000)
app$wait_for_idle(timeout = 60000)
screenshot_path <- file.path(gate_dir, "gate6_final_local_app.png")
if (file.exists(screenshot_path)) unlink(screenshot_path)
app$get_screenshot(file = screenshot_path, selector = "body")

tab_metrics <- data.frame(screen = names(tab_times), elapsed_seconds = as.numeric(tab_times), result = ifelse(tab_times <= 2, "PASS", "FAIL"))
write_csv(checks, file.path(gate_dir, "browser_functional_checks.csv"))
write_csv(tab_metrics, file.path(gate_dir, "main_tab_render_times.csv"))
result <- nrow(checks) >= 27L && all(checks$result == "PASS") && all(tab_metrics$result == "PASS")
cat("Gate 6 browser functional: ", if (result) "PASS" else "FAIL", " (", sum(checks$result == "PASS"), "/", nrow(checks), ")\n", sep = "")
if (!result) quit(status = 1L)
