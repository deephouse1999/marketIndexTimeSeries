# ECOS Open API adapter -----------------------------------------------------
# Network access is collector-only. The Shiny app must never source this file
# unless an explicit collection action is running outside the user session.

suppressPackageStartupMessages({
  library(dplyr)
  library(fst)
  library(httr2)
  library(jsonlite)
  library(readr)
  library(tibble)
})

ECOS_BASE_URL <- "https://ecos.bok.or.kr/api"
ECOS_PAGE_SIZE <- 1000L
ECOS_OVERLAP_BUSINESS_DAYS <- 5L

ecos_api_key <- function() {
  key <- trimws(Sys.getenv("ECOS_API_KEY", unset = ""))
  if (!nzchar(key)) return(NA_character_)
  key
}

ecos_key_status <- function() {
  if (is.na(ecos_api_key())) "SKIPPED_NO_KEY" else "KEY_BOUND"
}

ecos_encode <- function(x) {
  vapply(
    as.character(x),
    utils::URLencode,
    FUN.VALUE = character(1),
    reserved = TRUE,
    USE.NAMES = FALSE
  )
}

ecos_api_url <- function(service, start_row, end_row, args = character(), key = ecos_api_key()) {
  if (is.na(key) || !nzchar(key)) stop("SKIPPED_NO_KEY: ECOS_API_KEY is not set")
  pieces <- c(ECOS_BASE_URL, service, key, "json", "kr", start_row, end_row, ecos_encode(args))
  paste(pieces, collapse = "/")
}

ecos_error_code <- function(payload, service) {
  candidates <- list(
    payload$RESULT,
    payload[[service]]$RESULT
  )
  for (candidate in candidates) {
    if (!is.null(candidate$CODE)) {
      return(list(code = as.character(candidate$CODE), message = as.character(candidate$MESSAGE %||% "")))
    }
  }
  NULL
}

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) y else x

ecos_request_page <- function(service, args = character(), start_row = 1L,
                              end_row = ECOS_PAGE_SIZE, timeout_seconds = 30) {
  url <- ecos_api_url(service, start_row, end_row, args)
  response <- request(url) %>%
    req_timeout(timeout_seconds) %>%
    req_retry(max_tries = 3, backoff = ~ min(8, 2^.x)) %>%
    req_user_agent("marketIndexTimeSeries ECOS collector") %>%
    req_perform()

  payload <- resp_body_json(response, simplifyVector = FALSE)
  api_error <- ecos_error_code(payload, service)
  if (!is.null(api_error) && !api_error$code %in% c("INFO-000")) {
    stop(api_error$code, ": ", api_error$message)
  }

  block <- payload[[service]]
  if (is.null(block)) stop("ECOS_RESPONSE_SCHEMA_ERROR: missing ", service, " block")
  rows <- block$row %||% list()
  if (length(rows) == 0L) {
    data <- tibble()
  } else {
    data <- bind_rows(lapply(rows, function(row) {
      normalized <- lapply(row, function(value) {
        if (is.null(value) || length(value) == 0L) NA_character_ else as.character(value[[1]])
      })
      as_tibble(normalized)
    }))
  }

  list(
    total_count = as.integer(block$list_total_count %||% nrow(data)),
    data = data
  )
}

ecos_paginate <- function(service, args = character(), page_size = ECOS_PAGE_SIZE) {
  first <- ecos_request_page(service, args, 1L, page_size)
  total <- first$total_count
  if (is.na(total) || total <= nrow(first$data)) return(first$data)

  starts <- seq.int(page_size + 1L, total, by = page_size)
  pages <- lapply(starts, function(start_row) {
    ecos_request_page(service, args, start_row, min(start_row + page_size - 1L, total))$data
  })
  result <- bind_rows(c(list(first$data), pages))
  if (nrow(result) != total) {
    stop("ECOS_ROW_COUNT_MISMATCH: expected ", total, ", received ", nrow(result))
  }
  result
}

ecos_statistic_table_list <- function(search = "") {
  ecos_paginate("StatisticTableList", if (nzchar(search)) search else character())
}

ecos_statistic_item_list <- function(stat_code) {
  ecos_paginate("StatisticItemList", stat_code)
}

ecos_statistic_meta <- function(data_name) {
  ecos_paginate("StatisticMeta", data_name)
}

ecos_statistic_search <- function(stat_code, cycle, start_time, end_time,
                                  item_code1, item_code2 = "", item_code3 = "",
                                  item_code4 = "") {
  args <- c(stat_code, cycle, start_time, end_time, item_code1)
  optional <- c(item_code2, item_code3, item_code4)
  last_nonempty <- max(c(0L, which(nzchar(optional))))
  if (last_nonempty > 0L) args <- c(args, optional[seq_len(last_nonempty)])
  ecos_paginate("StatisticSearch", args)
}

