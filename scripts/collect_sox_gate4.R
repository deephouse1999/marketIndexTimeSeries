suppressPackageStartupMessages({
  library(dplyr)
  library(fst)
  library(httr)
  library(jsonlite)
  library(quantmod)
  library(readr)
  library(tibble)
})

repo_dir <- normalizePath(".", winslash = "/", mustWork = TRUE)
app_dir <- file.path(repo_dir, "apps", "timeseries")
gate_dir <- file.path(repo_dir, "docs", "gate4")
dir.create(gate_dir, recursive = TRUE, showWarnings = FALSE)

nasdaq_url <- "https://indexes.nasdaqomx.com/Index/WeightingData"
invesco_url <- "https://dng-api.invesco.com/cache/v1/accounts/en_US/shareclasses/46138G615/holdings/fund?idType=cusip&productType=ETF"
membership_as_of <- as.Date(Sys.getenv("GATE5_EXPECTED_SESSION", unset = as.character(Sys.Date())))
if (is.na(membership_as_of)) stop("INVALID_MEMBERSHIP_AS_OF")

nasdaq_response <- POST(
  nasdaq_url,
  body = list(id = "SOX", tradeDate = as.character(membership_as_of), timeOfDay = "SOD"),
  encode = "form", timeout(60)
)
stop_for_status(nasdaq_response)
nasdaq_json <- content(nasdaq_response, as = "parsed", simplifyVector = TRUE)
official <- as_tibble(nasdaq_json$aaData) %>%
  transmute(ticker = Symbol, official_name = Name) %>%
  arrange(ticker)
if (nrow(official) != 30L || n_distinct(official$ticker) != 30L) {
  stop("NASDAQ_MEMBERSHIP_VALIDATION_FAILED")
}

invesco_response <- GET(invesco_url, timeout(60))
stop_for_status(invesco_response)
invesco_json <- content(invesco_response, as = "parsed", simplifyVector = TRUE)
holdings <- as_tibble(invesco_json$holdings) %>%
  filter(ticker %in% official$ticker) %>%
  transmute(
    ticker,
    proxy_name = issuerName,
    proxy_weight_decimal = as.numeric(percentageOfTotalNetAssets) / 100,
    security_type = securityTypeName
  )
if (!setequal(official$ticker, holdings$ticker) || nrow(holdings) != 30L) {
  stop("SOXQ_PROXY_MEMBERSHIP_MISMATCH")
}

