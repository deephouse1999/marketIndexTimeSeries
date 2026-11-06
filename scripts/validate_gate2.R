suppressPackageStartupMessages({
  library(dplyr)
  library(fst)
  library(readr)
  library(tibble)
})

locale_result <- Sys.setlocale("LC_CTYPE", "Korean_Korea.utf8")
if (is.na(locale_result)) stop("UTF-8 Korean locale is required")

repo_dir <- normalizePath(".", winslash = "/", mustWork = TRUE)
app_dir <- file.path(repo_dir, "apps", "timeseries")
gate_dir <- file.path(repo_dir, "docs", "gate2")
source(file.path(app_dir, "ecos_adapter.R"), local = TRUE)

checks <- tibble(check = character(), status = character(), detail = character())
add_check <- function(name, condition, detail) {
  checks <<- bind_rows(checks, tibble(
    check = name,
    status = if (isTRUE(condition)) "PASS" else "FAIL",
    detail = as.character(detail)
  ))
}

sha256_file <- function(path) {
  output <- system2(
    "certutil",
    c("-hashfile", shQuote(normalizePath(path, winslash = "\\")), "SHA256"),
    stdout = TRUE
  )
  output <- iconv(output, from = "", to = "UTF-8", sub = "")
  toupper(trimws(output[grepl("^[0-9a-fA-F]{64}$", trimws(output))][1]))
}

fred_path <- file.path(app_dir, "original_ts_fred.fst")
yahoo_path <- file.path(app_dir, "original_ts_yahoo.fst")
ecos_path <- file.path(app_dir, "original_ts_ecos.fst")
last_good_path <- paste0(ecos_path, ".last_good")

fred <- read.fst(fred_path, as.data.table = FALSE)
yahoo <- read.fst(yahoo_path, as.data.table = FALSE)
ecos <- read.fst(ecos_path, as.data.table = FALSE) %>% as_tibble() %>% mutate(date = as.Date(date))
last_good <- read.fst(last_good_path, as.data.table = FALSE) %>% as_tibble() %>% mutate(date = as.Date(date))

add_check("legacy_fred_unchanged", nrow(fred) == 456067L && sha256_file(fred_path) == "67CBDA72DEB4ED07A559584711F8AB71F83D1C578CC9F719774438F96DE53884", paste(nrow(fred), "rows"))
add_check("legacy_yahoo_unchanged", nrow(yahoo) == 437232L && sha256_file(yahoo_path) == "D9431E63A096991AEA2B03FDE34116155572F52F6FCA1A3F318EE7B8A3671972", paste(nrow(yahoo), "rows"))

readback <- validate_ecos_dataset(ecos)
last_good_readback <- validate_ecos_dataset(last_good)
add_check("ecos_independent_readback", readback$valid && readback$rows == 125625L && readback$series == 18L, paste(readback$rows, "rows,", readback$series, "series"))
add_check("ecos_duplicate_keys", readback$duplicate_keys == 0L, "duplicate (source, series_id, date) = 0")
add_check("ecos_date_range", min(ecos$date) == as.Date("1964-05-04") && max(ecos$date) == as.Date("2026-11-05"), paste(min(ecos$date), "to", max(ecos$date)))
add_check("last_good_readable", last_good_readback$valid && last_good_readback$series == 18L, paste(last_good_readback$rows, "rows,", last_good_readback$series, "series"))

catalog <- read_csv(file.path(app_dir, "series_catalog.csv"), col_types = cols(.default = col_character()), na = character())
ecos_catalog <- catalog %>% filter(source == "ECOS")
collectable <- ecos_catalog %>% filter(as.logical(collect_flag), as.logical(active))
special <- ecos_catalog %>% filter(series_id == "SPECIAL_AAA_03Y")
add_check("ecos_catalog_contract", nrow(ecos_catalog) == 19L && nrow(collectable) == 18L && setequal(collectable$series_id, unique(ecos$series_id)), "19 catalog rows = 18 collectable + 1 unavailable")
add_check("special_bond_unavailable", nrow(special) == 1L && !as.logical(special$collect_flag) && special$notes == "SOURCE_NOT_AVAILABLE; no verified representative special-bond AAA series in official ECOS 817Y002 readback", "No unverified substitute was used")

