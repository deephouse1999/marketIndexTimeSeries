gate5_r_lib <- "C:/Users/yjh14/AppData/Local/R/win-library/4.5"
if (dir.exists(gate5_r_lib)) .libPaths(c(gate5_r_lib, .libPaths()))

suppressPackageStartupMessages({
  library(fst)
  library(jsonlite)
})

`%||%` <- function(x, y) if (is.null(x) || !length(x) || all(is.na(x))) y else x

gate5_now <- function() {
  injected <- Sys.getenv("GATE5_NOW", unset = "")
  if (nzchar(injected)) {
    parsed <- as.POSIXct(injected, tz = "Asia/Seoul")
    if (is.na(parsed)) stop("GATE5_NOW must be an ISO-like datetime in Asia/Seoul")
    return(parsed)
  }
  Sys.time()
}

gate5_local_time <- function(now, tz) {
  as.POSIXct(format(now, tz = tz, format = "%Y-%m-%d %H:%M:%S"), tz = tz)
}

gate5_expected_session <- function(batch, now = gate5_now()) {
  tz <- if (identical(batch, "us_close")) "America/New_York" else "Asia/Seoul"
  as.Date(format(now, tz = tz, format = "%Y-%m-%d"))
}

gate5_is_new_york_dst <- function(now = gate5_now()) {
  as.POSIXlt(now, tz = "America/New_York")$isdst == 1L
}

gate5_schedule_status <- function(batch, now = gate5_now(), tolerance_minutes = 10L) {
  if (!batch %in% c("us_close", "kr_close")) stop("Unknown Gate 5 batch: ", batch)
  tz <- if (batch == "us_close") "America/New_York" else "Asia/Seoul"
  local <- gate5_local_time(now, tz)
  weekday <- as.integer(format(local, "%u"))
  target_minutes <- if (batch == "us_close") 18L * 60L + 5L else 16L * 60L + 5L
  actual_minutes <- as.integer(format(local, "%H")) * 60L + as.integer(format(local, "%M"))
  list(
    eligible = weekday <= 5L && abs(actual_minutes - target_minutes) <= tolerance_minutes,
    timezone = tz,
    local_time = format(local, "%Y-%m-%d %H:%M:%S %Z"),
    weekday = weekday,
    target = if (batch == "us_close") "18:05" else "16:05",
    new_york_dst = gate5_is_new_york_dst(now)
  )
}

gate5_empty_state <- function(batch, now = gate5_now()) {
  list(
    batch_id = paste0(toupper(batch), "_", format(now, tz = "Asia/Seoul", "%Y%m%dT%H%M%S")),
    expected_session = as.character(gate5_expected_session(batch, now)),
    started_at = format(now, tz = "Asia/Seoul", usetz = TRUE),
    completed_at = NA_character_, status = "STARTED",
    configured_series = 0L, updated_series = 0L, no_new_data_series = 0L,
    missing_critical = character(), pending_source = character(), published = FALSE
  )
}

gate5_write_state <- function(state, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  staging <- paste0(path, ".staging")
  write_json(state, staging, pretty = TRUE, auto_unbox = TRUE, na = "null")
  if (file.exists(path) && !file.remove(path)) stop("BATCH_STATE_REPLACE_FAILED: ", path)
  if (!file.rename(staging, path)) stop("BATCH_STATE_PUBLICATION_FAILED: ", path)
  invisible(path)
}

gate5_copy_tree <- function(source, target) {
  if (!dir.exists(source)) stop("Source directory missing: ", source)
  dir.create(target, recursive = TRUE, showWarnings = FALSE)
  source_norm <- normalizePath(source, winslash = "/")
  entries <- list.files(source, recursive = TRUE, full.names = TRUE, all.files = TRUE, no.. = TRUE)
  dirs <- entries[dir.exists(entries)]
  files <- entries[file.exists(entries) & !dir.exists(entries)]
  if (length(dirs)) {
    rel <- substring(normalizePath(dirs, winslash = "/"), nchar(source_norm) + 2L)
    invisible(lapply(file.path(target, rel), dir.create, recursive = TRUE, showWarnings = FALSE))
  }
  if (length(files)) {
    rel <- substring(normalizePath(files, winslash = "/"), nchar(source_norm) + 2L)
    destinations <- file.path(target, rel)
    invisible(lapply(unique(dirname(destinations)), dir.create, recursive = TRUE, showWarnings = FALSE))
    if (!all(file.copy(files, destinations, overwrite = TRUE, copy.date = TRUE))) stop("STAGING_COPY_FAILED")
  }
  invisible(target)
}

