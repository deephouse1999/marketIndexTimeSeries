suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tibble)
})

script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
script_path <- if (length(script_arg)) sub("^--file=", "", script_arg[[1]]) else file.path("scripts", "migrate_catalog_gate1.R")
repo_dir <- normalizePath(file.path(dirname(script_path), ".."), winslash = "/", mustWork = TRUE)
catalog_path <- file.path(repo_dir, "apps", "timeseries", "series_catalog.csv")
gate_dir <- file.path(repo_dir, "docs", "gate1")
backup_path <- file.path(gate_dir, "series_catalog_pre_gate1.csv")

dir.create(gate_dir, recursive = TRUE, showWarnings = FALSE)
if (!file.exists(backup_path)) file.copy(catalog_path, backup_path, overwrite = FALSE)

column_order <- c(
  "source", "series_id", "display_name", "display_name_ko", "series_cls",
  "series_group", "sector", "industry", "region", "currency",
  "benchmark_series", "price_policy", "stat_code", "cycle", "item_code1",
  "item_code2", "item_code3", "item_code4", "unit", "transform",
  "collect_flag", "default_visible", "active", "display_order", "notes"
)

catalog <- read_csv(
  catalog_path,
  col_types = cols(.default = col_character()),
  show_col_types = FALSE,
  na = character()
)

character_cols <- setdiff(column_order, c("collect_flag", "default_visible", "active", "display_order"))
for (nm in setdiff(character_cols, names(catalog))) catalog[[nm]] <- ""
for (nm in c("collect_flag", "default_visible")) {
  if (!nm %in% names(catalog)) catalog[[nm]] <- as.logical(catalog$active)
}
if (!"active" %in% names(catalog)) catalog$active <- TRUE
if (!"display_order" %in% names(catalog)) catalog$display_order <- seq_len(nrow(catalog))

catalog <- catalog %>%
  mutate(
    across(all_of(character_cols), ~ ifelse(is.na(.x), "", as.character(.x))),
    source = toupper(trimws(source)),
    series_id = trimws(series_id),
    collect_flag = as.logical(collect_flag),
    default_visible = as.logical(default_visible),
    active = as.logical(active),
    display_order = as.integer(display_order),
    transform = case_when(
      series_id %in% c("CPIAUCSL", "CPILFESL", "PPIACO") ~ "yoy",
      TRUE ~ transform
    )
  )

set_fields <- function(data, source_value, series_value, values) {
  idx <- data$source == source_value & data$series_id == series_value
  if (!any(idx)) stop("Series not found for metadata correction: ", source_value, ":", series_value)
  for (nm in names(values)) data[[nm]][idx] <- values[[nm]]
  data
}

append_if_missing <- function(data, row) {
  exists <- data$source == row$source & data$series_id == row$series_id
  if (any(exists)) return(data)
  bind_rows(data, as_tibble(row)[, column_order])
}

new_row <- function(source, series_id, display_name, display_name_ko, series_cls,
                    series_group, sector = "", industry = "", region = "US",
                    currency = "USD", benchmark_series = "", price_policy = "close",
                    stat_code = "", cycle = "", item_code1 = "", item_code2 = "",
                    item_code3 = "", item_code4 = "", unit = "", transform = "",
                    collect_flag = TRUE, default_visible = TRUE, active = TRUE,
                    display_order, notes = "") {
  tibble(
    source, series_id, display_name, display_name_ko, series_cls, series_group,
    sector, industry, region, currency, benchmark_series, price_policy,
    stat_code, cycle, item_code1, item_code2, item_code3, item_code4, unit,
    transform, collect_flag, default_visible, active, display_order, notes
  )
}

