gate6_r_lib <- "C:/Users/yjh14/AppData/Local/R/win-library/4.5"
if (dir.exists(gate6_r_lib)) .libPaths(c(gate6_r_lib, .libPaths()))
Sys.setenv(NOT_CRAN = "true")

suppressPackageStartupMessages({
  library(readr)
  library(shinytest2)
  library(tibble)
})

repo_dir <- normalizePath(".", winslash = "/", mustWork = TRUE)
app_dir <- file.path(repo_dir, "apps", "timeseries")
gate_dir <- file.path(repo_dir, "docs", "gate6")
dir.create(gate_dir, recursive = TRUE, showWarnings = FALSE)

app <- AppDriver$new(app_dir, name = "series-explorer-plots", load_timeout = 120000,
                     timeout = 60000, seed = 20261106, width = 1600, height = 1000)
on.exit(app$stop(), add = TRUE)
app$wait_for_idle(timeout = 60000)

app$set_inputs(
  main_tab = "Series Explorer",
  date_range = c("2024-11-01", "2026-11-06"),
  f_class = "All", f_group = "All", f_sector = "All", f_region = "All",
  f_search = "BAMLH0A0HYM2", corr_mode = "Daily Return", benchmark = "SPY",
  beta_min_obs = 20, wait_ = FALSE, timeout_ = 60000, allow_no_input_binding_ = TRUE
)
app$wait_for_idle(timeout = 60000)
app$click(selector = "#currentChangeTable table.dataTable tbody tr:first-child td:first-child")
app$wait_for_idle(timeout = 60000)
app$set_inputs(currentChangeTable_rows_selected = 1L, wait_ = FALSE, timeout_ = 60000,
               allow_no_input_binding_ = TRUE)
app$wait_for_idle(timeout = 60000)

trace_json <- app$get_js("(() => { const root=document.getElementById('rawLevelPlot'); const p=root?.data ? root : (root?.querySelector('.js-plotly-plot') || root?.querySelector('.plotly')); if(!p?.data) return '[]'; return JSON.stringify(p.data.map(t => { const y=Array.from(t.y || []).map(Number).filter(Number.isFinite); return {type:t.type, mode:t.mode, n:t.y?.length || 0, finite:y.length, range:y.length ? Math.max(...y)-Math.min(...y) : 0}; })); })()")
traces <- jsonlite::fromJSON(trace_json)
raw_ok <- nrow(traces) >= 1L && any(traces$type == "scatter" & traces$finite >= 100L & traces$range > 0.01)
mom_rows <- app$get_js("document.querySelectorAll('#momStatsTable table.dataTable tbody tr').length")
mom_text <- app$get_js("document.querySelector('#momStatsTable')?.innerText || ''")
mom_ok <- is.numeric(mom_rows) && mom_rows >= 1L && !grepl("Error", mom_text, ignore.case = TRUE)

checks <- tibble(
  check = c("raw_source_line_trace", "monthly_return_distribution"),
  actual = c(if (nrow(traces)) paste0(traces$finite, " rows; range=", round(traces$range, 4), collapse = "/") else "0", as.character(mom_rows)),
  result = ifelse(c(raw_ok, mom_ok), "PASS", "FAIL")
)
write_csv(checks, file.path(gate_dir, "series_explorer_plot_checks.csv"))
screenshot_path <- file.path(gate_dir, "series_explorer_raw_plot.png")
if (file.exists(screenshot_path)) unlink(screenshot_path)
app$get_screenshot(file = screenshot_path, selector = "#rawLevelPlot")

ok <- all(checks$result == "PASS")
cat("Series Explorer plots: ", ifelse(ok, "PASS", "FAIL"), " (", sum(checks$result == "PASS"), "/", nrow(checks), ")\n", sep = "")
if (!ok) quit(status = 1L)
