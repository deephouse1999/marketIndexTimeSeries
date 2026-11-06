suppressPackageStartupMessages(library(chromote))
repo_dir <- normalizePath(".", winslash = "/", mustWork = TRUE)
gate_dir <- file.path(repo_dir, "docs", "gate4")
browser <- ChromoteSession$new(); on.exit(browser$close(), add = TRUE)
browser$Emulation$setDeviceMetricsOverride(width = 1440, height = 1000, deviceScaleFactor = 1, mobile = FALSE)
browser$Page$navigate("http://127.0.0.1:5414/"); browser$Page$loadEventFired(wait_ = TRUE); Sys.sleep(2)
click <- function(selector, label) {
  js <- paste0("(() => { const xs=[...document.querySelectorAll('", selector, "')]; const x=xs.find(v=>v.textContent.trim()===", jsonlite::toJSON(label, auto_unbox=TRUE), "); if(!x)return false; x.click(); return true; })()")
  ok <- browser$Runtime$evaluate(expression = js, returnByValue = TRUE)$result$value
  if (!isTRUE(ok)) stop("Tab not found: ", label)
  Sys.sleep(2)
}
click("a", "SOX Constituents")
body <- browser$Runtime$evaluate(expression = "document.body.innerText", returnByValue = TRUE)$result$value
stopifnot(grepl("SOXQ proxy", body, fixed = TRUE), grepl("Historical membership before 2026-11-04", body, fixed = TRUE))
browser$screenshot(filename = file.path(gate_dir, "sox_overview.png"), selector = "body")
for (label in c("Breadth", "Contribution", "Value Chain", "Korea Link", "Constituents", "Data Quality")) {
  click("#sox_subtab a", label)
  browser$screenshot(filename = file.path(gate_dir, paste0("sox_", gsub(" ", "_", tolower(label)), ".png")), selector = "body")
}
cat("Gate 4 browser capture: PASS\n")
