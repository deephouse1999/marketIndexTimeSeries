suppressPackageStartupMessages({
  library(dplyr)
  library(fst)
  library(readr)
  library(tibble)
})

script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
script_path <- if (length(script_arg)) sub("^--file=", "", script_arg[[1]]) else file.path("scripts", "validate_gate1.R")
repo_dir <- normalizePath(file.path(dirname(script_path), ".."), winslash = "/", mustWork = TRUE)
app_dir <- file.path(repo_dir, "apps", "timeseries")
gate_dir <- file.path(repo_dir, "docs", "gate1")

catalog_path <- file.path(app_dir, "series_catalog.csv")
fred_path <- file.path(app_dir, "original_ts_fred.fst")
yahoo_path <- file.path(app_dir, "original_ts_yahoo.fst")

catalog <- read_csv(catalog_path, col_types = cols(.default = col_character()), na = character()) %>%
  mutate(
    collect_flag = as.logical(collect_flag),
    default_visible = as.logical(default_visible),
    active = as.logical(active),
    display_order = as.integer(display_order)
  )
legacy_catalog <- catalog %>% filter(source %in% c("FRED", "YAHOO"))
fred <- read.fst(fred_path, as.data.table = FALSE) %>% mutate(date = as.Date(date))
yahoo <- read.fst(yahoo_path, as.data.table = FALSE) %>% mutate(date = as.Date(date))

expected_columns <- c(
  "source", "series_id", "display_name", "display_name_ko", "series_cls",
  "series_group", "sector", "industry", "region", "currency",
  "benchmark_series", "price_policy", "stat_code", "cycle", "item_code1",
  "item_code2", "item_code3", "item_code4", "unit", "transform",
  "collect_flag", "default_visible", "active", "display_order", "notes"
)
allowed_sources <- c("FRED", "YAHOO", "ECOS")
allowed_cycles <- c("", "D", "M", "Q", "A")
allowed_policies <- c("close", "adjusted")

checks <- tibble(check = character(), status = character(), detail = character())
add_check <- function(name, condition, detail) {
  checks <<- bind_rows(checks, tibble(
    check = name,
    status = if (isTRUE(condition)) "PASS" else "FAIL",
    detail = as.character(detail)
  ))
}

add_check("catalog_schema", identical(names(catalog), expected_columns), paste(ncol(catalog), "columns"))
add_check("catalog_unique_key", nrow(catalog %>% count(source, series_id) %>% filter(n > 1)) == 0, "duplicate (source, series_id) = 0")
add_check("catalog_source_domain", all(catalog$source %in% allowed_sources), paste(sort(unique(catalog$source)), collapse = ", "))
add_check("catalog_cycle_domain", all(catalog$cycle %in% allowed_cycles), paste(sort(unique(catalog$cycle)), collapse = ", "))
add_check("catalog_price_policy_domain", all(catalog$price_policy %in% allowed_policies), paste(sort(unique(catalog$price_policy)), collapse = ", "))
add_check("catalog_names", all(nzchar(catalog$display_name)) && all(nzchar(catalog$display_name_ko)), "English and Korean names populated")

hidden_no_collect <- c("AAPL", "GOOG", "TSLA", "META", "LLY", "ZC=F", "HE=F")
hidden_collect <- c("^FTSE", "^GDAXI", "ACWI", "URTH")
inactive_rows <- catalog %>% filter(source == "YAHOO", series_id %in% hidden_no_collect)
hidden_rows <- catalog %>% filter(source == "YAHOO", series_id %in% hidden_collect)
add_check("non_destructive_deactivation", nrow(inactive_rows) == length(hidden_no_collect) && all(inactive_rows$active) && !any(inactive_rows$collect_flag) && !any(inactive_rows$default_visible), "7 legacy rows retained, collection/default display disabled")
add_check("hidden_but_collectable", nrow(hidden_rows) == length(hidden_collect) && all(hidden_rows$active) && all(hidden_rows$collect_flag) && !any(hidden_rows$default_visible), "4 global rows remain collectable but hidden by default")
add_check("legacy_history_preserved", all(hidden_no_collect %in% unique(yahoo$series_id)), "all deactivated Yahoo series remain in FST")

