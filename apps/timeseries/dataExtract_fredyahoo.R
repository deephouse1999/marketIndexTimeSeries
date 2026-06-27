# dataExtract_fredyahoo.R ----------------------------------------------------
# Edit series only in the two tables below:
#   1. series_interface_fred
#   2. series_interface_yahoo
#
# Behavior:
#   - Existing series: download only rows after the latest saved date.
#   - Newly added series: download full history.
#   - Removed series: drop from the saved fst on the next run.

suppressPackageStartupMessages({
  library(fst)
  library(dplyr)
  library(purrr)
  library(lubridate)
  library(fredr)
  library(quantmod)
  library(readr)
})

# I. Paths -------------------------------------------------------------------

get_project_dir <- function() {
  candidates <- unique(c(
    getwd(),
    file.path(getwd(), "us_dat_extract"),
    file.path(getwd(), "econ", "us_dat_extract"),
    "C:/app/econ_ts/us_dat_extract",
    "/cloud/project/econ/us_dat_extract"
  ))

  for (candidate in candidates) {
    if (file.exists(file.path(candidate, "dataExtract_fredyahoo.R"))) {
      return(normalizePath(candidate, winslash = "/", mustWork = TRUE))
    }
  }

  normalizePath(getwd(), winslash = "/", mustWork = TRUE)
}

project_dir <- get_project_dir()
data_dir <- project_dir
dir.create(data_dir, showWarnings = FALSE, recursive = TRUE)

fn_path <- function(file) file.path(data_dir, file)

fred_ts_path <- fn_path("original_ts_fred.fst")
fred_desc_path <- fn_path("tab_stat_description_fred.fst")
yahoo_ts_path <- fn_path("original_ts_yahoo.fst")
yahoo_desc_path <- fn_path("tab_stat_description_yahoo.fst")
old_dji_path <- file.path(project_dir, "old_dja.csv")

# II. Series Config ----------------------------------------------------------
# Add/change/delete rows here. Keep one row per series.

series_interface_fred <- tibble::tribble(
  ~series_id,          ~series_cls,
  "DGS1",              "rf",
  "DGS2",              "rf",
  "DGS5",              "rf",
  "DGS10",             "rf",
  "DGS30",             "rf",
  "T10Y2Y",            "rf",
  "FEDFUNDS",          "rf",
  "DFEDTAR",           "rf",
  "DFEDTARU",          "rf",
  "BAMLC0A1CAAAEY",    "credit",
  "BAMLC0A3CAEY",      "credit",
  "BAMLC0A2CAAEY",     "credit",
  "BAMLC0A4CBBBEY",    "credit",
  "BAMLH0A0HYM2EY",    "credit",
  "DJIA",              "stock_index",
  "NASDAQCOM",         "stock_index",
  "SP500",             "stock_index",
  "VIXCLS",            "stock_index",
  "DEXKOUS",           "forex",
  "DEXJPUS",           "forex",
  "DEXCHUS",           "forex",
  "DEXUSEU",           "forex",
  "DEXUSUK",           "forex",
  "GDP",               "gdp",
  "GDPC1",             "gdp",
  "B935RC1Q027SBEA",   "invest",
  "CPIAUCSL",          "inflation",
  "CPILFESL",          "inflation",
  "PCEPI",             "inflation",
  "PCEPILFE",          "inflation",
  "PPIACO",            "inflation",
  "WPSFD4131",         "inflation",
  "UNRATE",            "employment",
  "ICSA",              "employment",
  "PAYEMS",            "employment",
  "WTISPLC",           "commodity",
  "FYFSD",             "gvt_debt",
  "MVGFD027MNFRBDAL",  "gvt_debt"
)

series_interface_yahoo <- tibble::tribble(
  ~series_id,     ~series_cls,
  "2YY=F",        "rf",
  "^TNX",         "rf",
  "^TYX",         "rf",
  "AGGG.L",       "rf",
  "^DJI",         "stock_index",
  "^GSPC",        "stock_index",
  "^IXIC",        "stock_index",
  "^VIX",         "stock_index",
  "^TOPX",        "stock_index",
  "^FTSE",        "stock_index",
  "^GDAXI",       "stock_index",
  "^HSI",         "stock_index",
  "^KS11",        "stock_index",
  "EWY",          "stock_index",
  "ACWI",         "stock_index",
  "URTH",         "stock_index",
  "EEM",          "stock_index",
  "USDKRW=X",     "forex",
  "USDJPY=X",     "forex",
  "USDCNY=X",     "forex",
  "USDEUR=X",     "forex",
  "USDGBP=X",     "forex",
  "DX-Y.NYB",     "forex",
  "AAPL",         "stock_price",
  "GOOG",         "stock_price",
  "TSLA",         "stock_price",
  "META",         "stock_price",
  "NVDA",         "stock_price",
  "LLY",          "stock_price",
  "ZC=F",         "commodity",
  "HE=F",         "commodity",
  "CL=F",         "commodity",
  "NG=F",         "commodity",
  "GC=F",         "commodity",
  "BTC-USD",      "commodity"
)