profiles <- tribble(
  ~ticker, ~company_name, ~country, ~value_chain, ~core_products, ~end_market, ~korea_link,
  "ADI", "Analog Devices", "US", "Analog / Power", "analog and mixed-signal ICs", "industrial; automotive; communications", "Korean electronics demand and analog supply chain",
  "ALAB", "Astera Labs", "US", "Connectivity / RF", "data-center connectivity semiconductors", "AI and cloud data centers", "AI server memory and connectivity demand",
  "AMAT", "Applied Materials", "US", "Semiconductor Equipment", "wafer fabrication equipment", "foundry; logic; memory", "Samsung and SK hynix capex exposure",
  "AMD", "Advanced Micro Devices", "US", "AI / Compute", "CPU; GPU; accelerators", "PC; server; AI data center", "HBM and foundry demand",
  "ARM", "Arm Holdings", "UK", "AI / Compute", "CPU architecture and IP", "mobile; server; automotive", "Korean fabless and device ecosystem",
  "ASML", "ASML Holding", "Netherlands", "Semiconductor Equipment", "lithography systems", "foundry; logic; memory", "Samsung and SK hynix leading-edge capex",
  "AVGO", "Broadcom", "US", "Connectivity / RF", "networking; broadband; custom accelerators", "AI data center; communications", "HBM and AI server demand",
  "COHR", "Coherent", "US", "Materials / Process", "optical and compound semiconductor products", "data center; industrial; communications", "optical interconnect supply chain",
  "CRDO", "Credo Technology", "Cayman Islands", "Connectivity / RF", "high-speed connectivity semiconductors", "AI and cloud data centers", "AI server interconnect demand",
  "ENTG", "Entegris", "US", "Materials / Process", "materials and contamination control", "semiconductor manufacturing", "Korean fab materials demand",
  "GFS", "GlobalFoundries", "US", "Foundry", "specialty semiconductor foundry", "automotive; industrial; communications", "global foundry cycle comparison",
  "INTC", "Intel", "US", "AI / Compute", "CPU; accelerators; foundry", "PC; server; data center", "memory and foundry cycle linkage",
  "KLAC", "KLA", "US", "Semiconductor Equipment", "process control and metrology", "foundry; logic; memory", "Samsung and SK hynix capex exposure",
  "LRCX", "Lam Research", "US", "Semiconductor Equipment", "etch and deposition equipment", "foundry; logic; memory", "Korean memory capex exposure",
  "LSCC", "Lattice Semiconductor", "US", "AI / Compute", "low-power FPGA", "industrial; automotive; communications", "Korean electronics component demand",
  "MCHP", "Microchip Technology", "US", "Automotive / Industrial", "MCU; analog; connectivity", "industrial; automotive", "Korean automotive and industrial cycle",
  "MPWR", "Monolithic Power Systems", "US", "Analog / Power", "power management ICs", "data center; automotive; industrial", "AI server and electronics power demand",
  "MRVL", "Marvell Technology", "US", "Connectivity / RF", "data infrastructure semiconductors", "AI data center; carrier", "HBM and AI networking demand",
  "MTSI", "MACOM Technology Solutions", "US", "Connectivity / RF", "RF; microwave; optical semiconductors", "communications; data center; industrial", "optical and RF supply chain",
  "MU", "Micron Technology", "US", "Memory", "DRAM; NAND; HBM", "data center; mobile; PC", "direct Samsung and SK hynix peer",
  "NVDA", "NVIDIA", "US", "AI / Compute", "GPU; AI accelerators; networking", "AI and cloud data centers", "HBM demand and Korean memory cycle",
  "NXPI", "NXP Semiconductors", "Netherlands", "Automotive / Industrial", "automotive and industrial semiconductors", "automotive; industrial; IoT", "Korean automotive electronics demand",
  "ON", "onsemi", "US", "Automotive / Industrial", "power and sensing semiconductors", "automotive; industrial", "Korean EV and power semiconductor chain",
  "Q", "Qnity Electronics", "US", "Materials / Process", "electronics materials and interconnect solutions", "semiconductor and electronics manufacturing", "Korean semiconductor materials demand",
  "QCOM", "Qualcomm", "US", "Connectivity / RF", "mobile SoC; modem; RF", "mobile; automotive; IoT", "Samsung handset and foundry linkage",
  "SITM", "SiTime", "US", "Connectivity / RF", "MEMS timing", "data center; communications; industrial", "electronics timing supply chain",
  "TER", "Teradyne", "US", "Semiconductor Equipment", "automated test equipment", "semiconductor manufacturing", "Korean memory and logic test demand",
  "TSEM", "Tower Semiconductor", "Israel", "Foundry", "specialty analog foundry", "automotive; industrial; RF", "specialty foundry cycle comparison",
  "TSM", "Taiwan Semiconductor Manufacturing", "Taiwan", "Foundry", "advanced semiconductor foundry", "AI; mobile; automotive", "Samsung foundry peer and HBM demand",
  "TXN", "Texas Instruments", "US", "Analog / Power", "analog and embedded semiconductors", "industrial; automotive", "Korean industrial and auto electronics cycle"
)
profiles <- profiles %>%
  left_join(read_csv(file.path(app_dir, "sox_company_sources.csv"), show_col_types = FALSE), by = "ticker")

constituents <- official %>%
  left_join(holdings, by = "ticker") %>%
  left_join(profiles, by = "ticker") %>%
  transmute(
    index_id = "SOX", ticker, company_name, official_name, country,
    value_chain, core_products, end_market, korea_link,
    effective_from = membership_as_of, effective_to = as.Date(NA),
    membership_source = "NASDAQ_OFFICIAL",
    membership_source_url = "https://indexes.nasdaqomx.com/Index/Weighting/SOX",
    membership_as_of = membership_as_of,
    proxy_weight_decimal, weight_source = "SOXQ_PROXY",
    weight_source_url = "https://www.invesco.com/us/en/financial-products/etfs/invesco-phlx-semiconductor-etf.html",
    weight_as_of = as.Date(invesco_json$effectiveDate),
    quality_flag = "PROXY_WEIGHT_NOT_OFFICIAL_INDEX_WEIGHT",
    profile_source,
    profile_updated_at = Sys.Date()
  )
weight_history_path <- file.path(app_dir, "sox_weight_history.csv")
weight_snapshot <- constituents %>%
  select(ticker, proxy_weight_decimal, weight_source, weight_source_url, weight_as_of) %>%
  mutate(
    snapshot_type = "OFFICIAL_SOXQ_EOD",
    quality_flag = "PROXY_WEIGHT_NOT_OFFICIAL_INDEX_WEIGHT",
    reconstruction_basis = NA_character_
  )