normalize_ecos_item_snapshot <- function(items) {
  required <- c("STAT_CODE", "ITEM_CODE", "ITEM_NAME", "CYCLE", "START_TIME", "END_TIME")
  missing <- setdiff(required, names(items))
  if (length(missing)) stop("ECOS_ITEM_SCHEMA_ERROR: missing ", paste(missing, collapse = ", "))

  items %>%
    transmute(
      stat_code = as.character(STAT_CODE),
      stat_name = as.character(STAT_NAME %||% NA_character_),
      item_code = as.character(ITEM_CODE),
      item_name = as.character(ITEM_NAME),
      parent_item_code = as.character(P_ITEM_CODE %||% NA_character_),
      cycle = toupper(as.character(CYCLE)),
      unit = as.character(UNIT_NAME %||% NA_character_),
      start_date = as.character(START_TIME),
      end_date = as.character(END_TIME),
      data_count = suppressWarnings(as.integer(DATA_CNT %||% NA_integer_)),
      source_updated_at = NA_character_
    ) %>%
    distinct(stat_code, item_code, cycle, .keep_all = TRUE)
}

validate_ecos_catalog_rows <- function(config, item_snapshot) {
  required <- c("series_id", "stat_code", "cycle", "item_code1", "unit", "collect_flag")
  missing <- setdiff(required, names(config))
  if (length(missing)) stop("ECOS_CONFIG_SCHEMA_ERROR: missing ", paste(missing, collapse = ", "))

  active <- config %>% filter(collect_flag %in% TRUE)
  validation <- active %>%
    left_join(
      item_snapshot %>%
        select(stat_code, item_code1 = item_code, source_item_name = item_name,
               source_cycle = cycle, source_unit = unit, start_date, end_date),
      by = c("stat_code", "item_code1", "cycle" = "source_cycle")
    ) %>%
    mutate(
      status = case_when(
        is.na(source_item_name) ~ "CONFIG_CODE_MISMATCH",
        nzchar(unit) & !is.na(source_unit) & trimws(unit) != trimws(source_unit) ~ "CONFIG_CODE_MISMATCH",
        TRUE ~ "VERIFIED"
      )
    )

  validation
}

parse_ecos_date <- function(time_value, cycle) {
  value <- as.character(time_value)
  cycle <- toupper(as.character(cycle))
  out <- rep(as.Date(NA), length(value))
  daily <- cycle == "D"
  monthly <- cycle == "M"
  quarterly <- cycle == "Q"
  annual <- cycle == "A"
  out[daily] <- as.Date(value[daily], format = "%Y%m%d")
  out[monthly] <- as.Date(paste0(value[monthly], "01"), format = "%Y%m%d")
  if (any(quarterly)) {
    year <- suppressWarnings(as.integer(substr(value[quarterly], 1, 4)))
    quarter <- suppressWarnings(as.integer(gsub("[^1-4]", "", substr(value[quarterly], 5, nchar(value[quarterly])))))
    month <- (quarter - 1L) * 3L + 1L
    out[quarterly] <- as.Date(sprintf("%04d-%02d-01", year, month))
  }
  out[annual] <- as.Date(paste0(value[annual], "0101"), format = "%Y%m%d")
  out
}

normalize_ecos_observations <- function(rows, series_id, cycle) {
  if (nrow(rows) == 0L) {
    return(tibble(
      date = as.Date(character()), value = numeric(), series_id = character(),
      source = character(), observation_date = as.Date(character()), available_at = character(),
      collected_at = character(), source_updated_at = character(), vintage = character(),
      quality_status = character(), calculation_version = character()
    ))
  }
  if (!all(c("TIME", "DATA_VALUE") %in% names(rows))) {
    stop("ECOS_DATA_SCHEMA_ERROR: TIME or DATA_VALUE missing")
  }

  collected_at <- format(Sys.time(), tz = "Asia/Seoul", usetz = TRUE)
  rows %>%
    transmute(
      date = parse_ecos_date(TIME, cycle),
      value = readr::parse_number(as.character(DATA_VALUE), na = c("", "NA", "-")),
      series_id = as.character(series_id),
      source = "ECOS",
      observation_date = date,
      available_at = collected_at,
      collected_at = collected_at,
      source_updated_at = NA_character_,
      vintage = collected_at,
      quality_status = "VERIFIED_SOURCE",
      calculation_version = "RAW_ECOS_V1"
    ) %>%
    filter(!is.na(date)) %>%
    distinct(source, series_id, date, .keep_all = TRUE) %>%
    arrange(date)
}

normalize_ecos_storage_schema <- function(data) {
  data <- as_tibble(data)
  if (!"observation_date" %in% names(data)) data$observation_date <- as.Date(data$date)
  if (!"available_at" %in% names(data)) data$available_at <- as.character(data$collected_at)
  # ECOS StatisticSearch does not provide a historical publication/revision timestamp.
  # Keep this unknown rather than substituting the collector clock.
  data$source_updated_at <- NA_character_
  if (!"vintage" %in% names(data)) data$vintage <- as.character(data$collected_at)
  if (!"quality_status" %in% names(data)) data$quality_status <- "LEGACY_SOURCE_VERIFIED"
  if (!"calculation_version" %in% names(data)) data$calculation_version <- "RAW_ECOS_V1"
  data %>% mutate(date = as.Date(date), observation_date = as.Date(observation_date))
}