validate_series_config <- function(config, source_name) {
  required_cols <- c("series_id", "series_cls")
  missing_cols <- setdiff(required_cols, names(config))
  if (length(missing_cols) > 0) {
    stop(source_name, " config is missing columns: ", paste(missing_cols, collapse = ", "))
  }

  dup_ids <- config$series_id[duplicated(config$series_id)]
  if (length(dup_ids) > 0) {
    stop(source_name, " config has duplicate series_id values: ", paste(unique(dup_ids), collapse = ", "))
  }

  config %>%
    mutate(
      series_id = as.character(series_id),
      series_cls = as.character(series_cls)
    )
}

series_interface_fred <- validate_series_config(series_interface_fred, "FRED")
series_interface_yahoo <- validate_series_config(series_interface_yahoo, "Yahoo")

# III. Download Helpers ------------------------------------------------------

fred_api_key <- Sys.getenv("FRED_API_KEY")
if (!nzchar(fred_api_key)) {
  stop("FRED_API_KEY is not set. Add it to .Renviron before running this script.")
}
fredr_set_key(fred_api_key)

safe_fred_series <- purrr::possibly(function(series_id, start_date = NULL) {
  args <- list(series_id = series_id)
  if (!is.null(start_date)) {
    args$observation_start <- as.Date(start_date)
  }

  do.call(fredr, args) %>%
    transmute(
      date = as.Date(date),
      value = as.numeric(value),
      series_id = series_id
    ) %>%
    filter(!is.na(date))
}, otherwise = tibble::tibble())

safe_fred_description <- purrr::possibly(function(series_id) {
  fredr_series_search_id(series_id) %>%
    filter(id == series_id) %>%
    select(id, title, contains("obser"), contains("short"), last_updated)
}, otherwise = tibble::tibble())

safe_yahoo_series <- purrr::possibly(function(series_id, start_date = as.Date("1976-01-01")) {
  start_date <- as.Date(start_date)
  if (is.na(start_date) || start_date > Sys.Date()) return(tibble::tibble())

  raw_xts <- suppressWarnings(getSymbols(series_id, src = "yahoo", from = start_date, auto.assign = FALSE))
  raw_df <- data.frame(date = index(raw_xts), coredata(raw_xts))

  close_col <- grep("\\.Close$", names(raw_df), value = TRUE)
  if (length(close_col) == 0) {
    close_col <- grep("Close", names(raw_df), value = TRUE)
  }
  if (length(close_col) == 0) return(tibble::tibble())

  raw_df %>%
    transmute(
      date = as.Date(date),
      value = as.numeric(.data[[close_col[1]]]),
      series_id = series_id
    ) %>%
    filter(!is.na(date), !is.na(value))
}, otherwise = tibble::tibble())

load_old_dji_history <- function(path) {
  if (!file.exists(path)) {
    warning("old_dja.csv was not found: ", path)
    return(tibble::tibble(date = as.Date(character()), value = numeric(), series_id = character()))
  }

  raw_old_dji <- read_csv(path, show_col_types = FALSE)
  required_cols <- c("Date", "DJIA")
  missing_cols <- setdiff(required_cols, names(raw_old_dji))
  if (length(missing_cols) > 0) {
    stop("old_dja.csv is missing columns: ", paste(missing_cols, collapse = ", "))
  }

  raw_old_dji %>%
    transmute(
      date = lubridate::mdy(Date),
      value = readr::parse_number(as.character(DJIA)),
      series_id = "^DJI",
      source_priority = 2L
    ) %>%
    filter(!is.na(date), !is.na(value)) %>%
    distinct(series_id, date, .keep_all = TRUE) %>%
    arrange(date)
}

