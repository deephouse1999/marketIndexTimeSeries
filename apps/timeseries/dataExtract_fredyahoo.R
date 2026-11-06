# dataExtract_fredyahoo.R ----------------------------------------------------
# Catalog-driven FRED + Yahoo collector for marketIndexTimeSeries.

suppressPackageStartupMessages({
  library(fst)
  library(dplyr)
  library(purrr)
  library(lubridate)
  library(readr)
  library(fredr)
  library(quantmod)
})

ALLOWED_SOURCES <- c("FRED", "YAHOO", "ECOS")
ALLOWED_CLS <- c(
  "broad_index", "broad_etf", "global_etf", "country_etf", "sector_etf",
  "industry_etf", "signal_stock", "legacy_stock", "rate", "credit",
  "forex", "commodity", "gdp", "employment", "emerging_market_etf",
  "gvt_debt", "investment", "labor", "general_inflation", "inflation",
  "macro", "policy", "volatility", "volatility_index", "etf", "sectors",
  "industries", "emerging_market_index", "index_constituent", "producer_price_index",
  "freight_futures_etf_proxy"
)
ALLOWED_CYCLES <- c("", "D", "M", "Q", "A")
ALLOWED_PRICE_POLICIES <- c("close", "adjusted")

get_project_dir <- function() {
  candidates <- c(
    normalizePath(getwd(), winslash = "/", mustWork = TRUE),
    normalizePath(file.path(getwd(), "..", "marketIndexTimeSeries"), winslash = "/", mustWork = FALSE),
    normalizePath(file.path(getwd(), "marketIndexTimeSeries"), winslash = "/", mustWork = FALSE),
    "C:/app/econ_ts/marketIndexTimeSeries",
    "C:/app/econ_ts",
    "/cloud/project/econ_ts"
  )

  for (candidate in candidates) {
    if (is.na(candidate)) next
    if (
      file.exists(file.path(candidate, "marketIndexTimeSeries", "apps", "timeseries", "dataExtract_fredyahoo.R")) ||
      file.exists(file.path(candidate, "apps", "timeseries", "dataExtract_fredyahoo.R")) ||
      file.exists(file.path(candidate, "apps", "timeseries", "series_catalog.csv"))
    ) {
      return(normalizePath(candidate, winslash = "/", mustWork = TRUE))
    }
  }
  normalizePath(getwd(), winslash = "/", mustWork = TRUE)
}

project_dir <- get_project_dir()
data_dir <- project_dir
if (basename(normalizePath(project_dir)) == "marketIndexTimeSeries") {
  data_dir <- file.path(project_dir, "apps", "timeseries")
} else if (!file.exists(file.path(data_dir, "series_catalog.csv")) && file.exists(file.path(data_dir, "marketIndexTimeSeries", "apps", "timeseries", "series_catalog.csv"))) {
  data_dir <- file.path(data_dir, "marketIndexTimeSeries", "apps", "timeseries")
} else if (!file.exists(file.path(data_dir, "series_catalog.csv")) && file.exists(file.path(data_dir, "apps", "timeseries", "series_catalog.csv"))) {
  data_dir <- file.path(data_dir, "apps", "timeseries")
}
dir.create(data_dir, showWarnings = FALSE, recursive = TRUE)

fn_path <- function(file) file.path(data_dir, file)
fred_ts_path <- fn_path("original_ts_fred.fst")
fred_desc_path <- fn_path("tab_stat_description_fred.fst")
yahoo_ts_path <- fn_path("original_ts_yahoo.fst")
yahoo_desc_path <- fn_path("tab_stat_description_yahoo.fst")
update_log_path <- fn_path("ts_update_log.csv")

catalog_path <- fn_path("series_catalog.csv")
if (!file.exists(catalog_path)) {
  fallback <- file.path(project_dir, "apps", "timeseries", "series_catalog.csv")
  if (file.exists(fallback)) catalog_path <- fallback
}
if (!file.exists(catalog_path)) {
  stop("series_catalog.csv not found in apps/timeseries.")
}

empty_data_schema <- tibble::tibble(
  date = as.Date(character()),
  observation_date = as.Date(character()),
  series_id = character(),
  close_value = numeric(),
  adjusted_value = numeric(),
  volume = numeric(),
  source = character(),
  available_at = character(),
  collected_at = character(),
  source_updated_at = character(),
  vintage = character(),
  quality_status = character(),
  calculation_version = character()
)

