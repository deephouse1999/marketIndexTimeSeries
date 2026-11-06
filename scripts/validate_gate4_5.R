#!/usr/bin/env Rscript

gate_r_lib <- "C:/Users/yjh14/AppData/Local/R/win-library/4.5"
if (dir.exists(gate_r_lib)) .libPaths(c(gate_r_lib, .libPaths()))
suppressPackageStartupMessages({ library(dplyr); library(fst); library(readr) })

repo_dir <- normalizePath(".", winslash = "/", mustWork = TRUE)
app_dir <- file.path(repo_dir, "apps", "timeseries")
gate_dir <- file.path(repo_dir, "docs", "gate4_5")
dir.create(gate_dir, recursive = TRUE, showWarnings = FALSE)

catalog <- read_csv(file.path(app_dir, "series_catalog.csv"), show_col_types = FALSE)
ecos <- read.fst(file.path(app_dir, "original_ts_ecos.fst"), as.data.table = FALSE)
yahoo <- read.fst(file.path(app_dir, "original_ts_yahoo.fst"), as.data.table = FALSE)
derived <- read.fst(file.path(app_dir, "derived_physical_indicators.fst"), as.data.table = FALSE)
metadata <- read_csv(file.path(gate_dir, "ecos_physical_metadata_snapshot.csv"), show_col_types = FALSE)
browser <- read_csv(file.path(gate_dir, "ui_browser_checks.csv"), show_col_types = FALSE)
performance <- read_csv(file.path(repo_dir, "docs", "gate6", "performance_summary.csv"), show_col_types = FALSE)
server_runtime <- read_csv(file.path(repo_dir, "docs", "gate6", "server_runtime_checks.csv"), show_col_types = FALSE)

ids <- c("KR_DRAM_PPI", "KR_FLASH_MEMORY_PPI", "BWET_VLCC_PROXY")
ppi_ids <- ids[1:2]
ppi <- ecos[ecos$series_id %in% ppi_ids, , drop = FALSE]
bwet <- yahoo[yahoo$series_id == "BWET_VLCC_PROXY", , drop = FALSE]
dup_count <- function(x, key) sum(duplicated(x[key]))

collection_report <- bind_rows(
  ppi %>% group_by(source, series_id) %>% summarize(
    rows = n(), start_date = min(as.Date(date)), end_date = max(as.Date(date)),
    close_non_missing = sum(is.finite(value)), adjusted_non_missing = NA_integer_,
    duplicate_keys = sum(duplicated(as.Date(date))),
    quality_status = paste(sort(unique(quality_status)), collapse = ";"), .groups = "drop"
  ),
  bwet %>% group_by(source, series_id) %>% summarize(
    rows = n(), start_date = min(as.Date(date)), end_date = max(as.Date(date)),
    close_non_missing = sum(is.finite(close_value)), adjusted_non_missing = sum(is.finite(adjusted_value)),
    duplicate_keys = sum(duplicated(as.Date(date))),
    quality_status = paste(sort(unique(quality_status)), collapse = ";"), .groups = "drop"
  )
)
write_csv(collection_report, file.path(gate_dir, "physical_series_collection_report.csv"))

available_validation <- bind_rows(
  ppi %>% transmute(source, series_id, observation_date = as.Date(observation_date), available_at,
                    available_date = as.Date(substr(available_at, 1, 10)), policy = "COLLECTED_AT_CONSERVATIVE"),
  bwet %>% transmute(source, series_id, observation_date = as.Date(observation_date), available_at,
                     available_date = as.Date(substr(available_at, 1, 10)), policy = "US_CLOSE_AVAILABLE")
) %>% mutate(result = ifelse(!is.na(available_date) & available_date >= observation_date, "PASS", "FAIL"))
write_csv(available_validation, file.path(gate_dir, "available_at_validation.csv"))

