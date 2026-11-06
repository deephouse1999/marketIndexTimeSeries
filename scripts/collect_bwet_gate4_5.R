#!/usr/bin/env Rscript

gate6_r_lib <- "C:/Users/yjh14/AppData/Local/R/win-library/4.5"
if (dir.exists(gate6_r_lib)) .libPaths(c(gate6_r_lib, .libPaths()))
options(market_ts.skip_autorun = TRUE)
source(file.path("apps", "timeseries", "dataExtract_fredyahoo.R"), local = TRUE)

catalog <- read_series_catalog(catalog_path)
config <- catalog %>% filter(source == "YAHOO", series_id == "BWET_VLCC_PROXY")
if (nrow(config) != 1L || config$source_symbol[[1]] != "BWET") stop("BWET_CONFIG_CODE_MISMATCH")

updated <- update_series(
  config, yahoo_ts_path, safe_yahoo_series, "YAHOO",
  full_start_date = as.Date("1976-01-01"), force_full_history = FALSE
)
bwet <- updated %>% filter(series_id == "BWET_VLCC_PROXY")
if (!nrow(bwet)) stop("SOURCE_NOT_AVAILABLE: Yahoo BWET")
if (any(duplicated(bwet[c("source", "series_id", "date")]))) stop("BWET_DUPLICATE_KEY")
write.fst(build_descriptor(updated, catalog %>% filter(source == "YAHOO")), yahoo_desc_path, compress = 50)
cat("BWET collection: PASS (", nrow(bwet), " rows, ", min(bwet$date), " to ", max(bwet$date), ")\n", sep = "")