bovespa <- catalog %>% filter(source == "YAHOO", series_id == "^BVSP")
add_check(
  "bovespa_regional_classification",
  nrow(bovespa) == 1 && bovespa$series_cls == "emerging_market_index" &&
    bovespa$series_group == "regional_comparison" && bovespa$benchmark_series == "^KS11" &&
    bovespa$collect_flag && bovespa$default_visible && bovespa$active &&
    grepl("included_in_regional_view", bovespa$notes, fixed = TRUE) &&
    grepl("no_standalone_module", bovespa$notes, fixed = TRUE),
  "Bovespa retained in Regional View with no standalone module"
)

metadata_expectations <- tribble(
  ~source, ~series_id, ~display_name, ~series_cls,
  "FRED", "DFEDTAR", "Federal Funds Target Rate (Discontinued)", "rate",
  "FRED", "DFEDTARU", "Federal Funds Target Range Upper Limit", "rate",
  "FRED", "DFEDTARL", "Federal Funds Target Range Lower Limit", "rate",
  "FRED", "BAMLC0A1CAAAEY", "US AAA Corporate Effective Yield", "credit",
  "FRED", "BAMLC0A2CAAEY", "US AA Corporate Effective Yield", "credit",
  "FRED", "BAMLC0A3CAEY", "US Single-A Corporate Effective Yield", "credit",
  "FRED", "BAMLC0A4CBBBEY", "US BBB Corporate Effective Yield", "credit",
  "FRED", "WPSFD4131", "Core Finished Goods PPI", "inflation",
  "FRED", "B935RC1Q027SBEA", "Computer & Peripheral Equipment Investment", "investment",
  "FRED", "WTISPLC", "WTI Spot Price", "commodity",
  "YAHOO", "AGGG.L", "Global Aggregate Bond ETF", "broad_etf",
  "YAHOO", "^VIX", "VIX", "volatility_index"
)
metadata_observed <- catalog %>%
  inner_join(metadata_expectations, by = c("source", "series_id"), suffix = c("_actual", "_expected"))
add_check(
  "required_metadata_corrections",
  nrow(metadata_observed) == nrow(metadata_expectations) &&
    all(metadata_observed$display_name_actual == metadata_observed$display_name_expected) &&
    all(metadata_observed$series_cls_actual == metadata_observed$series_cls_expected),
  "12 required identifiers, names, and classes match the Gate 1 contract"
)

new_fred <- c("DFEDTARL", "DFII10", "T10YIE", "DFF", "SOFR")
new_yahoo <- c("SHY", "IEF", "TLT", "LQD", "HYG", "SOXQ", "005930.KS", "HG=F")
add_check("new_fred_registered", all(new_fred %in% catalog$series_id[catalog$source == "FRED"]), paste(new_fred, collapse = ", "))
add_check("new_yahoo_registered", all(new_yahoo %in% catalog$series_id[catalog$source == "YAHOO"]), paste(new_yahoo, collapse = ", "))

stored_keys <- bind_rows(
  fred %>% distinct(series_id) %>% mutate(source = "FRED", .before = 1),
  yahoo %>% distinct(series_id) %>% mutate(source = "YAHOO", .before = 1)
) %>% distinct(source, series_id)
pending_keys <- bind_rows(
  tibble(source = "FRED", series_id = new_fred),
  tibble(source = "YAHOO", series_id = new_yahoo)
)
intentional_keys <- tibble(source = "YAHOO", series_id = "^TOPX")

