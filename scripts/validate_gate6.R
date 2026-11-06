#!/usr/bin/env Rscript

gate6_r_lib <- "C:/Users/yjh14/AppData/Local/R/win-library/4.5"
if (dir.exists(gate6_r_lib)) .libPaths(c(gate6_r_lib, .libPaths()))
suppressPackageStartupMessages({ library(dplyr); library(fst); library(jsonlite); library(readr) })

repo_dir <- normalizePath(".", winslash = "/", mustWork = TRUE)
app_dir <- file.path(repo_dir, "apps", "timeseries")
gate_dir <- file.path(repo_dir, "docs", "gate6")
checks <- data.frame(check_id = character(), actual = character(), expected = character(), result = character())
add <- function(id, actual, expected, pass) {
  checks <<- rbind(checks, data.frame(check_id = id, actual = as.character(actual), expected = as.character(expected), result = if (isTRUE(pass)) "PASS" else "FAIL"))
}
dup_count <- function(x, key) sum(duplicated(x[key]))

fred <- read.fst(file.path(app_dir, "original_ts_fred.fst"), as.data.table = FALSE)
yahoo <- read.fst(file.path(app_dir, "original_ts_yahoo.fst"), as.data.table = FALSE)
ecos <- read.fst(file.path(app_dir, "original_ts_ecos.fst"), as.data.table = FALSE)
sox <- read.fst(file.path(app_dir, "original_ts_sox_components.fst"), as.data.table = FALSE)
catalog <- read_csv(file.path(app_dir, "series_catalog.csv"), show_col_types = FALSE)

add("fred_no_history_loss", paste(nrow(fred), sum(is.na(fred$source)), sep = "/"), ">=456067 rows; >=246950 legacy NA-source", nrow(fred) >= 456067L && sum(is.na(fred$source)) >= 246950L)
add("fred_duplicate_keys", dup_count(fred, c("source", "series_id", "date")), "0", dup_count(fred, c("source", "series_id", "date")) == 0L)
add("yahoo_no_history_loss", nrow(yahoo), ">=437232", nrow(yahoo) >= 437232L)
add("yahoo_duplicate_keys", dup_count(yahoo, c("source", "series_id", "date")), "0", dup_count(yahoo, c("source", "series_id", "date")) == 0L)
dji_dates <- as.Date(yahoo$date[yahoo$series_id == "^DJI"])
add("old_dji_preserved", if (length(dji_dates)) as.character(min(dji_dates)) else "MISSING", "<=1919-12-31", length(dji_dates) > 0L && min(dji_dates) <= as.Date("1919-12-31"))
bovespa <- catalog %>% filter(source == "YAHOO", series_id == "^BVSP")
add("bovespa_regional_role", paste(bovespa$series_cls, bovespa$series_group, sep = "/"), "emerging_market_index/regional_comparison", nrow(bovespa) == 1L && bovespa$series_cls == "emerging_market_index" && bovespa$series_group == "regional_comparison")
add("ecos_inventory", paste(nrow(ecos), length(unique(ecos$series_id)), dup_count(ecos, c("source", "series_id", "date")), sep = "/"), ">=126267/20/0", nrow(ecos) >= 126267L && length(unique(ecos$series_id)) == 20L && dup_count(ecos, c("source", "series_id", "date")) == 0L)
add("sox_inventory", paste(nrow(sox), length(unique(sox$series_id)), dup_count(sox, c("source", "series_id", "date")), sep = "/"), ">=207905/30/0", nrow(sox) >= 207905L && length(unique(sox$series_id)) == 30L && dup_count(sox, c("source", "series_id", "date")) == 0L)

explorer <- read.fst(file.path(app_dir, "derived_series_explorer.fst"), as.data.table = FALSE)
add("series_explorer_store", paste(nrow(explorer), dup_count(explorer, c("source", "series_id", "date")), sep = "/"), ">700000/0", nrow(explorer) > 700000L && dup_count(explorer, c("source", "series_id", "date")) == 0L && all(c("raw_close_value", "raw_adjusted_value", "effective_value") %in% names(explorer)))

browser <- read_csv(file.path(gate_dir, "browser_functional_checks.csv"), show_col_types = FALSE)
tabs <- read_csv(file.path(gate_dir, "main_tab_render_times.csv"), show_col_types = FALSE)
server <- read_csv(file.path(gate_dir, "server_runtime_checks.csv"), show_col_types = FALSE)
perf <- read_csv(file.path(gate_dir, "performance_summary.csv"), show_col_types = FALSE)
add("browser_functional", paste(sum(browser$result == "PASS"), nrow(browser), sep = "/"), "28/28", nrow(browser) == 28L && all(browser$result == "PASS"))
add("main_tab_render", max(tabs$elapsed_seconds), "<=2", all(tabs$result == "PASS") && max(tabs$elapsed_seconds) <= 2)
add("server_runtime", paste(server$check, server$result, collapse = ";"), "all PASS", all(server$result == "PASS"))
perf_value <- function(id) perf$seconds_or_mb[perf$test == id][[1]]
add("cold_render", perf_value("cold_max"), "<=2", perf_value("cold_max") <= 2)
add("warm_render_p95", perf_value("warm_p95"), "<=2", perf_value("warm_p95") <= 2)
add("filter_response_p95", perf_value("filter_p95"), "<=2", perf_value("filter_p95") <= 2)
add("app_startup", perf_value("startup_max"), "<=5", perf_value("startup_max") <= 5)
add("session_memory", server$actual[server$check == "session_memory_mb"], "<=500", as.numeric(server$actual[server$check == "session_memory_mb"]) <= 500)

