#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
batch <- if (length(args)) tolower(args[[1]]) else ""
if (!batch %in% c("us", "kr")) stop("Usage: reconcile_gate5_state.R <us|kr>")
batch_name <- paste0(batch, "_close")
repo_dir <- normalizePath(Sys.getenv("MARKET_TS_REPO", unset = "."), winslash = "/", mustWork = TRUE)
source(file.path(repo_dir, "scripts", "gate5_common.R"), local = TRUE)

state_path <- file.path(repo_dir, "batch_state", paste0(batch_name, "_latest.json"))
state <- jsonlite::read_json(state_path, simplifyVector = TRUE)
stage_root <- file.path(repo_dir, "batch_staging", state$batch_id)
app_dir <- file.path(stage_root, "apps", "timeseries")

legacy <- read.csv(file.path(app_dir, "gate5_legacy_result.csv"), stringsAsFactors = FALSE)
ecos <- read.csv(file.path(app_dir, "ecos_update_log.csv"), stringsAsFactors = FALSE)
ecos <- ecos[ecos$batch_id == tail(unique(ecos$batch_id), 1L), , drop = FALSE]
legacy_configured <- nrow(legacy)
legacy_updated <- sum(legacy$status == "success" & legacy$row_count > 0L, na.rm = TRUE)
legacy_no_new <- sum(legacy$status %in% c("empty_update", "skipped"), na.rm = TRUE)
ecos_configured <- nrow(ecos)
ecos_updated <- sum(ecos$status == "SUCCESS" & as.numeric(ecos$rows_received) > 0L, na.rm = TRUE)
ecos_pending <- sum(grepl("PENDING_SOURCE", ecos$status, fixed = TRUE), na.rm = TRUE)

sox_configured <- 0L
sox_updated <- 0L
if (batch == "us") {
  disposition <- read.csv(file.path(stage_root, "docs", "gate4", "series_disposition.csv"), stringsAsFactors = FALSE)
  sox_ids <- disposition$series_id[disposition$disposition == "COLLECTED_GATE4_FST"]
  components <- read.fst(file.path(app_dir, "original_ts_sox_components.fst"), as.data.table = FALSE)
  sox_configured <- length(unique(sox_ids))
  sox_updated <- length(intersect(
    unique(as.character(components$series_id[as.Date(components$date) == as.Date(state$expected_session)])),
    sox_ids
  ))
}

state$configured_series <- legacy_configured + ecos_configured + sox_configured
state$updated_series <- legacy_updated + ecos_updated + sox_updated
state$no_new_data_series <- legacy_no_new + max(0L, ecos_configured - ecos_updated - ecos_pending) + (sox_configured - sox_updated)
gate5_write_state(state, state_path)
cat(batch_name, "state reconciled:", state$configured_series, state$updated_series, state$no_new_data_series, "\n")
