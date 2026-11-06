#!/usr/bin/env Rscript

gate6_r_lib <- "C:/Users/yjh14/AppData/Local/R/win-library/4.5"
if (dir.exists(gate6_r_lib)) .libPaths(c(gate6_r_lib, .libPaths()))
suppressPackageStartupMessages({ library(shiny); library(readr) })

repo_dir <- normalizePath(".", winslash = "/", mustWork = TRUE)
app_dir <- file.path(repo_dir, "apps", "timeseries")
gate_dir <- file.path(repo_dir, "docs", "gate6")
old_wd <- setwd(app_dir)
started <- Sys.time()
source("app.R", local = globalenv())
startup_seconds <- as.numeric(difftime(Sys.time(), started, units = "secs"))
setwd(old_wd)

loaded_series_cache <- FALSE
sox_assets_loaded <- FALSE
physical_assets_loaded <- FALSE
testServer(server, {
  session$setInputs(main_tab = "Korea Rates & Funding", kr_subtab = "Yield Curve")
  session$flushReact()
  session$setInputs(main_tab = "Series Explorer")
  session$flushReact()
  loaded_series_cache <<- isTRUE(full_market_loaded()) && nrow(shiny_data()) > 700000L
  session$setInputs(main_tab = "Sector Rotation")
  session$flushReact()
  session$setInputs(main_tab = "SOX Constituents", sox_subtab = "Overview")
  session$flushReact()
  sox_assets_loaded <<- !is.null(sox_constituents_state$latest_store()) && !is.null(sox_constituents_state$constituent_store())
  session$setInputs(main_tab = "Semiconductor & Korea Link", link_subtab = "Physical Indicators")
  session$flushReact()
  physical_assets_loaded <<- !is.null(physical_indicators_state$raw_store()) &&
    !is.null(physical_indicators_state$derived_store())
})
gc(FALSE)
memory_mb <- as.numeric(ps::ps_memory_info()[["rss"]]) / 1024^2
source_files <- file.path(app_dir, c("app.R", "sector_server.R", "link_server.R", "physical_indicators_server.R", "korea_rates_server.R", "sox_constituents_server.R"))
source_text <- paste(unlist(lapply(source_files, readLines, warn = FALSE)), collapse = "\n")
startup_api_call <- grepl("httr::|GET\\(|POST\\(|fredr\\(|getSymbols\\(|StatisticSearch", source_text)

checks <- data.frame(
  check = c("startup_seconds", "session_memory_mb", "series_explorer_cache_loaded", "sox_initial_assets_loaded", "physical_lazy_assets_loaded", "startup_external_api_call"),
  actual = c(startup_seconds, memory_mb, loaded_series_cache, sox_assets_loaded, physical_assets_loaded, startup_api_call),
  expected = c("<=5", "<=500", "TRUE", "TRUE", "TRUE", "FALSE"),
  result = c(ifelse(startup_seconds <= 5, "PASS", "FAIL"), ifelse(memory_mb <= 500, "PASS", "FAIL"),
             ifelse(loaded_series_cache, "PASS", "FAIL"), ifelse(sox_assets_loaded, "PASS", "FAIL"),
             ifelse(physical_assets_loaded, "PASS", "FAIL"), ifelse(!startup_api_call, "PASS", "FAIL"))
)
write_csv(checks, file.path(gate_dir, "server_runtime_checks.csv"))
cat("Gate 6 server runtime: ", ifelse(all(checks$result == "PASS"), "PASS", "FAIL"), " startup=", round(startup_seconds, 3), "s rss=", round(memory_mb, 1), "MB\n", sep = "")
if (any(checks$result != "PASS")) quit(status = 1L)