us_close_available_at <- function(date) {
  close_et <- as.POSIXct(paste(as.Date(date), "16:00:00"), tz = "America/New_York")
  format(close_et, tz = "Asia/Seoul", format = "%Y-%m-%d %H:%M:%S %Z")
}

parse_logical <- function(x) {
  v <- trimws(tolower(as.character(x)))
  out <- rep(NA, length(v))
  out[v %in% c("1", "true", "t", "y", "yes")] <- TRUE
  out[v %in% c("0", "false", "f", "n", "no")] <- FALSE
  as.logical(out)
}

read_series_catalog <- function(path) {
  raw <- suppressMessages(readr::read_csv(path, show_col_types = FALSE))

  required_cols <- c(
    "source", "series_id", "display_name", "display_name_ko", "series_cls",
    "series_group", "sector", "industry", "region", "currency",
    "benchmark_series", "price_policy", "stat_code", "cycle", "item_code1",
    "item_code2", "item_code3", "item_code4", "unit", "transform",
    "collect_flag", "default_visible", "active", "display_order", "notes"
  )
  missing_cols <- setdiff(required_cols, names(raw))
  if (length(missing_cols) > 0) {
    stop("series_catalog missing required columns: ", paste(missing_cols, collapse = ", "))
  }

  catalog <- raw %>%
    mutate(
      source = toupper(trimws(as.character(source))),
      series_id = trimws(as.character(series_id)),
      source_symbol = if ("source_symbol" %in% names(raw)) trimws(as.character(source_symbol)) else series_id,
      source_symbol = ifelse(is.na(source_symbol) | source_symbol == "", series_id, source_symbol),
      display_name = trimws(as.character(display_name)),
      display_name_ko = trimws(as.character(display_name_ko)),
      series_cls = trimws(as.character(series_cls)),
      series_group = trimws(as.character(series_group)),
      sector = trimws(as.character(sector)),
      industry = trimws(as.character(industry)),
      region = trimws(as.character(region)),
      currency = trimws(as.character(currency)),
      benchmark_series = na_if(trimws(as.character(benchmark_series)), ""),
      price_policy = na_if(trimws(as.character(price_policy)), ""),
      stat_code = na_if(trimws(as.character(stat_code)), ""),
      cycle = toupper(ifelse(is.na(cycle), "", trimws(as.character(cycle)))),
      item_code1 = na_if(trimws(as.character(item_code1)), ""),
      item_code2 = na_if(trimws(as.character(item_code2)), ""),
      item_code3 = na_if(trimws(as.character(item_code3)), ""),
      item_code4 = na_if(trimws(as.character(item_code4)), ""),
      unit = na_if(trimws(as.character(unit)), ""),
      transform = na_if(trimws(as.character(transform)), ""),
      notes = ifelse(is.na(notes), "", trimws(as.character(notes))),
      collect_flag = parse_logical(collect_flag),
      default_visible = parse_logical(default_visible),
      active = parse_logical(active),
      display_order = readr::parse_integer(as.character(display_order))
    ) %>%
    mutate(
      display_name = ifelse(is.na(display_name) | display_name == "", series_id, display_name),
      display_name_ko = ifelse(is.na(display_name_ko) | display_name_ko == "", display_name, display_name_ko)
    )

  bad_source <- setdiff(unique(toupper(catalog$source)), ALLOWED_SOURCES)
  bad_source <- bad_source[!is.na(bad_source) & nzchar(bad_source)]
  if (length(bad_source) > 0) {
    stop("Unsupported source in catalog: ", paste(bad_source, collapse = ", "))
  }

  bad_cls <- setdiff(unique(catalog$series_cls), ALLOWED_CLS)
  bad_cls <- bad_cls[!is.na(bad_cls) & nzchar(bad_cls)]
  if (length(bad_cls) > 0) {
    stop("Unsupported series_cls in catalog: ", paste(bad_cls, collapse = ", "))
  }

  bad_cycle <- setdiff(unique(catalog$cycle), ALLOWED_CYCLES)
  bad_cycle <- bad_cycle[!is.na(bad_cycle) & nzchar(bad_cycle)]
  if (length(bad_cycle) > 0) {
    stop("Unsupported cycle in catalog: ", paste(bad_cycle, collapse = ", "))
  }

  bad_policy <- setdiff(unique(catalog$price_policy), ALLOWED_PRICE_POLICIES)
  bad_policy <- bad_policy[!is.na(bad_policy) & nzchar(bad_policy)]
  if (length(bad_policy) > 0) {
    stop("Unsupported price_policy in catalog: ", paste(bad_policy, collapse = ", "))
  }

  dup <- catalog %>%
    filter(!is.na(series_id), series_id != "") %>%
    count(source, series_id) %>%
    filter(n > 1)
  if (nrow(dup) > 0) {
    stop(
      "Duplicate (source, series_id) found in catalog: ",
      paste(paste0(dup$source, ":", dup$series_id), collapse = ", ")
    )
  }

  missing_name <- catalog %>% filter(is.na(display_name) | display_name == "")
  if (nrow(missing_name) > 0) {
    stop("display_name missing for: ", paste(missing_name$series_id, collapse = ", "))
  }

  bad_ecos <- catalog %>%
    filter(
      source == "ECOS",
      collect_flag %in% TRUE,
      is.na(stat_code) | cycle == "" | is.na(item_code1)
    )
  if (nrow(bad_ecos) > 0) {
    stop(
      "Collectable ECOS rows require stat_code, cycle, and item_code1: ",
      paste(bad_ecos$series_id, collapse = ", ")
    )
  }

  catalog
}