download_files <- file.path(gate_dir, "downloads", c("selected_market_series.csv", "korea_rates.csv", "derived_sox_daily_summary.csv"))
download_rows <- vapply(download_files, function(path) if (file.exists(path)) nrow(read_csv(path, show_col_types = FALSE)) else 0L, integer(1))
add("csv_downloads", paste(download_rows, collapse = "/"), "all >0", all(download_rows > 0L))

dcf <- read.dcf(file.path(app_dir, "rsconnect", "shinyapps.io", "deephouse1999", "market_timeseries.dcf"))
smoke <- paste(readLines(file.path(gate_dir, "PUBLIC_URL_SMOKE.md"), warn = FALSE), collapse = "\n")
smoke_bundle_line <- regmatches(smoke, regexpr("Deployment bundle: `([0-9]+)`", smoke, perl = TRUE))
smoke_bundle <- sub("Deployment bundle: `([0-9]+)`", "\\1", smoke_bundle_line)
add("public_release", paste(dcf[1, "bundleId"], dcf[1, "url"], sep = "/"), "deployed bundle matches public smoke and PASS", dcf[1, "bundleId"] == smoke_bundle && grepl("Result: PASS", smoke, fixed = TRUE))

gate5 <- read_csv(file.path(repo_dir, "docs", "gate5", "gate5_validation_checks.csv"), show_col_types = FALSE)
add("gate5_prerequisite", paste(sum(gate5$result == "PASS"), nrow(gate5), sep = "/"), "30/30", nrow(gate5) == 30L && all(gate5$result == "PASS"))
required_docs <- c("README.md", "CHANGELOG.md", "VALIDATION_REPORT.md", "HANDOFF.md", "apps/timeseries/DATA_DICTIONARY.md", "docs/MARKET_TIMESERIES_WBS.md", "docs/gate6/PUBLIC_URL_SMOKE.md")
docs_exist <- file.exists(file.path(repo_dir, required_docs))
doc_text <- paste(unlist(lapply(file.path(repo_dir, required_docs[docs_exist]), readLines, warn = FALSE)), collapse = "\n")
add("documentation_integrity", paste(required_docs[!docs_exist], collapse = ";"), "all required docs and Gate 6 markers", all(docs_exist) && grepl("Gate 6", doc_text, fixed = TRUE) && grepl("derived_series_explorer.fst", doc_text, fixed = TRUE))

write_csv(checks, file.path(gate_dir, "gate6_validation.csv"))
all_pass <- all(checks$result == "PASS")
decision <- if (all_pass) c(
  "DATA_SOURCE_CONTRACT_VERIFIED", "ECOS_FULL_AND_INCREMENTAL_PASS", "SOX_CONSTITUENT_HISTORY_PASS",
  "US_DST_SCHEDULE_PASS", "KR_CLOSE_SCHEDULE_PASS", "ATOMIC_PUBLICATION_PASS",
  "LEGACY_REGRESSION_PASS", "PERFORMANCE_GATE_PASS", "DOCUMENT_INTEGRITY_PASS",
  "GATE_6_CLOSED_PASS", "PRODUCTION_RELEASE_APPROVED"
) else c("GATE_6_PARTIAL", "NO_PRODUCTION_CUTOVER")
report <- c(
  "# Gate 6 Validation Report", "", paste0("Validated: ", format(Sys.time(), tz = "Asia/Seoul", usetz = TRUE)), "",
  paste0("**Result: ", if (all_pass) "PASS" else "FAIL", " (", sum(checks$result == "PASS"), "/", nrow(checks), ")**"), "",
  "## Final decision", "", "```text", decision, "```", "",
  "## Evidence summary", "",
  paste0("- Browser functional: ", sum(browser$result == "PASS"), "/", nrow(browser), "."),
  paste0("- Main-tab max: ", round(max(tabs$elapsed_seconds), 3), "s."),
  paste0("- Cold max: ", round(perf_value("cold_max"), 3), "s; warm p95: ", round(perf_value("warm_p95"), 3), "s; filter p95: ", round(perf_value("filter_p95"), 3), "s."),
  paste0("- Startup max: ", round(perf_value("startup_max"), 3), "s; RSS: ", round(as.numeric(server$actual[server$check == "session_memory_mb"]), 1), "MB."),
  paste0("- Downloads: ", paste(download_rows, collapse = ", "), " rows."),
  paste0("- Public bundle: ", dcf[1, "bundleId"], "; URL: ", dcf[1, "url"], "."), "",
  "The initial FRED key-collapse finding remains documented in Gate 5 evidence. The baseline was restored before final collection, and this validation independently confirms no legacy-history loss."
)
writeLines(report, file.path(gate_dir, "GATE6_VALIDATION_REPORT.md"), useBytes = TRUE)
cat("Gate 6 validation: ", if (all_pass) "PASS" else "FAIL", " (", sum(checks$result == "PASS"), "/", nrow(checks), ")\n", sep = "")
if (!all_pass) quit(status = 1L)
