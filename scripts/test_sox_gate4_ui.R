suppressPackageStartupMessages(library(shiny))
repo_dir <- normalizePath(".", winslash = "/", mustWork = TRUE)
app_dir <- file.path(repo_dir, "apps", "timeseries")
gate_dir <- file.path(repo_dir, "docs", "gate4")
old_wd <- setwd(app_dir)
started <- Sys.time()
source("app.R", local = globalenv())
startup_seconds <- as.numeric(difftime(Sys.time(), started, units = "secs"))
setwd(old_wd)

rendered <- character()
lazy_pass <- FALSE
testServer(server, {
  stopifnot(!is.null(sox_constituents_state$latest_store()),
            !is.null(sox_constituents_state$constituent_store()), is.null(sox_constituents_state$full_store()))
  session$setInputs(main_tab = "SOX Constituents", sox_subtab = "Overview")
  session$flushReact()
  stopifnot(!is.null(sox_constituents_state$latest_store()), !is.null(sox_constituents_state$constituent_store()))
  lazy_pass <<- TRUE
  for (id in c("sox_status", "sox_benchmark_plot")) stopifnot(nzchar(output[[id]]))
  rendered <<- c(rendered, "sox_status", "sox_benchmark_plot")

  session$setInputs(sox_subtab = "Breadth"); session$flushReact()
  for (id in c("sox_breadth_plot", "sox_daily_table")) stopifnot(nzchar(output[[id]]))
  session$setInputs(sox_subtab = "Contribution"); session$flushReact(); stopifnot(nzchar(output$sox_contribution_plot))
  session$setInputs(sox_subtab = "Value Chain"); session$flushReact(); stopifnot(nzchar(output$sox_chain_plot))
  latest <- sox_constituents_state$latest_store()
  link_metric <- latest$metric_id[latest$metric_group == "us_next_korea"][[1]]
  session$setInputs(sox_subtab = "Korea Link", sox_link_metric = link_metric, sox_link_range = c(as.Date("2021-01-01"), Sys.Date()))
  session$flushReact(); stopifnot(nzchar(output$sox_korea_plot))
  session$setInputs(sox_subtab = "Constituents"); session$flushReact(); stopifnot(nzchar(output$sox_constituents_table))
  session$setInputs(sox_subtab = "Data Quality"); session$flushReact(); stopifnot(nzchar(output$sox_quality_table))
  rendered <<- c(rendered, "sox_breadth_plot", "sox_daily_table", "sox_contribution_plot", "sox_chain_plot", "sox_korea_plot", "sox_constituents_table", "sox_quality_table")
})

memory_mb <- as.numeric(ps::ps_memory_info()[["rss"]]) / 1024^2
result <- if (startup_seconds <= 5 && memory_mb <= 500 && lazy_pass && length(rendered) == 9L) "PASS" else "FAIL"
readr::write_csv(data.frame(check = c("app_startup_seconds", "session_memory_mb", "lazy_load", "rendered_outputs"),
                            value = c(startup_seconds, memory_mb, as.integer(lazy_pass), length(rendered)),
                            status = c(ifelse(startup_seconds <= 5, "PASS", "FAIL"), ifelse(memory_mb <= 500, "PASS", "FAIL"), ifelse(lazy_pass, "PASS", "FAIL"), ifelse(length(rendered) == 9L, "PASS", "FAIL"))),
                 file.path(gate_dir, "ui_smoke_metrics.csv"))
writeLines(c("# Gate 4 UI Smoke Test", "", paste0("**Result: ", result, "**"), "",
             paste0("- App startup: ", round(startup_seconds, 3), " seconds."),
             paste0("- Session RSS: ", round(memory_mb, 1), " MB."),
             "- Official membership and SOXQ proxy disclosure rendered.",
             "- Overview, Breadth, Contribution, Value Chain, Korea Link, Constituents, and Data Quality outputs rendered.",
             "- Historical derived store loaded only after the SOX tab was entered."),
           file.path(gate_dir, "ui_regression_retest.md"))
cat("Gate 4 UI smoke: ", result, " startup=", round(startup_seconds, 3), "s memory=", round(memory_mb, 1), "MB\n", sep = "")
if (result != "PASS") quit(status = 1L)
