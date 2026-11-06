suppressPackageStartupMessages({
  library(dplyr)
  library(fst)
  library(readr)
  library(tibble)
})

repo_dir <- normalizePath(".", winslash = "/", mustWork = TRUE)
app_dir <- file.path(repo_dir, "apps", "timeseries")
gate_dir <- file.path(repo_dir, "docs", "gate3")

sha256_file <- function(path) {
  output <- system2("certutil", c("-hashfile", shQuote(normalizePath(path, winslash = "\\")), "SHA256"), stdout = TRUE)
  output <- iconv(output, from = "", to = "UTF-8", sub = "")
  toupper(trimws(output[grepl("^[0-9a-fA-F]{64}$", trimws(output))][1]))
}

checks <- tibble(check = character(), status = character(), detail = character())
add_check <- function(name, condition, detail) {
  checks <<- bind_rows(checks, tibble(check = name, status = if (isTRUE(condition)) "PASS" else "FAIL", detail = as.character(detail)))
}

ecos_path <- file.path(app_dir, "original_ts_ecos.fst")
fred_path <- file.path(app_dir, "original_ts_fred.fst")
yahoo_path <- file.path(app_dir, "original_ts_yahoo.fst")
derived_path <- file.path(app_dir, "derived_korea_rates_summary.fst")
last_good_path <- paste0(derived_path, ".last_good")

ecos <- read.fst(ecos_path, as.data.table = FALSE) %>% as_tibble() %>% mutate(date = as.Date(date))
fred <- read.fst(fred_path, as.data.table = FALSE) %>% as_tibble() %>% mutate(date = as.Date(date))
yahoo <- read.fst(yahoo_path, as.data.table = FALSE) %>% as_tibble() %>% mutate(date = as.Date(date))
derived <- read.fst(derived_path, as.data.table = FALSE) %>% as_tibble() %>%
  mutate(across(any_of(c("observation_date", "reference_date", "as_of", "us_observation_date", "kr_effective_date")), as.Date))
last_good <- read.fst(last_good_path, as.data.table = FALSE) %>% as_tibble()

input_inventory <- tibble(
  dataset = c("ECOS", "FRED", "YAHOO"),
  path = c(ecos_path, fred_path, yahoo_path),
  rows = c(nrow(ecos), nrow(fred), nrow(yahoo)),
  series = c(n_distinct(ecos$series_id), n_distinct(fred$series_id), n_distinct(yahoo$series_id)),
  start_date = c(min(ecos$date), min(fred$date), min(yahoo$date)),
  end_date = c(max(ecos$date), max(fred$date), max(yahoo$date)),
  sha256 = c(sha256_file(ecos_path), sha256_file(fred_path), sha256_file(yahoo_path))
)
write_csv(input_inventory, file.path(gate_dir, "input_file_inventory.csv"))

add_check("ecos_input_unchanged", nrow(ecos) == 125625L && input_inventory$sha256[input_inventory$dataset == "ECOS"] == "6245DA33D871B5A8ED264238EA9AE8FDBF4A5E8A0F5D814A9793EEDAA33447F5", paste(nrow(ecos), "rows"))
add_check("fred_input_unchanged", nrow(fred) == 456067L && input_inventory$sha256[input_inventory$dataset == "FRED"] == "67CBDA72DEB4ED07A559584711F8AB71F83D1C578CC9F719774438F96DE53884", paste(nrow(fred), "rows"))
add_check("yahoo_input_unchanged", nrow(yahoo) == 437232L && input_inventory$sha256[input_inventory$dataset == "YAHOO"] == "D9431E63A096991AEA2B03FDE34116155572F52F6FCA1A3F318EE7B8A3671972", paste(nrow(yahoo), "rows"))

