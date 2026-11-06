suppressPackageStartupMessages({ library(shiny); library(dplyr); library(readr) })
args <- commandArgs(trailingOnly = TRUE)
mode <- args[[1]]
run_id <- args[[2]]
out_path <- args[[3]]
repo_dir <- normalizePath(".", winslash = "/", mustWork = TRUE)
app_dir <- file.path(repo_dir, "apps", "timeseries")
old_wd <- setwd(app_dir)
source_started <- Sys.time()
source("app.R", local = globalenv())
startup <- as.numeric(difftime(Sys.time(), source_started, units = "secs"))
setwd(old_wd)
rows <- list()
add_row <- function(id, type, started, completed, cache_state, visible, result = "PASS") {
  rows[[length(rows) + 1L]] <<- data.frame(
    run_id = id, test_type = type,
    started_at = format(started, tz = "Asia/Seoul", usetz = TRUE),
    completed_at = format(completed, tz = "Asia/Seoul", usetz = TRUE),
    elapsed_seconds = as.numeric(difftime(completed, started, units = "secs")),
    cache_state = cache_state, visible_outputs = visible, result = result,
    app_startup_seconds = startup
  )
}

testServer(server, {
  if (mode == "cold") {
    t0 <- Sys.time()
    session$setInputs(main_tab = "SOX Constituents", sox_subtab = "Overview")
    session$flushReact()
    rendered <- output$sox_benchmark_plot
    t1 <- Sys.time()
    add_row(run_id, "cold_initial_visible_render", t0, t1, "fresh_process", "status+benchmark", ifelse(nzchar(rendered), "PASS", "FAIL"))
  } else {
    session$setInputs(main_tab = "SOX Constituents", sox_subtab = "Overview")
    session$flushReact(); invisible(output$sox_benchmark_plot)
    if (mode == "warm") {
      tabs <- rep(c("Breadth", "Contribution", "Value Chain", "Overview"), length.out = 10)
      ids <- c(Breadth = "sox_breadth_plot", Contribution = "sox_contribution_plot", `Value Chain` = "sox_chain_plot", Overview = "sox_benchmark_plot")
      for (i in seq_along(tabs)) {
        t0 <- Sys.time(); session$setInputs(sox_subtab = tabs[[i]]); session$flushReact(); rendered <- output[[ids[[tabs[[i]]]]]]; t1 <- Sys.time()
        add_row(paste0(run_id, "_", i), "warm_tab_render", t0, t1, "warm_session", ids[[tabs[[i]]]], ifelse(nzchar(rendered), "PASS", "FAIL"))
      }
    } else {
      d <- fst::read_fst(file.path(app_dir, "derived_sox_latest.fst"))
      metric <- d$metric_id[d$metric_group == "us_next_korea"][[1]]
      session$setInputs(sox_subtab = "Korea Link", sox_link_metric = metric)
      session$flushReact()
      ends <- as.Date("2026-11-05") - 0:9 * 15
      for (i in seq_along(ends)) {
        t0 <- Sys.time(); session$setInputs(sox_link_range = c(ends[[i]] - 365 * 3, ends[[i]])); session$flushReact(); rendered <- output$sox_korea_plot; t1 <- Sys.time()
        add_row(paste0(run_id, "_", i), "filter_response", t0, t1, "warm_cached_store", "korea_link_plot", ifelse(nzchar(rendered), "PASS", "FAIL"))
      }
    }
  }
})
write_csv(bind_rows(rows), out_path)
