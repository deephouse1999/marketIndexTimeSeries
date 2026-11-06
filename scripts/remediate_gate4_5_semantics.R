#!/usr/bin/env Rscript

gate_r_lib <- "C:/Users/yjh14/AppData/Local/R/win-library/4.5"
if (dir.exists(gate_r_lib)) .libPaths(c(gate_r_lib, .libPaths()))
suppressPackageStartupMessages({ library(fst); library(readr) })

ecos_path <- file.path("apps", "timeseries", "original_ts_ecos.fst")
ecos <- read.fst(ecos_path, as.data.table = FALSE)
rows_before <- nrow(ecos)
keys_before <- ecos[c("source", "series_id", "date")]
ecos$source_updated_at <- NA_character_

staging <- paste0(ecos_path, ".semantic.staging")
write.fst(ecos, staging, compress = 50)
readback <- read.fst(staging, as.data.table = FALSE)
stopifnot(nrow(readback) == rows_before, identical(keys_before$series_id, readback$series_id),
          sum(duplicated(readback[c("source", "series_id", "date")])) == 0L)
file.copy(staging, ecos_path, overwrite = TRUE)
unlink(staging)

snapshot_path <- file.path("docs", "gate4_5", "ecos_physical_metadata_snapshot.csv")
snapshot <- read_csv(snapshot_path, show_col_types = FALSE)
snapshot$source_updated_at <- NA_character_
snapshot$source_updated_at_status <- "NOT_PROVIDED_BY_ECOS_ITEM_API"
write_csv(snapshot, snapshot_path, na = "")
cat("Gate 4.5 semantic remediation: PASS (", rows_before, " ECOS rows unchanged)\n", sep = "")