corrections <- list(
  list("FRED", "DFEDTAR", list(display_name = "Federal Funds Target Rate (Discontinued)", display_name_ko = "연방기금 목표금리(중단)", series_cls = "rate", series_group = "policy", cycle = "D", unit = "Percent", notes = "Discontinued Federal Funds target rate")),
  list("FRED", "DFEDTARU", list(display_name = "Federal Funds Target Range Upper Limit", display_name_ko = "연방기금 목표금리 범위 상단", series_cls = "rate", series_group = "policy", cycle = "D", unit = "Percent", notes = "Federal Funds target range upper limit")),
  list("FRED", "BAMLC0A1CAAAEY", list(display_name = "US AAA Corporate Effective Yield", display_name_ko = "미국 AAA 회사채 유효수익률", series_cls = "credit", series_group = "credit", cycle = "D", unit = "Percent")),
  list("FRED", "BAMLC0A2CAAEY", list(display_name = "US AA Corporate Effective Yield", display_name_ko = "미국 AA 회사채 유효수익률", series_cls = "credit", series_group = "credit", cycle = "D", unit = "Percent")),
  list("FRED", "BAMLC0A3CAEY", list(display_name = "US Single-A Corporate Effective Yield", display_name_ko = "미국 A 회사채 유효수익률", series_cls = "credit", series_group = "credit", cycle = "D", unit = "Percent")),
  list("FRED", "BAMLC0A4CBBBEY", list(display_name = "US BBB Corporate Effective Yield", display_name_ko = "미국 BBB 회사채 유효수익률", series_cls = "credit", series_group = "credit", cycle = "D", unit = "Percent")),
  list("FRED", "BAMLH0A0HYM2EY", list(display_name = "US High Yield Effective Yield", display_name_ko = "미국 하이일드 유효수익률", series_cls = "credit", series_group = "credit", cycle = "D", unit = "Percent")),
  list("FRED", "WPSFD4131", list(display_name = "Core Finished Goods PPI", display_name_ko = "근원 완제품 PPI", series_cls = "inflation", series_group = "macro", cycle = "M", unit = "Index 1982=100", notes = "Finished goods less foods and energy")),
  list("FRED", "B935RC1Q027SBEA", list(display_name = "Computer & Peripheral Equipment Investment", display_name_ko = "컴퓨터·주변기기 투자", series_cls = "investment", series_group = "macro", cycle = "Q", unit = "Billions USD", notes = "Private fixed investment in computers and peripheral equipment")),
  list("FRED", "WTISPLC", list(display_name = "WTI Spot Price", display_name_ko = "WTI 현물가격", series_cls = "commodity", series_group = "macro", cycle = "M", unit = "USD per barrel", notes = "Spot West Texas Intermediate crude oil price")),
  list("YAHOO", "AGGG.L", list(display_name = "Global Aggregate Bond ETF", display_name_ko = "글로벌 종합채권 ETF", series_cls = "broad_etf", notes = "Global aggregate bond proxy")),
  list("YAHOO", "^VIX", list(series_cls = "volatility_index", series_group = "volatility")),
  list("YAHOO", "^BVSP", list(series_cls = "emerging_market_index", series_group = "regional_comparison", benchmark_series = "^KS11", collect_flag = TRUE, default_visible = TRUE, active = TRUE, notes = "included_in_regional_view; no_standalone_module; large_em_market_comparison")),
  list("YAHOO", "^TOPX", list(collect_flag = FALSE, default_visible = FALSE, active = TRUE, notes = "INTENTIONALLY_CATALOG_ONLY; unsupported Yahoo TOPIX symbol; replacement source pending"))
)
for (item in corrections) catalog <- set_fields(catalog, item[[1]], item[[2]], item[[3]])

catalog <- append_if_missing(catalog, new_row("FRED", "DFEDTARL", "Federal Funds Target Range Lower Limit", "연방기금 목표금리 범위 하단", "rate", "policy", cycle = "D", unit = "Percent", display_order = 143, notes = "Federal Reserve policy rate"))
catalog <- append_if_missing(catalog, new_row("FRED", "DFII10", "US 10Y Real Treasury Yield", "미국 10년 실질국채금리", "rate", "rates", cycle = "D", unit = "Percent", display_order = 144, notes = "Inflation-indexed Treasury yield"))
catalog <- append_if_missing(catalog, new_row("FRED", "T10YIE", "US 10Y Breakeven Inflation Rate", "미국 10년 기대인플레이션", "rate", "rates", cycle = "D", unit = "Percent", display_order = 145, notes = "10-year breakeven inflation"))
catalog <- append_if_missing(catalog, new_row("FRED", "DFF", "Effective Federal Funds Rate", "실효 연방기금금리", "rate", "policy", cycle = "D", unit = "Percent", display_order = 146, notes = "Federal Reserve policy rate"))
catalog <- append_if_missing(catalog, new_row("FRED", "SOFR", "Secured Overnight Financing Rate", "담보부 익일물 조달금리", "rate", "policy", cycle = "D", unit = "Percent", display_order = 147, notes = "US overnight funding rate"))

