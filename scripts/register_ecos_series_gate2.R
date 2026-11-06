suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tibble)
})

script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
script_path <- if (length(script_arg)) sub("^--file=", "", script_arg[[1]]) else file.path("scripts", "register_ecos_series_gate2.R")
repo_dir <- normalizePath(file.path(dirname(script_path), ".."), winslash = "/", mustWork = TRUE)
app_dir <- file.path(repo_dir, "apps", "timeseries")
gate_dir <- file.path(repo_dir, "docs", "gate2")
catalog_path <- file.path(app_dir, "series_catalog.csv")
snapshot_path <- file.path(app_dir, "ecos_item_snapshot.csv")

if (!file.exists(snapshot_path)) stop("Official ECOS item snapshot is required before registration")

column_order <- c(
  "source", "series_id", "display_name", "display_name_ko", "series_cls",
  "series_group", "sector", "industry", "region", "currency",
  "benchmark_series", "price_policy", "stat_code", "cycle", "item_code1",
  "item_code2", "item_code3", "item_code4", "unit", "transform",
  "collect_flag", "default_visible", "active", "display_order", "notes"
)

catalog <- read_csv(catalog_path, col_types = cols(.default = col_character()), na = character()) %>%
  mutate(
    collect_flag = as.logical(collect_flag),
    default_visible = as.logical(default_visible),
    active = as.logical(active),
    display_order = as.integer(display_order)
  )
snapshot <- read_csv(snapshot_path, col_types = cols(.default = col_character()), na = character())

mapping <- tribble(
  ~series_id, ~display_name, ~display_name_ko, ~series_group, ~stat_code, ~cycle, ~item_code1, ~expected_item_name, ~unit, ~display_order,
  "BOK_BASE_RATE", "Bank of Korea Base Rate", "한국은행 기준금리", "kr_policy", "722Y001", "D", "0101000", "한국은행 기준금리", "연%", 201L,
  "CALL_01D", "Korea Call Rate 1D", "콜금리 1일", "kr_short_rate", "817Y002", "D", "010101000", "콜금리(1일, 전체거래)", "연%", 202L,
  "CD_091D", "Korea CD 91D Rate", "CD 91일 금리", "kr_short_rate", "817Y002", "D", "010502000", "CD(91일)", "연%", 203L,
  "CP_091D", "Korea CP 91D Rate", "CP 91일 금리", "kr_short_rate", "817Y002", "D", "010503000", "CP(91일)", "연%", 204L,
  "MSB_091D", "Monetary Stabilization Bond 91D", "통안증권 91일", "kr_short_rate", "817Y002", "D", "010400000", "통안증권(91일)", "연%", 205L,
  "MSB_01Y", "Monetary Stabilization Bond 1Y", "통안증권 1년", "kr_short_rate", "817Y002", "D", "010400001", "통안증권(1년)", "연%", 206L,
  "MSB_02Y", "Monetary Stabilization Bond 2Y", "통안증권 2년", "kr_short_rate", "817Y002", "D", "010400002", "통안증권(2년)", "연%", 207L,
  "KTB_01Y", "Korea Treasury Bond 1Y", "국고채 1년", "kr_government_bond", "817Y002", "D", "010190000", "국고채(1년)", "연%", 208L,
  "KTB_02Y", "Korea Treasury Bond 2Y", "국고채 2년", "kr_government_bond", "817Y002", "D", "010195000", "국고채(2년)", "연%", 209L,
  "KTB_03Y", "Korea Treasury Bond 3Y", "국고채 3년", "kr_government_bond", "817Y002", "D", "010200000", "국고채(3년)", "연%", 210L,
  "KTB_05Y", "Korea Treasury Bond 5Y", "국고채 5년", "kr_government_bond", "817Y002", "D", "010200001", "국고채(5년)", "연%", 211L,
  "KTB_10Y", "Korea Treasury Bond 10Y", "국고채 10년", "kr_government_bond", "817Y002", "D", "010210000", "국고채(10년)", "연%", 212L,
  "KTB_20Y", "Korea Treasury Bond 20Y", "국고채 20년", "kr_government_bond", "817Y002", "D", "010220000", "국고채(20년)", "연%", 213L,
  "KTB_30Y", "Korea Treasury Bond 30Y", "국고채 30년", "kr_government_bond", "817Y002", "D", "010230000", "국고채(30년)", "연%", 214L,
  "KTB_50Y", "Korea Treasury Bond 50Y", "국고채 50년", "kr_government_bond", "817Y002", "D", "010240000", "국고채(50년)", "연%", 215L,
  "CORP_AAM_03Y", "Korea Corporate AA- 3Y", "회사채 AA- 3년", "kr_credit", "817Y002", "D", "010300000", "회사채(3년, AA-)", "연%", 216L,
  "CORP_BBBM_03Y", "Korea Corporate BBB- 3Y", "회사채 BBB- 3년", "kr_credit", "817Y002", "D", "010320000", "회사채(3년, BBB-)", "연%", 217L,
  "ECOS_USDKRW", "Official KRW per USD", "공식 원/달러 환율", "fx_official", "731Y001", "D", "0000001", "원/미국달러(매매기준율)", "원", 218L
)