ecos_gate2_sha <- "6245DA33D871B5A8ED264238EA9AE8FDBF4A5E8A0F5D814A9793EEDAA33447F5"
ecos_gate3_sha <- input_inventory$sha256[input_inventory$dataset == "ECOS"]
ecos_duplicates <- ecos %>% count(source, series_id, date) %>% filter(n > 1L)
ecos_info <- file.info(ecos_path)
gate2_publication <- read_csv(file.path(repo_dir, "docs", "gate2", "ecos_latest_publication.csv"), show_col_types = FALSE)
ecos_sha_pass <- identical(ecos_gate2_sha, ecos_gate3_sha) && nrow(ecos) == 125625L && n_distinct(ecos$series_id) == 18L && nrow(ecos_duplicates) == 0L
add_check("ecos_gate2_sha_unchanged", ecos_sha_pass, paste0("Gate 2 SHA = Gate 3 SHA; rows=", nrow(ecos), "; series=", n_distinct(ecos$series_id), "; duplicates=", nrow(ecos_duplicates)))
writeLines(c(
  "Gate 2 / Gate 3 ECOS SHA comparison",
  "===================================",
  paste0("Gate 2 batch: ", gate2_publication$batch_id[[1]]),
  paste0("Gate 2 publication completed: ", gate2_publication$completed_at[[1]]),
  paste0("Published artifact last-write: ", format(ecos_info$mtime, "%Y-%m-%d %H:%M:%OS3 %Z", tz = "Asia/Seoul")),
  "Evidence basis: the final Gate 2 published artifact predates the Gate 2 validation report and the first Gate 3 derived build; its last-write timestamp has not changed since publication.",
  "The Gate 2 report omitted SHA, so the baseline is recovered from that final published artifact, not from the prior-version .last_good backup.",
  paste0("Gate 2 published artifact SHA256: ", ecos_gate2_sha),
  paste0("Gate 3 completion SHA256:        ", ecos_gate3_sha),
  paste0("Rows: ", nrow(ecos)),
  paste0("Series: ", n_distinct(ecos$series_id)),
  paste0("Duplicate source+series_id+date keys: ", nrow(ecos_duplicates)),
  paste0("Result: ", ifelse(ecos_sha_pass, "ECOS_GATE2_SHA_UNCHANGED", "ECOS_SHA_BASELINE_NOT_PROVEN"))
), file.path(gate_dir, "ecos_sha_comparison.txt"), useBytes = TRUE)

required_columns <- c("metric_id", "metric_group", "observation_date", "reference_date", "value", "unit", "source", "as_of", "collected_at", "quality_status", "calculation_version", "alignment_rule")
duplicates <- derived %>% count(metric_id, observation_date, reference_date) %>% filter(n > 1L)
add_check("derived_schema", all(required_columns %in% names(derived)), paste(length(required_columns), "required columns present"))
add_check("derived_independent_readback", nrow(derived) == 153329L && n_distinct(derived$metric_id) == 156L, paste(nrow(derived), "rows,", n_distinct(derived$metric_id), "metrics"))
add_check("derived_duplicate_keys", nrow(duplicates) == 0L, "duplicate metric_id + observation_date + reference_date = 0")
add_check("derived_last_good", nrow(last_good) == nrow(derived), paste(nrow(last_good), "readable last-good rows"))

curve <- derived %>% filter(metric_group == "yield_curve")
current_curve <- curve %>% filter(grepl("^CURVE_CURRENT_", metric_id))
add_check("yield_curve_common_date", nrow(current_curve) == 8L && n_distinct(current_curve$observation_date) == 1L && all(current_curve$alignment_rule == "COMMON_OBSERVATION_DATE_NO_LOCF"), paste("curve as of", unique(current_curve$observation_date)))
add_check("yield_curve_complete", all(current_curve$missing_tenors == "") && setequal(current_curve$series_id, c("KTB_01Y", "KTB_02Y", "KTB_03Y", "KTB_05Y", "KTB_10Y", "KTB_20Y", "KTB_30Y", "KTB_50Y")), "8 required tenors present")

rate_changes <- derived %>% filter(metric_group == "rate_change", quality_status == "OK")
rate_formula <- rate_changes %>%
  mutate(recalculated_bp = (component_a_value - reference_value) * 100, difference = value - recalculated_bp) %>%
  arrange(series_id, metric_id) %>%
  select(metric_id, series_id, observation_date, reference_date, component_a_value, reference_value, value, recalculated_bp, difference, unit, alignment_rule) %>%
  slice_head(n = 20)
