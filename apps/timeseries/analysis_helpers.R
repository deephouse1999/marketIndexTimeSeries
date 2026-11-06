# Analysis helpers shared by the Yahoo Shiny app.

catalog_tag <- function(notes, key) {
  pattern <- paste0("(?:^|;)", key, "=([^;]+)")
  hit <- regexec(pattern, ifelse(is.na(notes), "", notes), perl = TRUE)
  parts <- regmatches(ifelse(is.na(notes), "", notes), hit)
  vapply(parts, function(x) if (length(x) >= 2L) x[[2]] else NA_character_, character(1))
}

period_return_pct <- function(value, date, trading_days = NULL, ytd = FALSE) {
  ok <- is.finite(value) & !is.na(date)
  value <- as.numeric(value[ok])
  date <- as.Date(date[ok])
  if (length(value) < 2L) return(NA_real_)
  if (isTRUE(ytd)) {
    idx <- which(date >= lubridate::floor_date(max(date), "year"))
    if (!length(idx)) return(NA_real_)
    base <- value[min(idx)]
  } else {
    base <- value[max(1L, length(value) - as.integer(trading_days))]
  }
  if (!is.finite(base) || base == 0) return(NA_real_)
  (tail(value, 1L) / base - 1) * 100
}

annualized_vol_pct <- function(value, window) {
  ret <- value / dplyr::lag(value) - 1
  ret <- tail(ret[is.finite(ret)], window)
  if (length(ret) < min(10L, window)) return(NA_real_)
  stats::sd(ret) * sqrt(252) * 100
}

performance_metrics <- function(data, as_of = Sys.Date()) {
  data %>%
    dplyr::filter(date <= as.Date(as_of), is.finite(effective_value)) %>%
    dplyr::group_by(series_id, display_name) %>%
    dplyr::arrange(date, .by_group = TRUE) %>%
    dplyr::summarize(
      LastDate = max(date),
      Last = dplyr::last(effective_value),
      Return1W = period_return_pct(effective_value, date, 5L),
      Return1M = period_return_pct(effective_value, date, 21L),
      Return3M = period_return_pct(effective_value, date, 63L),
      Return6M = period_return_pct(effective_value, date, 126L),
      YTD = period_return_pct(effective_value, date, ytd = TRUE),
      Vol20 = annualized_vol_pct(effective_value, 20L),
      Vol60 = annualized_vol_pct(effective_value, 60L),
      Vol120 = annualized_vol_pct(effective_value, 120L),
      .groups = "drop"
    )
}

monthly_rank_change <- function(data, as_of = Sys.Date()) {
  monthly <- data %>%
    dplyr::filter(date <= as.Date(as_of), is.finite(effective_value)) %>%
    dplyr::mutate(month = lubridate::floor_date(date, "month")) %>%
    dplyr::group_by(series_id, display_name, month) %>%
    dplyr::arrange(date, .by_group = TRUE) %>%
    dplyr::summarize(month_end = dplyr::last(effective_value), .groups = "drop") %>%
    dplyr::group_by(series_id, display_name) %>%
    dplyr::arrange(month, .by_group = TRUE) %>%
    dplyr::mutate(month_return = month_end / dplyr::lag(month_end) - 1) %>%
    dplyr::ungroup() %>%
    dplyr::filter(is.finite(month_return)) %>%
    dplyr::group_by(month) %>%
    dplyr::mutate(rank = dplyr::min_rank(dplyr::desc(month_return))) %>%
    dplyr::ungroup()
  months <- sort(unique(monthly$month), decreasing = TRUE)
  if (length(months) < 2L) return(tibble::tibble(series_id = character(), RankChange = integer()))
  current <- monthly %>% dplyr::filter(month == months[1]) %>% dplyr::select(series_id, current_rank = rank)
  previous <- monthly %>% dplyr::filter(month == months[2]) %>% dplyr::select(series_id, previous_rank = rank)
  dplyr::left_join(current, previous, by = "series_id") %>%
    dplyr::transmute(series_id, RankChange = previous_rank - current_rank)
}

align_us_kr_returns <- function(us, kr, mode = "Next KR trading day") {
  us <- us %>% dplyr::arrange(date) %>% dplyr::filter(is.finite(ret))
  kr <- kr %>% dplyr::arrange(date) %>% dplyr::filter(is.finite(ret))
  if (mode == "Same calendar date") {
    return(dplyr::inner_join(
      us %>% dplyr::rename(us_ret = ret),
      kr %>% dplyr::rename(kr_ret = ret),
      by = "date"
    ) %>% dplyr::transmute(us_date = date, kr_date = date, us_ret, kr_ret))
  }
  idx <- findInterval(us$date, kr$date) + 1L
  keep <- idx <= nrow(kr)
  tibble::tibble(
    us_date = us$date[keep], kr_date = kr$date[idx[keep]],
    us_ret = us$ret[keep], kr_ret = kr$ret[idx[keep]]
  )
}

rolling_correlation <- function(x, y, window) {
  vapply(seq_along(x), function(i) {
    if (i < window) return(NA_real_)
    idx <- (i - window + 1L):i
    ok <- stats::complete.cases(x[idx], y[idx])
    if (sum(ok) < max(10L, ceiling(window * 0.7))) return(NA_real_)
    stats::cor(x[idx][ok], y[idx][ok])
  }, numeric(1))
}
