library(shiny)
library(fst)
library(dplyr)
library(lubridate)
library(DT)
library(ggplot2)
library(plotly)
library(tidyr)
library(viridis)
library(purrr)
library(readr)

get_app_dir <- function() {
  candidates <- c(
    normalizePath(getwd(), winslash = "/", mustWork = TRUE),
    normalizePath(file.path(getwd(), "..", "marketIndexTimeSeries", "apps", "timeseries"), winslash = "/", mustWork = FALSE),
    "C:/app/econ_ts/marketIndexTimeSeries/apps/timeseries",
    "C:/app/econ_ts/marketIndexTimeSeries"
  )

  for (candidate in candidates) {
    if (!is.na(candidate) && file.exists(file.path(candidate, "dataExtract_fredyahoo.R"))) {
      return(normalizePath(candidate, winslash = "/", mustWork = TRUE))
    }
  }

  "C:/app/econ_ts/marketIndexTimeSeries/apps/timeseries"
}

data_dir <- get_app_dir()
data_paths <- c(
  YAHOO = file.path(data_dir, "original_ts_yahoo.fst"),
  FRED = file.path(data_dir, "original_ts_fred.fst")
)
catalog_path <- file.path(data_dir, "series_catalog.csv")
collector_path <- file.path(data_dir, "dataExtract_fredyahoo.R")
market_ui_core_path <- file.path(data_dir, "derived_market_ui_core.fst")
series_explorer_path <- file.path(data_dir, "derived_series_explorer.fst")
source(file.path(data_dir, "analysis_helpers.R"), local = TRUE)
source(file.path(data_dir, "sector_server.R"), local = TRUE)
source(file.path(data_dir, "link_server.R"), local = TRUE)
source(file.path(data_dir, "physical_indicators_server.R"), local = TRUE)
source(file.path(data_dir, "korea_rates_server.R"), local = TRUE)
source(file.path(data_dir, "sox_constituents_server.R"), local = TRUE)
if (!file.exists(catalog_path)) {
  stop("series_catalog.csv not found. Place it in apps/timeseries.")
}

empty_data <- tibble::tibble(
  date = as.Date(character()),
  series_id = character(),
  close_value = numeric(),
  adjusted_value = numeric(),
  volume = numeric(),
  source = character(),
  collected_at = character()
)

parse_logical <- function(x) {
  v <- trimws(tolower(as.character(x)))
  out <- rep(NA, length(v))
  out[v %in% c("1", "true", "t", "y", "yes")] <- TRUE
  out[v %in% c("0", "false", "f", "n", "no")] <- FALSE
  as.logical(out)
}

read_series_catalog <- function(path) {
  raw <- suppressMessages(readr::read_csv(path, show_col_types = FALSE))
  required <- c(
    "source", "series_id", "display_name", "display_name_ko", "series_cls",
    "series_group", "sector", "industry", "region", "currency",
    "benchmark_series", "price_policy", "stat_code", "cycle", "item_code1",
    "item_code2", "item_code3", "item_code4", "unit", "transform",
    "collect_flag", "default_visible", "active", "display_order", "notes"
  )
  missing <- setdiff(required, names(raw))
  if (length(missing) > 0) stop("Missing columns in catalog: ", paste(missing, collapse = ", "))

  raw %>%
    mutate(
      source = toupper(trimws(as.character(source))),
      series_id = trimws(as.character(series_id)),
      source_symbol = if ("source_symbol" %in% names(raw)) trimws(as.character(source_symbol)) else series_id,
      source_symbol = ifelse(is.na(source_symbol) | source_symbol == "", series_id, source_symbol),
      display_name = ifelse(is.na(display_name) | trimws(display_name) == "", series_id, as.character(display_name)),
      display_name_ko = ifelse(is.na(display_name_ko) | trimws(display_name_ko) == "", as.character(display_name), as.character(display_name_ko)),
      series_cls = trimws(as.character(series_cls)),
      series_group = trimws(as.character(series_group)),
      sector = trimws(as.character(sector)),
      industry = trimws(as.character(industry)),
      region = trimws(as.character(region)),
      currency = trimws(as.character(currency)),
      benchmark_series = na_if(trimws(as.character(benchmark_series)), ""),
      price_policy = na_if(trimws(as.character(price_policy)), ""),
      transform = na_if(trimws(as.character(transform)), ""),
      collect_flag = parse_logical(collect_flag),
      default_visible = parse_logical(default_visible),
      active = parse_logical(active),
      display_order = readr::parse_integer(as.character(display_order)),
      notes = ifelse(is.na(notes), "", as.character(notes))
    ) %>%
    arrange(display_order, series_id)
}

