suppressPackageStartupMessages({
  library(chromote)
  library(dplyr)
  library(processx)
  library(readr)
  library(tibble)
})

repo_dir <- normalizePath(".", winslash = "/", mustWork = TRUE)
gate_dir <- file.path(repo_dir, "docs", "gate3")
dir.create(gate_dir, recursive = TRUE, showWarnings = FALSE)
rscript <- "C:/Program Files/R/R-4.5.2/bin/Rscript.exe"
r_lib <- "C:/Users/yjh14/AppData/Local/R/win-library/4.5"
app_dir <- file.path(repo_dir, "apps", "timeseries")

now_kst <- function() format(Sys.time(), "%Y-%m-%d %H:%M:%OS3 %Z", tz = "Asia/Seoul")

start_app <- function(port, run_id) {
  log_dir <- file.path(gate_dir, "performance_logs")
  dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)
  log_path <- file.path(log_dir, paste0("gate3_perf_", run_id, ".log"))
  expression <- sprintf(
    "shiny::runApp(%s, host='127.0.0.1', port=%d, launch.browser=FALSE)",
    shQuote(app_dir), port
  )
  process$new(
    rscript, c("-e", expression), wd = repo_dir,
    env = c(R_LIBS_USER = r_lib), stdout = log_path, stderr = "2>&1",
    cleanup = TRUE, supervise = TRUE
  )
}

listener_pid <- function(port) {
  command <- sprintf("(Get-NetTCPConnection -LocalPort %d -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1).OwningProcess", as.integer(port))
  value <- suppressWarnings(system2("powershell", c("-NoProfile", "-Command", shQuote(command)), stdout = TRUE, stderr = FALSE))
  pid <- suppressWarnings(as.integer(trimws(value[[1]] %||% "")))
  if (length(pid) != 1L || is.na(pid)) NA_integer_ else pid
}

`%||%` <- function(x, y) if (is.null(x) || !length(x)) y else x

listener_memory_mb <- function(port) {
  pid <- listener_pid(port)
  if (is.na(pid)) return(NA_real_)
  tryCatch(as.numeric(ps::ps_memory_info(ps::ps_handle(pid))[["rss"]]) / 1024^2, error = function(e) NA_real_)
}

stop_app <- function(app, port) {
  pid <- listener_pid(port)
  if (!is.na(pid)) try(ps::ps_kill(ps::ps_handle(pid)), silent = TRUE)
  try(if (app$is_alive()) app$kill(), silent = TRUE)
  try(app$wait(timeout = 5000), silent = TRUE)
}

wait_for_server <- function(process, url, timeout = 15) {
  started <- Sys.time()
  repeat {
    if (!process$is_alive()) stop("Shiny process exited before startup: ", paste(process$read_all_output_lines(), collapse = "\n"))
    ok <- tryCatch({
      curl::curl_fetch_memory(url, handle = curl::new_handle(timeout = 1))
      TRUE
    }, error = function(e) FALSE)
    if (ok) return(invisible(TRUE))
    if (as.numeric(difftime(Sys.time(), started, units = "secs")) > timeout) stop("Shiny startup timeout")
    Sys.sleep(0.05)
  }
}

evaluate_value <- function(browser, expression) {
  browser$Runtime$evaluate(expression = expression, returnByValue = TRUE)$result$value
}

wait_js <- function(browser, condition, timeout = 10) {
  started <- Sys.time()
  repeat {
    value <- tryCatch(isTRUE(evaluate_value(browser, condition)), error = function(e) FALSE)
    if (value) return(invisible(TRUE))
    if (as.numeric(difftime(Sys.time(), started, units = "secs")) > timeout) stop("Browser condition timeout: ", condition)
    Sys.sleep(0.01)
  }
}

