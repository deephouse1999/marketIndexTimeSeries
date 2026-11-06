#!/usr/bin/env Rscript

repo_dir <- normalizePath(Sys.getenv("MARKET_TS_REPO", unset = "."), winslash = "/", mustWork = TRUE)
source(file.path(repo_dir, "scripts", "gate5_common.R"), local = TRUE)
evidence_dir <- file.path(repo_dir, "docs", "gate5")
dir.create(evidence_dir, recursive = TRUE, showWarnings = FALSE)

checks <- data.frame(check_id = character(), expected = character(), actual = character(), result = character())
add_check <- function(id, expected, actual, pass) {
  checks <<- rbind(checks, data.frame(check_id = id, expected = as.character(expected), actual = as.character(actual), result = if (isTRUE(pass)) "PASS" else "FAIL"))
}

for (batch in c("us_close", "kr_close")) {
  state <- read_json(file.path(repo_dir, "batch_state", paste0(batch, "_latest.json")), simplifyVector = TRUE)
  add_check(paste0(batch, "_status"), "PASS", state$status, identical(state$status, "PASS"))
  add_check(paste0(batch, "_published"), "TRUE", state$published, isTRUE(state$published))
  required <- c("batch_id", "expected_session", "started_at", "completed_at", "status", "configured_series", "updated_series", "no_new_data_series", "missing_critical", "pending_source", "published")
  add_check(paste0(batch, "_state_contract"), paste(required, collapse = ";"), paste(intersect(required, names(state)), collapse = ";"), all(required %in% names(state)))
  add_check(paste0(batch, "_critical"), "0", length(state$missing_critical), !length(state$missing_critical))
  add_check(paste0(batch, "_transaction"), "EXISTS", state$batch_id, dir.exists(file.path(repo_dir, "batch_state", "transactions", state$batch_id)))
}

fst_rel <- c(
  "original_ts_fred.fst", "original_ts_yahoo.fst", "original_ts_ecos.fst", "original_ts_sox_components.fst",
  "derived_korea_rates_summary.fst", "derived_korea_rates_latest.fst", "derived_sox_daily_summary.fst",
  "derived_sox_latest.fst", "derived_sox_overview.fst", "derived_market_ui_core.fst"
)
for (name in fst_rel) {
  path <- file.path(repo_dir, "apps", "timeseries", name)
  validation <- gate5_validate_fst(path)
  add_check(paste0("fst_", name), "READBACK_PASS_DUPLICATES_0", paste(validation$reason, validation$duplicates, validation$rows, sep = "/"), validation$valid)
}
for (name in fst_rel[grepl("^original_ts_", fst_rel)]) {
  add_check(paste0("last_good_", name), "EXISTS", file.exists(paste0(file.path(repo_dir, "apps", "timeseries", name), ".last_good")), file.exists(paste0(file.path(repo_dir, "apps", "timeseries", name), ".last_good")))
}

us_state <- read_json(file.path(repo_dir, "batch_state", "us_close_latest.json"), simplifyVector = TRUE)
fred_baseline_path <- file.path(repo_dir, "batch_state", "transactions", us_state$batch_id, "apps", "timeseries", "original_ts_fred.fst")
fred_live <- read.fst(file.path(repo_dir, "apps", "timeseries", "original_ts_fred.fst"), as.data.table = FALSE)
fred_baseline_hash <- if (requireNamespace("digest", quietly = TRUE)) toupper(digest::digest(fred_baseline_path, algo = "sha256", file = TRUE)) else "DIGEST_PACKAGE_MISSING"
add_check("fred_gate4_baseline_backup", "67CBDA72DEB4ED07A559584711F8AB71F83D1C578CC9F719774438F96DE53884", fred_baseline_hash,
          identical(fred_baseline_hash, "67CBDA72DEB4ED07A559584711F8AB71F83D1C578CC9F719774438F96DE53884"))
add_check("fred_legacy_rows_preserved", ">=456067 rows and >=246950 source=NA", paste(nrow(fred_live), sum(is.na(fred_live$source)), sep = "/"),
          nrow(fred_live) >= 456067L && sum(is.na(fred_live$source)) >= 246950L)
prior_weight_path <- file.path(repo_dir, "batch_state", "transactions", us_state$batch_id, "apps", "timeseries", "sox_weight_history.csv")
live_weight_path <- file.path(repo_dir, "apps", "timeseries", "sox_weight_history.csv")
prior_weights <- read.csv(prior_weight_path, stringsAsFactors = FALSE)
live_weights <- read.csv(live_weight_path, stringsAsFactors = FALSE)
weight_key <- c("ticker", "weight_as_of", "snapshot_type")
prior_keys <- do.call(paste, c(prior_weights[weight_key], sep = "|"))
live_keys <- do.call(paste, c(live_weights[weight_key], sep = "|"))
add_check("sox_weight_history_append_only", "0 prior keys missing", length(setdiff(prior_keys, live_keys)), !length(setdiff(prior_keys, live_keys)))

task_names <- c("MARKET_TS_US_CLOSE_DST", "MARKET_TS_US_CLOSE_STANDARD", "MARKET_TS_KR_CLOSE")
task_text <- character()
for (task in task_names) {
  output <- system2("schtasks.exe", c("/Query", "/TN", task, "/FO", "LIST", "/V"), stdout = TRUE, stderr = TRUE)
  task_text <- c(task_text, paste0("===== ", task, " ====="), output, "")
  add_check(paste0("task_", task), "READY_AND_CORRECT_RUNNER", paste(output, collapse = " | "),
            any(grepl("Ready", output, fixed = TRUE)) && any(grepl("run_gate5_batch.ps1", output, fixed = TRUE)))
}
writeLines(task_text, file.path(evidence_dir, "scheduled_tasks_readback.txt"))
write.csv(checks, file.path(evidence_dir, "gate5_validation_checks.csv"), row.names = FALSE, na = "")
if (any(checks$result != "PASS")) stop("GATE5_VALIDATION_FAILED: ", paste(checks$check_id[checks$result != "PASS"], collapse = ","))
cat("Gate 5 validation: PASS (", nrow(checks), "/", nrow(checks), ")\n", sep = "")