normalize_old_schema <- function(df) {
  if (nrow(df) == 0) return(empty_data_schema)
  out <- as_tibble(df)
  if ("value" %in% names(out) && !"close_value" %in% names(out)) {
    out$close_value <- as.numeric(out$value)
  }
  if (!"close_value" %in% names(out)) out$close_value <- NA_real_
  if (!"adjusted_value" %in% names(out)) out$adjusted_value <- NA_real_
  if (!"volume" %in% names(out)) out$volume <- NA_real_
  if (!"source" %in% names(out)) out$source <- NA_character_
  if (!"collected_at" %in% names(out)) out$collected_at <- as.character(Sys.time())
  if (!"observation_date" %in% names(out)) out$observation_date <- as.Date(out$date)
  if (!"available_at" %in% names(out)) out$available_at <- NA_character_
  yahoo_missing <- toupper(as.character(out$source)) == "YAHOO" & (is.na(out$available_at) | out$available_at == "")
  out$available_at[yahoo_missing] <- us_close_available_at(out$date[yahoo_missing])
  other_missing <- !yahoo_missing & (is.na(out$available_at) | out$available_at == "")
  out$available_at[other_missing] <- as.character(out$collected_at[other_missing])
  if (!"source_updated_at" %in% names(out)) out$source_updated_at <- NA_character_
  if (!"vintage" %in% names(out)) out$vintage <- as.character(as.Date(out$date))
  if (!"quality_status" %in% names(out)) out$quality_status <- ifelse(toupper(as.character(out$source)) == "YAHOO", "SOURCE_MARKET_CLOSE", "SOURCE_OBSERVATION")
  if (!"calculation_version" %in% names(out)) out$calculation_version <- ifelse(toupper(as.character(out$source)) == "YAHOO", "RAW_YAHOO_V2", "RAW_FRED_V2")

  out %>%
    transmute(
      date = as.Date(date),
      observation_date = as.Date(observation_date),
      series_id = as.character(series_id),
      close_value = as.numeric(close_value),
      adjusted_value = as.numeric(adjusted_value),
      volume = as.numeric(volume),
      source = as.character(source),
      available_at = as.character(available_at),
      collected_at = as.character(collected_at),
      source_updated_at = as.character(source_updated_at),
      vintage = as.character(vintage),
      quality_status = as.character(quality_status),
      calculation_version = as.character(calculation_version)
    ) %>%
    filter(!is.na(series_id), !is.na(date)) %>%
    # Legacy rows with an unknown source and official source rows are distinct records.
    distinct(source, series_id, date, .keep_all = TRUE)
}

load_existing_data <- function(path) {
  if (!file.exists(path)) return(empty_data_schema)
  normalize_old_schema(read.fst(path))
}

append_run_log <- function(path, run_log) {
  if (nrow(run_log) == 0) return(invisible(NULL))
  if (file.exists(path)) {
    write.table(run_log, file = path, sep = ",", row.names = FALSE, col.names = FALSE, append = TRUE)
  } else {
    write.table(run_log, file = path, sep = ",", row.names = FALSE, col.names = TRUE, append = FALSE)
  }
}