normalize_data <- function(df, source_default = "YAHOO") {
  if (nrow(df) == 0) return(empty_data)
  out <- as_tibble(df)

  if ("value" %in% names(out) && !"close_value" %in% names(out)) {
    out$close_value <- as.numeric(out$value)
  }
  if (!"close_value" %in% names(out)) out$close_value <- NA_real_
  if (!"adjusted_value" %in% names(out)) out$adjusted_value <- NA_real_
  if (!"volume" %in% names(out)) out$volume <- NA_real_
  if (!"source" %in% names(out)) out$source <- source_default
  out$source[is.na(out$source) | trimws(as.character(out$source)) == ""] <- source_default
  if (!"collected_at" %in% names(out)) out$collected_at <- as.character(Sys.time())

  out %>%
    transmute(
      date = as.Date(date),
      series_id = as.character(series_id),
      close_value = as.numeric(close_value),
      adjusted_value = as.numeric(adjusted_value),
      volume = as.numeric(volume),
      source = as.character(source),
      collected_at = as.character(collected_at)
    ) %>%
    filter(!is.na(series_id), !is.na(date)) %>%
    distinct(series_id, date, .keep_all = TRUE)
}

load_source_data <- function(path, source_name) {
  if (!file.exists(path)) {
    message("No local ", source_name, " fst found: ", path)
    return(empty_data)
  }
  normalize_data(read.fst(path), source_default = source_name)
}

load_market_data <- function(paths = data_paths) {
  purrr::map2_dfr(
    unname(paths),
    names(paths),
    ~ load_source_data(.x, .y)
  ) %>%
    distinct(source, series_id, date, .keep_all = TRUE)
}

load_market_ui_core <- function(path = market_ui_core_path) {
  if (!file.exists(path)) return(load_market_data())
  normalize_data(read.fst(path), source_default = "YAHOO")
}

load_series_explorer_data <- function(path = series_explorer_path) {
  if (!file.exists(path)) return(load_market_data())
  out <- read.fst(path, as.data.table = FALSE)
  if (!inherits(out$date, "Date")) out$date <- as.Date(out$date)
  out
}

effective_value <- function(close_value, adjusted_value) {
  as.numeric(ifelse(!is.na(adjusted_value), adjusted_value, close_value))
}

apply_display_transform <- function(d) {
  if (!"display_transform" %in% names(d)) return(d)

  d %>%
    group_by(source, series_id) %>%
    arrange(date, .by_group = TRUE) %>%
    mutate(
      .raw_close = close_value,
      .raw_adjusted = adjusted_value,
      close_value = ifelse(
        display_transform %in% "yoy",
        100 * (.raw_close / lag(.raw_close, 12L) - 1),
        .raw_close
      ),
      adjusted_value = ifelse(
        display_transform %in% "yoy" & !is.na(.raw_adjusted),
        100 * (.raw_adjusted / lag(.raw_adjusted, 12L) - 1),
        .raw_adjusted
      )
    ) %>%
    select(-.raw_close, -.raw_adjusted) %>%
    ungroup()
}

build_catalog_filter <- function(catalog) {
  group_values <- sort(unique(catalog$series_group[!is.na(catalog$series_group) & catalog$series_group != ""], na.last = NA))
  group_labels <- ifelse(group_values == "physical_indicator", "Physical Indicators", group_values)
  list(
    cls = c("All", sort(unique(catalog$series_cls[!is.na(catalog$series_cls) & catalog$series_cls != ""], na.last = NA))),
    group = c("All" = "All", stats::setNames(group_values, group_labels)),
    sector = c("All", sort(unique(catalog$sector[!is.na(catalog$sector) & catalog$sector != "" & catalog$sector != "NA"], na.last = NA))),
    region = c("All", sort(unique(catalog$region[!is.na(catalog$region) & catalog$region != "" & catalog$region != "NA"], na.last = NA)))
  )
}

scale_to_endpoint_band <- function(d) {
  endpts <- d %>%
    group_by(series_id, display_name) %>%
    summarize(endpoint_value = dplyr::last(close_value[!is.na(close_value)]), .groups = "drop") %>%
    mutate(
      scale_factor = ifelse(!is.na(endpoint_value) & endpoint_value != 0, abs(endpoint_value) / 100, 1),
      scale_factor = ifelse(is.na(scale_factor) | scale_factor == 0, 1, scale_factor),
      scaled_label = paste0(display_name, " (1/", format(round(scale_factor, 4), trim = TRUE), ")")
    )

  d %>%
    left_join(endpts, by = c("series_id", "display_name")) %>%
    mutate(scale_factor = ifelse(is.na(scale_factor), 1, scale_factor),
           scaled_value = close_value / scale_factor)
}

max_drawdown_pct <- function(x) {
  x <- na.omit(as.numeric(x))
  if (length(x) < 2) return(NA_real_)
  min((x / cummax(x) - 1) * 100, na.rm = TRUE)
}

