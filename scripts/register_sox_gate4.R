suppressPackageStartupMessages({ library(dplyr); library(readr); library(tibble) })

repo_dir <- normalizePath(".", winslash = "/", mustWork = TRUE)
app_dir <- file.path(repo_dir, "apps", "timeseries")
catalog_path <- file.path(app_dir, "series_catalog.csv")
members <- read_csv(file.path(app_dir, "sox_constituents.csv"), show_col_types = FALSE)
catalog <- read_csv(catalog_path, col_types = cols(.default = col_character()), na = character())

names_by_id <- setNames(members$company_name, members$ticker)
new_ids <- setdiff(c(members$ticker, "SOXQ", "005930.KS"), catalog$series_id)
if (length(new_ids)) {
  base_order <- max(suppressWarnings(as.integer(catalog$display_order)), na.rm = TRUE)
  additions <- tibble(
    source = "YAHOO", series_id = new_ids,
    display_name = ifelse(new_ids == "SOXQ", "Invesco PHLX Semiconductor ETF",
                          ifelse(new_ids == "005930.KS", "Samsung Electronics", unname(names_by_id[new_ids]))),
    display_name_ko = ifelse(new_ids == "005930.KS", "삼성전자", ifelse(new_ids == "SOXQ", "SOXQ 반도체 ETF", unname(names_by_id[new_ids]))),
    series_cls = ifelse(new_ids %in% c("SOXQ", "005930.KS"), ifelse(new_ids == "SOXQ", "sector_etf", "equity"), "index_constituent"),
    series_group = ifelse(new_ids == "005930.KS", "korea_semiconductor", "sox_components"),
    sector = "Semiconductors", industry = "Semiconductors",
    region = ifelse(new_ids == "005930.KS", "Korea", "Global"),
    currency = ifelse(new_ids == "005930.KS", "KRW", "USD"),
    benchmark_series = ifelse(new_ids == "005930.KS", "^KS11", "^SOX"),
    price_policy = "adjusted", stat_code = "", cycle = "", item_code1 = "", item_code2 = "",
    item_code3 = "", item_code4 = "", unit = "Index/Price", transform = "",
    collect_flag = "FALSE", default_visible = "FALSE", active = "TRUE",
    display_order = as.character(base_order + seq_along(new_ids)),
    notes = ifelse(new_ids == "005930.KS", "analysis_group=semiconductor_korea;link_role=korea_equity;gate4=TRUE",
                   "analysis_group=sox_constituents;price_basis=adjusted_close;gate4=TRUE")
  )
  catalog <- bind_rows(catalog, additions)
}

legacy_owned_ids <- c("NVDA", "MU")
gate4_owned_ids <- setdiff(c(members$ticker, "SOXQ", "005930.KS"), legacy_owned_ids)
catalog <- catalog %>%
  mutate(collect_flag = ifelse(source == "YAHOO" & series_id %in% gate4_owned_ids, "FALSE", collect_flag))

if (anyDuplicated(paste(catalog$source, catalog$series_id, sep = "::"))) stop("CATALOG_DUPLICATE_KEY")
write_csv(catalog, catalog_path, na = "")
cat("Catalog registered:", length(new_ids), "new rows\n")