ready_condition <- function(selectors) {
  selector_json <- jsonlite::toJSON(selectors, auto_unbox = FALSE)
  sprintf(
    "(() => { const s=%s; const visible=(e)=>!!e && e.offsetParent!==null; const visibleBusy=[...document.querySelectorAll('.recalculating')].some(visible); return !document.documentElement.classList.contains('shiny-busy') && !visibleBusy && s.every(x=>visible(document.querySelector(x))); })()",
    selector_json
  )
}

click_text <- function(browser, text, selectors, scope = "a") {
  target <- jsonlite::toJSON(text, auto_unbox = TRUE)
  scope_json <- jsonlite::toJSON(scope, auto_unbox = TRUE)
  expression <- sprintf(
    "(() => { const target=[...document.querySelectorAll(%s)].find(x=>x.textContent.trim()===%s); if(!target) return false; window.__gateStart=performance.now(); target.click(); return true; })()",
    scope_json, target
  )
  if (!isTRUE(evaluate_value(browser, expression))) stop("UI target not found: ", text)
  wait_js(browser, ready_condition(selectors))
  as.numeric(evaluate_value(browser, "performance.now()-window.__gateStart")) / 1000
}

start_mutation_measure <- function(browser, target_selector, action_js) {
  target_json <- jsonlite::toJSON(target_selector, auto_unbox = TRUE)
  expression <- sprintf(
    "(() => { const target=document.querySelector(%s); if(!target) return false; if(window.__gateObserver) window.__gateObserver.disconnect(); window.__gateMutated=false; window.__gateStart=performance.now(); window.__gateObserver=new MutationObserver(()=>{window.__gateMutated=true;}); window.__gateObserver.observe(target,{subtree:true,childList:true,attributes:true,characterData:true}); %s; return true; })()",
    target_json, action_js
  )
  if (!isTRUE(evaluate_value(browser, expression))) stop("Filter target not found: ", target_selector)
  wait_js(browser, "window.__gateMutated===true && !document.documentElement.classList.contains('shiny-busy') && ![...document.querySelectorAll('.recalculating')].some(e=>e.offsetParent!==null)")
  as.numeric(evaluate_value(browser, "performance.now()-window.__gateStart")) / 1000
}

set_selectize_action <- function(id, value) {
  sprintf(
    "const el=document.getElementById(%s); if(!el || !el.selectize) throw new Error('selectize missing'); el.selectize.setValue(%s);",
    jsonlite::toJSON(id, auto_unbox = TRUE), jsonlite::toJSON(value, auto_unbox = length(value) == 1L)
  )
}

set_shiny_input_action <- function(id, value) {
  sprintf(
    "Shiny.setInputValue(%s,%s,{priority:'event'});",
    jsonlite::toJSON(id, auto_unbox = TRUE), jsonlite::toJSON(value, auto_unbox = length(value) == 1L)
  )
}

open_browser <- function(url) {
  browser <- ChromoteSession$new()
  browser$Emulation$setDeviceMetricsOverride(width = 1440, height = 1000, deviceScaleFactor = 1, mobile = FALSE)
  browser$Network$clearBrowserCache()
  browser$Page$navigate(url)
  browser$Page$loadEventFired(wait_ = TRUE)
  wait_js(browser, "!!(typeof Shiny !== 'undefined' && Shiny.shinyapp && document.querySelector('#sector_excess_plot'))")
  browser
}

initial_selectors <- c(
  "#kr_status_text:not(:empty)", "#kr_build_text:not(:empty)",
  "#kr_curve_plot.js-plotly-plot", "#kr_rate_summary_table table", "#kr_spread_summary_table table"
)

cold_rows <- list()
startup_values <- numeric()
memory_values <- numeric()