gate5_validate_fst <- function(path) {
  if (!file.exists(path)) return(list(valid = FALSE, reason = "MISSING_FILE", rows = 0L, series = 0L, duplicates = NA_integer_))
  data <- tryCatch(read.fst(path, as.data.table = FALSE), error = identity)
  if (inherits(data, "error")) return(list(valid = FALSE, reason = conditionMessage(data), rows = 0L, series = 0L, duplicates = NA_integer_))
  key <- character()
  candidate_keys <- list(
    c("metric_group", "metric_id", "date"),
    c("metric_id", "observation_date", "reference_date"),
    c("source", "series_id", "date")
  )
  for (candidate in candidate_keys) {
    if (all(candidate %in% names(data))) {
      key <- candidate
      break
    }
  }
  duplicates <- if (length(key)) sum(duplicated(data[key])) else 0L
  series_col <- if ("series_id" %in% names(data)) "series_id" else if ("metric_id" %in% names(data)) "metric_id" else NULL
  series <- if (is.null(series_col)) 0L else length(unique(data[[series_col]]))
  list(valid = nrow(data) > 0L && duplicates == 0L, reason = if (duplicates) "DUPLICATE_KEYS" else "PASS",
       rows = nrow(data), series = series, duplicates = duplicates)
}

gate5_atomic_publish <- function(staging_root, live_root, relative_paths, batch_id) {
  relative_paths <- unique(relative_paths[file.exists(file.path(staging_root, relative_paths))])
  if (!length(relative_paths)) stop("NO_STAGED_ARTIFACTS_TO_PUBLISH")
  transaction_dir <- file.path(live_root, "batch_state", "transactions", batch_id)
  dir.create(transaction_dir, recursive = TRUE, showWarnings = FALSE)
  published <- character()
  rollback <- function() {
    for (rel in rev(published)) {
      live <- file.path(live_root, rel)
      backup <- file.path(transaction_dir, rel)
      if (file.exists(live)) unlink(live)
      if (file.exists(backup)) {
        dir.create(dirname(live), recursive = TRUE, showWarnings = FALSE)
        file.copy(backup, live, overwrite = TRUE, copy.date = TRUE)
      }
    }
  }
  for (rel in relative_paths) {
    staged <- file.path(staging_root, rel)
    live <- file.path(live_root, rel)
    backup <- file.path(transaction_dir, rel)
    incoming <- paste0(live, ".gate5_incoming")
    dir.create(dirname(live), recursive = TRUE, showWarnings = FALSE)
    dir.create(dirname(backup), recursive = TRUE, showWarnings = FALSE)
    if (file.exists(live) && !file.copy(live, backup, overwrite = TRUE, copy.date = TRUE)) {
      rollback(); stop("TRANSACTION_BACKUP_FAILED: ", rel)
    }
    if (!file.copy(staged, incoming, overwrite = TRUE, copy.date = TRUE)) {
      rollback(); stop("INCOMING_COPY_FAILED: ", rel)
    }
    if (file.exists(live) && !file.remove(live)) {
      unlink(incoming); rollback(); stop("LIVE_REMOVE_FAILED: ", rel)
    }
    if (!file.rename(incoming, live)) {
      if (file.exists(backup)) file.copy(backup, live, overwrite = TRUE, copy.date = TRUE)
      rollback(); stop("ATOMIC_RENAME_FAILED: ", rel)
    }
    published <- c(published, rel)
    fail_after <- suppressWarnings(as.integer(Sys.getenv("GATE5_FAIL_AFTER_PUBLISH_N", unset = "")))
    if (is.finite(fail_after) && length(published) >= fail_after) {
      rollback()
      stop("INJECTED_PUBLICATION_FAILURE_AFTER_", fail_after)
    }
  }
  for (rel in relative_paths) {
    backup <- file.path(transaction_dir, rel)
    if (file.exists(backup) && grepl("\\.fst$", rel, ignore.case = TRUE)) {
      file.copy(backup, paste0(file.path(live_root, rel), ".last_good"), overwrite = TRUE, copy.date = TRUE)
    }
  }
  list(published = relative_paths, transaction_dir = transaction_dir)
}