catalog <- append_if_missing(catalog, new_row("YAHOO", "SHY", "iShares 1-3 Year Treasury Bond ETF", "미국 단기국채 ETF", "broad_etf", "bond_etf", region = "US", price_policy = "adjusted", display_order = 507, notes = "Treasury duration"))
catalog <- append_if_missing(catalog, new_row("YAHOO", "IEF", "iShares 7-10 Year Treasury Bond ETF", "미국 중기국채 ETF", "broad_etf", "bond_etf", region = "US", price_policy = "adjusted", display_order = 508, notes = "Treasury duration"))
catalog <- append_if_missing(catalog, new_row("YAHOO", "TLT", "iShares 20+ Year Treasury Bond ETF", "미국 장기국채 ETF", "broad_etf", "bond_etf", region = "US", price_policy = "adjusted", display_order = 509, notes = "Treasury duration"))
catalog <- append_if_missing(catalog, new_row("YAHOO", "LQD", "iShares Investment Grade Corporate Bond ETF", "미국 투자등급 회사채 ETF", "broad_etf", "credit", region = "US", price_policy = "adjusted", display_order = 510, notes = "Credit risk proxy"))
catalog <- append_if_missing(catalog, new_row("YAHOO", "HYG", "iShares High Yield Corporate Bond ETF", "미국 하이일드 회사채 ETF", "broad_etf", "credit", region = "US", price_policy = "adjusted", display_order = 511, notes = "Credit risk proxy"))
catalog <- append_if_missing(catalog, new_row("YAHOO", "SOXQ", "Invesco PHLX Semiconductor ETF", "SOXQ 반도체 ETF", "industry_etf", "industries", sector = "Technology", industry = "Semiconductors", region = "US", benchmark_series = "SOXX", price_policy = "adjusted", display_order = 512, notes = "Semiconductor industry"))
catalog <- append_if_missing(catalog, new_row("YAHOO", "005930.KS", "Samsung Electronics", "삼성전자", "signal_stock", "signal", sector = "Technology", industry = "Semiconductors", region = "KR", currency = "KRW", benchmark_series = "SOXX", price_policy = "adjusted", display_order = 513, notes = "analysis_group=semiconductor_korea;link_role=kr_samsung"))
catalog <- append_if_missing(catalog, new_row("YAHOO", "HG=F", "Copper Futures", "구리 선물", "commodity", "commodity", region = "Global", currency = "USD", price_policy = "adjusted", display_order = 514, notes = "Industrial metals proxy"))

deactivate_collection <- c("AAPL", "GOOG", "TSLA", "META", "LLY", "ZC=F", "HE=F")
catalog <- catalog %>%
  mutate(
    collect_flag = ifelse(source == "YAHOO" & series_id %in% deactivate_collection, FALSE, collect_flag),
    default_visible = ifelse(source == "YAHOO" & series_id %in% deactivate_collection, FALSE, default_visible),
    default_visible = ifelse(source == "YAHOO" & series_id %in% c("^FTSE", "^GDAXI", "ACWI", "URTH"), FALSE, default_visible)
  )

catalog <- catalog %>%
  select(all_of(column_order)) %>%
  arrange(display_order, source, series_id)

allowed_sources <- c("FRED", "YAHOO", "ECOS")
allowed_classes <- c(
  "broad_index", "broad_etf", "global_etf", "country_etf", "sector_etf",
  "industry_etf", "signal_stock", "legacy_stock", "rate", "credit", "forex",
  "commodity", "gdp", "employment", "emerging_market_etf", "gvt_debt",
  "investment", "labor", "general_inflation", "inflation", "macro", "policy",
  "volatility", "volatility_index", "etf", "sectors", "industries",
  "emerging_market_index", "index_constituent"
)

stopifnot(
  identical(names(catalog), column_order),
  nrow(catalog %>% count(source, series_id) %>% filter(n > 1)) == 0,
  all(catalog$source %in% allowed_sources),
  all(catalog$series_cls %in% allowed_classes),
  all(catalog$cycle %in% c("", "D", "M", "Q", "A")),
  all(catalog$price_policy %in% c("close", "adjusted")),
  all(nzchar(catalog$display_name)),
  all(nzchar(catalog$display_name_ko)),
  nrow(catalog) >= 115
)

write_csv(catalog, catalog_path, na = "")
message("Gate 1 catalog migration complete: ", nrow(catalog), " rows, ", ncol(catalog), " columns")

