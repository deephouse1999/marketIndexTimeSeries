#!/usr/bin/env Rscript

gate6_r_lib <- "C:/Users/yjh14/AppData/Local/R/win-library/4.5"
if (dir.exists(gate6_r_lib)) .libPaths(c(gate6_r_lib, .libPaths()))
suppressPackageStartupMessages({ library(dplyr); library(readr); library(tibble) })

repo_dir <- normalizePath(".", winslash = "/", mustWork = TRUE)
app_dir <- file.path(repo_dir, "apps", "timeseries")
gate_dir <- file.path(repo_dir, "docs", "gate4_5")
dir.create(gate_dir, recursive = TRUE, showWarnings = FALSE)
source(file.path(app_dir, "ecos_adapter.R"), local = TRUE)

if (ecos_key_status() != "KEY_BOUND") stop("SKIPPED_NO_KEY")
items <- ecos_statistic_item_list("404Y016")
snapshot <- normalize_ecos_item_snapshot(items)

expected <- tibble(
  series_id = c("KR_DRAM_PPI", "KR_FLASH_MEMORY_PPI"),
  stat_code = "404Y016",
  item_code = c("30911201AA", "30911202AA"),
  expected_item_name = c("DRAM", intToUtf8(c(0xD50C, 0xB798, 0xC2DC, 0xBA54, 0xBAA8, 0xB9AC))),
  cycle = "M",
  unit = "2020=100"
)
verified <- expected %>%
  left_join(snapshot, by = c("stat_code", "item_code", "cycle"), suffix = c("_expected", "_source")) %>%
  mutate(
    source_updated_at_status = "NOT_PROVIDED_BY_ECOS_ITEM_API",
    status = case_when(
      is.na(item_name) ~ "SOURCE_NOT_AVAILABLE",
      item_name != expected_item_name | unit_source != unit_expected ~ "CONFIG_CODE_MISMATCH",
      TRUE ~ "VERIFIED"
    ),
    official_readback_at = format(Sys.time(), tz = "Asia/Seoul", usetz = TRUE)
  )

write_csv(verified, file.path(gate_dir, "ecos_physical_metadata_snapshot.csv"), na = "")
if (any(verified$status != "VERIFIED")) {
  stop(paste(unique(verified$status[verified$status != "VERIFIED"]), collapse = ","))
}
cat("Gate 4.5 ECOS metadata readback: PASS (2/2)\n")