checks <- data.frame(check_id = character(), actual = character(), expected = character(), result = character())
add <- function(id, actual, expected, pass) {
  checks <<- rbind(checks, data.frame(check_id = id, actual = as.character(actual), expected = expected,
                                      result = if (isTRUE(pass)) "PASS" else "FAIL"))
}

physical_catalog <- catalog %>% filter(series_id %in% ids)
add("catalog_registration", nrow(physical_catalog), "3 active/collectable/default-visible physical indicators",
    nrow(physical_catalog) == 3L && all(physical_catalog$series_group == "physical_indicator") &&
      all(physical_catalog$active) && all(physical_catalog$collect_flag) && all(physical_catalog$default_visible))
add("catalog_metadata_contract", paste(setdiff(c("indicator_type", "proxy_for", "frequency", "release_lag", "license_status", "source_definition", "available_at_policy", "do_not_interpret_as", "display_location"), names(catalog)), collapse = ";"),
    "all metadata columns populated", all(c("indicator_type", "proxy_for", "frequency", "release_lag", "license_status", "source_definition", "available_at_policy", "do_not_interpret_as", "display_location") %in% names(catalog)) &&
      all(vapply(physical_catalog[c("indicator_type", "proxy_for", "frequency", "release_lag", "license_status", "source_definition", "available_at_policy", "do_not_interpret_as", "display_location")], function(x) all(!is.na(x) & nzchar(x)), logical(1))))
add("ecos_metadata_readback", paste(metadata$series_id, metadata$status, collapse = ";"), "2/2 VERIFIED official readback",
    nrow(metadata) == 2L && all(metadata$status == "VERIFIED") && all(metadata$cycle == "M") && all(metadata$unit_source == "2020=100"))
add("ecos_source_updated_at_semantics", paste(unique(metadata$source_updated_at_status), collapse = ";"),
    "NOT_PROVIDED_BY_ECOS_ITEM_API and raw source_updated_at=NA",
    all(metadata$source_updated_at_status == "NOT_PROVIDED_BY_ECOS_ITEM_API") && all(is.na(ppi$source_updated_at)))
add("physical_collection_inventory", paste(collection_report$series_id, collection_report$rows, sep = "=", collapse = ";"),
    "DRAM=381; Flash=261; BWET>=880", all(collection_report$rows[match(ids, collection_report$series_id)] >= c(381L, 261L, 880L)))
add("physical_duplicate_keys", sum(collection_report$duplicate_keys), "0", sum(collection_report$duplicate_keys) == 0L)
add("ppi_monthly_no_locf", paste(unique(format(as.Date(ppi$date), "%d")), collapse = ";"), "one row per reference month and day=01",
    all(format(as.Date(ppi$date), "%d") == "01") && !any(duplicated(data.frame(ppi$series_id, format(as.Date(ppi$date), "%Y-%m")))))
add("bwet_close_adjusted_preserved", paste(sum(is.finite(bwet$close_value)), sum(is.finite(bwet$adjusted_value)), sep = "/"),
    "both equal BWET row count", nrow(bwet) > 0L && all(is.finite(bwet$close_value)) && all(is.finite(bwet$adjusted_value)))
required_time <- c("observation_date", "available_at", "collected_at", "source_updated_at", "vintage", "quality_status", "source", "calculation_version")
add("time_metadata_fields", paste(setdiff(required_time, intersect(names(ppi), names(bwet))), collapse = ";"), "all required fields in ECOS and Yahoo stores",
    all(required_time %in% names(ppi)) && all(required_time %in% names(bwet)))
add("available_at_contract", paste(table(available_validation$result), collapse = ";"), "all PASS",
    nrow(available_validation) == nrow(ppi) + nrow(bwet) && all(available_validation$result == "PASS"))

