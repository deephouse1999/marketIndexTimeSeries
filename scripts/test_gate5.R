#!/usr/bin/env Rscript

repo_dir <- normalizePath(Sys.getenv("MARKET_TS_REPO", unset = "."), winslash = "/", mustWork = TRUE)
source(file.path(repo_dir, "scripts", "gate5_common.R"), local = TRUE)

cases <- data.frame(
  test_id = c("US_DST", "US_STANDARD", "US_DST_WRONG_SLOT", "US_STANDARD_WRONG_SLOT", "KR_CLOSE", "KR_WEEKEND"),
  batch = c("us_close", "us_close", "us_close", "us_close", "kr_close", "kr_close"),
  now_kst = c("2026-07-07 07:05:00", "2026-11-10 08:05:00", "2026-07-07 08:05:00", "2026-11-10 07:05:00", "2026-11-09 16:05:00", "2026-11-08 16:05:00"),
  expected_eligible = c(TRUE, TRUE, FALSE, FALSE, TRUE, FALSE),
  expected_dst = c(TRUE, FALSE, TRUE, FALSE, FALSE, FALSE),
  stringsAsFactors = FALSE
)

results <- do.call(rbind, lapply(seq_len(nrow(cases)), function(i) {
  now <- as.POSIXct(cases$now_kst[[i]], tz = "Asia/Seoul")
  actual <- gate5_schedule_status(cases$batch[[i]], now)
  data.frame(
    test_id = cases$test_id[[i]], batch = cases$batch[[i]], now_kst = cases$now_kst[[i]],
    local_time = actual$local_time, expected_eligible = cases$expected_eligible[[i]],
    actual_eligible = actual$eligible, expected_dst = cases$expected_dst[[i]],
    actual_dst = actual$new_york_dst,
    result = if (identical(actual$eligible, cases$expected_eligible[[i]]) && identical(actual$new_york_dst, cases$expected_dst[[i]])) "PASS" else "FAIL",
    stringsAsFactors = FALSE
  )
}))

tmp <- file.path(repo_dir, "batch_staging", paste0("gate5_publish_test_", Sys.getpid()))
on.exit(unlink(tmp, recursive = TRUE, force = TRUE), add = TRUE)
stage <- file.path(tmp, "stage")
live <- file.path(tmp, "live")
dir.create(file.path(stage, "data"), recursive = TRUE)
dir.create(file.path(live, "data"), recursive = TRUE)
writeLines("new-a", file.path(stage, "data", "a.txt"))
writeLines("new-b", file.path(stage, "data", "b.txt"))
writeLines("old-a", file.path(live, "data", "a.txt"))
writeLines("old-b", file.path(live, "data", "b.txt"))
Sys.setenv(GATE5_FAIL_AFTER_PUBLISH_N = "1")
injected <- try(gate5_atomic_publish(stage, live, c("data/a.txt", "data/b.txt"), "ROLLBACK_TEST"), silent = TRUE)
Sys.unsetenv("GATE5_FAIL_AFTER_PUBLISH_N")
rollback_pass <- inherits(injected, "try-error") &&
  grepl("INJECTED_PUBLICATION_FAILURE_AFTER_1", as.character(injected), fixed = TRUE) &&
  identical(readLines(file.path(live, "data", "a.txt")), "old-a") &&
  identical(readLines(file.path(live, "data", "b.txt")), "old-b")
results <- rbind(results, data.frame(
  test_id = "ATOMIC_ROLLBACK", batch = "publication", now_kst = NA_character_, local_time = NA_character_,
  expected_eligible = TRUE, actual_eligible = rollback_pass, expected_dst = NA, actual_dst = NA,
  result = if (rollback_pass) "PASS" else "FAIL", stringsAsFactors = FALSE
))

out_dir <- file.path(repo_dir, "docs", "gate5")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
write.csv(results, file.path(out_dir, "gate5_schedule_and_rollback_tests.csv"), row.names = FALSE, na = "")
unlink(tmp, recursive = TRUE, force = TRUE)
if (any(results$result != "PASS")) stop("GATE5_FOUNDATION_TEST_FAILED")
cat("Gate 5 foundation tests: PASS (", nrow(results), "/", nrow(results), ")\n", sep = "")
