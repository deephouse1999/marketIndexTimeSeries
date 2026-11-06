#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
positional <- args[!grepl("^--", args)]
batch_arg <- if (length(positional)) positional[[1]] else ""
batch <- switch(tolower(batch_arg), us = "us_close", us_close = "us_close", kr = "kr_close", kr_close = "kr_close", NA_character_)
if (is.na(batch)) stop("Usage: run_gate5_batch.R <us|kr> [--plan-only] [--force]")

repo_dir <- normalizePath(Sys.getenv("MARKET_TS_REPO", unset = "."), winslash = "/", mustWork = TRUE)
source(file.path(repo_dir, "scripts", "gate5_common.R"), local = TRUE)

plan_only <- "--plan-only" %in% args || identical(toupper(Sys.getenv("GATE5_PLAN_ONLY")), "TRUE")
validation_only <- "--validate-only" %in% args || identical(toupper(Sys.getenv("GATE5_VALIDATE_ONLY")), "TRUE")
force <- "--force" %in% args || identical(toupper(Sys.getenv("GATE5_FORCE")), "TRUE")
now <- gate5_now()
schedule <- gate5_schedule_status(batch, now)
state <- gate5_empty_state(batch, now)
state_path <- file.path(repo_dir, "batch_state", paste0(batch, "_latest.json"))
state_dir_override <- Sys.getenv("GATE5_STATE_DIR", unset = "")
if (nzchar(state_dir_override)) state_path <- file.path(state_dir_override, paste0(batch, "_latest.json"))
state$schedule <- schedule
gate5_write_state(state, state_path)

finish <- function(status, published = FALSE, error = NULL) {
  state$status <<- status
  state$published <<- isTRUE(published)
  state$completed_at <<- format(Sys.time(), tz = "Asia/Seoul", usetz = TRUE)
  if (!is.null(error)) state$error <<- as.character(error)
  gate5_write_state(state, state_path)
  cat(status, "\n")
}
signal_terminal <- function(status) {
  stop(structure(list(message = status, call = NULL), class = c("gate5_terminal", "error", "condition")))
}

if (!force && !schedule$eligible) {
  finish("SCHEDULE_GUARD_NOOP")
  quit(save = "no", status = 0L)
}
if (plan_only) {
  finish("PLAN_VALIDATED")
  quit(save = "no", status = 0L)
}
market_override <- toupper(Sys.getenv("GATE5_MARKET_STATUS_OVERRIDE", unset = ""))
if (market_override == "HOLIDAY") {
  finish(if (batch == "us_close") "US_MARKET_HOLIDAY_NOOP" else "KR_MARKET_HOLIDAY_NOOP")
  quit(save = "no", status = 0L)
}

lock_dir <- file.path(repo_dir, "batch_state", paste0(batch, ".lock"))
if (dir.exists(lock_dir)) {
  age_hours <- as.numeric(difftime(Sys.time(), file.info(lock_dir)$mtime, units = "hours"))
  if (is.finite(age_hours) && age_hours > 6) unlink(lock_dir, recursive = TRUE, force = TRUE)
}
if (!dir.create(lock_dir, recursive = FALSE, showWarnings = FALSE)) {
  finish("BATCH_ALREADY_RUNNING")
  quit(save = "no", status = 2L)
}
writeLines(c(state$batch_id, state$started_at), file.path(lock_dir, "owner.txt"))

stage_root <- file.path(repo_dir, "batch_staging", state$batch_id)
dir.create(stage_root, recursive = TRUE, showWarnings = FALSE)
gate5_copy_tree(file.path(repo_dir, "apps"), file.path(stage_root, "apps"))
gate5_copy_tree(file.path(repo_dir, "scripts"), file.path(stage_root, "scripts"))
gate5_copy_tree(file.path(repo_dir, "docs"), file.path(stage_root, "docs"))