contract <- read_csv(file.path(gate_dir, "ecos_catalog_contract_validation.csv"), col_types = cols(.default = col_character()), na = character())
add_check("official_item_contract", nrow(contract) == 18L && all(contract$status == "VERIFIED"), "18/18 code, item name, cycle, and unit contracts verified")

readback_status <- read_csv(file.path(gate_dir, "ecos_readback_status.csv"), col_types = cols(.default = col_character()), na = character())
required_services <- c("ECOS_API_KEY", "StatisticTableList", "StatisticMeta", "StatisticItemList:722Y001", "StatisticItemList:817Y002", "StatisticItemList:731Y001", "ITEM_SNAPSHOT_WRITE")
add_check("official_service_readback", all(required_services %in% readback_status$step) && all(readback_status$status == c("KEY_BOUND", rep("PASS", nrow(readback_status) - 1L))), paste(nrow(readback_status), "service checks"))

sample_validation <- read_csv(file.path(gate_dir, "ecos_sample_validation.csv"), col_types = cols(.default = col_character()), na = character())
pagination <- read_csv(file.path(gate_dir, "ecos_pagination_validation.csv"), show_col_types = FALSE)
add_check("sample_collection", sample_validation$status[sample_validation$test == "recent_sample"] == "PASS", sample_validation$detail[sample_validation$test == "recent_sample"])
add_check("pagination", pagination$status == "PASS" && pagination$rows > ECOS_PAGE_SIZE && pagination$duplicate_keys == 0L, paste(pagination$rows, "rows across at least", pagination$pages_minimum, "pages"))
add_check("pending_source", sample_validation$status[sample_validation$test == "future_unpublished"] == "PENDING_SOURCE", "Future unpublished data produced no fabricated row")

update_log <- read_csv(file.path(app_dir, "ecos_update_log.csv"), col_types = cols(.default = col_character()), na = character())
full_batches <- update_log %>% filter(mode == "FULL_HISTORY") %>% distinct(batch_id)
incremental_batches <- update_log %>% filter(mode == "INCREMENTAL_OVERLAP_5BD") %>% distinct(batch_id)
latest_batch <- update_log %>% filter(batch_id == tail(unique(batch_id), 1L))
add_check("full_history_collection", nrow(full_batches) >= 1L && sum(update_log$mode == "FULL_HISTORY") == 18L, "18 full-history series logged")
add_check("overlap_incremental", nrow(incremental_batches) >= 1L && nrow(latest_batch) == 18L && all(latest_batch$mode == "INCREMENTAL_OVERLAP_5BD"), "18 series used five-business-day overlap")
add_check("incremental_no_row_growth", nrow(ecos) == 125625L, "Incremental rerun retained 125,625 unique rows")

staging_files <- list.files(app_dir, pattern = "\\.staging$", full.names = TRUE)
add_check("no_unpublished_staging", length(staging_files) == 0L, "No staging file remains after publication")

temp_target <- file.path(tempdir(), "gate2_atomic_test.fst")
file.copy(ecos_path, temp_target, overwrite = TRUE)
temp_hash_before <- sha256_file(temp_target)
invalid <- bind_rows(ecos[1:2, ], ecos[1, ])
failure_caught <- inherits(try(atomic_publish_ecos_fst(invalid, temp_target), silent = TRUE), "try-error")
temp_hash_after <- sha256_file(temp_target)
add_check("atomic_failure_preserves_last_good", failure_caught && identical(temp_hash_before, temp_hash_after), "Invalid duplicate-key staging was rejected and target hash stayed unchanged")
unlink(c(temp_target, paste0(temp_target, ".staging"), paste0(temp_target, ".last_good")))