safe_fred_series <- purrr::possibly(function(series_id, start_date = NULL) {
  args <- list(series_id = series_id)
  if (!is.null(start_date)) args$observation_start <- as.Date(start_date)
  got <- do.call(fredr, args)
  collected <- as.character(Sys.time())
  got %>%
    transmute(
      date = as.Date(date),
      observation_date = as.Date(date),
      close_value = as.numeric(value),
      adjusted_value = NA_real_,
      volume = NA_real_,
      series_id = series_id,
      source = "FRED",
      available_at = collected,
      collected_at = collected,
      source_updated_at = NA_character_,
      vintage = as.character(as.Date(date)),
      quality_status = "SOURCE_OBSERVATION",
      calculation_version = "RAW_FRED_V2"
    ) %>%
    filter(!is.na(date), !is.na(close_value))
}, otherwise = tibble::tibble())

safe_yahoo_series <- purrr::possibly(function(series_id, start_date = as.Date("1976-01-01")) {
  start_date <- as.Date(start_date)
  if (is.na(start_date) || start_date > Sys.Date()) return(tibble::tibble())

  raw_xts <- suppressWarnings(quantmod::getSymbols(
    series_id,
    src = "yahoo",
    from = start_date,
    auto.assign = FALSE
  ))
  if (is.null(raw_xts) || nrow(raw_xts) == 0) return(tibble::tibble())
  raw_df <- data.frame(date = index(raw_xts), coredata(raw_xts))

  close_col <- grep("\\.Close$", names(raw_df), value = TRUE)
  if (length(close_col) == 0) return(tibble::tibble())

  adj_col <- grep("\\.Adjusted$", names(raw_df), value = TRUE)
  vol_col <- grep("\\.Volume$", names(raw_df), value = TRUE)
  close_v <- as.numeric(raw_df[[close_col[1]]])
  adj_v <- if (length(adj_col) > 0) as.numeric(raw_df[[adj_col[1]]]) else rep(NA_real_, length(close_v))
  vol_v <- if (length(vol_col) > 0) as.numeric(raw_df[[vol_col[1]]]) else rep(NA_real_, length(close_v))
  if (all(is.na(adj_v))) adj_v <- close_v

  collected <- as.character(Sys.time())
  tibble::tibble(
    date = as.Date(raw_df$date),
    observation_date = as.Date(raw_df$date),
    close_value = close_v,
    adjusted_value = adj_v,
    volume = vol_v,
    series_id = series_id,
    source = "YAHOO",
    available_at = us_close_available_at(raw_df$date),
    collected_at = collected,
    source_updated_at = NA_character_,
    vintage = as.character(as.Date(raw_df$date)),
    quality_status = "SOURCE_MARKET_CLOSE",
    calculation_version = "RAW_YAHOO_V2"
  ) %>%
    filter(!is.na(date), !is.na(close_value))
}, otherwise = tibble::tibble())

find_old_dji <- function(project_dir) {
  candidates <- c(
    file.path(project_dir, "old_dja.csv"),
    file.path(dirname(project_dir), "old_dja.csv"),
    "C:/app/econ_ts/us_dat_extract/old_dja.csv",
    "C:/app/econ_ts/market_timeseries_bundle/timeseries/old_dja.csv",
    "C:/app/econ_ts/us_dat_extract/bl_us_econ_data/original_data/old_dja.csv"
  )
  for (f in candidates) {
    if (file.exists(f)) return(normalizePath(f, winslash = "/", mustWork = TRUE))
  }
  NA_character_
}

load_old_dji_history <- function(path) {
  if (is.na(path) || !file.exists(path)) return(empty_data_schema[0, , drop = FALSE])
  raw_old_dji <- suppressMessages(readr::read_csv(path, show_col_types = FALSE))
  required_cols <- c("Date", "DJIA")
  if (any(!required_cols %in% names(raw_old_dji))) {
    warning("old_dja.csv is missing required columns: ", paste(setdiff(required_cols, names(raw_old_dji)), collapse = ", "))
    return(empty_data_schema[0, , drop = FALSE])
  }

  raw_old_dji %>%
    transmute(
      date = as.Date(suppressWarnings(lubridate::mdy(as.character(Date)))),
      observation_date = date,
      close_value = readr::parse_number(as.character(DJIA)),
      adjusted_value = NA_real_,
      volume = NA_real_,
      series_id = "^DJI",
      source = "YAHOO",
      available_at = us_close_available_at(date),
      collected_at = as.character(Sys.time()),
      source_updated_at = NA_character_,
      vintage = as.character(date),
      quality_status = "HISTORICAL_SUPPLEMENT",
      calculation_version = "RAW_YAHOO_V2"
    ) %>%
    filter(!is.na(date), !is.na(close_value))
}

