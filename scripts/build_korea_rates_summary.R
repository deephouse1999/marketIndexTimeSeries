suppressPackageStartupMessages({
  library(dplyr)
  library(fst)
  library(lubridate)
  library(purrr)
  library(readr)
  library(tibble)
})

repo_dir <- normalizePath(".", winslash = "/", mustWork = TRUE)
app_dir <- file.path(repo_dir, "apps", "timeseries")
gate_dir <- file.path(repo_dir, "docs", "gate3")
dir.create(gate_dir, recursive = TRUE, showWarnings = FALSE)

ecos_path <- file.path(app_dir, "original_ts_ecos.fst")
fred_path <- file.path(app_dir, "original_ts_fred.fst")
catalog_path <- file.path(app_dir, "series_catalog.csv")
target_path <- file.path(app_dir, "derived_korea_rates_summary.fst")
last_good_path <- paste0(target_path, ".last_good")
staging_path <- paste0(target_path, ".staging")
latest_target_path <- file.path(app_dir, "derived_korea_rates_latest.fst")
latest_last_good_path <- paste0(latest_target_path, ".last_good")
latest_staging_path <- paste0(latest_target_path, ".staging")

calculation_version <- "gate3_v1"
build_time <- format(Sys.time(), tz = "Asia/Seoul", usetz = TRUE)
`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L || all(is.na(x))) y else x

ecos <- read.fst(ecos_path, as.data.table = FALSE) %>%
  as_tibble() %>%
  transmute(
    date = as.Date(date), value = as.numeric(value), series_id = as.character(series_id),
    source = "ECOS", collected_at = as.character(collected_at)
  ) %>%
  filter(!is.na(date), is.finite(value)) %>%
  distinct(series_id, date, .keep_all = TRUE)

fred <- read.fst(fred_path, as.data.table = FALSE) %>%
  as_tibble() %>%
  transmute(
    date = as.Date(date), value = as.numeric(close_value), series_id = as.character(series_id),
    source = "FRED", collected_at = as.character(collected_at)
  ) %>%
  filter(series_id %in% c("DGS2", "DGS10"), !is.na(date), is.finite(value)) %>%
  distinct(series_id, date, .keep_all = TRUE)

catalog <- read_csv(catalog_path, col_types = cols(.default = col_character()), na = character())

derived_schema <- function() {
  tibble(
    metric_id = character(), metric_group = character(), observation_date = as.Date(character()),
    reference_date = as.Date(character()), value = numeric(), unit = character(), source = character(),
    as_of = as.Date(character()), collected_at = character(), quality_status = character(),
    calculation_version = character(), alignment_rule = character(), series_id = character(),
    component_a = character(), component_b = character(), window = integer(),
    observation_count = integer(), us_observation_date = as.Date(character()),
    kr_effective_date = as.Date(character()), auxiliary_value = numeric(),
    auxiliary_unit = character(), tenor_years = numeric(), data_freshness_days = integer(),
    missing_tenors = character(), component_a_value = numeric(), component_b_value = numeric(),
    reference_value = numeric()
  )
}

standardize_rows <- function(data) {
  template <- derived_schema()
  for (nm in setdiff(names(template), names(data))) data[[nm]] <- template[[nm]]
  data %>% select(all_of(names(template)))
}

previous_weekday <- function(date, n) {
  candidate <- as.Date(date)
  remaining <- as.integer(n)
  while (remaining > 0L) {
    candidate <- candidate - 1L
    if (!as.integer(format(candidate, "%u")) %in% c(6L, 7L)) remaining <- remaining - 1L
  }
  candidate
}

latest_at_or_before <- function(dates, target) {
  eligible <- dates[dates <= as.Date(target)]
  if (length(eligible)) max(eligible) else as.Date(NA)
}

curve_ids <- c("KTB_01Y", "KTB_02Y", "KTB_03Y", "KTB_05Y", "KTB_10Y", "KTB_20Y", "KTB_30Y", "KTB_50Y")
tenor_years <- c(KTB_01Y = 1, KTB_02Y = 2, KTB_03Y = 3, KTB_05Y = 5, KTB_10Y = 10, KTB_20Y = 20, KTB_30Y = 30, KTB_50Y = 50)
curve_data <- ecos %>% filter(series_id %in% curve_ids)
common_dates <- reduce(lapply(curve_ids, function(id) curve_data$date[curve_data$series_id == id]), intersect) %>% sort()
if (!length(common_dates)) stop("KOREA_YIELD_CURVE_FAILED: no common observation date across all tenors")

curve_current <- max(common_dates)
prior_common <- common_dates[common_dates < curve_current]
curve_dates <- c(
  current = curve_current,
  `1D` = if (length(prior_common)) max(prior_common) else as.Date(NA),
  `1W` = latest_at_or_before(common_dates, curve_current - 7L),
  `1M` = latest_at_or_before(common_dates, curve_current %m-% months(1))
)

curve_rows <- imap_dfr(curve_dates, function(curve_date, label) {
  if (is.na(curve_date)) return(derived_schema())
  selected <- curve_data %>% filter(date == curve_date)
  missing <- setdiff(curve_ids, selected$series_id)
  selected %>%
    transmute(
      metric_id = paste0("CURVE_", toupper(label), "_", series_id),
      metric_group = "yield_curve", observation_date = date, reference_date = date,
      value, unit = "Percent", source = "ECOS", as_of = curve_current,
      collected_at = build_time,
      quality_status = if (length(missing)) "INCOMPLETE_CURVE" else if (curve_current < Sys.Date()) "PENDING_SOURCE" else "OK",
      calculation_version, alignment_rule = "COMMON_OBSERVATION_DATE_NO_LOCF",
      series_id, component_a = series_id, component_b = "", window = NA_integer_,
      observation_count = nrow(selected), us_observation_date = as.Date(NA),
      kr_effective_date = date, auxiliary_value = NA_real_, auxiliary_unit = "",
      tenor_years = unname(tenor_years[series_id]),
      data_freshness_days = as.integer(Sys.Date() - curve_current),
      missing_tenors = paste(missing, collapse = ";"), component_a_value = value,
      component_b_value = NA_real_, reference_value = NA_real_
    ) %>% standardize_rows()
})

rate_ids <- catalog %>%
  filter(source == "ECOS", series_cls == "rate", as.logical(collect_flag), as.logical(active)) %>%
  pull(series_id)

rate_change_rows <- map_dfr(rate_ids, function(id) {
  d <- ecos %>% filter(series_id == id) %>% arrange(date)
  if (!nrow(d)) return(derived_schema())
  current_date <- max(d$date)
  current_value <- d$value[match(current_date, d$date)]
  dates <- d$date
  reference_dates <- c(
    `1D` = if (sum(dates < current_date)) max(dates[dates < current_date]) else as.Date(NA),
    `5D` = latest_at_or_before(dates, previous_weekday(current_date, 5L)),
    `1M` = latest_at_or_before(dates, current_date %m-% months(1)),
    `3M` = latest_at_or_before(dates, current_date %m-% months(3)),
    YTD = if (any(year(dates) == year(current_date))) min(dates[year(dates) == year(current_date)]) else as.Date(NA)
  )
  imap_dfr(reference_dates, function(reference_date, window_name) {
    reference_value <- if (is.na(reference_date)) NA_real_ else d$value[match(reference_date, d$date)]
    quality <- if (is.na(reference_date) || !is.finite(reference_value)) "INSUFFICIENT_HISTORY" else "OK"
    tibble(
      metric_id = paste0("CHANGE_", toupper(window_name), "_", id), metric_group = "rate_change",
      observation_date = current_date, reference_date = reference_date,
      value = if (quality == "OK") (current_value - reference_value) * 100 else NA_real_,
      unit = "bp", source = "ECOS", as_of = current_date, collected_at = build_time,
      quality_status = quality, calculation_version, alignment_rule = paste0(window_name, "_ACTUAL_OBSERVATION_NO_LOCF"),
      series_id = id, component_a = id, component_b = "", window = NA_integer_,
      observation_count = if (quality == "OK") 2L else 1L, us_observation_date = as.Date(NA),
      kr_effective_date = current_date, auxiliary_value = NA_real_, auxiliary_unit = "",
      tenor_years = unname(tenor_years[id] %||% NA_real_), data_freshness_days = as.integer(Sys.Date() - current_date),
      missing_tenors = "", component_a_value = current_value, component_b_value = NA_real_,
      reference_value = reference_value
    ) %>% standardize_rows()
  })
})

spread_definitions <- tribble(
  ~metric_id, ~metric_group, ~component_a, ~component_b,
  "KTB10Y_MINUS_KTB3Y", "funding_spread", "KTB_10Y", "KTB_03Y",
  "KTB5Y_MINUS_KTB3Y", "funding_spread", "KTB_05Y", "KTB_03Y",
  "CD91D_MINUS_BOK_BASE", "funding_spread", "CD_091D", "BOK_BASE_RATE",
  "CORP_AAM3Y_MINUS_KTB3Y", "credit_spread", "CORP_AAM_03Y", "KTB_03Y",
  "CORP_BBBM3Y_MINUS_KTB3Y", "credit_spread", "CORP_BBBM_03Y", "KTB_03Y",
  "CORP_BBBM3Y_MINUS_AAM3Y", "credit_spread", "CORP_BBBM_03Y", "CORP_AAM_03Y"
)

build_spread <- function(metric_id, metric_group, component_a, component_b) {
  a <- ecos %>% filter(series_id == component_a) %>% select(date, a_value = value, a_collected = collected_at)
  b <- ecos %>% filter(series_id == component_b) %>% select(date, b_value = value, b_collected = collected_at)
  inner_join(a, b, by = "date") %>%
    transmute(
      metric_id, metric_group, observation_date = date, reference_date = date,
      value = (a_value - b_value) * 100, unit = "bp", source = "ECOS", as_of = max(date),
      collected_at = build_time, quality_status = "OK", calculation_version,
      alignment_rule = "EXACT_SAME_OBSERVATION_DATE", series_id = metric_id,
      component_a, component_b, window = NA_integer_, observation_count = 2L,
      us_observation_date = as.Date(NA), kr_effective_date = date,
      auxiliary_value = NA_real_, auxiliary_unit = "", tenor_years = NA_real_,
      data_freshness_days = as.integer(Sys.Date() - max(date)), missing_tenors = "",
      component_a_value = a_value, component_b_value = b_value, reference_value = NA_real_
    ) %>% standardize_rows()
}

spread_rows <- pmap_dfr(spread_definitions, build_spread)

build_exact_level_pair <- function(kr_id, us_id, prefix) {
  kr <- ecos %>% filter(series_id == kr_id) %>% select(date, kr_value = value)
  us <- fred %>% filter(series_id == us_id) %>% select(date, us_value = value)
  joined <- inner_join(kr, us, by = "date")
  bind_rows(
    joined %>% transmute(metric_id = paste0(prefix, "_KR_LEVEL"), metric_group = "kr_us_spread", observation_date = date, reference_date = date, value = kr_value, unit = "Percent", source = "ECOS", as_of = max(date), collected_at = build_time, quality_status = "OK", calculation_version, alignment_rule = "EXACT_SAME_CALENDAR_OBSERVATION", series_id = kr_id, component_a = kr_id, component_b = us_id, window = NA_integer_, observation_count = 2L, us_observation_date = date, kr_effective_date = date, auxiliary_value = us_value, auxiliary_unit = "Percent", tenor_years = NA_real_, data_freshness_days = as.integer(Sys.Date() - max(date)), missing_tenors = "", component_a_value = kr_value, component_b_value = us_value, reference_value = NA_real_),
    joined %>% transmute(metric_id = paste0(prefix, "_US_LEVEL"), metric_group = "kr_us_spread", observation_date = date, reference_date = date, value = us_value, unit = "Percent", source = "FRED", as_of = max(date), collected_at = build_time, quality_status = "OK", calculation_version, alignment_rule = "EXACT_SAME_CALENDAR_OBSERVATION", series_id = us_id, component_a = us_id, component_b = kr_id, window = NA_integer_, observation_count = 2L, us_observation_date = date, kr_effective_date = date, auxiliary_value = kr_value, auxiliary_unit = "Percent", tenor_years = NA_real_, data_freshness_days = as.integer(Sys.Date() - max(date)), missing_tenors = "", component_a_value = us_value, component_b_value = kr_value, reference_value = NA_real_)
  ) %>% standardize_rows()
}

kr_us_level_rows <- bind_rows(
  build_exact_level_pair("KTB_03Y", "DGS2", "KR3Y_US2Y"),
  build_exact_level_pair("KTB_10Y", "DGS10", "KR10Y_US10Y")
)

kr10 <- ecos %>% filter(series_id == "KTB_10Y") %>% select(date, kr_value = value)
us10 <- fred %>% filter(series_id == "DGS10") %>% select(date, us_value = value)
kr_us_10_spread <- inner_join(kr10, us10, by = "date") %>%
  transmute(
    metric_id = "KR_US_10Y_SPREAD_BP", metric_group = "kr_us_spread",
    observation_date = date, reference_date = date, value = (kr_value - us_value) * 100,
    unit = "bp", source = "ECOS+FRED", as_of = max(date), collected_at = build_time,
    quality_status = "OK", calculation_version, alignment_rule = "EXACT_SAME_CALENDAR_OBSERVATION",
    series_id = "KR_US_10Y_SPREAD_BP", component_a = "KTB_10Y", component_b = "DGS10",
    window = NA_integer_, observation_count = 2L, us_observation_date = date,
    kr_effective_date = date, auxiliary_value = NA_real_, auxiliary_unit = "",
    tenor_years = 10, data_freshness_days = as.integer(Sys.Date() - max(date)), missing_tenors = "",
    component_a_value = kr_value, component_b_value = us_value, reference_value = NA_real_
  ) %>% standardize_rows()

fx <- ecos %>% filter(series_id == "ECOS_USDKRW") %>% select(date, fx_value = value)
fx_joined <- inner_join(fx, kr_us_10_spread %>% select(date = observation_date, spread_value = value), by = "date")
fx_link_rows <- bind_rows(
  fx_joined %>% transmute(metric_id = "FX_ECOS_USDKRW", metric_group = "fx_rate_link", observation_date = date, reference_date = date, value = fx_value, unit = "KRW per USD", source = "ECOS", as_of = max(date), collected_at = build_time, quality_status = "OK", calculation_version, alignment_rule = "EXACT_SAME_OBSERVATION_DATE_NO_SOURCE_MERGE", series_id = "ECOS_USDKRW", component_a = "ECOS_USDKRW", component_b = "KR_US_10Y_SPREAD_BP", window = NA_integer_, observation_count = 2L, us_observation_date = date, kr_effective_date = date, auxiliary_value = spread_value, auxiliary_unit = "bp", tenor_years = NA_real_, data_freshness_days = as.integer(Sys.Date() - max(date)), missing_tenors = "", component_a_value = fx_value, component_b_value = spread_value, reference_value = NA_real_),
  fx_joined %>% transmute(metric_id = "FX_LINK_KR_US_10Y_SPREAD_BP", metric_group = "fx_rate_link", observation_date = date, reference_date = date, value = spread_value, unit = "bp", source = "ECOS+FRED", as_of = max(date), collected_at = build_time, quality_status = "OK", calculation_version, alignment_rule = "EXACT_SAME_OBSERVATION_DATE_NO_SOURCE_MERGE", series_id = "KR_US_10Y_SPREAD_BP", component_a = "KTB_10Y", component_b = "DGS10", window = NA_integer_, observation_count = 2L, us_observation_date = date, kr_effective_date = date, auxiliary_value = fx_value, auxiliary_unit = "KRW per USD", tenor_years = 10, data_freshness_days = as.integer(Sys.Date() - max(date)), missing_tenors = "", component_a_value = spread_value, component_b_value = fx_value, reference_value = NA_real_)
) %>% standardize_rows()

daily_change <- function(data, id) {
  data %>% filter(series_id == id) %>% arrange(date) %>% mutate(change_bp = (value - lag(value)) * 100) %>% filter(is.finite(change_bp)) %>% select(date, change_bp)
}

align_us_to_next_kr <- function(us_id, kr_id, metric_id) {
  us <- daily_change(fred, us_id)
  kr <- daily_change(ecos, kr_id)
  index <- findInterval(us$date, kr$date) + 1L
  keep <- index <= nrow(kr)
  tibble(
    metric_id, metric_group = "kr_us_spread", observation_date = kr$date[index[keep]],
    reference_date = us$date[keep], value = kr$change_bp[index[keep]], unit = "bp",
    source = "FRED+ECOS", as_of = max(kr$date[index[keep]]), collected_at = build_time,
    quality_status = "OK", calculation_version,
    alignment_rule = "US_CLOSE_T_TO_FIRST_LATER_KR_BUSINESS_OBSERVATION",
    series_id = metric_id, component_a = us_id, component_b = kr_id,
    window = NA_integer_, observation_count = 1L, us_observation_date = us$date[keep],
    kr_effective_date = kr$date[index[keep]], auxiliary_value = us$change_bp[keep],
    auxiliary_unit = "bp", tenor_years = NA_real_,
    data_freshness_days = as.integer(Sys.Date() - max(kr$date[index[keep]])), missing_tenors = "",
    component_a_value = us$change_bp[keep], component_b_value = kr$change_bp[index[keep]],
    reference_value = NA_real_
  ) %>%
    filter(kr_effective_date > us_observation_date) %>%
    distinct(metric_id, observation_date, reference_date, .keep_all = TRUE) %>%
    standardize_rows()
}

transmission_rows <- bind_rows(
  align_us_to_next_kr("DGS2", "KTB_03Y", "US2Y_TO_NEXT_KR3Y_CHANGE"),
  align_us_to_next_kr("DGS10", "KTB_10Y", "US10Y_TO_NEXT_KR10Y_CHANGE")
)

rolling_rows <- transmission_rows %>%
  group_split(metric_id) %>%
  map_dfr(function(d) {
    d <- d %>% arrange(kr_effective_date, us_observation_date)
    map_dfr(c(20L, 60L, 120L), function(w) {
      idx <- seq_len(nrow(d))
      corr <- vapply(idx, function(i) {
        if (i < w) return(NA_real_)
        rows <- (i - w + 1L):i
        if (sum(complete.cases(d$auxiliary_value[rows], d$value[rows])) < w) return(NA_real_)
        if (sd(d$auxiliary_value[rows]) == 0 || sd(d$value[rows]) == 0) return(NA_real_)
        cor(d$auxiliary_value[rows], d$value[rows])
      }, numeric(1))
      keep <- which(is.finite(corr))
      if (!length(keep)) return(derived_schema())
      d[keep, ] %>%
        transmute(
          metric_id = paste0("ROLLCORR_", .data$metric_id, "_W", w),
          metric_group = "rolling_correlation", observation_date, reference_date,
          value = corr[keep], unit = "correlation", source, as_of, collected_at = build_time,
          quality_status = "OK", calculation_version,
          alignment_rule = "ROLLING_CORRELATION_OF_US_CHANGE_AND_NEXT_KR_CHANGE",
          series_id = .data$metric_id, component_a, component_b, window = w,
          observation_count = w, us_observation_date, kr_effective_date,
          auxiliary_value, auxiliary_unit, tenor_years, data_freshness_days,
          missing_tenors = "", component_a_value, component_b_value, reference_value
        ) %>% standardize_rows()
    })
  })

freshness_rows <- ecos %>%
  group_by(series_id) %>%
  summarize(observation_date = max(date), .groups = "drop") %>%
  transmute(
    metric_id = paste0("FRESHNESS_", series_id), metric_group = "data_quality",
    observation_date, reference_date = observation_date,
    value = as.numeric(Sys.Date() - observation_date), unit = "calendar_days", source = "ECOS",
    as_of = observation_date, collected_at = build_time,
    quality_status = case_when(value <= 1 ~ "OK", value <= 5 ~ "PENDING_SOURCE", TRUE ~ "DELAYED"),
    calculation_version, alignment_rule = "LATEST_OFFICIAL_OBSERVATION",
    series_id, component_a = series_id, component_b = "", window = NA_integer_,
    observation_count = 1L, us_observation_date = as.Date(NA), kr_effective_date = observation_date,
    auxiliary_value = NA_real_, auxiliary_unit = "", tenor_years = unname(tenor_years[series_id]),
    data_freshness_days = as.integer(value), missing_tenors = "", component_a_value = NA_real_,
    component_b_value = NA_real_, reference_value = NA_real_
  ) %>% standardize_rows()

derived <- bind_rows(
  curve_rows, rate_change_rows, spread_rows, kr_us_level_rows, kr_us_10_spread,
  fx_link_rows, transmission_rows, rolling_rows, freshness_rows
) %>%
  arrange(metric_group, metric_id, observation_date, reference_date)

required <- names(derived_schema())
if (!identical(names(derived), required)) stop("DERIVED_SCHEMA_VALIDATION_FAILED")
duplicate_keys <- derived %>% count(metric_id, observation_date, reference_date) %>% filter(n > 1L)
if (nrow(duplicate_keys)) stop("DERIVED_DUPLICATE_KEY_FAILED")
if (any(derived$metric_group == "rate_change" & derived$unit != "bp")) stop("RATE_CHANGE_BP_UNIT_FAILED")
if (any(grepl("SPECIAL_AAA", derived$metric_id, fixed = TRUE))) stop("SPECIAL_AAA_DISABLED_FAILED")
if (any(derived$metric_group == "funding_spread" & derived$observation_date != derived$reference_date)) stop("SPREAD_DATE_ALIGNMENT_FAILED")
if (any(derived$metric_group == "credit_spread" & derived$observation_date != derived$reference_date)) stop("SPREAD_DATE_ALIGNMENT_FAILED")
if (any(!is.na(derived$us_observation_date) & !is.na(derived$kr_effective_date) & grepl("TO_NEXT", derived$metric_id) & derived$kr_effective_date <= derived$us_observation_date)) stop("KR_US_ALIGNMENT_FAILED")

on.exit(if (file.exists(staging_path)) unlink(staging_path), add = TRUE)
write.fst(derived, staging_path, compress = 50)
readback <- read.fst(staging_path, as.data.table = FALSE) %>% as_tibble()
if (nrow(readback) != nrow(derived) || !identical(names(readback), names(derived))) stop("DERIVED_INDEPENDENT_READBACK_FAILED")

if (file.exists(last_good_path)) unlink(last_good_path)
if (file.exists(target_path) && !file.rename(target_path, last_good_path)) stop("DERIVED_LAST_GOOD_BACKUP_FAILED")
if (!file.rename(staging_path, target_path)) {
  if (file.exists(last_good_path)) file.rename(last_good_path, target_path)
  stop("DERIVED_ATOMIC_PUBLICATION_FAILED")
}

latest_spreads <- derived %>%
  filter(metric_group %in% c("funding_spread", "credit_spread")) %>%
  group_by(metric_id) %>%
  slice_max(observation_date, n = 1L, with_ties = FALSE) %>%
  ungroup()
latest_index <- bind_rows(
  derived %>% filter(metric_group %in% c("yield_curve", "rate_change", "data_quality")),
  latest_spreads
) %>%
  arrange(metric_group, metric_id, observation_date, reference_date)
latest_duplicates <- latest_index %>% count(metric_id, observation_date, reference_date) %>% filter(n > 1L)
if (nrow(latest_duplicates)) stop("LATEST_INDEX_DUPLICATE_KEY_FAILED")

on.exit(if (file.exists(latest_staging_path)) unlink(latest_staging_path), add = TRUE)
write.fst(latest_index, latest_staging_path, compress = 50)
latest_readback <- read.fst(latest_staging_path, as.data.table = FALSE) %>% as_tibble()
if (nrow(latest_readback) != nrow(latest_index) || !identical(names(latest_readback), names(latest_index))) {
  stop("LATEST_INDEX_INDEPENDENT_READBACK_FAILED")
}
if (file.exists(latest_last_good_path)) unlink(latest_last_good_path)
if (file.exists(latest_target_path) && !file.rename(latest_target_path, latest_last_good_path)) {
  stop("LATEST_INDEX_LAST_GOOD_BACKUP_FAILED")
}
if (!file.rename(latest_staging_path, latest_target_path)) {
  if (file.exists(latest_last_good_path)) file.rename(latest_last_good_path, latest_target_path)
  stop("LATEST_INDEX_ATOMIC_PUBLICATION_FAILED")
}

write_csv(
  tibble(
    built_at = build_time, calculation_version, rows = nrow(derived),
    metrics = n_distinct(derived$metric_id), start_date = min(derived$observation_date, na.rm = TRUE),
    end_date = max(derived$observation_date, na.rm = TRUE), duplicate_keys = 0L,
    curve_as_of = curve_current, latest_index_rows = nrow(latest_index), status = "PASS"
  ),
  file.path(gate_dir, "derived_build_summary.csv")
)

cat("Korea rates derived build: PASS (", nrow(derived), " rows, ", n_distinct(derived$metric_id),
    " metrics; latest index ", nrow(latest_index), " rows)\n", sep = "")

