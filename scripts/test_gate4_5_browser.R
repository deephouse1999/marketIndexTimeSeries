#!/usr/bin/env Rscript

gate_r_lib <- "C:/Users/yjh14/AppData/Local/R/win-library/4.5"
if (dir.exists(gate_r_lib)) .libPaths(c(gate_r_lib, .libPaths()))
Sys.setenv(NOT_CRAN = "true")
suppressPackageStartupMessages({ library(readr); library(shinytest2) })

repo_dir <- normalizePath(Sys.getenv("MARKET_TS_REPO", unset = "."), winslash = "/", mustWork = TRUE)
app_dir <- file.path(repo_dir, "apps", "timeseries")
gate_dir <- file.path(repo_dir, "docs", "gate4_5")
dir.create(gate_dir, recursive = TRUE, showWarnings = FALSE)

app <- AppDriver$new(app_dir = app_dir, name = "gate4_5_browser", seed = 20261106,
                     load_timeout = 120000, timeout = 60000)
on.exit(app$stop(), add = TRUE)
app$wait_for_idle(timeout = 60000)

checks <- data.frame(check_id = character(), actual = character(), expected = character(), result = character())
record <- function(id, actual, expected, pass) {
  checks <<- rbind(checks, data.frame(check_id = id, actual = as.character(actual),
                                      expected = expected, result = if (isTRUE(pass)) "PASS" else "FAIL"))
}
js_text <- function(selector) app$get_js(sprintf("(() => { const x=document.querySelector(%s); return x ? x.innerText : ''; })()", jsonlite::toJSON(selector, auto_unbox = TRUE)))
plot_points <- function(id) app$get_js(sprintf("(() => { const x=document.getElementById('%s'); return x && x.data ? x.data.reduce((n,t) => n + ((t.x||[]).length),0) : 0; })()", id))

startup <- app$get_js("performance.now()") / 1000
record("app_started", round(startup, 3), "app loaded", is.finite(startup))

app$set_inputs(main_tab = "Semiconductor & Korea Link", wait_ = FALSE, timeout_ = 60000)
app$wait_for_idle(timeout = 60000)
started <- Sys.time()
app$set_inputs(link_subtab = "Physical Indicators", wait_ = FALSE, timeout_ = 60000, allow_no_input_binding_ = TRUE)
app$wait_for_idle(timeout = 60000)
physical_elapsed <- as.numeric(difftime(Sys.time(), started, units = "secs"))

status_text <- js_text("#physical_status")
page_text <- js_text("body")
dram_points <- plot_points("dram_physical_plot")
flash_points <- plot_points("flash_physical_plot")
record("physical_tab_render", round(physical_elapsed, 3), "<=2 seconds", physical_elapsed <= 2)
record("ppi_definition_warning", grepl("not TrendForce", page_text, fixed = TRUE), "warning visible", grepl("not TrendForce", page_text, fixed = TRUE))
record("dram_plot_points", dram_points, "100-150", dram_points >= 100 && dram_points <= 150)
record("flash_plot_points", flash_points, "100-150", flash_points >= 100 && flash_points <= 150)
record("physical_status_metadata", status_text, "source/frequency/unit/quality visible",
       all(vapply(c("Bank of Korea ECOS", "monthly", "2020=100", "VERIFIED_SOURCE"), grepl, logical(1), x = status_text, fixed = TRUE)))
record("physical_summary_table", grepl("Korea DRAM Producer Price Index", page_text, fixed = TRUE), "summary visible", grepl("Korea DRAM Producer Price Index", page_text, fixed = TRUE))
record("physical_correlation_table", grepl("KR_DRAM_PPI", page_text, fixed = TRUE), "correlation rows visible", grepl("KR_DRAM_PPI", page_text, fixed = TRUE))

physical_screenshot <- file.path(gate_dir, "gate4_5_physical_indicators.png")
if (file.exists(physical_screenshot)) unlink(physical_screenshot)
app$get_screenshot(file = physical_screenshot, selector = "body")

app$set_inputs(main_tab = "Series Explorer", wait_ = FALSE, timeout_ = 60000)
app$wait_for_idle(timeout = 60000)
app$set_inputs(f_group = "physical_indicator", f_search = "BWET", wait_ = FALSE,
               timeout_ = 60000, allow_no_input_binding_ = TRUE)
app$wait_for_idle(timeout = 60000)
table_text <- js_text("#currentChangeTable")
record("physical_group_bwet_visible", table_text, "BWET proxy row visible",
       grepl("Tanker Freight Futures ETF Proxy", table_text, fixed = TRUE))

app$click(selector = "#currentChangeTable table.dataTable tbody tr:first-child td:first-child")
app$wait_for_idle(timeout = 60000)
app$set_inputs(currentChangeTable_rows_selected = 1L, wait_ = FALSE, timeout_ = 60000,
               allow_no_input_binding_ = TRUE)
app$wait_for_idle(timeout = 60000)
proxy_text <- js_text("#series_proxy_note")
raw_points <- plot_points("rawLevelPlot")
record("bwet_proxy_warning", proxy_text, "ETF proxy and not official index", grepl("not a VLCC spot rate", proxy_text, fixed = TRUE) && grepl("tracking error", proxy_text, fixed = TRUE))
record("bwet_raw_plot_points", raw_points, ">=400", raw_points >= 400)

screenshot <- file.path(gate_dir, "gate4_5_local_ui.png")
if (file.exists(screenshot)) unlink(screenshot)
app$get_screenshot(file = screenshot, selector = "body")
write_csv(checks, file.path(gate_dir, "ui_browser_checks.csv"))

ok <- nrow(checks) >= 11L && all(checks$result == "PASS")
cat("Gate 4.5 browser: ", if (ok) "PASS" else "FAIL", " (", sum(checks$result == "PASS"), "/", nrow(checks), ")\n", sep = "")
if (!ok) quit(status = 1L)