catalog_without_storage <- legacy_catalog %>%
  anti_join(stored_keys, by = c("source", "series_id")) %>%
  left_join(pending_keys %>% mutate(pending = TRUE), by = c("source", "series_id")) %>%
  left_join(intentional_keys %>% mutate(intentional = TRUE), by = c("source", "series_id")) %>%
  mutate(
    classification = case_when(
      pending %in% TRUE ~ "EXPECTED_PENDING_COLLECTION",
      intentional %in% TRUE ~ "INTENTIONALLY_CATALOG_ONLY",
      TRUE ~ "UNEXPECTED_MISSING_HISTORY"
    ),
    rationale = case_when(
      classification == "EXPECTED_PENDING_COLLECTION" ~ "Registered in Gate 1; collection begins in the applicable later gate",
      classification == "INTENTIONALLY_CATALOG_ONLY" ~ "Unsupported Yahoo TOPIX symbol retained for mapping; collection and default display disabled",
      TRUE ~ "No approved explanation"
    )
  ) %>%
  select(source, series_id, display_name, collect_flag, default_visible, active, classification, rationale)

write_csv(catalog_without_storage, file.path(gate_dir, "catalog_fst_anti_join.csv"))
write_csv(
  catalog_without_storage %>% filter(classification == "EXPECTED_PENDING_COLLECTION"),
  file.path(gate_dir, "pending_collection_13.csv")
)

classification_counts <- catalog_without_storage %>% count(classification, name = "series")
stored_count <- nrow(stored_keys)
pending_count <- sum(catalog_without_storage$classification == "EXPECTED_PENDING_COLLECTION")
intentional_count <- sum(catalog_without_storage$classification == "INTENTIONALLY_CATALOG_ONLY")
unexpected_count <- sum(catalog_without_storage$classification == "UNEXPECTED_MISSING_HISTORY")
add_check("catalog_inventory_reconciled", nrow(legacy_catalog) == stored_count + pending_count + intentional_count && unexpected_count == 0, paste0(nrow(legacy_catalog), " = ", stored_count, " stored + ", pending_count, " pending + ", intentional_count, " intentional"))
topx <- catalog_without_storage %>% filter(source == "YAHOO", series_id == "^TOPX")
add_check("topix_catalog_only", nrow(topx) == 1 && topx$classification == "INTENTIONALLY_CATALOG_ONLY" && !topx$collect_flag && !topx$default_visible && topx$active, "^TOPX retained only as a disabled catalog mapping")

baseline_inventory <- read_csv(file.path(gate_dir, "baseline_data_inventory.csv"), show_col_types = FALSE)
baseline_hash <- read_csv(file.path(gate_dir, "baseline_sha256.csv"), show_col_types = FALSE)
dataset_check <- function(name, path, data) {
  base <- baseline_inventory %>% filter(dataset == name)
  expected_hash <- baseline_hash$Hash[grepl(basename(path), baseline_hash$Path, fixed = TRUE)]
  hash_output <- system2(
    "certutil",
    c("-hashfile", shQuote(normalizePath(path, winslash = "\\")), "SHA256"),
    stdout = TRUE
  )
  actual_hash <- toupper(trimws(hash_output[grepl("^[0-9a-fA-F]{64}$", trimws(hash_output))][1]))
  dup_count <- data %>% count(source, series_id, date) %>% filter(n > 1) %>% nrow()
  add_check(paste0(tolower(name), "_row_count"), nrow(data) == base$rows, paste(nrow(data), "rows"))
  add_check(paste0(tolower(name), "_date_range"), min(data$date) == as.Date(base$start_date) && max(data$date) == as.Date(base$end_date), paste(min(data$date), "to", max(data$date)))
  add_check(paste0(tolower(name), "_unique_key"), dup_count == 0, paste("duplicate keys =", dup_count))
  add_check(paste0(tolower(name), "_sha256"), identical(actual_hash, expected_hash), actual_hash)
}
dataset_check("FRED", fred_path, fred)
dataset_check("YAHOO", yahoo_path, yahoo)

options(market_ts.skip_autorun = TRUE)
collector_env <- new.env(parent = globalenv())
collector_ok <- tryCatch({
  sys.source(file.path(app_dir, "dataExtract_fredyahoo.R"), envir = collector_env)
  parsed <- collector_env$read_series_catalog(catalog_path)
  nrow(parsed) == nrow(catalog)
}, error = function(e) FALSE)
add_check("collector_catalog_load", collector_ok, "collector parser accepts Gate 1 schema")

