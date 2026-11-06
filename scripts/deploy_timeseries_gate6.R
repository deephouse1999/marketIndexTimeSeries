#!/usr/bin/env Rscript

gate6_r_lib <- "C:/Users/yjh14/AppData/Local/R/win-library/4.5"
if (dir.exists(gate6_r_lib)) .libPaths(c(gate6_r_lib, .libPaths()))
suppressPackageStartupMessages({ library(readr); library(rsconnect) })

repo_dir <- normalizePath(".", winslash = "/", mustWork = TRUE)
app_dir <- file.path(repo_dir, "apps", "timeseries")
gate_dir <- file.path(repo_dir, "docs", "gate6")
all_files <- list.files(app_dir, recursive = TRUE, all.files = TRUE, no.. = TRUE)
exclude <- grepl("(^|/)rsconnect/|\\.last_good$|\\.staging$|^original_ts_sox_components\\.fst$|^ecos_update_log\\.csv$|^ts_update_log\\.csv$", all_files)
app_files <- all_files[!exclude]
required <- c(
  "app.R", "series_catalog.csv", "original_ts_fred.fst", "original_ts_yahoo.fst",
  "original_ts_ecos.fst", "physical_indicators_server.R", "derived_physical_indicators.fst",
  "derived_series_explorer.fst", "derived_market_ui_core.fst",
  "derived_korea_rates_summary.fst", "derived_korea_rates_latest.fst",
  "derived_sox_daily_summary.fst", "derived_sox_latest.fst", "derived_sox_overview.png",
  "sox_constituents.csv"
)
missing <- setdiff(required, app_files)
if (length(missing)) stop("DEPLOYMENT_REQUIRED_FILE_MISSING: ", paste(missing, collapse = ","))

manifest <- data.frame(
  file = app_files,
  bytes = file.info(file.path(app_dir, app_files))$size,
  stringsAsFactors = FALSE
)
write_csv(manifest, file.path(gate_dir, "deployment_manifest.csv"))
cat("Deployment bundle:", nrow(manifest), "files,", round(sum(manifest$bytes) / 1024^2, 2), "MB\n")

accounts <- rsconnect::accounts()
if (!any(accounts$name == "deephouse1999")) stop("RSCONNECT_ACCOUNT_NOT_CONFIGURED")
rsconnect::deployApp(
  appDir = app_dir,
  appFiles = app_files,
  appName = "market_timeseries",
  account = "deephouse1999",
  forceUpdate = TRUE,
  launch.browser = FALSE
)