format_ecos_time <- function(date, cycle) {
  cycle <- toupper(cycle)
  switch(
    cycle,
    D = format(as.Date(date), "%Y%m%d"),
    M = format(as.Date(date), "%Y%m"),
    Q = paste0(format(as.Date(date), "%Y"), "Q", ((as.integer(format(as.Date(date), "%m")) - 1L) %/% 3L) + 1L),
    A = format(as.Date(date), "%Y"),
    stop("Unsupported ECOS cycle: ", cycle)
  )
}

ecos_collect_one <- function(config_row, start_date, end_date) {
  row <- as.list(config_row[1, , drop = FALSE])
  raw <- ecos_statistic_search(
    row$stat_code, row$cycle,
    format_ecos_time(start_date, row$cycle),
    format_ecos_time(end_date, row$cycle),
    row$item_code1, row$item_code2, row$item_code3, row$item_code4
  )
  normalize_ecos_observations(raw, row$series_id, row$cycle)
}

ecos_collect_one_safe <- function(config_row, start_date, end_date) {
  tryCatch({
    data <- ecos_collect_one(config_row, start_date, end_date)
    status <- if (nrow(data) > 0L && as.Date(end_date) >= Sys.Date() && max(data$date) < as.Date(end_date)) {
      "SUCCESS_PENDING_SOURCE"
    } else if (nrow(data) > 0L) {
      "SUCCESS"
    } else if (as.Date(end_date) >= Sys.Date()) {
      "PENDING_SOURCE"
    } else {
      "NO_DATA"
    }
    list(status = status, data = data, error = NA_character_)
  }, error = function(e) {
    message <- conditionMessage(e)
    if (grepl("SKIPPED_NO_KEY", message, fixed = TRUE)) {
      status <- "SKIPPED_NO_KEY"
    } else if (grepl("INFO-200", message, fixed = TRUE) && as.Date(end_date) >= Sys.Date()) {
      status <- "PENDING_SOURCE"
    } else if (grepl("INFO-200", message, fixed = TRUE)) {
      status <- "NO_DATA"
    } else {
      status <- "ERROR"
    }
    list(status = status, data = normalize_ecos_observations(tibble(), as.character(config_row$series_id[[1]]), as.character(config_row$cycle[[1]])), error = message)
  })
}

previous_business_date <- function(date, business_days = ECOS_OVERLAP_BUSINESS_DAYS) {
  candidate <- as.Date(date)
  remaining <- as.integer(business_days)
  while (remaining > 0L) {
    candidate <- candidate - 1L
    if (!as.integer(format(candidate, "%u")) %in% c(6L, 7L)) remaining <- remaining - 1L
  }
  candidate
}

ecos_merge_overlap <- function(existing, incoming) {
  bind_rows(existing, incoming) %>%
    arrange(source, series_id, date, collected_at) %>%
    distinct(source, series_id, date, .keep_all = FALSE) %>%
    arrange(series_id, date)
}

validate_ecos_dataset <- function(data) {
  required <- c("date", "observation_date", "value", "series_id", "source", "available_at",
                "collected_at", "source_updated_at", "vintage", "quality_status", "calculation_version")
  missing <- setdiff(required, names(data))
  duplicate_keys <- if (length(missing)) NA_integer_ else data %>% count(source, series_id, date) %>% filter(n > 1L) %>% nrow()
  list(
    valid = length(missing) == 0L && duplicate_keys == 0L && all(data$source == "ECOS") && all(!is.na(data$date)),
    missing_columns = missing,
    duplicate_keys = duplicate_keys,
    rows = nrow(data),
    series = dplyr::n_distinct(data$series_id)
  )
}

atomic_publish_ecos_fst <- function(data, target_path) {
  validation <- validate_ecos_dataset(data)
  if (!validation$valid) stop("ECOS_STAGING_VALIDATION_FAILED")
  dir.create(dirname(target_path), recursive = TRUE, showWarnings = FALSE)
  staging_path <- paste0(target_path, ".staging")
  backup_path <- paste0(target_path, ".last_good")
  on.exit(if (file.exists(staging_path)) unlink(staging_path), add = TRUE)

  write.fst(data, staging_path, compress = 50)
  readback <- read.fst(staging_path, as.data.table = FALSE)
  readback_validation <- validate_ecos_dataset(readback)
  if (!readback_validation$valid || readback_validation$rows != nrow(data)) {
    stop("ECOS_STAGING_READBACK_FAILED")
  }

  if (file.exists(backup_path)) unlink(backup_path)
  if (file.exists(target_path) && !file.rename(target_path, backup_path)) {
    stop("ECOS_BACKUP_FAILED: last good file was not moved")
  }
  if (!file.rename(staging_path, target_path)) {
    if (file.exists(backup_path)) file.rename(backup_path, target_path)
    stop("ECOS_ATOMIC_PUBLICATION_FAILED: last good file restored")
  }
  invisible(readback_validation)
}

