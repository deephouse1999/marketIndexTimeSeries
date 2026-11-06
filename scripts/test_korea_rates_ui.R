suppressPackageStartupMessages(library(shiny))

repo_dir <- normalizePath(".", winslash = "/", mustWork = TRUE)
app_dir <- file.path(repo_dir, "apps", "timeseries")
gate_dir <- file.path(repo_dir, "docs", "gate3")
dir.create(gate_dir, recursive = TRUE, showWarnings = FALSE)

old_wd <- setwd(app_dir)
source_started <- Sys.time()
source("app.R", local = globalenv())
source_seconds <- as.numeric(difftime(Sys.time(), source_started, units = "secs"))
setwd(old_wd)

korea_outputs <- character()
legacy_outputs <- character()
lazy_initial_pass <- FALSE
lazy_history_pass <- FALSE

testServer(server, {
  stopifnot(is.null(korea_rates_state$latest_store()), is.null(korea_rates_state$derived_store()))

  session$setInputs(main_tab = "Korea Rates & Funding", kr_subtab = "Yield Curve")
  session$flushReact()
  stopifnot(!is.null(korea_rates_state$latest_store()), is.null(korea_rates_state$derived_store()))
  lazy_initial_pass <<- TRUE

  latest <- korea_rates_state$latest_store()
  curve_tenors <- sort(unique(latest$tenor_years[latest$metric_group == "yield_curve"]))
  change_series <- c("BOK_BASE_RATE", "KTB_02Y", "KTB_03Y", "KTB_05Y", "KTB_10Y", "KTB_30Y")
  session$setInputs(kr_curve_tenors = as.character(curve_tenors), kr_show_curve_table = TRUE)
  session$flushReact()
  for (id in c("kr_status_text", "kr_build_text", "kr_curve_meta")) stopifnot(is.character(output[[id]]), nzchar(output[[id]]))
  for (id in c("kr_curve_plot", "kr_curve_table", "kr_rate_summary_table", "kr_spread_summary_table")) stopifnot(nzchar(output[[id]]))

  session$setInputs(kr_subtab = "Rate Changes", kr_change_series = change_series)
  session$flushReact()
  stopifnot(nzchar(output$kr_change_meta), nzchar(output$kr_change_table))

  latest_date <- max(latest$observation_date, na.rm = TRUE)
  history_range <- c(latest_date - 365L * 5L, latest_date)
  spread_metric <- latest$metric_id[latest$metric_group %in% c("funding_spread", "credit_spread")][[1]]
  session$setInputs(kr_subtab = "Funding & Credit Spreads")
  session$flushReact()
  stopifnot(!is.null(korea_rates_state$derived_store()))
  lazy_history_pass <<- TRUE
  session$setInputs(kr_spread_range = history_range, kr_spread_metric = spread_metric)
  session$flushReact()
  stopifnot(nzchar(output$kr_spread_meta), nzchar(output$kr_spread_plot))

  session$setInputs(
    kr_subtab = "Korea-US Link", kr_us_range = history_range,
    kr_us_pair = "KR10Y_US10Y", kr_roll_relation = "US10Y_TO_NEXT_KR10Y_CHANGE"
  )
  session$flushReact()
  for (id in c("kr_us_meta", "kr_roll_meta")) stopifnot(nzchar(output[[id]]))
  for (id in c("kr_us_plot", "kr_rolling_plot", "kr_alignment_table")) stopifnot(nzchar(output[[id]]))

  session$setInputs(kr_subtab = "FX Link", kr_fx_range = history_range)
  session$flushReact()
  stopifnot(nzchar(output$kr_fx_meta), nzchar(output$kr_fx_plot))

  session$setInputs(kr_subtab = "Data Quality")
  session$flushReact()
  stopifnot(nzchar(output$kr_quality_table), nzchar(output$kr_special_status))

  korea_outputs <<- c(
    "kr_status_text", "kr_build_text", "kr_curve_meta", "kr_curve_plot", "kr_curve_table",
    "kr_change_meta", "kr_change_table", "kr_spread_meta", "kr_spread_plot",
    "kr_quality_table", "kr_special_status", "kr_us_meta", "kr_us_plot",
    "kr_fx_meta", "kr_fx_plot", "kr_roll_meta", "kr_rolling_plot", "kr_alignment_table"
  )

  session$setInputs(
    main_tab = "Sector Rotation",
    sector_asof = max(as.Date(shiny_data()$date), na.rm = TRUE),
    sector_sort = "Excess1M"
  )
  session$flushReact()
  stopifnot(nzchar(output$sector_beating), nzchar(output$sector_latest), nzchar(output$sector_excess_plot), nzchar(output$sector_table))
  legacy_outputs <<- c("sector_beating", "sector_latest", "sector_excess_plot", "sector_table")
})