for (i in seq_len(5L)) {
  run_id <- paste0("cold_", i)
  port <- 5600L + i
  url <- paste0("http://127.0.0.1:", port, "/")
  process_started <- Sys.time()
  app <- start_app(port, run_id)
  browser <- NULL
  tryCatch({
    wait_for_server(app, url)
    startup_seconds <- as.numeric(difftime(Sys.time(), process_started, units = "secs"))
    browser <- open_browser(url)
    wait_js(browser, ready_condition(c("#sector_excess_plot.js-plotly-plot", "#sector_table table")))
    started_at <- now_kst()
    elapsed <- click_text(browser, "Korea Rates & Funding", initial_selectors)
    completed_at <- now_kst()
    memory_mb <- listener_memory_mb(port)
    cold_rows[[i]] <- tibble(
      run_id, test_type = "cold_initial_visible_render", started_at, completed_at,
      elapsed_seconds = elapsed, cache_state = "new_r_process_new_browser_cleared_cache",
      visible_outputs = "status;build;curve_plot;rate_summary;spread_summary",
      result = ifelse(elapsed <= 2, "PASS", "FAIL"), startup_seconds, memory_mb
    )
    startup_values <- c(startup_values, startup_seconds)
    memory_values <- c(memory_values, memory_mb)
  }, finally = {
    if (!is.null(browser)) browser$close()
    stop_app(app, port)
  })
}

cold <- bind_rows(cold_rows)
write_csv(cold, file.path(gate_dir, "performance_cold_runs.csv"))

port <- 5620L
url <- paste0("http://127.0.0.1:", port, "/")
app <- start_app(port, "warm_filter")
browser <- NULL
warm_rows <- list()
filter_rows <- list()
tryCatch({
  wait_for_server(app, url)
  browser <- open_browser(url)
  click_text(browser, "Korea Rates & Funding", initial_selectors)

  for (i in seq_len(10L)) {
    click_text(browser, "Sector Rotation", c("#sector_excess_plot.js-plotly-plot", "#sector_table table"))
    started_at <- now_kst()
    elapsed <- click_text(browser, "Korea Rates & Funding", initial_selectors)
    completed_at <- now_kst()
    warm_rows[[i]] <- tibble(
      run_id = paste0("warm_", i), test_type = "warm_tab_render", started_at, completed_at,
      elapsed_seconds = elapsed, cache_state = "same_session_latest_index_cached",
      visible_outputs = "status;build;curve_plot;rate_summary;spread_summary",
      result = ifelse(elapsed <= 2, "PASS", "FAIL")
    )
  }

  click_text(browser, "Yield Curve", initial_selectors, scope = "#kr_subtab a")
  filter_cases <- list(
    list(id = "tenor_a", tab = "Yield Curve", target = "#kr_curve_plot", action = set_selectize_action("kr_curve_tenors", c("2", "3", "5", "10")), visible = "curve_plot"),
    list(id = "tenor_b", tab = "Yield Curve", target = "#kr_curve_plot", action = set_selectize_action("kr_curve_tenors", c("1", "2", "3", "5", "10", "20", "30", "50")), visible = "curve_plot"),
    list(id = "tenor_c", tab = "Yield Curve", target = "#kr_curve_plot", action = set_selectize_action("kr_curve_tenors", c("3", "10", "30")), visible = "curve_plot"),
    list(id = "spread_a", tab = "Funding & Credit Spreads", target = "#kr_spread_plot", action = set_shiny_input_action("kr_spread_metric", "KTB10Y_MINUS_KTB3Y"), visible = "spread_plot"),
    list(id = "spread_b", tab = "Funding & Credit Spreads", target = "#kr_spread_plot", action = set_shiny_input_action("kr_spread_metric", "CORP_AAM3Y_MINUS_KTB3Y"), visible = "spread_plot"),
    list(id = "spread_c", tab = "Funding & Credit Spreads", target = "#kr_spread_plot", action = set_shiny_input_action("kr_spread_metric", "CORP_BBBM3Y_MINUS_AAM3Y"), visible = "spread_plot"),
    list(id = "pair_a", tab = "Korea-US Link", target = "#kr_us_plot", action = set_shiny_input_action("kr_us_pair", "KR10Y_US10Y"), visible = "kr_us_plot"),
    list(id = "pair_b", tab = "Korea-US Link", target = "#kr_us_plot", action = set_shiny_input_action("kr_us_pair", "KR3Y_US2Y"), visible = "kr_us_plot"),
    list(id = "relation_a", tab = "Korea-US Link", target = "#kr_rolling_plot", action = set_shiny_input_action("kr_roll_relation", "US10Y_TO_NEXT_KR10Y_CHANGE"), visible = "rolling_plot"),
    list(id = "relation_b", tab = "Korea-US Link", target = "#kr_rolling_plot", action = set_shiny_input_action("kr_roll_relation", "US2Y_TO_NEXT_KR3Y_CHANGE"), visible = "rolling_plot"),
    list(id = "range_a", tab = "FX Link", target = "#kr_fx_plot", action = set_shiny_input_action("kr_fx_range", c("2023-01-01", "2026-11-05")), visible = "fx_plot"),
    list(id = "range_b", tab = "FX Link", target = "#kr_fx_plot", action = set_shiny_input_action("kr_fx_range", c("2021-11-05", "2026-11-05")), visible = "fx_plot")
  )

  current_tab <- "Yield Curve"
  for (i in seq_along(filter_cases)) {
    case <- filter_cases[[i]]
    if (!identical(current_tab, case$tab)) {
      target_selector <- switch(
        case$tab,
        "Funding & Credit Spreads" = c("#kr_spread_plot.js-plotly-plot"),
        "Korea-US Link" = c("#kr_us_plot.js-plotly-plot", "#kr_rolling_plot.js-plotly-plot", "#kr_alignment_table table"),
        "FX Link" = c("#kr_fx_plot.js-plotly-plot"),
        initial_selectors
      )
      click_text(browser, case$tab, target_selector, scope = "#kr_subtab a")
      current_tab <- case$tab
    }
    started_at <- now_kst()
    elapsed <- start_mutation_measure(browser, case$target, case$action)
    completed_at <- now_kst()
    filter_rows[[i]] <- tibble(
      run_id = paste0("filter_", i), test_type = paste0("filter_response_", case$id), started_at, completed_at,
      elapsed_seconds = elapsed, cache_state = "same_session_historical_store_cached",
      visible_outputs = case$visible, result = ifelse(elapsed <= 2, "PASS", "FAIL")
    )
  }
  memory_values <- c(memory_values, listener_memory_mb(port))
}, finally = {
  if (!is.null(browser)) browser$close()
  stop_app(app, port)
})

