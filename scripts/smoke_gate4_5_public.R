#!/usr/bin/env Rscript

gate_r_lib <- "C:/Users/yjh14/AppData/Local/R/win-library/4.5"
if (dir.exists(gate_r_lib)) .libPaths(c(gate_r_lib, .libPaths()))
suppressPackageStartupMessages({ library(chromote); library(jsonlite); library(readr) })

url <- "https://deephouse1999.shinyapps.io/market_timeseries/"
gate_dir <- file.path("docs", "gate4_5")
dir.create(gate_dir, recursive = TRUE, showWarnings = FALSE)
browser <- ChromoteSession$new()
on.exit(try(browser$close(), silent = TRUE), add = TRUE)
browser$Emulation$setDeviceMetricsOverride(width = 1440, height = 1100, deviceScaleFactor = 1, mobile = FALSE)

eval_js <- function(code) browser$Runtime$evaluate(expression = code, returnByValue = TRUE)$result$value
wait_for <- function(code, timeout = 120) {
  started <- Sys.time()
  repeat {
    if (isTRUE(tryCatch(eval_js(code), error = function(e) FALSE))) return(TRUE)
    if (as.numeric(difftime(Sys.time(), started, units = "secs")) > timeout) return(FALSE)
    Sys.sleep(0.1)
  }
}
click_text <- function(selector, label) eval_js(paste0(
  "(() => { const x=[...document.querySelectorAll(", toJSON(selector, auto_unbox = TRUE), ")].find(v=>v.textContent.trim()===",
  toJSON(label, auto_unbox = TRUE), "); if(!x)return false; x.click(); return true; })()"
))
text_of <- function(selector) eval_js(paste0("(() => { const x=document.querySelector(", toJSON(selector, auto_unbox = TRUE), "); return x ? x.innerText : ''; })()"))
points <- function(id) eval_js(sprintf("(() => { const x=document.getElementById('%s'); return x&&x.data ? x.data.reduce((n,t)=>n+((t.x||[]).length),0) : 0; })()", id))

browser$Page$navigate(url)
browser$Page$loadEventFired(wait_ = TRUE)
connected <- wait_for("window.Shiny && Shiny.shinyapp && Shiny.shinyapp.$socket && Shiny.shinyapp.$socket.readyState===1 && !document.body.classList.contains('shiny-busy')")
nav_text <- text_of(".navbar")

checks <- data.frame(check_id = character(), actual = character(), result = character())
add <- function(id, actual, pass) checks <<- rbind(checks, data.frame(check_id = id, actual = as.character(actual), result = if (isTRUE(pass)) "PASS" else "FAIL"))
add("public_shiny_connected", connected, connected)
add("public_gate_tabs", nav_text, all(vapply(c("Korea Rates & Funding", "SOX Constituents", "Semiconductor & Korea Link"), grepl, logical(1), x = nav_text, fixed = TRUE)))

clicked_link <- isTRUE(click_text(".navbar a", "Semiconductor & Korea Link"))
wait_for("!document.body.classList.contains('shiny-busy')")
clicked_physical <- isTRUE(click_text("#link_subtab a", "Physical Indicators"))
physical_ready <- wait_for("document.querySelector('#physical_status') && document.querySelector('#physical_status').innerText.includes('Bank of Korea ECOS')", timeout = 60)
status <- text_of("#physical_status")
body <- text_of("body")
physical_ready <- physical_ready && points("dram_physical_plot") >= 100 && points("flash_physical_plot") >= 100
add("public_physical_navigation", paste(clicked_link, clicked_physical, physical_ready, sep = "/"), clicked_link && clicked_physical && physical_ready)
add("public_physical_metadata", status, all(vapply(c("Bank of Korea ECOS", "monthly", "2020=100", "VERIFIED_SOURCE"), grepl, logical(1), x = status, fixed = TRUE)))
add("public_physical_semantics", grepl("reference-month alignment", body, fixed = TRUE), grepl("reference-month alignment", body, fixed = TRUE) && grepl("not TrendForce", body, fixed = TRUE))
add("public_dram_plot", points("dram_physical_plot"), points("dram_physical_plot") >= 100)
add("public_flash_plot", points("flash_physical_plot"), points("flash_physical_plot") >= 100)

click_text(".navbar a", "Series Explorer")
wait_for("document.querySelector('#currentChangeTable table')", timeout = 60)
eval_js("Shiny.setInputValue('f_group','physical_indicator',{priority:'event'}); Shiny.setInputValue('f_search','BWET',{priority:'event'}); true")
bwet_ready <- wait_for("document.querySelector('#currentChangeTable').innerText.includes('BWET_VLCC_PROXY')", timeout = 60)
table_text <- text_of("#currentChangeTable")
add("public_bwet_visible", table_text, bwet_ready && grepl("Tanker Freight Futures ETF Proxy", table_text, fixed = TRUE))
eval_js("Shiny.setInputValue('currentChangeTable_rows_selected',[1],{priority:'event'}); true")
proxy_ready <- wait_for("document.querySelector('#series_proxy_note') && document.querySelector('#series_proxy_note').innerText.includes('not a VLCC spot rate')", timeout = 60)
proxy_text <- text_of("#series_proxy_note")
add("public_bwet_proxy_warning", proxy_text, proxy_ready && grepl("tracking error", proxy_text, fixed = TRUE))

browser$screenshot(filename = file.path(gate_dir, "public_gate4_5.png"), selector = "body")
write_csv(checks, file.path(gate_dir, "public_smoke_checks.csv"))
bundle <- read.dcf(file.path("apps", "timeseries", "rsconnect", "shinyapps.io", "deephouse1999", "market_timeseries.dcf"))[1, "bundleId"]
ok <- nrow(checks) == 9L && all(checks$result == "PASS")
writeLines(c(
  "# Gate 4.5 Public URL Smoke", "", paste0("URL: ", url), paste0("Bundle: `", bundle, "`"),
  paste0("Result: ", if (ok) "PASS" else "FAIL", " (", sum(checks$result == "PASS"), "/", nrow(checks), ")")
), file.path(gate_dir, "PUBLIC_URL_SMOKE.md"))
cat("Gate 4.5 public smoke: ", if (ok) "PASS" else "FAIL", " (", sum(checks$result == "PASS"), "/", nrow(checks), ") bundle ", bundle, "\n", sep = "")
if (!ok) quit(status = 1L)