ppi_measures <- sort(unique(derived$measure[derived$metric_group == "physical_change"]))
bwet_measures <- sort(unique(derived$measure[derived$metric_group == "bwet_summary"]))
add("ppi_derived_metrics", paste(ppi_measures, collapse = ";"), "LEVEL/MOM/YOY/CHANGE_3M/CHANGE_6M/STREAK_MONTHS",
    setequal(ppi_measures, c("LEVEL", "MOM", "YOY", "CHANGE_3M", "CHANGE_6M", "STREAK_MONTHS")))
add("bwet_derived_metrics", paste(bwet_measures, collapse = ";"), "returns/correlations/regimes/volatility/MDD",
    all(c("RETURN_1D", "RETURN_1W", "RETURN_1M", "RETURN_3M", "VOL_20D", "MAX_DRAWDOWN",
          "CORR_252D_CL=F", "CORR_252D_XLE", "CORR_252D_XOP", "WTI_UP_EXCESS_VS_XLE", "WTI_DOWN_EXCESS_VS_XLE") %in% bwet_measures))
corr <- derived %>% filter(metric_group == "physical_reference_month_correlation")
add("ppi_reference_month_lead_lag", paste(nrow(corr), paste(range(sub("LAG_", "", sub(".*\\|", "", corr$metric_id))), collapse = ":"), sep = "/"),
    "104 exploratory rows across -6..+6; release-time limitation explicit",
    nrow(corr) == 104L && all(corr$quality_status == "REFERENCE_MONTH_ONLY") && all(corr$calculation_version == "PHYSICAL_V2_REFERENCE_MONTH"))
add("derived_duplicate_keys", dup_count(derived, c("metric_group", "metric_id", "date")), "0",
    dup_count(derived, c("metric_group", "metric_id", "date")) == 0L)
add("proxy_semantics", physical_catalog$do_not_interpret_as[physical_catalog$series_id == "BWET_VLCC_PROXY"],
    "vlcc_spot_rate_or_baltic_official_index", identical(physical_catalog$do_not_interpret_as[physical_catalog$series_id == "BWET_VLCC_PROXY"], "vlcc_spot_rate_or_baltic_official_index"))

collector_text <- paste(readLines(file.path(repo_dir, "scripts", "run_gate5_batch.R"), warn = FALSE), collapse = "\n")
legacy_text <- paste(readLines(file.path(repo_dir, "scripts", "gate5_collect_legacy.R"), warn = FALSE), collapse = "\n")
add("scheduled_batch_inclusion", "KR ECOS + US catalog-driven Yahoo + physical build", "both schedules include collectors and derived build",
    grepl('run_child\\("collect_ecos_gate2.R"\\)', collector_text) && grepl('run_market_data_update\\(update_fred = TRUE, update_yahoo = TRUE\\)', legacy_text) && grepl('build_physical_indicators.R', collector_text, fixed = TRUE))
app_text <- paste(readLines(file.path(app_dir, "app.R"), warn = FALSE), readLines(file.path(app_dir, "physical_indicators_server.R"), warn = FALSE), collapse = "\n")
add("app_external_api_calls", any(grepl("getSymbols|fredr\\(|StatisticSearch", app_text)), "FALSE", !any(grepl("getSymbols|fredr\\(|StatisticSearch", app_text)))
add("browser_functional", paste(sum(browser$result == "PASS"), nrow(browser), sep = "/"), "11/11", nrow(browser) == 11L && all(browser$result == "PASS"))
render_seconds <- as.numeric(browser$actual[browser$check_id == "physical_tab_render"])
add("physical_cold_visible_render", render_seconds, "<=2 seconds", length(render_seconds) == 1L && is.finite(render_seconds) && render_seconds <= 2)
perf <- setNames(performance$seconds_or_mb, performance$test)
add("integrated_performance", paste(round(perf[c("cold_max", "warm_p95", "filter_p95", "startup_max")], 3), collapse = "/"),
    "cold/warm/filter <=2; startup <=5", perf[["cold_max"]] <= 2 && perf[["warm_p95"]] <= 2 && perf[["filter_p95"]] <= 2 && perf[["startup_max"]] <= 5)