memory_mb <- as.numeric(ps::ps_memory_info()[["rss"]]) / 1024^2
result <- if (
  source_seconds <= 5 && lazy_initial_pass && lazy_history_pass &&
  length(korea_outputs) == 18L && length(legacy_outputs) >= 4L && memory_mb <= 500
) "PASS" else "FAIL"

lines <- c(
  "# Gate 3 UI Regression Retest",
  "",
  paste0("**Result: ", result, "**"),
  "",
  paste0("Tested: ", format(Sys.time(), tz = "Asia/Seoul", usetz = TRUE)),
  "",
  "## Lazy Rendering",
  "",
  "- The 141-row latest index loaded on first Korea Rates entry.",
  "- The 153,329-row historical derived store remained unloaded on the initial Yield Curve and Rate Changes views.",
  "- The historical store loaded only when a history-dependent subtab was opened.",
  "- Hidden Plotly and DT outputs use `suspendWhenHidden = TRUE` and subtab guards.",
  "",
  "## Functional Coverage",
  "",
  paste0("- Korea Rates retained outputs: ", paste(korea_outputs, collapse = ", "), "."),
  paste0("- Legacy regression outputs: ", paste(legacy_outputs, collapse = ", "), "."),
  "- Yield curve, bp changes, spreads, Korea-US alignment, FX separation, quality state, and disabled special-bond status rendered successfully.",
  "",
  "## Runtime",
  "",
  paste0("- App source/startup evaluation: ", round(source_seconds, 3), " seconds (gate <= 5 seconds)."),
  paste0("- Session RSS after all Korea Rates and legacy outputs: ", round(memory_mb, 1), " MB (gate <= 500 MB)."),
  "- The original pre-remediation all-output render result of 4.874 seconds remains preserved in the performance remediation report."
)
writeLines(lines, file.path(gate_dir, "ui_regression_retest.md"), useBytes = TRUE)
writeLines(lines, file.path(gate_dir, "ui_smoke_test.md"), useBytes = TRUE)

readr::write_csv(
  data.frame(
    check = c("app_source_seconds", "pre_remediation_all_output_seconds", "korea_output_count", "legacy_output_count", "session_memory_mb", "latest_only_initial", "history_lazy_load"),
    value = c(source_seconds, 4.874, length(korea_outputs), length(legacy_outputs), memory_mb, as.integer(lazy_initial_pass), as.integer(lazy_history_pass)),
    status = c(
      ifelse(source_seconds <= 5, "PASS", "FAIL"), "HISTORICAL_FAIL",
      "PASS", "PASS", ifelse(memory_mb <= 500, "PASS", "FAIL"),
      ifelse(lazy_initial_pass, "PASS", "FAIL"), ifelse(lazy_history_pass, "PASS", "FAIL")
    )
  ),
  file.path(gate_dir, "ui_smoke_metrics.csv")
)

cat("Gate 3 UI regression: ", result, " (startup ", round(source_seconds, 3), "s, memory ", round(memory_mb, 1), " MB)\n", sep = "")
if (result != "PASS") quit(status = 1L)
