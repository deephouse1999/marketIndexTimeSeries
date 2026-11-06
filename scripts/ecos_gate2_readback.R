suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tibble)
})

script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
script_path <- if (length(script_arg)) sub("^--file=", "", script_arg[[1]]) else file.path("scripts", "ecos_gate2_readback.R")
repo_dir <- normalizePath(file.path(dirname(script_path), ".."), winslash = "/", mustWork = TRUE)
app_dir <- file.path(repo_dir, "apps", "timeseries")
gate_dir <- file.path(repo_dir, "docs", "gate2")
dir.create(gate_dir, recursive = TRUE, showWarnings = FALSE)

source(file.path(app_dir, "ecos_adapter.R"), local = TRUE)

status_path <- file.path(gate_dir, "ecos_readback_status.csv")
status_rows <- tibble(
  checked_at = format(Sys.time(), tz = "Asia/Seoul", usetz = TRUE),
  step = "ECOS_API_KEY",
  status = ecos_key_status(),
  detail = if (ecos_key_status() == "KEY_BOUND") "Environment variable is bound; value not logged" else "Set ECOS_API_KEY before official readback"
)

if (ecos_key_status() != "KEY_BOUND") {
  write_csv(status_rows, status_path)
  cat("Gate 2 readback: SKIPPED_NO_KEY\n")
  quit(status = 2L)
}

record_step <- function(step, expression) {
  tryCatch({
    result <- force(expression)
    status_rows <<- bind_rows(status_rows, tibble(
      checked_at = format(Sys.time(), tz = "Asia/Seoul", usetz = TRUE),
      step = step, status = "PASS", detail = paste(nrow(result), "rows")
    ))
    result
  }, error = function(e) {
    status_rows <<- bind_rows(status_rows, tibble(
      checked_at = format(Sys.time(), tz = "Asia/Seoul", usetz = TRUE),
      step = step, status = "FAIL", detail = conditionMessage(e)
    ))
    write_csv(status_rows, status_path)
    stop(e)
  })
}

tables <- record_step("StatisticTableList", ecos_statistic_table_list())
write_csv(tables, file.path(gate_dir, "statistic_table_list.csv"))

meta <- record_step(
  "StatisticMeta",
  ecos_statistic_meta("\uACBD\uC81C\uC2EC\uB9AC\uC9C0\uC218")
)
write_csv(meta, file.path(gate_dir, "statistic_meta_economic_sentiment.csv"))

stat_codes <- c("722Y001", "817Y002", "731Y001")
items <- bind_rows(lapply(stat_codes, function(code) {
  record_step(paste0("StatisticItemList:", code), ecos_statistic_item_list(code))
}))
write_csv(items, file.path(gate_dir, "statistic_item_list_raw.csv"))

snapshot <- normalize_ecos_item_snapshot(items)
write_csv(snapshot, file.path(app_dir, "ecos_item_snapshot.csv"))
write_csv(snapshot, file.path(gate_dir, "ecos_item_snapshot.csv"))

target_codes <- c(
  "0101000",
  "010101000", "010190000", "010195000", "010200000", "010200001",
  "010210000", "010220000", "010230000", "010240000", "010300000",
  "010320000", "010400000", "010400001", "010400002", "010502000",
  "010503000"
)
target_candidates <- snapshot %>%
  filter(item_code %in% target_codes | stat_code == "731Y001") %>%
  arrange(stat_code, item_name, item_code)
write_csv(target_candidates, file.path(gate_dir, "ecos_target_candidates.csv"))

status_rows <- bind_rows(status_rows, tibble(
  checked_at = format(Sys.time(), tz = "Asia/Seoul", usetz = TRUE),
  step = "ITEM_SNAPSHOT_WRITE",
  status = "PASS",
  detail = paste(nrow(snapshot), "official item rows;", nrow(target_candidates), "target-name candidates")
))
write_csv(status_rows, status_path)
cat("Gate 2 official readback: PASS (", nrow(snapshot), " item rows)\n", sep = "")