verified <- mapping %>%
  left_join(
    snapshot %>% select(stat_code, cycle, item_code1 = item_code, official_item_name = item_name, official_unit = unit, start_date, end_date),
    by = c("stat_code", "cycle", "item_code1")
  ) %>%
  mutate(
    status = case_when(
      is.na(official_item_name) | official_item_name == "" ~ "CONFIG_CODE_MISMATCH",
      official_item_name != expected_item_name ~ "CONFIG_CODE_MISMATCH",
      official_unit != unit ~ "CONFIG_CODE_MISMATCH",
      TRUE ~ "VERIFIED"
    )
  )

write_csv(verified, file.path(gate_dir, "ecos_catalog_contract_validation.csv"))
if (any(verified$status != "VERIFIED")) {
  stop("CONFIG_CODE_MISMATCH: official ECOS item name/cycle/unit validation failed")
}

ecos_rows <- verified %>%
  transmute(
    source = "ECOS", series_id, display_name, display_name_ko,
    series_cls = ifelse(series_id == "ECOS_USDKRW", "forex", "rate"),
    series_group, sector = "", industry = "", region = "KR", currency = "KRW",
    benchmark_series = "", price_policy = "close", stat_code, cycle, item_code1,
    item_code2 = "", item_code3 = "", item_code4 = "", unit, transform = "",
    collect_flag = TRUE, default_visible = FALSE, active = TRUE, display_order,
    notes = paste0("official_item_name=", expected_item_name, "; official_readback_verified")
  )

special_row <- tibble(
  source = "ECOS", series_id = "SPECIAL_AAA_03Y",
  display_name = "Korea Special Bond AAA 3Y", display_name_ko = "특수채 AAA 3년",
  series_cls = "rate", series_group = "kr_credit", sector = "", industry = "",
  region = "KR", currency = "KRW", benchmark_series = "", price_policy = "close",
  stat_code = "", cycle = "", item_code1 = "", item_code2 = "", item_code3 = "",
  item_code4 = "", unit = "", transform = "", collect_flag = FALSE,
  default_visible = FALSE, active = FALSE, display_order = 219L,
  notes = "SOURCE_NOT_AVAILABLE; no verified representative special-bond AAA series in official ECOS 817Y002 readback"
)

catalog <- catalog %>% filter(!(source == "ECOS" & series_id %in% c(ecos_rows$series_id, special_row$series_id)))
output <- bind_rows(catalog, ecos_rows, special_row) %>%
  select(all_of(column_order)) %>%
  arrange(display_order, source, series_id)

stopifnot(nrow(output %>% count(source, series_id) %>% filter(n > 1L)) == 0L)
write_csv(output, catalog_path, na = "")
cat("Gate 2 ECOS catalog registration: 18 VERIFIED, 1 SOURCE_NOT_AVAILABLE\n")