merge_old_dji_history <- function(yahoo_df, project_dir, active_ids) {
  if (!"^DJI" %in% active_ids) return(yahoo_df)
  old_dji <- load_old_dji_history(find_old_dji(project_dir))
  if (nrow(old_dji) == 0) return(yahoo_df)

  yahoo_dji <- yahoo_df %>% filter(series_id == "^DJI") %>% mutate(source = "YAHOO")
  dji_merged <- bind_rows(yahoo_dji, old_dji) %>%
    arrange(date) %>%
    distinct(series_id, date, .keep_all = TRUE)

  message(sprintf(
    "DJI merged with historical supplement: %s rows (%s ~ %s)",
    nrow(dji_merged),
    format(min(dji_merged$date), "%Y-%m-%d"),
    format(max(dji_merged$date), "%Y-%m-%d")
  ))

  yahoo_df %>%
    filter(series_id != "^DJI") %>%
    bind_rows(dji_merged) %>%
    arrange(series_id, date)
}

update_series <- function(config, data_path, download_fun, source_name, full_start_date = NULL, force_full_history = FALSE) {
  active_config <- config %>% filter(active %in% TRUE, collect_flag %in% TRUE)
  if (!"source_symbol" %in% names(active_config)) active_config$source_symbol <- active_config$series_id
  active_config$source_symbol[is.na(active_config$source_symbol) | active_config$source_symbol == ""] <- active_config$series_id[is.na(active_config$source_symbol) | active_config$source_symbol == ""]
  source_symbols <- stats::setNames(active_config$source_symbol, active_config$series_id)
  configured_series <- unique(active_config$series_id)
  configured_series <- configured_series[!is.na(configured_series) & configured_series != ""]

  existing_df <- load_existing_data(data_path)
  existing_last <- existing_df %>%
    filter(series_id %in% configured_series) %>%
    filter(!is.na(date)) %>%
    group_by(series_id) %>%
    summarize(last_date = max(date), .groups = "drop")

  new_series <- if (isTRUE(force_full_history)) configured_series else setdiff(configured_series, existing_last$series_id)
  old_series <- if (isTRUE(force_full_history)) character() else setdiff(configured_series, new_series)

  run_log <- tibble::tibble(
    series_id = character(),
    requested_start = as.Date(character()),
    requested_end = as.Date(character()),
    status = character(),
    row_count = integer(),
    error_message = character(),
    collected_at = as.character(Sys.time())
  )

  add_log <- function(series_id, requested_start, status, row_count = 0L, error_message = NA_character_) {
    run_log <<- bind_rows(
      run_log,
      tibble::tibble(
        series_id = series_id,
        requested_start = as.Date(requested_start),
        requested_end = Sys.Date(),
        status = status,
        row_count = as.integer(row_count),
        error_message = error_message,
        collected_at = as.character(Sys.time())
      )
    )
  }

  download_series <- function(series_id, requested_start, is_new_series) {
    if (is.na(requested_start) || requested_start > Sys.Date()) {
      add_log(series_id, requested_start, "skipped", 0L, "No update window")
      return(tibble::tibble())
    }

    result <- tryCatch(
      {
        source_symbol <- unname(source_symbols[[series_id]])
        rows <- download_fun(source_symbol, requested_start)
        if (nrow(rows) > 0L) rows$series_id <- series_id
        status <- ifelse(
          nrow(rows) == 0L,
          ifelse(is_new_series, "empty_new_series", "empty_update"),
          "success"
        )
        add_log(series_id, requested_start, status, nrow(rows), NA_character_)
        rows
      },
      error = function(e) {
        add_log(series_id, requested_start, "error", 0L, conditionMessage(e))
        message(sprintf("%s series %s failed: %s", source_name, series_id, conditionMessage(e)))
        tibble::tibble()
      }
    )
    result
  }

  downloaded_new <- bind_rows(lapply(new_series, function(sid) {
    st <- if (is.null(full_start_date)) as.Date("1776-01-01") else as.Date(full_start_date)
    download_series(sid, st, TRUE)
  }))

  downloaded_inc <- bind_rows(lapply(old_series, function(sid) {
    st <- existing_df %>% filter(series_id == sid) %>% pull(date) %>% max(na.rm = TRUE)
    if (length(st) == 0L || !is.finite(as.numeric(st))) st <- as.Date("1976-01-01")
    st <- as.Date(st) + 1L
    download_series(sid, st, FALSE)
  }))

  downloaded <- bind_rows(downloaded_new, downloaded_inc)
  before_n <- nrow(existing_df)
  # Downloaded rows take precedence so a full resync can refresh adjusted history.
  updated <- bind_rows(downloaded, existing_df) %>%
    distinct(source, series_id, date, .keep_all = TRUE) %>%
    arrange(series_id, date)

  if (source_name == "YAHOO") {
    updated <- merge_old_dji_history(updated, project_dir, configured_series)
  }

  write.fst(updated, data_path, compress = 50)

  status_summary <- run_log %>%
    group_by(status) %>%
    summarize(n_series = n(), rows = sum(row_count, na.rm = TRUE), .groups = "drop")
  message(sprintf("%s status summary:", source_name))
  print(status_summary)

  failed <- run_log %>% filter(!status %in% c("success", "empty_update"))
  if (nrow(failed) > 0) {
    warning(sprintf("%s update finished with %s failed/errored series", source_name, nrow(failed)))
  }

  append_run_log(update_log_path, run_log)
  message(sprintf("%s update complete: existing=%s, downloaded=%s, final=%s -> %s", source_name, before_n, nrow(downloaded), nrow(updated), data_path))

  updated
}

