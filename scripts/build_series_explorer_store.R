#!/usr/bin/env Rscript

gate6_r_lib <- "C:/Users/yjh14/AppData/Local/R/win-library/4.5"
if (dir.exists(gate6_r_lib)) .libPaths(c(gate6_r_lib, .libPaths()))
suppressPackageStartupMessages({ library(dplyr); library(fst); library(readr); library(tibble) })

repo_dir <- normalizePath(".", winslash = "/", mustWork = TRUE)
app_dir <- file.path(repo_dir, "apps", "timeseries")

normalize_source <- function(path, source_default) {
  out <- read.fst(path, as.data.table = FALSE) %>% as_tibble()
  if ("value" %in% names(out) && !"close_value" %in% names(out)) out$close_value <- out$value
  if (!"adjusted_value" %in% names(out)) out$adjusted_value <- NA_real_
  if (!"volume" %in% names(out)) out$volume <- NA_real_
  if (!"source" %in% names(out)) out$source <- source_default
  out$source[is.na(out$source) | trimws(as.character(out$source)) == ""] <- source_default
  out %>%
    transmute(date = as.Date(date), series_id = as.character(series_id), close_value = as.numeric(close_value),
              adjusted_value = as.numeric(adjusted_value), volume = as.numeric(volume), source = as.character(source)) %>%
    filter(!is.na(date), !is.na(series_id)) %>%
    distinct(source, series_id, date, .keep_all = TRUE)
}

catalog <- read_csv(file.path(app_dir, "series_catalog.csv"), show_col_types = FALSE) %>%
  transmute(
    source = toupper(trimws(source)), series_id = trimws(series_id),
    display_name = ifelse(is.na(display_name) | trimws(display_name) == "", series_id, display_name),
    display_transform = ifelse(!is.na(transform) & transform != "", transform,
      ifelse(grepl("(?:^|;)display_transform=", notes), sub(".*(?:^|;)display_transform=([^;]+).*", "\\1", notes), NA_character_))
  )

store <- bind_rows(
  normalize_source(file.path(app_dir, "original_ts_yahoo.fst"), "YAHOO"),
  normalize_source(file.path(app_dir, "original_ts_fred.fst"), "FRED")
) %>%
  distinct(source, series_id, date, .keep_all = TRUE) %>%
  left_join(catalog, by = c("source", "series_id")) %>%
  mutate(display_name = ifelse(is.na(display_name), series_id, display_name),
         raw_close_value = close_value, raw_adjusted_value = adjusted_value) %>%
  group_by(source, series_id) %>% arrange(date, .by_group = TRUE) %>%
  mutate(
    close_value = ifelse(display_transform %in% "yoy", 100 * (raw_close_value / lag(raw_close_value, 12L) - 1), raw_close_value),
    adjusted_value = ifelse(display_transform %in% "yoy" & !is.na(raw_adjusted_value), 100 * (raw_adjusted_value / lag(raw_adjusted_value, 12L) - 1), raw_adjusted_value),
    effective_value = ifelse(!is.na(adjusted_value), adjusted_value, close_value)
  ) %>% ungroup() %>% arrange(source, series_id, date)

target <- file.path(app_dir, "derived_series_explorer.fst")
staging <- paste0(target, ".staging")
last_good <- paste0(target, ".last_good")
on.exit(if (file.exists(staging)) unlink(staging), add = TRUE)
write.fst(store, staging, compress = 50)
readback <- read.fst(staging, as.data.table = FALSE)
duplicates <- sum(duplicated(readback[c("source", "series_id", "date")]))
if (nrow(readback) != nrow(store) || duplicates != 0L) stop("SERIES_EXPLORER_STORE_READBACK_FAILED")
if (file.exists(last_good)) unlink(last_good)
if (file.exists(target) && !file.rename(target, last_good)) stop("SERIES_EXPLORER_STORE_BACKUP_FAILED")
if (!file.rename(staging, target)) {
  if (file.exists(last_good)) file.rename(last_good, target)
  stop("SERIES_EXPLORER_STORE_PUBLICATION_FAILED")
}
cat("Series Explorer store: PASS (", nrow(readback), " rows, ", length(unique(readback$series_id)), " series)\n", sep = "")
