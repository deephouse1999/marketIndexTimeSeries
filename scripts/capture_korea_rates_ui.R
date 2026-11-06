suppressPackageStartupMessages(library(chromote))

repo_dir <- normalizePath(".", winslash = "/", mustWork = TRUE)
output_path <- file.path(repo_dir, "docs", "gate3", "korea_rates_ui.png")

browser <- ChromoteSession$new()
on.exit(browser$close(), add = TRUE)
browser$Emulation$setDeviceMetricsOverride(width = 1440, height = 1000, deviceScaleFactor = 1, mobile = FALSE)
browser$Page$navigate("http://127.0.0.1:5412/")
browser$Page$loadEventFired(wait_ = TRUE)
Sys.sleep(3)

click_result <- browser$Runtime$evaluate(
  expression = "(() => { const links=[...document.querySelectorAll('a')]; const target=links.find(x => x.textContent.trim()==='Korea Rates & Funding'); if(!target) return false; target.click(); return true; })()",
  returnByValue = TRUE
)
if (!isTRUE(click_result$result$value)) stop("Korea Rates & Funding tab was not found")
Sys.sleep(6)

body_text <- browser$Runtime$evaluate(
  expression = "document.body.innerText",
  returnByValue = TRUE
)$result$value
required_text <- c("Korea Treasury yield curve", "Major maturity changes (bp)", "Latest funding and credit spreads")
if (!all(vapply(required_text, grepl, logical(1), x = body_text, fixed = TRUE))) {
  stop("Rendered initial page is missing required Korea Rates outputs")
}

browser$screenshot(filename = output_path, selector = "body")

click_subtab <- function(label) {
  result <- browser$Runtime$evaluate(
    expression = paste0("(() => { const links=[...document.querySelectorAll('#kr_subtab a')]; const target=links.find(x => x.textContent.trim()===", jsonlite::toJSON(label, auto_unbox = TRUE), "); if(!target) return false; target.click(); return true; })()"),
    returnByValue = TRUE
  )
  if (!isTRUE(result$result$value)) stop("Korea Rates subtab was not found: ", label)
  Sys.sleep(3)
}

click_subtab("Funding & Credit Spreads")
browser$screenshot(filename = file.path(repo_dir, "docs", "gate3", "korea_rates_ui_spread.png"), selector = "#kr_spread_plot")
click_subtab("Korea-US Link")
browser$screenshot(filename = file.path(repo_dir, "docs", "gate3", "korea_rates_ui_kr_us.png"), selector = "#kr_us_plot")
browser$screenshot(filename = file.path(repo_dir, "docs", "gate3", "korea_rates_ui_rolling.png"), selector = "#kr_rolling_plot")
click_subtab("FX Link")
browser$screenshot(filename = file.path(repo_dir, "docs", "gate3", "korea_rates_ui_fx.png"), selector = "#kr_fx_plot")
click_subtab("Data Quality")
browser$screenshot(filename = file.path(repo_dir, "docs", "gate3", "korea_rates_ui_quality.png"), selector = "body")
cat("Gate 3 browser capture: PASS -> ", output_path, "\n", sep = "")

