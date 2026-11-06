#!/usr/bin/env Rscript

gate6_r_lib <- "C:/Users/yjh14/AppData/Local/R/win-library/4.5"
if (dir.exists(gate6_r_lib)) .libPaths(c(gate6_r_lib, .libPaths()))
suppressPackageStartupMessages({ library(dplyr); library(readr); library(tibble) })

repo_dir <- normalizePath(".", winslash = "/", mustWork = TRUE)
app_dir <- file.path(repo_dir, "apps", "timeseries")
gate_dir <- file.path(repo_dir, "docs", "gate4_5")
gate2_dir <- file.path(repo_dir, "docs", "gate2")
catalog_path <- file.path(app_dir, "series_catalog.csv")
evidence_path <- file.path(gate_dir, "ecos_physical_metadata_snapshot.csv")
if (!file.exists(evidence_path)) stop("OFFICIAL_METADATA_READBACK_REQUIRED")

evidence <- read_csv(evidence_path, col_types = cols(.default = col_character()), na = character())
if (nrow(evidence) != 2L || any(evidence$status != "VERIFIED")) stop("CONFIG_CODE_MISMATCH")
catalog <- read_csv(catalog_path, col_types = cols(.default = col_character()), na = character())

extra_columns <- c(
  "source_symbol", "indicator_type", "proxy_for", "frequency", "release_lag",
  "license_status", "source_definition", "available_at_policy",
  "do_not_interpret_as", "display_location"
)
for (nm in extra_columns) if (!nm %in% names(catalog)) catalog[[nm]] <- ""
catalog$source_symbol[catalog$source_symbol == ""] <- catalog$series_id[catalog$source_symbol == ""]

ko_dram <- paste0("DRAM ", intToUtf8(c(0xAD6D, 0xB0B4, 0x20, 0xC0DD, 0xC0B0, 0xC790, 0xBB3C, 0xAC00, 0xC9C0, 0xC218)))
ko_flash_name <- intToUtf8(c(0xD50C, 0xB798, 0xC2DC, 0xBA54, 0xBAA8, 0xB9AC))
ko_flash <- paste0("Flash Memory ", intToUtf8(c(0xAD6D, 0xB0B4, 0x20, 0xC0DD, 0xC0B0, 0xC790, 0xBB3C, 0xAC00, 0xC9C0, 0xC218)))
ko_bwet <- intToUtf8(c(0xC720, 0xC870, 0xC120, 0x20, 0xC6B4, 0xC784, 0xC120, 0xBB3C, 0x20, 0x45, 0x54, 0x46, 0x20, 0xD504, 0xB85D, 0xC2DC))

new_rows <- tribble(
  ~source, ~series_id, ~source_symbol, ~display_name, ~display_name_ko, ~series_cls, ~series_group, ~sector, ~industry, ~region, ~currency, ~benchmark_series, ~price_policy, ~stat_code, ~cycle, ~item_code1, ~item_code2, ~item_code3, ~item_code4, ~unit, ~transform, ~collect_flag, ~default_visible, ~active, ~display_order, ~notes, ~indicator_type, ~proxy_for, ~frequency, ~release_lag, ~license_status, ~source_definition, ~available_at_policy, ~do_not_interpret_as, ~display_location,
  "ECOS", "KR_DRAM_PPI", "KR_DRAM_PPI", "Korea DRAM Producer Price Index", ko_dram, "producer_price_index", "physical_indicator", "Technology", "Semiconductors", "KR", "KRW", "", "close", "404Y016", "M", "30911201AA", "", "", "", "2020=100", "", "TRUE", "TRUE", "TRUE", "601", "official_item_name=DRAM;physical_indicator=TRUE", "producer_price_index", "korean_dram_producer_price", "monthly", "source_publication_schedule", "public", "Bank of Korea ECOS producer price index by item", "COLLECTED_AT_CONSERVATIVE", "global_dram_spot_or_contract_price", "semiconductor_korea_link",
  "ECOS", "KR_FLASH_MEMORY_PPI", "KR_FLASH_MEMORY_PPI", "Korea Flash Memory Producer Price Index", ko_flash, "producer_price_index", "physical_indicator", "Technology", "Semiconductors", "KR", "KRW", "", "close", "404Y016", "M", "30911202AA", "", "", "", "2020=100", "", "TRUE", "TRUE", "TRUE", "602", paste0("official_item_name=", ko_flash_name, ";physical_indicator=TRUE"), "producer_price_index", "korean_flash_memory_producer_price", "monthly", "source_publication_schedule", "public", "Bank of Korea ECOS producer price index by item", "COLLECTED_AT_CONSERVATIVE", "global_flash_spot_or_contract_price", "semiconductor_korea_link",
  "YAHOO", "BWET_VLCC_PROXY", "BWET", "Tanker Freight Futures ETF Proxy (BWET)", ko_bwet, "freight_futures_etf_proxy", "physical_indicator", "Energy", "Tanker Freight", "US", "USD", "XLE", "adjusted", "", "", "", "", "", "", "USD", "", "TRUE", "TRUE", "TRUE", "603", "physical_indicator=TRUE;proxy_only=TRUE", "freight_futures_etf_proxy", "tanker_freight_market", "daily", "market_close", "public_market_price", "Breakwave Tanker Shipping ETF market price", "US_CLOSE_AVAILABLE", "vlcc_spot_rate_or_baltic_official_index", "series_explorer"
)

for (nm in setdiff(names(catalog), names(new_rows))) new_rows[[nm]] <- ""
for (nm in setdiff(names(new_rows), names(catalog))) catalog[[nm]] <- ""
new_rows <- new_rows[, names(catalog), drop = FALSE]
catalog <- bind_rows(catalog %>% filter(!series_id %in% new_rows$series_id), new_rows) %>%
  mutate(display_order = as.integer(display_order)) %>% arrange(display_order, source, series_id)

preferred <- c("source", "series_id", "source_symbol", setdiff(names(catalog), c("source", "series_id", "source_symbol")))
write_csv(catalog[, preferred], catalog_path, na = "")

source(file.path(app_dir, "ecos_adapter.R"), local = TRUE)
official_rows <- evidence %>%
  transmute(stat_code, stat_name, item_code, item_name, parent_item_code, cycle,
            unit = unit_source, start_date, end_date, data_count, source_updated_at)
snapshot_path <- file.path(app_dir, "ecos_item_snapshot.csv")
snapshot <- read_csv(snapshot_path, col_types = cols(.default = col_character()), na = character())
snapshot <- bind_rows(snapshot %>% filter(!(stat_code == "404Y016" & item_code %in% official_rows$item_code & cycle == "M")), official_rows) %>%
  distinct(stat_code, item_code, cycle, .keep_all = TRUE)
write_csv(snapshot, snapshot_path, na = "")

config <- catalog %>% mutate(collect_flag = as.logical(collect_flag)) %>% filter(source == "ECOS", collect_flag)
contract <- validate_ecos_catalog_rows(config, snapshot)
write_csv(contract, file.path(gate2_dir, "ecos_catalog_contract_validation.csv"), na = "")
if (any(contract$status != "VERIFIED")) stop("CONFIG_CODE_MISMATCH")
write_csv(new_rows, file.path(gate_dir, "physical_catalog_rows.csv"), na = "")
cat("Gate 4.5 catalog registration: PASS (3 series)\n")