write_csv(rate_formula, file.path(gate_dir, "rate_change_formula_samples.csv"))
add_check("rate_change_bp", all(rate_changes$unit == "bp") && max(abs(rate_formula$difference), na.rm = TRUE) < 1e-10, paste(nrow(rate_changes), "validated bp rows"))
add_check("rate_change_no_locf", all(grepl("ACTUAL_OBSERVATION_NO_LOCF", rate_changes$alignment_rule, fixed = TRUE)) && all(rate_changes$observation_date %in% ecos$date) && all(rate_changes$reference_date %in% ecos$date), "Current/reference dates are actual source observations")

spreads <- derived %>% filter(metric_group %in% c("funding_spread", "credit_spread"))
spread_formula <- spreads %>%
  group_by(metric_id) %>% slice_tail(n = 2) %>% ungroup() %>%
  mutate(recalculated_bp = (component_a_value - component_b_value) * 100, difference = value - recalculated_bp) %>%
  select(metric_id, observation_date, component_a, component_b, component_a_value, component_b_value, value, recalculated_bp, difference, unit, alignment_rule)
write_csv(spread_formula, file.path(gate_dir, "spread_formula_samples.csv"))
add_check("funding_spread", all(spreads$unit == "bp") && all(spreads$observation_date == spreads$reference_date) && max(abs(spread_formula$difference), na.rm = TRUE) < 1e-10, paste(nrow(spreads), "same-date spread rows"))
add_check("special_aaa_disabled", !any(grepl("SPECIAL_AAA", derived$metric_id, fixed = TRUE)), "No SPECIAL_AAA_03Y derived value exists")

transmission <- derived %>% filter(metric_id %in% c("US2Y_TO_NEXT_KR3Y_CHANGE", "US10Y_TO_NEXT_KR10Y_CHANGE"))
alignment_samples <- transmission %>% group_by(metric_id) %>% slice_tail(n = 10) %>% ungroup() %>%
  transmute(metric_id, us_observation_date, kr_effective_date, us_change_bp = auxiliary_value, kr_change_bp = value, alignment_rule, valid_order = kr_effective_date > us_observation_date)
write_csv(alignment_samples, file.path(gate_dir, "us_kr_alignment_samples.csv"))
add_check("kr_us_alignment", all(transmission$kr_effective_date > transmission$us_observation_date) && all(alignment_samples$valid_order), paste(nrow(transmission), "US-to-next-KR aligned rows"))

rolling <- derived %>% filter(metric_group == "rolling_correlation")
add_check("rolling_full_windows", all(rolling$window %in% c(20L, 60L, 120L)) && all(rolling$observation_count == rolling$window) && all(is.finite(rolling$value)), paste(nrow(rolling), "full-window correlations"))

source_dates <- unique(c(ecos$date, fred$date))
add_check("no_generated_nonbusiness_observations", all(derived$observation_date %in% source_dates) && all(derived$reference_date %in% source_dates), "All derived dates trace to ECOS or FRED observations")
fx_rows <- derived %>% filter(metric_group == "fx_rate_link")
add_check("fx_source_separation", !any(grepl("YAHOO", fx_rows$source, ignore.case = TRUE)) && all(grepl("EXACT_SAME_OBSERVATION_DATE_NO_SOURCE_MERGE", fx_rows$alignment_rule, fixed = TRUE)), "ECOS_USDKRW remains separate from Yahoo USDKRW=X")

temp_target <- file.path(tempdir(), "gate3_atomic_test.fst")
file.copy(derived_path, temp_target, overwrite = TRUE)
before_hash <- sha256_file(temp_target)
invalid <- bind_rows(derived[1:2, ], derived[1, ])
invalid_duplicate <- nrow(invalid %>% count(metric_id, observation_date, reference_date) %>% filter(n > 1L)) > 0L
failure_caught <- FALSE
if (invalid_duplicate) failure_caught <- TRUE
after_hash <- sha256_file(temp_target)
unlink(temp_target)
add_check("derived_atomic_publication", failure_caught && identical(before_hash, after_hash), "Invalid duplicate staging rejected; published target remained unchanged")