floor_decimal <- function(x, digits = 2L) {
  scale <- 10^digits
  floor(as.numeric(x) * scale) / scale
}

compute_return_df <- function(d, mode = c("Daily Return", "Weekly Return", "Price Level")) {
  mode <- match.arg(mode)
  if (mode == "Price Level") {
    return(d %>% transmute(date, series_id, value = as.numeric(close_value)))
  }

  d <- d %>%
    mutate(effective = effective_value(close_value, adjusted_value))

  if (mode == "Weekly Return") {
    d <- d %>%
      mutate(week = floor_date(date, "week", week_start = 1)) %>%
      group_by(series_id, week) %>%
      summarize(
        date = max(date),
        effective = dplyr::last(effective),
        .groups = "drop"
      )
  }

  d %>%
    group_by(series_id) %>%
    arrange(date) %>%
    mutate(value = effective / lag(effective) - 1) %>%
    ungroup() %>%
    filter(!is.na(value)) %>%
    transmute(date, series_id, value)
}

catalog <- read_series_catalog(catalog_path) %>%
  mutate(
    rotation_bucket = catalog_tag(notes, "rotation_bucket"),
    analysis_group = catalog_tag(notes, "analysis_group"),
    link_role = catalog_tag(notes, "link_role"),
    display_transform = ifelse(
      !is.na(transform) & transform != "",
      transform,
      catalog_tag(notes, "display_transform")
    )
  )
filter_choices <- build_catalog_filter(catalog)
sector_catalog <- catalog %>% filter(active %in% TRUE, series_cls == "sector_etf")
link_catalog <- catalog %>% filter(active %in% TRUE, analysis_group == "semiconductor_korea")
physical_catalog <- catalog %>% filter(active %in% TRUE, series_group == "physical_indicator")