app_env <- new.env(parent = globalenv())
app_ok <- tryCatch({
  old_wd <- setwd(app_dir)
  on.exit(setwd(old_wd), add = TRUE)
  sys.source(file.path(app_dir, "app.R"), envir = app_env)
  exists("ui", envir = app_env) && exists("server", envir = app_env)
}, error = function(e) FALSE)
add_check("shiny_source_load", app_ok, "app.R defines ui and server")

write_csv(checks, file.path(gate_dir, "gate1_validation.csv"))

overall <- if (all(checks$status == "PASS")) "PASS" else "FAIL"
report_lines <- c(
  "# Gate 1 Validation Report",
  "",
  paste0("**Result: ", overall, "**"),
  "",
  "Initial review disposition: `PASS WITH MINOR RECONCILIATION`. The catalog/FST reconciliation and Bovespa Regional View correction are now complete.",
  "",
  paste0("Validated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
  "",
  "## Scope",
  "",
  "- Catalog schema migration and metadata correction only.",
  "- Existing FRED and Yahoo FST files were not recollected or rewritten.",
  "- ECOS and SOX collection are deferred to later gates.",
  "",
  "## Checks",
  "",
  "| Check | Status | Detail |",
  "|---|---|---|",
  paste0("| ", checks$check, " | ", checks$status, " | ", gsub("\\|", "\\\\|", checks$detail), " |"),
  "",
  "## Inventory",
  "",
  paste0("- Gate 1 legacy catalog: ", nrow(legacy_catalog), " rows, ", ncol(catalog), " columns (FRED ", sum(legacy_catalog$source == "FRED"), ", Yahoo ", sum(legacy_catalog$source == "YAHOO"), ")."),
  paste0("- FRED FST: ", format(nrow(fred), big.mark = ","), " rows, ", length(unique(fred$series_id)), " stored series."),
  paste0("- Yahoo FST: ", format(nrow(yahoo), big.mark = ","), " rows, ", length(unique(yahoo$series_id)), " stored series."),
  paste0("- Newly registered, pending collection: ", length(new_fred) + length(new_yahoo), " series."),
  paste0("- Reconciliation: legacy catalog ", nrow(legacy_catalog), " = stored ", stored_count, " + pending ", pending_count, " + intentional catalog-only ", intentional_count, "."),
  "",
  "## Catalog-FST Anti-Join",
  "",
  "| Source | Series | Classification | Rationale |",
  "|---|---|---|---|",
  paste0("| ", catalog_without_storage$source, " | ", catalog_without_storage$series_id, " | ", catalog_without_storage$classification, " | ", catalog_without_storage$rationale, " |"),
  "",
  "## Gate 1 Closure",
  "",
  if (overall == "PASS" && unexpected_count == 0) c(
    "- `CATALOG_INVENTORY_RECONCILED`",
    "- `BOVESPA_REGIONAL_CLASSIFICATION_PASS`",
    "- `LEGACY_FST_HASH_UNCHANGED`",
    "- `DOCUMENTATION_UPDATED`",
    "- `GATE_1_CLOSED_PASS`",
    "- `GATE_2_APPROVED_TO_START`"
  ) else "- `GATE_1_RECONCILIATION_FAILED`",
  "",
  "## Gate Decision",
  "",
  if (overall == "PASS" && unexpected_count == 0) "Gate 1 is closed. Gate 2 ECOS Adapter development is approved to start." else "Gate 1 is not closed. Resolve unexplained history gaps before Gate 2."
)
writeLines(report_lines, file.path(gate_dir, "GATE1_VALIDATION_REPORT.md"), useBytes = TRUE)

cat("Gate 1 validation: ", overall, " (", sum(checks$status == "PASS"), "/", nrow(checks), " checks passed)\n", sep = "")
if (overall != "PASS") quit(status = 1)