rscript <- file.path(R.home("bin"), "Rscript.exe")
Sys.setenv(
  R_LIBS_USER = gate5_r_lib,
  MARKET_TS_GATE5_STAGING = "TRUE",
  GATE5_EXPECTED_SESSION = state$expected_session
)
run_child <- function(script, child_args = character()) {
  output <- system2(rscript, c(file.path("scripts", script), child_args), stdout = TRUE, stderr = TRUE)
  status <- attr(output, "status") %||% 0L
  writeLines(output, file.path(repo_dir, "batch_state", paste0(state$batch_id, "_", sub("\\.R$", "", script), ".log")))
  if (status != 0L) stop("CHILD_PROCESS_FAILED: ", script, " (", status, ")")
  invisible(output)
}

old_wd <- getwd()
setwd(stage_root)
on.exit(setwd(old_wd), add = TRUE)

result <- tryCatch({
  if (!validation_only) {
    if (batch == "us_close") {
      run_child("gate5_collect_legacy.R", "us")
      run_child("collect_sox_gate4.R")
      run_child("collect_ecos_gate2.R")
    } else {
      run_child("gate5_collect_legacy.R", "kr")
      run_child("collect_ecos_gate2.R")
    }
  }
  run_child("build_korea_rates_summary.R")
  run_child("build_sox_gate4_summary.R")
  run_child("build_physical_indicators.R")
  run_child("build_market_ui_core.R")
  run_child("build_series_explorer_store.R")

  app_dir <- file.path(stage_root, "apps", "timeseries")
  ecos_log_path <- file.path(app_dir, "ecos_update_log.csv")
  ecos_latest <- data.frame()
  if (!validation_only && file.exists(ecos_log_path)) {
    ecos_log <- read.csv(ecos_log_path, stringsAsFactors = FALSE)
    if ("batch_id" %in% names(ecos_log) && nrow(ecos_log)) {
      latest_ecos_batch <- tail(unique(ecos_log$batch_id), 1L)
      ecos_log <- ecos_log[ecos_log$batch_id == latest_ecos_batch, , drop = FALSE]
    }
    ecos_latest <- ecos_log
    pending <- grepl("PENDING_SOURCE", ecos_log$status, fixed = TRUE)
    state$pending_source <- unique(as.character(ecos_log$series_id[pending]))
  }
  present <- character()
  if (!validation_only) {
    critical <- if (batch == "us_close") c("^GSPC") else c("^KS11", "000660.KS", "005930.KS")
    yahoo <- read.fst(file.path(app_dir, "original_ts_yahoo.fst"), as.data.table = FALSE)
    components <- read.fst(file.path(app_dir, "original_ts_sox_components.fst"), as.data.table = FALSE)
    combined <- rbind(
      yahoo[, c("date", "series_id")],
      components[, c("date", "series_id")]
    )
    present <- unique(as.character(combined$series_id[as.Date(combined$date) == as.Date(state$expected_session)]))
    state$missing_critical <- setdiff(critical, present)
    if (length(state$missing_critical) == length(critical)) {
      signal_terminal(if (batch == "us_close") "US_MARKET_HOLIDAY_NOOP" else "KR_MARKET_HOLIDAY_NOOP")
    }
    if (length(state$missing_critical)) stop("MISSING_CRITICAL: ", paste(state$missing_critical, collapse = ","))
  }

  publish_files <- c(
    "apps/timeseries/original_ts_fred.fst", "apps/timeseries/tab_stat_description_fred.fst",
    "apps/timeseries/original_ts_yahoo.fst", "apps/timeseries/tab_stat_description_yahoo.fst",
    "apps/timeseries/original_ts_ecos.fst", "apps/timeseries/tab_stat_description_ecos.fst",
    "apps/timeseries/original_ts_sox_components.fst", "apps/timeseries/sox_constituents.csv",
    "apps/timeseries/sox_weight_history.csv", "apps/timeseries/derived_korea_rates_summary.fst",
    "apps/timeseries/derived_korea_rates_latest.fst", "apps/timeseries/derived_sox_daily_summary.fst",
    "apps/timeseries/derived_physical_indicators.fst",
    "apps/timeseries/derived_sox_latest.fst", "apps/timeseries/derived_sox_overview.fst",
    "apps/timeseries/derived_sox_overview.png", "apps/timeseries/derived_market_ui_core.fst"
    , "apps/timeseries/derived_series_explorer.fst"
  )
  fst_files <- publish_files[grepl("\\.fst$", publish_files)]
  checks <- lapply(fst_files, function(rel) gate5_validate_fst(file.path(stage_root, rel)))
  bad <- fst_files[!vapply(checks, `[[`, logical(1), "valid")]
  if (length(bad)) stop("STAGING_VALIDATION_FAILED: ", paste(bad, collapse = ","))

  if (validation_only) {
    signal_terminal("STAGING_VALIDATED_NO_PUBLICATION")
  }

  catalog <- read.csv(file.path(app_dir, "series_catalog.csv"), stringsAsFactors = FALSE)
  legacy_result_path <- file.path(app_dir, "gate5_legacy_result.csv")
  legacy_result <- if (file.exists(legacy_result_path)) read.csv(legacy_result_path, stringsAsFactors = FALSE) else data.frame()
  legacy_configured <- nrow(legacy_result)
  legacy_updated <- if (nrow(legacy_result)) sum(legacy_result$status == "success" & legacy_result$row_count > 0L, na.rm = TRUE) else 0L
  legacy_no_new <- if (nrow(legacy_result)) sum(legacy_result$status %in% c("empty_update", "skipped"), na.rm = TRUE) else 0L
  ecos_configured <- nrow(ecos_latest)
  ecos_updated <- if (nrow(ecos_latest)) sum(ecos_latest$status == "SUCCESS" & as.numeric(ecos_latest$rows_received) > 0L, na.rm = TRUE) else 0L
  ecos_pending <- if (nrow(ecos_latest)) sum(grepl("PENDING_SOURCE", ecos_latest$status, fixed = TRUE), na.rm = TRUE) else 0L
  ecos_no_new <- max(0L, ecos_configured - ecos_updated - ecos_pending)
  sox_configured <- 0L
  sox_updated <- 0L
  if (batch == "us_close") {
    disposition_path <- file.path(stage_root, "docs", "gate4", "series_disposition.csv")
    disposition <- if (file.exists(disposition_path)) read.csv(disposition_path, stringsAsFactors = FALSE) else data.frame()
    sox_ids <- if (nrow(disposition)) disposition$series_id[disposition$disposition == "COLLECTED_GATE4_FST"] else character()
    component_data <- read.fst(file.path(app_dir, "original_ts_sox_components.fst"), as.data.table = FALSE)
    sox_configured <- length(unique(sox_ids))
    sox_updated <- length(intersect(unique(as.character(component_data$series_id[as.Date(component_data$date) == as.Date(state$expected_session)])), sox_ids))
  }
  state$configured_series <- legacy_configured + ecos_configured + sox_configured
  state$updated_series <- legacy_updated + ecos_updated + sox_updated
  state$no_new_data_series <- legacy_no_new + ecos_no_new + (sox_configured - sox_updated)
  gate5_atomic_publish(stage_root, repo_dir, publish_files, state$batch_id)
  finish("PASS", TRUE)
  TRUE
}, error = function(e) {
  if (inherits(e, "gate5_terminal")) {
    finish(conditionMessage(e), FALSE)
    return(TRUE)
  }
  finish("FAILED_VALIDATION_OR_COLLECTION", FALSE, conditionMessage(e))
  FALSE
})

if (isTRUE(result) && state$status %in% c("PASS", "STAGING_VALIDATED_NO_PUBLICATION") &&
    !identical(toupper(Sys.getenv("GATE5_KEEP_STAGING", unset = "FALSE")), "TRUE")) {
  unlink(stage_root, recursive = TRUE, force = TRUE)
}
unlink(lock_dir, recursive = TRUE, force = TRUE)
quit(save = "no", status = if (isTRUE(result)) 0L else 1L)