build_descriptor <- function(ts_df, config_df) {
  stats <- if (nrow(ts_df) == 0L) {
    tibble::tibble(series_id = config_df$series_id, observation_start = as.Date(NA), observation_end = as.Date(NA), n_obs = 0L)
  } else {
    ts_df %>%
      group_by(series_id) %>%
      summarize(
        observation_start = min(date, na.rm = TRUE),
        observation_end = max(date, na.rm = TRUE),
        n_obs = dplyr::n(),
        .groups = "drop"
      )
  }
  stats %>%
    right_join(config_df, by = "series_id") %>%
    arrange(display_order, series_id)
}

get_fred_api_key <- function() {
  key <- Sys.getenv("FRED_API_KEY")
  if (!nzchar(key)) key <- Sys.getenv("FRED_API_KEY_1")
  key
}

run_market_data_update <- function(
    update_fred = TRUE,
    update_yahoo = TRUE,
    fred_full_resync = FALSE,
    yahoo_full_resync = FALSE) {
  series_catalog <- read_series_catalog(catalog_path)
  series_interface_fred <- series_catalog %>% filter(source == "FRED")
  series_interface_yahoo <- series_catalog %>% filter(source == "YAHOO")

  if (isTRUE(update_fred) && nrow(series_interface_fred) > 0L) {
    fred_api_key <- get_fred_api_key()
    if (!nzchar(fred_api_key)) {
      warning("FRED_API_KEY is not set. FRED update is skipped.")
      original_ts_fred <- load_existing_data(fred_ts_path)
    } else {
      fredr_set_key(fred_api_key)
      original_ts_fred <- update_series(
        series_interface_fred, fred_ts_path, safe_fred_series, "FRED", NULL,
        force_full_history = fred_full_resync
      )
    }
    fred_desc <- build_descriptor(original_ts_fred, series_interface_fred)
    write.fst(fred_desc, fred_desc_path, compress = 50)
  }

  if (isTRUE(update_yahoo) && nrow(series_interface_yahoo) > 0L) {
    original_ts_yahoo <- update_series(
      series_interface_yahoo, yahoo_ts_path, safe_yahoo_series, "YAHOO",
      as.Date("1976-01-01"), force_full_history = yahoo_full_resync
    )
    yahoo_desc <- build_descriptor(original_ts_yahoo, series_interface_yahoo)
    write.fst(yahoo_desc, yahoo_desc_path, compress = 50)
  }

  message("All done.")
  invisible(list(
    fred = if (exists("original_ts_fred")) original_ts_fred else NULL,
    yahoo = if (exists("original_ts_yahoo")) original_ts_yahoo else NULL
  ))
}

if (!isTRUE(getOption("market_ts.skip_autorun", FALSE))) {
  run_market_data_update()
}