ui <- navbarPage(
  title = "Market Time Series",
  id = "main_tab",
  header = tags$head(tags$style(HTML("
    body { background: #f5f7f9; color: #17212b; }
    .navbar { border-radius: 0; margin-bottom: 12px; }
    .container-fluid { max-width: 1700px; }
    .panel-note { padding: 10px 12px; border-left: 3px solid #2878b5; background: #eef5fa; margin-bottom: 12px; }
    .kr-status-band { padding: 10px 0; border-bottom: 1px solid #cbd5df; margin-bottom: 14px; }
    .kr-status-band span { margin-left: 6px; }
    .kr-status-separator { color: #94a3b0; margin: 0 10px !important; }
    .kr-chart-meta { color: #52606d; font-size: 12px; margin-bottom: 6px; }
    .kr-section-rule { border-top: 1px solid #d7dee5; margin: 18px 0; }
    .company-detail { margin: 14px 0; padding: 12px 16px; border-left: 3px solid #23846b; background: #f0f7f4; }
    .company-detail h4 { margin-top: 0; }
    .company-detail dl { display: grid; grid-template-columns: 120px 1fr; gap: 5px 12px; margin-bottom: 0; }
    .company-detail dt, .company-detail dd { margin: 0; }
  "))),
  tabPanel(
    "Sector Rotation",
    sidebarLayout(
      sidebarPanel(
        dateInput("sector_asof", "As of", value = Sys.Date()),
        selectInput("sector_sort", "Sort by", choices = c(
          "1M excess vs SPY" = "Excess1M", "1 month" = "Return1M",
          "3 months" = "Return3M", "YTD" = "YTD", "20-day volatility" = "Vol20"
        )),
        div(class = "panel-note",
            "Returns and volatility use Adjusted Close, with Close fallback when Adjusted is unavailable.")
      ),
      mainPanel(
        fluidRow(
          column(3, h5("Sectors beating SPY (1M)"), h3(textOutput("sector_beating", inline = TRUE))),
          column(3, h5("Cyclical avg excess"), h3(textOutput("cyclical_excess", inline = TRUE))),
          column(3, h5("Defensive avg excess"), h3(textOutput("defensive_excess", inline = TRUE))),
          column(3, h5("Latest observation"), h3(textOutput("sector_latest", inline = TRUE)))
        ),
        div(class = "panel-note",
            strong("1M excess"), " is each sector ETF's one-month return minus SPY. ",
            strong("Cyclical"), ": Technology, Communication Services, Consumer Discretionary, Energy, Financials, Industrials, and Materials. ",
            strong("Defensive"), ": Consumer Staples, Health Care, and Utilities. Real Estate is reported separately as rate-sensitive."),
        plotlyOutput("sector_excess_plot", height = "330px"),
        DTOutput("sector_table")
      )
    )
  ),
  tabPanel(
    "Series Explorer",
    sidebarLayout(
      sidebarPanel(
        actionButton("update_data", "Update Market Data", class = "btn-primary"),
        dateRangeInput("date_range", "Date range", start = floor_date(Sys.Date(), unit = "year") - years(1), end = Sys.Date()),
        checkboxInput("show_inactive", "Show inactive / legacy", FALSE),
        selectInput("f_class", "Asset class", choices = filter_choices$cls, selected = "All"),
        selectInput("f_group", "Series group", choices = filter_choices$group, selected = "All"),
        selectInput("f_sector", "Sector", choices = filter_choices$sector, selected = "All"),
        selectInput("f_region", "Region", choices = filter_choices$region, selected = "All"),
        textInput("f_search", "Series search", value = ""),
        selectInput("corr_mode", "Correlation mode", choices = c("Daily Return", "Weekly Return", "Price Level"), selected = "Daily Return"),
        selectInput("benchmark", "Beta benchmark", choices = catalog$series_id, selected = "SPY"),
        numericInput("beta_min_obs", "Minimum beta observations", value = 20, min = 10, max = 500, step = 10)
      ),
      mainPanel(
        div(class = "panel-note", textOutput("corr_note")),
        DTOutput("currentChangeTable"),
        uiOutput("download_selected_ui"),
        uiOutput("series_proxy_note"),
        conditionalPanel(
          condition = "output.table_has_selection",
          br(),
          h4("Selected Series Cumulative Return (from day 0, return basis)"),
          plotlyOutput("tsPlot", height = "430px"),
          h4("Selected Series Absolute Level (Endpoint-scaled)"),
          plotlyOutput("levelPlot", height = "460px"),
          h4("Selected Series Raw Source Level"),
          plotlyOutput("rawLevelPlot", height = "520px"),
          h4("Correlation Matrix"),
          DTOutput("corrMatrix"),
          h4("Beta Matrix"),
          DTOutput("betaMatrix"),
          h4("Monthly Return Distribution"),
          DTOutput("momStatsTable")
        )
      )
    )
  ),
  tabPanel(
    "Korea Rates & Funding",
    korea_rates_ui()
  ),
  tabPanel(
    "SOX Constituents",
    sox_constituents_ui()
  ),
  tabPanel(
    "Semiconductor & Korea Link",
    tabsetPanel(
      id = "link_subtab",
      tabPanel("Market Link", sidebarLayout(
      sidebarPanel(
        dateRangeInput("link_range", "Date range", start = Sys.Date() - years(3), end = Sys.Date()),
        selectizeInput(
          "link_series", "Series",
          choices = setNames(link_catalog$series_id, link_catalog$display_name),
          selected = link_catalog$series_id, multiple = TRUE
        ),
        selectInput("link_alignment", "US/Korea alignment",
                    choices = c("Next KR trading day", "Same calendar date")),
        selectInput("link_predictor", "US predictor", choices = character()),
        div(class = "panel-note",
            "Next KR trading day maps a US close to the first later Korean trading date.")
      ),
      mainPanel(
        h4("Period performance and SOXX excess"),
        div(class = "panel-note", "Returns are computed over the selected date range from locally stored market data. Excess columns subtract the matching SOXX return."),
        DTOutput("link_performance"),
        h4("Cumulative return from selected-period start"),
        plotlyOutput("link_cumulative_plot", height = "370px"),
        h4("Signal spreads"),
        div(class = "panel-note", "SOXX minus XSD compares large-cap and equal-weight semiconductor performance. NVIDIA minus Micron is a simple AI-compute versus memory signal spread."),
        plotlyOutput("link_spread_plot", height = "310px"),
        h4("US signal vs Korean next session"),
        div(class = "panel-note", "Correlation, beta, and R2 use daily returns after applying the selected US/Korea trading-date alignment. Rolling lines use 20, 60, and 120 observations."),
        DTOutput("link_relation_table"),
        plotlyOutput("link_rolling_plot", height = "330px")
      ))),
      tabPanel("Physical Indicators", physical_indicators_ui())
    )
  )
)
server <- function(input, output, session) {
  shiny_data <- reactiveVal(load_series_explorer_data())
  full_market_loaded <- reactiveVal(TRUE)

  observeEvent(input$main_tab, {
    if (identical(input$main_tab, "Series Explorer") && !isTRUE(full_market_loaded())) {
      shiny_data(load_series_explorer_data())
      full_market_loaded(TRUE)
    }
  }, ignoreInit = TRUE)

  all_meta <- reactive({
    base <- if (isTRUE(input$show_inactive)) {
      catalog
    } else {
      catalog %>% filter(active %in% TRUE, default_visible %in% TRUE)
    }

    if (!is.null(input$f_class) && input$f_class != "All") base <- base %>% filter(series_cls == input$f_class)
    if (!is.null(input$f_group) && input$f_group != "All") base <- base %>% filter(series_group == input$f_group)
    if (!is.null(input$f_sector) && input$f_sector != "All") base <- base %>% filter(sector == input$f_sector)
    if (!is.null(input$f_region) && input$f_region != "All") base <- base %>% filter(region == input$f_region)

    search <- trimws(input$f_search)
    if (!is.null(search) && nzchar(search)) {
      base <- base %>%
        filter(
          grepl(search, series_id, ignore.case = TRUE) |
            grepl(search, display_name, ignore.case = TRUE) |
            grepl(search, display_name_ko, ignore.case = TRUE)
        )
    }
    base
  })

  observe({
    all_meta_names <- if (isTRUE(input$show_inactive)) {
      catalog
    } else {
      catalog %>% filter(active %in% TRUE, default_visible %in% TRUE)
    }
    benchmark_choices <- all_meta_names$series_id
    if (length(benchmark_choices) == 0) benchmark_choices <- character()
    selected <- NULL
    if (isTRUE(input$benchmark) %in% c(FALSE, TRUE) && !is.null(input$benchmark) && input$benchmark %in% benchmark_choices) {
      selected <- input$benchmark
    }
    if (is.null(selected) || selected == "") {
      selected <- ifelse("SPY" %in% benchmark_choices, "SPY", benchmark_choices[1])
    }
    updateSelectInput(session, "benchmark", choices = benchmark_choices, selected = selected)
  })

  observeEvent(input$update_data, {
    withProgress(message = "Updating market data", value = 0.1, {
      collector_env <- new.env(parent = globalenv())
      old_options <- options(market_ts.skip_autorun = TRUE)
      on.exit(options(old_options), add = TRUE)
      sys.source(collector_path, envir = collector_env)
      incProgress(0.4)
      collector_env$run_market_data_update(update_fred = TRUE, update_yahoo = TRUE)
      incProgress(0.4)
      shiny_data(load_market_data())
      full_market_loaded(TRUE)
    })
  })

  filteredData <- reactive({
    fullDataBySeries() %>%
      semi_join(all_meta() %>% select(series_id, source), by = c("series_id", "source")) %>%
      filter(
        !is.na(series_id),
        date >= input$date_range[1],
        date <= input$date_range[2]
      )
  })

  fullDataBySeries <- reactive({
    d <- shiny_data()
    if (all(c("display_name", "display_transform", "effective_value") %in% names(d))) return(d)
    d %>%
      left_join(
        catalog %>% select(series_id, source, display_name, display_transform),
        by = c("series_id", "source")
      ) %>%
      apply_display_transform() %>%
      mutate(
        display_name = ifelse(is.na(display_name), series_id, display_name),
        effective_value = effective_value(close_value, adjusted_value)
      )
  })

  register_sector_server(input, output, session, fullDataBySeries, sector_catalog)
  register_link_server(input, output, session, fullDataBySeries, link_catalog)
  physical_indicators_state <- register_physical_indicators_server(
    input, output, session, reactive(input$main_tab),
    file.path(data_dir, "original_ts_ecos.fst"),
    file.path(data_dir, "derived_physical_indicators.fst"),
    physical_catalog
  )
  korea_rates_state <- register_korea_rates_server(
    input, output, session,
    reactive(input$main_tab),
    file.path(data_dir, "derived_korea_rates_summary.fst"),
    file.path(data_dir, "derived_korea_rates_latest.fst"),
    catalog
  )
  sox_constituents_state <- register_sox_constituents_server(
    input, output, session,
    reactive(input$main_tab),
    file.path(data_dir, "derived_sox_daily_summary.fst"),
    file.path(data_dir, "derived_sox_latest.fst"),
    file.path(data_dir, "derived_sox_overview.png"),
    file.path(data_dir, "sox_constituents.csv")
  )

  table_period <- reactive({
    filteredData() %>%
      group_by(source, series_id, display_name) %>%
      arrange(date) %>%
      summarize(
        CurrentBasisDy = dplyr::last(date[is.finite(effective_value)]),
        current_value = dplyr::last(close_value[is.finite(close_value)]),
        current_effective = dplyr::last(effective_value[is.finite(effective_value)]),
        first_val = dplyr::first(effective_value[is.finite(effective_value)]),
        prev_val = dplyr::nth(effective_value[is.finite(effective_value)], max(1L, sum(is.finite(effective_value)) - 1L)),
        max_val = max(effective_value, na.rm = TRUE),
        .groups = "drop"
      )
  })

  table_with_ytd <- reactive({
    period <- table_period()
    if (nrow(period) == 0) return(period)

    end_anchor <- as.Date(input$date_range[2])
    ytd_base <- fullDataBySeries() %>%
      filter(date >= floor_date(end_anchor, unit = "year"), date <= end_anchor) %>%
      group_by(source, series_id) %>%
      arrange(date, .by_group = TRUE) %>%
      summarize(ytd_base = dplyr::first(effective_value[is.finite(effective_value)]), .groups = "drop")

    period %>%
      left_join(ytd_base, by = c("source", "series_id")) %>%
      mutate(
        YTD = ifelse(is.na(ytd_base) | ytd_base == 0, NA_real_, round((current_effective / ytd_base - 1) * 100, 4)),
        PeriodReturn = round((current_effective / first_val - 1) * 100, 4),
        DoD = ifelse(is.na(prev_val), NA_real_, round((current_effective / prev_val - 1) * 100, 4)),
        CurrentDrawdown = round((current_effective / max_val - 1) * 100, 4)
      )
  })

  currentTableData <- reactive({
    base <- table_with_ytd()
    if (nrow(base) == 0) return(base)

    md <- filteredData() %>%
      group_by(source, series_id) %>%
      summarize(MaxDrawdown = max_drawdown_pct(effective_value), .groups = "drop")

    base %>%
      left_join(md, by = c("source", "series_id")) %>%
      mutate(
        current_value = round(current_value, 4),
        first_val = round(first_val, 4),
        MaxDrawdown = floor_decimal(MaxDrawdown, 2L)
      ) %>%
      select(source, series_id, display_name, CurrentBasisDy, current_value, YTD, PeriodReturn, DoD, CurrentDrawdown, MaxDrawdown)
  })

  output$currentChangeTable <- renderDT({
    dt <- currentTableData()
    datatable(dt, rownames = FALSE, selection = "multiple", options = list(pageLength = 50)) %>%
      formatRound(columns = c("CurrentDrawdown", "MaxDrawdown"), digits = 2) %>%
      formatStyle(
        columns = c("current_value", "YTD", "PeriodReturn", "DoD", "CurrentDrawdown", "MaxDrawdown"),
        color = styleInterval(0, c("#d73027", "#1a9850")),
        fontWeight = "bold"
      )
  })

  selectedSeries <- reactive({
    sel <- input$currentChangeTable_rows_selected
    dt <- currentTableData()
    if (is.null(sel) || length(sel) == 0) return(NULL)
    dt$series_id[sel]
  })

  output$table_has_selection <- reactive(!is.null(selectedSeries()))
  outputOptions(output, "table_has_selection", suspendWhenHidden = FALSE)

  output$download_selected_ui <- renderUI({
    if (is.null(selectedSeries())) {
      tags$button(
        "Download Selected CSV",
        type = "button",
        class = "btn btn-default disabled",
        disabled = "disabled",
        title = "Select one or more rows first"
      )
    } else {
      downloadButton("download_selected_csv", "Download Selected CSV")
    }
  })

  output$series_proxy_note <- renderUI({
    ids <- selectedSeries()
    if (is.null(ids) || !"BWET_VLCC_PROXY" %in% ids) return(NULL)
    div(
      class = "panel-note",
      strong("Proxy definition: "),
      "BWET is a tanker-freight futures ETF market-price proxy. It is not a VLCC spot rate or an official Baltic freight index. Returns may include futures roll, management fees, and tracking error."
    )
  })

  selectedData <- reactive({
    req(selectedSeries())
    filteredData() %>% filter(series_id %in% selectedSeries()) %>% arrange(series_id, date)
  })

  rawSelectedData <- reactive({
    req(selectedSeries())
    d <- fullDataBySeries()
    if (!"raw_close_value" %in% names(d)) d$raw_close_value <- d$close_value
    if (!"raw_adjusted_value" %in% names(d)) d$raw_adjusted_value <- d$adjusted_value

    d %>%
      filter(
        series_id %in% selectedSeries(),
        date >= input$date_range[1],
        date <= input$date_range[2]
      ) %>%
      mutate(
        display_name = ifelse(is.na(display_name), series_id, display_name),
        raw_value = effective_value(raw_close_value, raw_adjusted_value)
      ) %>%
      filter(is.finite(raw_value)) %>%
      arrange(series_id, date)
  })

  output$download_selected_csv <- downloadHandler(
    filename = function() {
      paste0(
        "selected_market_series_",
        format(input$date_range[1], "%Y%m%d"),
        "_",
        format(input$date_range[2], "%Y%m%d"),
        ".csv"
      )
    },
    content = function(file) {
      selectedData() %>%
        select(date, series_id, display_name, close_value, adjusted_value, effective_value, volume, source) %>%
        write.csv(file, row.names = FALSE, na = "")
    }
  )

  output$tsPlot <- renderPlotly({
    req(selectedSeries())
    d <- selectedData() %>%
      group_by(series_id, display_name) %>%
      arrange(date) %>%
      mutate(base = first(effective_value), pct_chg_from_day0 = (effective_value / base - 1) * 100) %>%
      ungroup()

    p <- ggplot(d, aes(x = date, y = pct_chg_from_day0, color = display_name)) +
      geom_hline(yintercept = 0, linewidth = 0.4, linetype = "dashed") +
      geom_line(linewidth = 0.65) +
      labs(x = "Date", y = "Pct change from Day 0 (%)", color = "Series") +
      scale_color_viridis_d() +
      theme_minimal()

    ggplotly(p)
  })

  output$levelPlot <- renderPlotly({
    req(selectedSeries())
    d <- filteredData() %>%
      filter(series_id %in% selectedSeries()) %>%
      arrange(series_id, date) %>%
      group_by(series_id, display_name) %>%
      filter(any(!is.na(close_value))) %>%
      ungroup()

    d <- scale_to_endpoint_band(d)

    plot_ly(
      d,
      x = ~date,
      y = ~scaled_value,
      color = ~scaled_label,
      text = ~paste0(scaled_label, "<br>Date: ", date, "<br>Close: ", round(close_value, 4)),
      type = "scatter",
      mode = "lines+markers",
      hoverinfo = "text",
      line = list(width = 2),
      marker = list(size = 4)
    ) %>%
      layout(
        xaxis = list(title = "Date"),
        yaxis = list(title = "Endpoint normalized level (close basis)"),
        legend = list(title = list(text = "Series"))
      )
  })

  output$rawLevelPlot <- renderPlotly({
    d <- rawSelectedData()
    req(nrow(d) > 0L)
    panels <- lapply(split(d, d$display_name), function(z) {
      y_range <- range(z$raw_value, na.rm = TRUE)
      y_pad <- max(diff(y_range) * 0.05, abs(y_range[1]) * 0.005, 1e-06)
      plot_ly(
        z, x = ~date, y = ~raw_value, type = "scatter", mode = "lines+markers",
        name = unique(z$display_name), showlegend = FALSE,
        line = list(width = 2, color = "#4b0b5a"),
        marker = list(size = 3, color = "#4b0b5a"),
        text = ~paste0(
          display_name, "<br>Source: ", source,
          "<br>Date: ", date, "<br>Raw value: ", round(raw_value, 4)
        ),
        hoverinfo = "text"
      ) %>% layout(
        title = list(text = unique(z$display_name), font = list(size = 13)),
        xaxis = list(title = "Date"),
        yaxis = list(title = "Raw source value", range = c(y_range[1] - y_pad, y_range[2] + y_pad))
      )
    })

    if (length(panels) == 1L) return(panels[[1]])
    do.call(
      plotly::subplot,
      c(panels, list(nrows = ceiling(length(panels) / 2), shareX = FALSE,
                     shareY = FALSE, titleX = TRUE, titleY = TRUE, margin = 0.06))
    ) %>% layout(showlegend = FALSE)
  })

  output$corr_note <- renderText({
    if (input$corr_mode == "Price Level") {
      "Price-level correlation is selected. Trend can inflate correlation values; use returns for signal comparison."
    } else {
      "Correlation is computed from return series."
    }
  })

  output$corrMatrix <- renderDT({
    sel_ids <- selectedSeries()
    if (is.null(sel_ids) || length(sel_ids) < 2) return(NULL)

    d <- filteredData() %>% filter(series_id %in% sel_ids)
    corr_df <- compute_return_df(d, input$corr_mode) %>%
      select(date, series_id, value) %>%
      pivot_wider(names_from = series_id, values_from = value)

    if (ncol(corr_df) <= 2) return(NULL)
    vals <- setdiff(names(corr_df), "date")
    corr_mat <- tryCatch(cor(corr_df[, vals], use = "pairwise.complete.obs"), error = function(e) NULL)
    if (is.null(corr_mat)) return(NULL)

    out <- as.data.frame(round(corr_mat, 3)) %>% tibble::rownames_to_column("Series")
    datatable(out, rownames = FALSE, options = list(scrollX = TRUE)) %>%
      formatStyle(
        columns = setdiff(names(out), "Series"),
        backgroundColor = styleInterval(c(-0.5, 0, 0.5), c("#d73027", "#ffffbf", "#1a9850", "#006837"))
      )
  })

  output$betaMatrix <- renderDT({
    sel_ids <- selectedSeries()
    benchmark_id <- input$benchmark
    if (is.null(sel_ids) || is.null(benchmark_id) || length(sel_ids) < 1) return(NULL)
    sel_ids <- unique(c(benchmark_id, sel_ids))

    d <- fullDataBySeries() %>%
      filter(date >= input$date_range[1], date <= input$date_range[2]) %>%
      filter(series_id %in% sel_ids) %>%
      mutate(value = as.numeric(effective_value(close_value, adjusted_value)))

    ret <- d %>%
      group_by(series_id) %>%
      arrange(date) %>%
      mutate(ret = value / lag(value) - 1) %>%
      ungroup() %>%
      select(date, series_id, ret)

    ret_wide <- ret %>%
      pivot_wider(names_from = series_id, values_from = ret)

    if (!benchmark_id %in% names(ret_wide)) return(NULL)
    rb <- ret_wide[[benchmark_id]]

    beta_df <- purrr::map_dfr(sel_ids, function(sid) {
      if (!sid %in% names(ret_wide)) {
        return(tibble(series_id = sid, n_obs = 0L, beta_vs_benchmark = NA_real_, rsq_vs_benchmark = NA_real_))
      }
      rs <- ret_wide[[sid]]
      idx <- complete.cases(rs, rb)
      n_obs <- sum(idx)
      benchmark_variance <- if (n_obs > 1L) var(rb[idx], na.rm = TRUE) else NA_real_
      enough_data <- n_obs >= input$beta_min_obs && is.finite(benchmark_variance) && benchmark_variance > 0
      beta <- if (enough_data) cov(rs[idx], rb[idx], use = "complete.obs") / benchmark_variance else NA_real_
      rsq <- if (enough_data) {
        fm <- suppressWarnings(lm(rs[idx] ~ rb[idx]))
        if (length(coefficients(fm)) >= 2) summary(fm)$r.squared else NA_real_
      } else {
        NA_real_
      }
      tibble(series_id = sid, n_obs = n_obs, beta_vs_benchmark = beta, rsq_vs_benchmark = rsq)
    })

    beta_df %>%
      left_join(catalog %>% select(series_id, display_name), by = "series_id") %>%
      mutate(display_name = ifelse(is.na(display_name), series_id, display_name),
             role = ifelse(series_id == benchmark_id, "Benchmark", "Asset")) %>%
      arrange(desc(role == "Benchmark"), match(series_id, sel_ids)) %>%
      select(role, display_name, n_obs, beta_vs_benchmark, rsq_vs_benchmark) %>%
      mutate(
        beta_vs_benchmark = round(beta_vs_benchmark, 4),
        rsq_vs_benchmark = round(rsq_vs_benchmark, 4),
        n_obs = as.integer(n_obs)
      ) %>%
      datatable(rownames = FALSE, options = list(dom = "t", pageLength = 50)) %>%
      formatStyle("beta_vs_benchmark", backgroundColor = styleInterval(c(0.5, 1, 1.5), c("#d9f0a3", "#addd8e", "#78c679", "#238443")))
  })

  output$momStatsTable <- renderDT({
    sel_ids <- selectedSeries()
    if (is.null(sel_ids) || length(sel_ids) == 0) return(NULL)

    d <- filteredData() %>%
      filter(series_id %in% sel_ids) %>%
      mutate(value = as.numeric(effective_value(close_value, adjusted_value)), month = floor_date(date, unit = "month")) %>%
      group_by(series_id, display_name, month) %>%
      summarize(month_end_val = dplyr::last(value), month_end_date = max(date), .groups = "drop") %>%
      arrange(series_id, month_end_date) %>%
      group_by(series_id, display_name) %>%
      mutate(month_ret_pct = (month_end_val / dplyr::lag(month_end_val) - 1) * 100) %>%
      ungroup() %>%
      filter(!is.na(month_ret_pct), is.finite(month_ret_pct))

    if (nrow(d) == 0) return(NULL)

    d %>%
      group_by(series_id, display_name) %>%
      summarize(
        n_months = dplyr::n(),
        mean = mean(month_ret_pct, na.rm = TRUE),
        median = median(month_ret_pct, na.rm = TRUE),
        p05 = as.numeric(quantile(month_ret_pct, 0.05, na.rm = TRUE, type = 7)),
        p25 = as.numeric(quantile(month_ret_pct, 0.25, na.rm = TRUE, type = 7)),
        p75 = as.numeric(quantile(month_ret_pct, 0.75, na.rm = TRUE, type = 7)),
        p95 = as.numeric(quantile(month_ret_pct, 0.95, na.rm = TRUE, type = 7)),
        .groups = "drop"
      ) %>%
      mutate(order = match(series_id, sel_ids)) %>%
      arrange(order) %>%
      select(-order) %>%
      mutate(across(c(mean, median, p05, p25, p75, p95), ~round(.x, 3)) ) %>%
      datatable(rownames = FALSE, options = list(pageLength = 50, scrollX = TRUE))
  })
}

shinyApp(ui, server)