merge_old_dji_history <- function(yahoo_df, old_dji_path) {
  if (!"^DJI" %in% series_interface_yahoo$series_id) {
    return(yahoo_df)
  }

  old_dji <- load_old_dji_history(old_dji_path)
  if (nrow(old_dji) == 0) {
    warning("No usable old DJI rows found. Yahoo ^DJI was left unchanged.")
    return(yahoo_df)
  }

  yahoo_dji <- yahoo_df %>%
    filter(series_id == "^DJI") %>%
    mutate(source_priority = 1L)

  dji_combined <- bind_rows(yahoo_dji, old_dji) %>%
    arrange(series_id, date, source_priority) %>%
    distinct(series_id, date, .keep_all = TRUE) %>%
    select(date, value, series_id) %>%
    arrange(date)

  message(sprintf(
    "DJI history ready: %s rows from %s to %s. Yahoo values are kept on overlapping dates.",
    nrow(dji_combined),
    format(min(dji_combined$date), "%Y-%m-%d"),
    format(max(dji_combined$date), "%Y-%m-%d")
  ))

  yahoo_df %>%
    filter(series_id != "^DJI") %>%
    bind_rows(dji_combined) %>%
    arrange(series_id, date)
}

# IV. Generic Update Logic ---------------------------------------------------

update_time_series <- function(config, data_path, download_fun, source_name, full_start_date = NULL) {
  configured_series <- unique(config$series_id)

  if (file.exists(data_path)) {
    existing_df <- read.fst(data_path) %>%
      mutate(date = as.Date(date)) %>%
      filter(series_id %in% configured_series)
  } else {
    existing_df <- tibble::tibble(
      date = as.Date(character()),
      value = numeric(),
      series_id = character()
    )
  }

  existing_last_dates <- existing_df %>%
    group_by(series_id) %>%
    summarize(last_date = max(date), .groups = "drop")

  new_series <- setdiff(configured_series, existing_last_dates$series_id)
  existing_series <- intersect(configured_series, existing_last_dates$series_id)

  full_history <- map_dfr(
    new_series,
    ~ download_fun(.x, full_start_date)
  )

  incremental <- existing_last_dates %>%
    filter(series_id %in% existing_series) %>%
    mutate(start_date = last_date + 1L) %>%
    filter(start_date <= Sys.Date()) %>%
    pmap_dfr(function(series_id, last_date, start_date) {
      download_fun(series_id, start_date) %>%
        filter(date > last_date)
    })

  downloaded <- bind_rows(full_history, incremental)

  updated_df <- bind_rows(existing_df, downloaded) %>%
    distinct(series_id, date, .keep_all = TRUE) %>%
    arrange(series_id, date)

  write.fst(updated_df, data_path, compress = 50)

  message(sprintf(
    "%s update complete: %s configured, %s new series, %s downloaded rows -> %s",
    source_name,
    length(configured_series),
    length(new_series),
    nrow(downloaded),
    data_path
  ))

  updated_df
}

# V. FRED --------------------------------------------------------------------

original_ts_fred <- update_time_series(
  config = series_interface_fred,
  data_path = fred_ts_path,
  download_fun = safe_fred_series,
  source_name = "FRED",
  full_start_date = NULL
)

tab_stat_description_fred <- map_dfr(
  series_interface_fred$series_id,
  safe_fred_description
) %>%
  left_join(series_interface_fred, by = c("id" = "series_id"))

write.fst(tab_stat_description_fred, fred_desc_path, compress = 50)

# VI. Yahoo ------------------------------------------------------------------

original_ts_yahoo <- update_time_series(
  config = series_interface_yahoo,
  data_path = yahoo_ts_path,
  download_fun = safe_yahoo_series,
  source_name = "Yahoo",
  full_start_date = as.Date("1976-01-01")
)

original_ts_yahoo <- merge_old_dji_history(original_ts_yahoo, old_dji_path)
write.fst(original_ts_yahoo, yahoo_ts_path, compress = 50)

tab_stat_description_yahoo <- original_ts_yahoo %>%
  group_by(series_id) %>%
  summarize(
    observation_start = min(date),
    observation_end = max(date),
    n_obs = n(),
    .groups = "drop"
  ) %>%
  left_join(series_interface_yahoo, by = "series_id") %>%
  arrange(match(series_id, series_interface_yahoo$series_id))

write.fst(tab_stat_description_yahoo, yahoo_desc_path, compress = 50)

message("All done.")