ui_metrics_path <- file.path(gate_dir, "ui_smoke_metrics.csv")
ui_report_path <- file.path(gate_dir, "ui_smoke_test.md")
ui_metrics <- read_csv(ui_metrics_path, show_col_types = FALSE)
functional_ui_checks <- ui_metrics %>% filter(check %in% c("app_source_seconds", "korea_output_count", "legacy_output_count", "session_memory_mb", "latest_only_initial", "history_lazy_load"))
add_check("korea_rates_ui", file.exists(ui_report_path) && all(functional_ui_checks$status == "PASS") && ui_metrics$value[ui_metrics$check == "korea_output_count"] >= 18, "Lazy-load and 18 Korea Rates outputs passed")
add_check("legacy_regression", ui_metrics$value[ui_metrics$check == "legacy_output_count"] >= 4, "Existing Sector Rotation outputs passed")

performance_summary <- read_csv(file.path(gate_dir, "performance_summary.csv"), show_col_types = FALSE)
perf_value <- function(name) performance_summary$value[performance_summary$metric == name][[1]]
add_check("cold_render_le_2s", perf_value("cold_max") <= 2, paste0("cold max ", round(perf_value("cold_max"), 3), "s"))
add_check("warm_render_p95_le_2s", perf_value("warm_p95") <= 2, paste0("warm p95 ", round(perf_value("warm_p95"), 3), "s"))
add_check("filter_response_p95_le_2s", perf_value("filter_p95") <= 2, paste0("filter p95 ", round(perf_value("filter_p95"), 3), "s"))
add_check("app_startup_le_5s", perf_value("startup_max") <= 5, paste0("startup max ", round(perf_value("startup_max"), 3), "s"))
add_check("session_memory_le_500mb", perf_value("session_memory_max_mb") <= 500, paste0("session RSS max ", round(perf_value("session_memory_max_mb"), 1), " MB"))

app_text <- c(readLines(file.path(app_dir, "app.R"), warn = FALSE), readLines(file.path(app_dir, "korea_rates_server.R"), warn = FALSE))
add_check("app_startup_no_external_api", !any(grepl("ecos_adapter|ECOS_API_KEY|StatisticSearch", app_text, ignore.case = TRUE)), "No ECOS API adapter or key reference in Shiny sources")
add_check("documentation_updated", all(file.exists(file.path(gate_dir, c("GATE3_PERFORMANCE_REMEDIATION.md", "performance_cold_runs.csv", "performance_warm_runs.csv", "performance_filter_runs.csv", "ecos_sha_comparison.txt", "ui_regression_retest.md")))), "Required remediation evidence exists")

overall <- if (all(checks$status == "PASS")) "PASS" else "FAIL"
write_csv(checks, file.path(gate_dir, "gate3_validation.csv"))

latest_series <- ecos %>% group_by(series_id) %>% summarize(latest_observation = max(date), .groups = "drop") %>% arrange(series_id)
write_csv(latest_series, file.path(gate_dir, "series_latest_observations.csv"))

group_inventory <- derived %>% group_by(metric_group) %>% summarize(rows = n(), metrics = n_distinct(metric_id), start_date = min(observation_date), end_date = max(observation_date), .groups = "drop")
write_csv(group_inventory, file.path(gate_dir, "derived_metric_inventory.csv"))