warm <- bind_rows(warm_rows)
filters <- bind_rows(filter_rows)
write_csv(warm, file.path(gate_dir, "performance_warm_runs.csv"))
write_csv(filters, file.path(gate_dir, "performance_filter_runs.csv"))

p95 <- function(x) as.numeric(quantile(x, 0.95, names = FALSE, type = 7))
summary <- tibble(
  metric = c("cold_p50", "cold_max", "warm_p50", "warm_p95", "warm_max", "filter_p50", "filter_p95", "filter_max", "startup_max", "session_memory_max_mb"),
  value = c(median(cold$elapsed_seconds), max(cold$elapsed_seconds), median(warm$elapsed_seconds), p95(warm$elapsed_seconds), max(warm$elapsed_seconds), median(filters$elapsed_seconds), p95(filters$elapsed_seconds), max(filters$elapsed_seconds), max(startup_values), max(memory_values, na.rm = TRUE)),
  threshold = c(2, 2, 2, 2, 2, 2, 2, 2, 5, 500)
) %>% mutate(result = ifelse(value <= threshold, "PASS", "FAIL"))
write_csv(summary, file.path(gate_dir, "performance_summary.csv"))

cat("Gate 3 performance: ", ifelse(all(summary$result == "PASS"), "PASS", "FAIL"), "\n", sep = "")
print(summary)
if (!all(summary$result == "PASS")) quit(status = 1L)
