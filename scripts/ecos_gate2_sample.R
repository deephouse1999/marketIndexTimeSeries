suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

locale_result <- Sys.setlocale("LC_CTYPE", "Korean_Korea.utf8")
if (is.na(locale_result)) stop("UTF-8 Korean locale is required")

repo_dir <- normalizePath(".", winslash = "/", mustWork = TRUE)
app_dir <- file.path(repo_dir, "apps", "timeseries")
gate_dir <- file.path(repo_dir, "docs", "gate2")
source(file.path(app_dir, "ecos_adapter.R"), local = TRUE)

catalog <- read_csv(file.path(app_dir, "series_catalog.csv"), col_types = cols(.default = col_character()), na = character()) %>%
  mutate(collect_flag = as.logical(collect_flag))
sample_config <- catalog %>% filter(source == "ECOS", series_id %in% c("BOK_BASE_RATE", "KTB_03Y", "ECOS_USDKRW"))
if (nrow(sample_config) != 3L) stop("ECOS sample configuration is incomplete")

sample_results <- lapply(seq_len(nrow(sample_config)), function(i) {
  result <- ecos_collect_one_safe(sample_config[i, ], Sys.Date() - 45L, Sys.Date())
  if (!startsWith(result$status, "SUCCESS")) stop(sample_config$series_id[[i]], " sample failed: ", result$status, " ", result$error)
  result$data
})
sample_data <- bind_rows(sample_results)
write_csv(sample_data, file.path(gate_dir, "ecos_sample_observations.csv"))

pagination_config <- catalog %>% filter(source == "ECOS", series_id == "KTB_03Y")
pagination_result <- ecos_collect_one_safe(pagination_config, as.Date("1998-11-13"), Sys.Date())
if (!startsWith(pagination_result$status, "SUCCESS")) stop("Pagination sample failed: ", pagination_result$status)
pagination_data <- pagination_result$data
pagination_duplicates <- pagination_data %>% count(source, series_id, date) %>% filter(n > 1L) %>% nrow()
if (nrow(pagination_data) <= ECOS_PAGE_SIZE || pagination_duplicates != 0L) {
  stop("PAGINATION_VALIDATION_FAILED: rows=", nrow(pagination_data), ", duplicates=", pagination_duplicates)
}
write_csv(
  tibble(
    checked_at = format(Sys.time(), tz = "Asia/Seoul", usetz = TRUE),
    series_id = "KTB_03Y",
    rows = nrow(pagination_data),
    start_date = min(pagination_data$date),
    end_date = max(pagination_data$date),
    pages_minimum = ceiling(nrow(pagination_data) / ECOS_PAGE_SIZE),
    duplicate_keys = pagination_duplicates,
    status = "PASS"
  ),
  file.path(gate_dir, "ecos_pagination_validation.csv")
)

pending_probe <- ecos_collect_one_safe(
  pagination_config,
  Sys.Date() + 30L,
  Sys.Date() + 30L
)
if (!pending_probe$status %in% c("PENDING_SOURCE", "NO_DATA")) {
  stop("PENDING_SOURCE handling failed: ", pending_probe$status)
}
write_csv(
  tibble(
    checked_at = format(Sys.time(), tz = "Asia/Seoul", usetz = TRUE),
    test = c("recent_sample", "pagination", "future_unpublished"),
    status = c("PASS", "PASS", pending_probe$status),
    detail = c(
      paste(nrow(sample_data), "rows across 3 series"),
      paste(nrow(pagination_data), "rows with", pagination_duplicates, "duplicate keys"),
      "No fabricated observation; response classified without publication"
    )
  ),
  file.path(gate_dir, "ecos_sample_validation.csv")
)

cat("Gate 2 sample and pagination: PASS\n")