weight_history <- if (file.exists(weight_history_path)) {
  bind_rows(read_csv(weight_history_path, show_col_types = FALSE), weight_snapshot) %>%
    mutate(weight_as_of = as.Date(weight_as_of)) %>%
    arrange(ticker, weight_as_of, desc(snapshot_type == "OFFICIAL_SOXQ_EOD")) %>%
    distinct(ticker, weight_as_of, .keep_all = TRUE) %>% arrange(weight_as_of, ticker)
} else {
  weight_snapshot
}
write_csv(weight_history, weight_history_path, na = "")
write_csv(weight_history, file.path(gate_dir, "sox_weight_history_evidence.csv"), na = "")
write_csv(constituents, file.path(app_dir, "sox_constituents.csv"), na = "")
write_csv(constituents, file.path(gate_dir, "official_membership_snapshot.csv"), na = "")
write_csv(
  constituents %>% select(ticker, proxy_weight_decimal, weight_source, weight_as_of, weight_source_url, quality_flag),
  file.path(gate_dir, "weight_source_evidence.csv"), na = ""
)

existing_path <- file.path(app_dir, "original_ts_yahoo.fst")
existing <- read.fst(existing_path, as.data.table = FALSE) %>% as_tibble()
existing_ids <- unique(existing$series_id)
required_ids <- c(constituents$ticker, "SOXQ", "005930.KS")
legacy_owned_ids <- c("NVDA", "MU")
collect_ids <- setdiff(required_ids, legacy_owned_ids)
target <- file.path(app_dir, "original_ts_sox_components.fst")
prior_components <- if (file.exists(target)) {
  read.fst(target, as.data.table = FALSE) %>% as_tibble() %>% mutate(date = as.Date(date))
} else {
  tibble(date = as.Date(character()), series_id = character(), close_value = numeric(),
         adjusted_value = numeric(), volume = numeric(), source = character(), collected_at = character())
}

collect_yahoo <- function(symbol, from) {
  x <- suppressWarnings(getSymbols(symbol, src = "yahoo", from = from, auto.assign = FALSE, warnings = FALSE))
  tibble(
    date = as.Date(index(x)), series_id = symbol,
    close_value = as.numeric(Cl(x)), adjusted_value = as.numeric(Ad(x)),
    volume = as.numeric(Vo(x)), source = "YAHOO",
    collected_at = format(Sys.time(), tz = "Asia/Seoul", usetz = TRUE)
  ) %>% filter(!is.na(close_value))
}

raw_list <- lapply(collect_ids, function(id) {
  prior <- prior_components %>% filter(series_id == id)
  from <- if (nrow(prior)) max(prior$date) - 10L else as.Date("1900-01-01")
  message("Collecting ", id, " from ", from)
  tryCatch(collect_yahoo(id, from), error = function(e) stop("YAHOO_COLLECTION_FAILED: ", id, ": ", conditionMessage(e)))
})
component_data <- bind_rows(prior_components, bind_rows(raw_list)) %>%
  arrange(series_id, date, desc(collected_at)) %>%
  distinct(source, series_id, date, .keep_all = TRUE)

staging <- paste0(target, ".staging")
last_good <- paste0(target, ".last_good")
on.exit(if (file.exists(staging)) unlink(staging), add = TRUE)
write.fst(component_data, staging, compress = 50)
readback <- read.fst(staging, as.data.table = FALSE) %>% as_tibble()
duplicates <- readback %>% count(source, series_id, date) %>% filter(n > 1L)
if (nrow(readback) != nrow(component_data) || nrow(duplicates) || !setequal(unique(readback$series_id), collect_ids)) {
  stop("SOX_COMPONENT_READBACK_FAILED")
}
if (file.exists(last_good)) unlink(last_good)
if (file.exists(target) && !file.rename(target, last_good)) stop("SOX_COMPONENT_BACKUP_FAILED")
if (!file.rename(staging, target)) {
  if (file.exists(last_good)) file.rename(last_good, target)
  stop("SOX_COMPONENT_PUBLICATION_FAILED")
}
if (!file.exists(last_good) && !file.copy(target, last_good, overwrite = FALSE)) {
  stop("SOX_COMPONENT_INITIAL_LAST_GOOD_FAILED")
}

write_csv(
  tibble(
    required_series = length(required_ids), existing_reused = length(legacy_owned_ids),
    newly_collected = length(collect_ids), rows = nrow(readback), duplicate_keys = nrow(duplicates),
    collection_mode = ifelse(nrow(prior_components), "INCREMENTAL_OVERLAP_10D", "FULL_HISTORY"),
    first_date = min(readback$date), last_date = max(readback$date),
    membership_effective_from = membership_as_of,
    historical_membership_before_effective_from = "NOT_AVAILABLE"
  ),
  file.path(gate_dir, "collection_summary.csv")
)
write_csv(tibble(series_id = required_ids, disposition = ifelse(required_ids %in% legacy_owned_ids, "REUSE_EXISTING_YAHOO", "COLLECTED_GATE4_FST")), file.path(gate_dir, "series_disposition.csv"))
cat("Gate 4 collection complete:", nrow(readback), "rows across", n_distinct(readback$series_id), "new series\n")