key <- ecos_api_key()
text_files <- list.files(repo_dir, pattern = "\\.(R|csv|md|json)$", recursive = TRUE, full.names = TRUE)
leak_count <- 0L
if (!is.na(key) && nzchar(key)) {
  for (path in text_files) {
    content <- tryCatch(readLines(path, warn = FALSE, encoding = "UTF-8"), error = function(e) character())
    if (any(grepl(key, content, fixed = TRUE))) leak_count <- leak_count + 1L
  }
}
add_check("api_key_not_persisted", leak_count == 0L, "ECOS_API_KEY value found in 0 repository text files")

app_source <- readLines(file.path(app_dir, "app.R"), warn = FALSE, encoding = "UTF-8")
in_session_ecos_reference <- any(grepl("ecos_adapter|ECOS_API_KEY|original_ts_ecos", app_source, ignore.case = TRUE))
add_check("app_session_no_ecos_api", !in_session_ecos_reference, "Shiny app has no ECOS adapter, key, or ECOS store reference during Gate 2")

overall <- if (all(checks$status == "PASS")) "PASS" else "FAIL"
write_csv(checks, file.path(gate_dir, "gate2_validation.csv"))

series_inventory <- ecos %>%
  group_by(series_id) %>%
  summarize(rows = n(), start_date = min(date), end_date = max(date), latest_value = value[which.max(date)], .groups = "drop") %>%
  left_join(ecos_catalog %>% select(series_id, display_name, display_name_ko, stat_code, item_code1, unit), by = "series_id") %>%
  arrange(series_id)
write_csv(series_inventory, file.path(gate_dir, "ecos_series_inventory.csv"))

report <- c(
  "# Gate 2 ECOS Adapter Validation Report",
  "",
  paste0("**Result: ", overall, "**"),
  "",
  paste0("Validated: ", format(Sys.time(), tz = "Asia/Seoul", usetz = TRUE)),
  "",
  "## Scope",
  "",
  "- Environment-only ECOS authentication.",
  "- Official table, item, and metadata readback.",
  "- Code, item name, cycle, and unit contract validation.",
  "- Sample, pagination, full-history, and five-business-day overlap collection.",
  "- Staging validation, independent readback, and atomic publication.",
  "",
  "## Checks",
  "",
  "| Check | Status | Detail |",
  "|---|---|---|",
  paste0("| ", checks$check, " | ", checks$status, " | ", gsub("\\|", "\\\\|", checks$detail), " |"),
  "",
  "## Publication Inventory",
  "",
  paste0("- ECOS: ", format(nrow(ecos), big.mark = ","), " rows, ", n_distinct(ecos$series_id), " series, ", min(ecos$date), " to ", max(ecos$date), "."),
  "- Catalog: 18 official contracts verified; `SPECIAL_AAA_03Y` recorded as `SOURCE_NOT_AVAILABLE`.",
  "- Latest daily observations may be `SUCCESS_PENDING_SOURCE`; no non-business-day or fabricated rows are generated.",
  "- `USDKRW=X` and `ECOS_USDKRW` remain separate series.",
  "",
  "## Decision",
  "",
  if (overall == "PASS") c(
    "- `ECOS_KEY_BINDING_PASS`",
    "- `ECOS_OFFICIAL_READBACK_PASS`",
    "- `ECOS_FULL_AND_INCREMENTAL_PASS`",
    "- `ECOS_DUPLICATE_KEY_ZERO`",
    "- `ECOS_ATOMIC_PUBLICATION_PASS`",
    "- `GATE_2_CLOSED_PASS`",
    "- `GATE_3_APPROVED_TO_START`"
  ) else "- `GATE_2_VALIDATION_FAILED`"
)
writeLines(report, file.path(gate_dir, "GATE2_VALIDATION_REPORT.md"), useBytes = TRUE)

cat("Gate 2 validation: ", overall, " (", sum(checks$status == "PASS"), "/", nrow(checks), " checks passed)\n", sep = "")
if (overall != "PASS") quit(status = 1L)