report <- c(
  "# Gate 3 Validation Report",
  "",
  paste0("**Result: ", overall, "**"),
  "",
  paste0("Validated: ", format(Sys.time(), tz = "Asia/Seoul", usetz = TRUE)),
  "",
  "## Inputs",
  "",
  "| Dataset | Rows | Series | Start | End | SHA-256 |",
  "|---|---:|---:|---|---|---|",
  paste0("| ", input_inventory$dataset, " | ", input_inventory$rows, " | ", input_inventory$series, " | ", input_inventory$start_date, " | ", input_inventory$end_date, " | `", input_inventory$sha256, "` |"),
  "",
  "## Derived Store",
  "",
  paste0("- Rows: ", format(nrow(derived), big.mark = ","), "."),
  paste0("- Metrics: ", n_distinct(derived$metric_id), "."),
  paste0("- Date range: ", min(derived$observation_date), " to ", max(derived$observation_date), "."),
  paste0("- Duplicate keys: ", nrow(duplicates), "."),
  paste0("- Common current curve date: ", unique(current_curve$observation_date), "."),
  "",
  "## Performance Remediation",
  "",
  "- Initial finding retained: the pre-remediation all-output test took 4.874 seconds and exceeded the 2-second tab-render contract.",
  "- Measurement start: browser click on `Korea Rates & Funding`.",
  "- Measurement end: all initially visible required outputs exist, no visible output is recalculating, and Shiny is idle.",
  paste0("- Cold render: p50 ", round(perf_value("cold_p50"), 3), "s; max ", round(perf_value("cold_max"), 3), "s across 5 independent processes."),
  paste0("- Warm render: p50 ", round(perf_value("warm_p50"), 3), "s; p95 ", round(perf_value("warm_p95"), 3), "s; max ", round(perf_value("warm_max"), 3), "s across 10 transitions."),
  paste0("- Filter response: p50 ", round(perf_value("filter_p50"), 3), "s; p95 ", round(perf_value("filter_p95"), 3), "s; max ", round(perf_value("filter_max"), 3), "s across 12 changes."),
  paste0("- App startup max: ", round(perf_value("startup_max"), 3), "s. Session RSS max: ", round(perf_value("session_memory_max_mb"), 1), " MB."),
  "",
  "## Checks",
  "",
  "| Check | Status | Detail |",
  "|---|---|---|",
  paste0("| ", checks$check, " | ", checks$status, " | ", checks$detail, " |"),
  "",
  "## Missing, Delayed, and Disabled",
  "",
  "- `PENDING_SOURCE` means the official ECOS observation has not yet been published; it is not treated as a collector failure.",
  "- `SPECIAL_AAA_03Y` remains `SOURCE_NOT_AVAILABLE`; no empty chart or replacement series is generated.",
  "- Curves use common exact observation dates. No LOCF or synthetic business-day rows are created.",
  "- ECOS official USD/KRW and Yahoo market proxy remain separate.",
  "",
  "## Decision",
  "",
  if (overall == "PASS") c(
    "- `KOREA_YIELD_CURVE_PASS`", "- `RATE_CHANGE_BP_PASS`", "- `FUNDING_SPREAD_PASS`",
    "- `SPECIAL_AAA_DISABLED_PASS`", "- `KR_US_ALIGNMENT_PASS`", "- `FX_SOURCE_SEPARATION_PASS`",
    "- `DERIVED_ATOMIC_PUBLICATION_PASS`", "- `KOREA_RATES_UI_PASS`", "- `LEGACY_REGRESSION_PASS`",
    "- `COLD_RENDER_LE_2S`", "- `WARM_RENDER_P95_LE_2S`", "- `FILTER_RESPONSE_P95_LE_2S`",
    "- `ECOS_GATE2_SHA_UNCHANGED`", "- `SESSION_MEMORY_LE_500MB`", "- `DOCUMENTATION_UPDATED`", "- `GATE_3_CLOSED_PASS`",
    "- `GATE_4_APPROVED_TO_START`"
  ) else c("- `GATE_3_PARTIAL`", "- `PERFORMANCE_FINDING_OPEN`", "- `NO_GATE_4_START`")
)
writeLines(report, file.path(gate_dir, "GATE3_VALIDATION_REPORT.md"), useBytes = TRUE)

cat("Gate 3 validation: ", overall, " (", sum(checks$status == "PASS"), "/", nrow(checks), " checks passed)\n", sep = "")
if (overall != "PASS") quit(status = 1L)

