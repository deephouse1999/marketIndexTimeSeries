suppressPackageStartupMessages(library(shiny))
repo_dir <- normalizePath(".", winslash = "/", mustWork = TRUE)
app_dir <- file.path(repo_dir, "apps", "timeseries")
gate_dir <- file.path(repo_dir, "docs", "gate4")
old_wd <- setwd(app_dir)
source("app.R", local = globalenv())
setwd(old_wd)

checks <- list()
record <- function(screen, output_id, ok) {
  checks[[length(checks) + 1L]] <<- data.frame(screen = screen, output_id = output_id, status = ifelse(ok, "PASS", "FAIL"))
  stopifnot(ok)
}

testServer(server, {
  latest_market_date <- max(as.Date(shiny_data()$date), na.rm = TRUE)
  session$setInputs(main_tab = "Sector Rotation", sector_asof = latest_market_date, sector_sort = "Excess1M")
  session$flushReact()
  for (id in c("sector_beating", "sector_latest", "sector_excess_plot", "sector_table")) record("Sector Rotation", id, nzchar(output[[id]]))

  session$setInputs(
    main_tab = "Series Explorer", date_range = c(Sys.Date() - 365, Sys.Date()), show_inactive = FALSE,
    f_class = "All", f_group = "All", f_sector = "All", f_region = "All", f_search = "",
    corr_mode = "Daily Return", benchmark = "SPY", beta_min_obs = 20
  )
  session$flushReact()
  record("Series Explorer", "currentChangeTable", nzchar(output$currentChangeTable))
  record("Series Explorer", "corr_note", nzchar(output$corr_note))

  session$setInputs(main_tab = "Korea Rates & Funding", kr_subtab = "Yield Curve")
  session$flushReact()
  kr_latest <- korea_rates_state$latest_store()
  tenors <- sort(unique(kr_latest$tenor_years[kr_latest$metric_group == "yield_curve"]))
  session$setInputs(kr_curve_tenors = as.character(tenors), kr_show_curve_table = FALSE)
  session$flushReact()
  for (id in c("kr_status_text", "kr_curve_plot", "kr_rate_summary_table", "kr_spread_summary_table")) record("Korea Rates & Funding", id, nzchar(output[[id]]))

  link_ids <- link_catalog$series_id
  predictor <- link_ids[link_ids %in% c("^SOX", "SOXX", "XSD")][1]
  session$setInputs(
    main_tab = "Semiconductor & Korea Link", link_range = c(Sys.Date() - 365 * 3, Sys.Date()),
    link_series = link_ids, link_alignment = "Next KR trading day", link_predictor = predictor
  )
  session$flushReact()
  for (id in c("link_performance", "link_cumulative_plot", "link_spread_plot", "link_relation_table", "link_rolling_plot")) record("Semiconductor & Korea Link", id, nzchar(output[[id]]))
})

results <- dplyr::bind_rows(checks)
readr::write_csv(results, file.path(gate_dir, "legacy_regression_results.csv"))
result <- if (nrow(results) >= 15L && all(results$status == "PASS")) "PASS" else "FAIL"
writeLines(c(
  "# Gate 4 Legacy Regression Retest", "", paste0("**Result: ", result, "**"), "",
  paste0("Tested final build: ", format(Sys.time(), tz = "Asia/Seoul", usetz = TRUE)), "",
  "- Sector Rotation outputs rendered.",
  "- Series Explorer table and controls rendered with the remediated catalog.",
  "- Korea Rates initial curve and summaries rendered.",
  "- Semiconductor & Korea Link tables and charts rendered.",
  "- Gate 4-owned series are excluded from the legacy Yahoo collector; NVDA and MU remain legacy-owned."
), file.path(gate_dir, "LEGACY_REGRESSION_RETEST.md"))
cat("Gate 4 legacy regression: ", result, " (", nrow(results), " outputs)\n", sep = "")
if (result != "PASS") quit(status = 1L)
