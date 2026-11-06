#!/usr/bin/env Rscript

gate_r_lib <- "C:/Users/yjh14/AppData/Local/R/win-library/4.5"
if (dir.exists(gate_r_lib)) .libPaths(c(gate_r_lib, .libPaths()))
options(market_ts.skip_autorun = TRUE)
source(file.path("apps", "timeseries", "dataExtract_fredyahoo.R"), local = TRUE)

path <- file.path("apps", "timeseries", "original_ts_yahoo.fst")
before <- read.fst(path, as.data.table = FALSE)
before_rows <- nrow(before)
before_keys <- before[c("source", "series_id", "date")]
updated <- normalize_old_schema(before)

stopifnot(nrow(updated) == before_rows)
stopifnot(identical(before_keys$series_id, updated$series_id))
stopifnot(sum(duplicated(updated[c("source", "series_id", "date")])) == 0L)

tmp <- paste0(path, ".gate4_5.staging")
write.fst(updated, tmp, compress = 50)
check <- read.fst(tmp, as.data.table = FALSE)
stopifnot(nrow(check) == before_rows)
file.copy(tmp, path, overwrite = TRUE)
unlink(tmp)

bwet <- check[check$series_id == "BWET_VLCC_PROXY", ]
required <- c("observation_date", "available_at", "collected_at", "source_updated_at",
              "vintage", "quality_status", "source", "calculation_version")
stopifnot(nrow(bwet) > 0L, all(required %in% names(bwet)), all(nzchar(bwet$available_at)))
cat("BWET metadata enrichment: PASS (", nrow(bwet), " rows; total rows unchanged ", before_rows, ")\n", sep = "")