rss <- as.numeric(server_runtime$actual[server_runtime$check == "session_memory_mb"])
add("session_memory_with_physical", rss, "<=500 MB and physical lazy assets loaded",
    rss <= 500 && server_runtime$result[server_runtime$check == "physical_lazy_assets_loaded"] == "PASS")

write_csv(checks, file.path(gate_dir, "gate4_5_validation_checks.csv"))
all_pass <- all(checks$result == "PASS")
decision <- if (all_pass) c(
  "ECOS_DRAM_METADATA_READBACK_PASS", "ECOS_FLASH_METADATA_READBACK_PASS",
  "PHYSICAL_COLLECTION_PASS", "AVAILABLE_AT_CONTRACT_PASS", "NO_DAILY_LOCF_PASS", "REFERENCE_MONTH_SEMANTICS_PASS",
  "BWET_PROXY_SEMANTICS_PASS", "UI_VISIBILITY_PASS", "SCHEDULE_INCLUSION_PASS",
  "GATE_4_5_SELF_VALIDATION_PASS", "INDEPENDENT_REAUDIT_REQUIRED"
) else c("GATE_4_5_PARTIAL", "NO_RELEASE")
report <- c(
  "# Gate 4.5 Physical Indicators Validation", "",
  paste0("Validated: ", format(Sys.time(), tz = "Asia/Seoul", usetz = TRUE)), "",
  paste0("**Result: ", if (all_pass) "PASS" else "FAIL", " (", sum(checks$result == "PASS"), "/", nrow(checks), ")**"), "",
  "## Decision", "", "```text", decision, "```", "",
  "## Inventory", "",
  paste0("- ", collection_report$series_id, ": ", format(collection_report$rows, big.mark = ","), " rows; ", collection_report$start_date, " to ", collection_report$end_date, "; duplicates ", collection_report$duplicate_keys, "."), "",
  "## Evidence", "",
  "- Official ECOS item metadata was read back before collection; both code contracts are VERIFIED.",
  "- ECOS monthly observations remain monthly and were not expanded with daily LOCF.",
  "- ECOS does not expose historical publication/revision timestamps through the item/search response used here. `source_updated_at` is therefore NA; `available_at` is explicitly conservative collection availability.",
  "- PPI lead/lag output is explicitly reference-month exploratory analysis, not a point-in-time release-lag trading signal.",
  "- BWET keeps Close and Adjusted Close and is explicitly labeled as an ETF proxy, not a VLCC spot or Baltic official index.",
  "- WTI regime relative performance is BWET daily return minus XLE daily return within WTI up/down regimes.",
  paste0("- Browser checks: ", sum(browser$result == "PASS"), "/", nrow(browser), "; Physical Indicators visible render ", round(render_seconds, 3), "s."),
  paste0("- Integrated performance: cold max ", round(perf[["cold_max"]], 3), "s; warm p95 ", round(perf[["warm_p95"]], 3), "s; filter p95 ", round(perf[["filter_p95"]], 3), "s; startup max ", round(perf[["startup_max"]], 3), "s; RSS ", round(rss, 1), "MB."),
  "- The Shiny session reads local FST files only; collection remains in scheduled batch scripts.", "",
  "## Files", "",
  "- `ecos_physical_metadata_snapshot.csv`", "- `physical_series_collection_report.csv`",
  "- `available_at_validation.csv`", "- `ui_browser_checks.csv`", "- `gate4_5_validation_checks.csv`"
)
writeLines(report, file.path(gate_dir, "GATE4_5_VALIDATION_REPORT.md"), useBytes = TRUE)
cat("Gate 4.5 validation: ", if (all_pass) "PASS" else "FAIL", " (", sum(checks$result == "PASS"), "/", nrow(checks), ")\n", sep = "")
if (!all_pass) quit(status = 1L)
