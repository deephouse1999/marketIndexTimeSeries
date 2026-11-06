gate6_r_lib <- "C:/Users/yjh14/AppData/Local/R/win-library/4.5"
if (dir.exists(gate6_r_lib)) .libPaths(c(gate6_r_lib, .libPaths()))
Sys.setenv(NOT_CRAN = "true")

suppressPackageStartupMessages({
  library(readr)
  library(shinytest2)
  library(tibble)
})

repo_dir <- normalizePath(".", winslash = "/", mustWork = TRUE)
app_dir <- file.path(repo_dir, "apps", "timeseries")
gate_dir <- file.path(repo_dir, "docs", "gate6")
dir.create(gate_dir, recursive = TRUE, showWarnings = FALSE)

app <- AppDriver$new(app_dir, name = "ui-remediation", load_timeout = 120000, seed = 20261106,
                     width = 1600, height = 1000)
on.exit(app$stop(), add = TRUE)

checks <- tibble(check = character(), result = character())
record <- function(name, ok) {
  checks <<- add_row(checks, check = name, result = ifelse(isTRUE(ok), "PASS", "FAIL"))
}
has_finite_trace <- function(id, trace_type = NULL) {
  value <- app$get_js(sprintf(
    "(() => { const root=document.getElementById('%s'); if(!root) return 'NO_ROOT'; const p=root.data ? root : (root.querySelector('.js-plotly-plot') || root.querySelector('.plotly')); if(!p) return 'NO_PLOT'; if(!p.data) return 'NO_DATA'; return JSON.stringify(p.data.map(t => ({type:t.type, mode:t.mode, nx:t.x?.length || 0, ny:t.y?.length || 0, finite:[t.x,t.y].some(a => a && typeof a.length === 'number' && Array.from(a).some(v => Number.isFinite(Number(v))))}))); })()",
    id
  ))
  if (!is.character(value) || value %in% c("NO_ROOT", "NO_PLOT", "NO_DATA")) return(FALSE)
  traces <- jsonlite::fromJSON(value)
  any(traces$type == trace_type & traces$finite)
}

app$set_inputs(main_tab = "SOX Constituents", sox_subtab = "Breadth", wait_ = FALSE, timeout_ = 60000)
app$wait_for_idle(timeout = 60000)
record("breadth_has_visible_bar_data", has_finite_trace("sox_breadth_plot", "bar"))

app$set_inputs(sox_subtab = "Value Chain", wait_ = FALSE, timeout_ = 60000)
app$wait_for_idle(timeout = 60000)
record("value_chain_has_visible_bar_data", has_finite_trace("sox_chain_plot", "bar"))

app$set_inputs(sox_subtab = "Korea Link", wait_ = FALSE, timeout_ = 60000)
app$wait_for_idle(timeout = 60000)
options_text <- app$get_js("[...document.querySelectorAll('#sox_link_metric option')].map(x=>x.value+' '+x.textContent).join(' | ')")
record("korea_link_uses_kospi", grepl("\\^KS11", options_text) && !grepl("000660|005930", options_text))
record("korea_link_has_line_data", has_finite_trace("sox_korea_plot", "scatter"))

app$set_inputs(sox_subtab = "Contribution", wait_ = FALSE, timeout_ = 60000)
app$wait_for_idle(timeout = 60000)
has_ticker_payload <- app$get_js("(() => { const root=document.getElementById('sox_contribution_plot'); const p=root.data ? root : (root.querySelector('.js-plotly-plot') || root.querySelector('.plotly')); return Array.from(p.data[0].customdata || []).includes('NVDA'); })()")
record("contribution_has_ticker_click_payload", isTRUE(has_ticker_payload))
app$set_inputs(sox_selected_ticker = "NVDA", wait_ = FALSE, timeout_ = 60000, allow_no_input_binding_ = TRUE)
app$wait_for_idle(timeout = 60000)
detail <- app$get_js("document.querySelector('#sox_selected_company')?.innerText || ''")
record("contribution_description_output", nzchar(detail) && grepl("Value chain", detail) && grepl("Core products", detail) && grepl("Korea linkage", detail))

app$set_inputs(main_tab = "Semiconductor & Korea Link", wait_ = FALSE, timeout_ = 60000)
app$wait_for_idle(timeout = 60000)
record("cumulative_chart_has_line_data", has_finite_trace("link_cumulative_plot", "scatter"))
record("spread_chart_has_line_data", has_finite_trace("link_spread_plot", "scatter"))
record("rolling_chart_has_line_data", has_finite_trace("link_rolling_plot", "scatter"))

write_csv(checks, file.path(gate_dir, "ui_remediation_checks.csv"))
ok <- nrow(checks) == 9L && all(checks$result == "PASS")
cat("UI remediation: ", ifelse(ok, "PASS", "FAIL"), " (", sum(checks$result == "PASS"), "/", nrow(checks), ")\n", sep = "")
if (!ok) quit(status = 1L)
