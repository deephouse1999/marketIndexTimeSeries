suppressPackageStartupMessages({
  library(chromote); library(dplyr); library(jsonlite); library(readr); library(tibble)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 4L) stop("Usage: mode url run_id startup_seconds")
mode <- args[[1]]
url <- args[[2]]
run_id <- args[[3]]
startup_seconds <- as.numeric(args[[4]])
repo_dir <- normalizePath(".", winslash = "/", mustWork = TRUE)
gate_dir <- Sys.getenv("MARKET_TS_PERF_DIR", unset = file.path(repo_dir, "docs", "gate4"))
dir.create(gate_dir, recursive = TRUE, showWarnings = FALSE)

js_eval <- function(browser, expression) {
  browser$Runtime$evaluate(expression = expression, returnByValue = TRUE)$result$value
}
wait_for <- function(browser, expression, timeout = 10) {
  started <- Sys.time()
  repeat {
    if (isTRUE(js_eval(browser, expression))) return(TRUE)
    if (as.numeric(difftime(Sys.time(), started, units = "secs")) > timeout) return(FALSE)
    Sys.sleep(.025)
  }
}
click_text <- function(browser, selector, label) {
  code <- paste0(
    "(() => { const x=[...document.querySelectorAll(", toJSON(selector, auto_unbox = TRUE), ")].find(v=>v.textContent.trim()===",
    toJSON(label, auto_unbox = TRUE), "); if(!x)return false; x.click(); return true; })()"
  )
  isTRUE(js_eval(browser, code))
}
result_row <- function(id, type, started_at, elapsed, cache_state, visible_outputs, result) {
  started_text <- format(started_at, tz = "Asia/Seoul", usetz = TRUE)
  completed_text <- format(started_at + elapsed, tz = "Asia/Seoul", usetz = TRUE)
  tibble(
    run_id = id, test_type = type,
    started_at = started_text,
    completed_at = completed_text,
    elapsed_seconds = elapsed, cache_state, visible_outputs, result,
    app_startup_seconds = startup_seconds,
    measurement_method = "CHROMIUM_DOM_VISIBLE_RENDER"
  )
}

browser <- ChromoteSession$new()
on.exit(try(browser$close(), silent = TRUE), add = TRUE)
browser$Emulation$setDeviceMetricsOverride(width = 1440, height = 1000, deviceScaleFactor = 1, mobile = FALSE)
browser$Page$navigate(url)
browser$Page$loadEventFired(wait_ = TRUE)
stopifnot(wait_for(browser, "document.querySelectorAll('.navbar a').length > 0"))
stopifnot(wait_for(browser, "window.Shiny && Shiny.shinyapp && Shiny.shinyapp.$socket && Shiny.shinyapp.$socket.readyState === 1 && !document.body.classList.contains('shiny-busy')"))
if (mode == "cold") {
  stopifnot(wait_for(browser, "!!document.querySelector('#sox_benchmark_plot img') && !document.body.classList.contains('shiny-busy')"))
}

if (mode == "cold") {
  t0 <- Sys.time()
  clicked <- click_text(browser, ".navbar a", "SOX Constituents")
  ready <- wait_for(browser, "!document.body.classList.contains('shiny-busy') && !!document.querySelector('#sox_benchmark_plot img') && document.querySelector('#sox_benchmark_plot').offsetParent !== null")
  elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  out <- result_row(paste0("browser_cold_", run_id), "cold_initial_visible_render", t0, elapsed,
                    "fresh_r_process_and_browser", "status+benchmark", ifelse(clicked && ready && elapsed <= 2, "PASS", "FAIL"))
  write_csv(out, file.path(gate_dir, paste0("performance_cold_run_", run_id, ".csv")))
  quit(status = ifelse(out$result == "PASS", 0L, 1L))
}

stopifnot(mode == "warm_filter", click_text(browser, ".navbar a", "SOX Constituents"))
stopifnot(wait_for(browser, "!!document.querySelector('#sox_benchmark_plot img')"))
views <- tribble(
  ~label, ~ready_js,
  "Breadth", "!!document.querySelector('#sox_breadth_plot .plot-container.plotly')",
  "Contribution", "!!document.querySelector('#sox_contribution_plot .plot-container.plotly')",
  "Value Chain", "!!document.querySelector('#sox_chain_plot .plot-container.plotly')",
  "Korea Link", "!!document.querySelector('#sox_korea_plot .plot-container.plotly')",
  "Constituents", "!!document.querySelector('#sox_constituents_table table')",
  "Data Quality", "!!document.querySelector('#sox_quality_table table')",
  "Overview", "!!document.querySelector('#sox_benchmark_plot img')"
)
warm_rows <- vector("list", 10L)
for (i in seq_len(10L)) {
  v <- views[(i - 1L) %% nrow(views) + 1L, ]
  t0 <- Sys.time(); clicked <- click_text(browser, "#sox_subtab a", v$label)
  ready <- wait_for(browser, paste0("!document.body.classList.contains('shiny-busy') && (", v$ready_js, ")"))
  elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  warm_rows[[i]] <- result_row(paste0("browser_warm_", i), "warm_tab_visible_render", t0, elapsed,
                               "warm_browser_session", v$label, ifelse(clicked && ready && elapsed <= 2, "PASS", "FAIL"))
}
warm <- bind_rows(warm_rows)
write_csv(warm, file.path(gate_dir, "performance_warm_runs.csv"))

stopifnot(click_text(browser, "#sox_subtab a", "Korea Link"), wait_for(browser, "!!document.querySelector('#sox_korea_plot .plot-container.plotly')"))
filter_rows <- vector("list", 10L)
for (i in seq_len(10L)) {
  end_date <- as.Date("2026-11-06") - (i - 1L) * 15L
  start_date <- end_date - 365L * 3L
  expression <- paste0(
    "(() => { window.__gate4_before=document.querySelector('#sox_korea_plot').innerHTML; Shiny.setInputValue('sox_link_range', [",
    toJSON(as.character(start_date), auto_unbox = TRUE), ",", toJSON(as.character(end_date), auto_unbox = TRUE),
    "], {priority:'event'}); return true; })()"
  )
  t0 <- Sys.time(); triggered <- isTRUE(js_eval(browser, expression))
  ready <- wait_for(browser, "!document.body.classList.contains('shiny-busy') && document.querySelector('#sox_korea_plot').innerHTML !== window.__gate4_before && !!document.querySelector('#sox_korea_plot .plot-container.plotly')")
  elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  filter_rows[[i]] <- result_row(paste0("browser_filter_", i), "filter_visible_response", t0, elapsed,
                                 "warm_browser_session", "Korea Link Plotly", ifelse(triggered && ready && elapsed <= 2, "PASS", "FAIL"))
}
filter_runs <- bind_rows(filter_rows)
write_csv(filter_runs, file.path(gate_dir, "performance_filter_runs.csv"))
browser$screenshot(filename = file.path(gate_dir, "sox_final_browser_performance.png"), selector = "body")

cold <- bind_rows(lapply(list.files(gate_dir, "^performance_cold_run_[1-5]\\.csv$", full.names = TRUE), read_csv, show_col_types = FALSE))
write_csv(cold, file.path(gate_dir, "performance_cold_runs.csv"))
summary <- tibble(
  test = c("cold_max", "warm_p50", "warm_p95", "warm_max", "filter_p50", "filter_p95", "filter_max", "startup_max"),
  seconds_or_mb = c(max(cold$elapsed_seconds), median(warm$elapsed_seconds), quantile(warm$elapsed_seconds, .95), max(warm$elapsed_seconds), median(filter_runs$elapsed_seconds), quantile(filter_runs$elapsed_seconds, .95), max(filter_runs$elapsed_seconds), max(c(cold$app_startup_seconds, warm$app_startup_seconds)))
)
write_csv(summary, file.path(gate_dir, "performance_summary.csv"))
all_pass <- nrow(cold) == 5L && all(cold$result == "PASS") && all(warm$result == "PASS") && all(filter_runs$result == "PASS") && summary$seconds_or_mb[summary$test == "startup_max"] <= 5
cat("Browser performance: ", ifelse(all_pass, "PASS", "FAIL"), "\n", sep = "")
if (!all_pass) quit(status = 1L)
