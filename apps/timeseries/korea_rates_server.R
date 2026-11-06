korea_rates_ui <- function() {
  tagList(
    fluidRow(
      column(
        12,
        div(
          class = "kr-status-band",
          strong("Data status"),
          span(textOutput("kr_status_text", inline = TRUE)),
          span(class = "kr-status-separator", "|"),
          strong("Build"),
          span(textOutput("kr_build_text", inline = TRUE))
        )
      )
    ),
    tabsetPanel(
      id = "kr_subtab",
      tabPanel(
        "Yield Curve",
        fluidRow(
          column(
            3,
            selectizeInput("kr_curve_tenors", "Maturities", choices = NULL, multiple = TRUE),
            checkboxInput("kr_show_curve_table", "Show curve observations", FALSE)
          ),
          column(
            9,
            h4("Korea Treasury yield curve"),
            div(class = "kr-chart-meta", textOutput("kr_curve_meta")),
            plotlyOutput("kr_curve_plot", height = "330px")
          )
        ),
        conditionalPanel(condition = "input.kr_show_curve_table === true", DTOutput("kr_curve_table")),
        div(class = "kr-section-rule"),
        fluidRow(
          column(7, h4("Major maturity changes (bp)"), DTOutput("kr_rate_summary_table")),
          column(5, h4("Latest funding and credit spreads"), DTOutput("kr_spread_summary_table"))
        )
      ),
      tabPanel(
        "Rate Changes",
        selectizeInput("kr_change_series", "Series", choices = NULL, multiple = TRUE),
        div(class = "kr-chart-meta", textOutput("kr_change_meta")),
        DTOutput("kr_change_table")
      ),
      tabPanel(
        "Funding & Credit Spreads",
        sidebarLayout(
          sidebarPanel(
            dateRangeInput("kr_spread_range", "History range", start = Sys.Date() - lubridate::years(5), end = Sys.Date()),
            selectInput("kr_spread_metric", "Spread", choices = character())
          ),
          mainPanel(
            div(class = "kr-chart-meta", textOutput("kr_spread_meta")),
            plotlyOutput("kr_spread_plot", height = "390px")
          )
        )
      ),
      tabPanel(
        "Korea-US Link",
        sidebarLayout(
          sidebarPanel(
            dateRangeInput("kr_us_range", "Analysis range", start = Sys.Date() - lubridate::years(5), end = Sys.Date()),
            selectInput(
              "kr_us_pair", "Korea / US pair",
              choices = c("KTB 3Y vs US 2Y" = "KR3Y_US2Y", "KTB 10Y vs US 10Y" = "KR10Y_US10Y")
            ),
            selectInput(
              "kr_roll_relation", "Transmission relation",
              choices = c("US 2Y to next KR 3Y" = "US2Y_TO_NEXT_KR3Y_CHANGE", "US 10Y to next KR 10Y" = "US10Y_TO_NEXT_KR10Y_CHANGE")
            )
          ),
          mainPanel(
            h4("Korea / US rate comparison"),
            div(class = "kr-chart-meta", textOutput("kr_us_meta")),
            plotlyOutput("kr_us_plot", height = "330px"),
            h4("US close to next Korea business observation"),
            div(class = "kr-chart-meta", textOutput("kr_roll_meta")),
            plotlyOutput("kr_rolling_plot", height = "330px"),
            h4("Alignment sample"),
            DTOutput("kr_alignment_table")
          )
        )
      ),
      tabPanel(
        "FX Link",
        dateRangeInput("kr_fx_range", "History range", start = Sys.Date() - lubridate::years(5), end = Sys.Date()),
        div(class = "kr-chart-meta", textOutput("kr_fx_meta")),
        plotlyOutput("kr_fx_plot", height = "390px")
      ),
      tabPanel(
        "Data Quality",
        fluidRow(
          column(8, h4("Official source availability"), DTOutput("kr_quality_table")),
          column(
            4,
            div(class = "panel-note", textOutput("kr_special_status")),
            selectInput(
              "kr_download_group", "Download dataset",
              choices = c(
                "All derived metrics" = "all", "Yield curve" = "yield_curve",
                "Rate changes" = "rate_change", "Funding spreads" = "funding_spread",
                "Credit spreads" = "credit_spread", "Korea / US" = "kr_us_spread",
                "Rolling correlation" = "rolling_correlation", "FX link" = "fx_rate_link"
              )
            ),
            downloadButton("download_korea_rates", "Download CSV", icon = icon("download"))
          )
        )
      )
    )
  )
}

register_korea_rates_server <- function(input, output, session, active_tab, derived_path, latest_path, catalog) {
  latest_store <- reactiveVal(NULL)
  derived_store <- reactiveVal(NULL)

  load_store <- function(path) {
    if (!file.exists(path)) stop(basename(path), " not found")
    d <- fst::read.fst(path, as.data.table = FALSE) %>% tibble::as_tibble()
    date_columns <- intersect(c("observation_date", "reference_date", "as_of", "us_observation_date", "kr_effective_date"), names(d))
    d %>% dplyr::mutate(dplyr::across(dplyr::all_of(date_columns), as.Date))
  }

  observeEvent(active_tab(), {
    if (identical(active_tab(), "Korea Rates & Funding") && is.null(latest_store())) {
      latest_store(load_store(latest_path))
    }
  }, ignoreInit = FALSE)

  historical_tabs <- c("Funding & Credit Spreads", "Korea-US Link", "FX Link", "Data Quality")
  observeEvent(list(active_tab(), input$kr_subtab), {
    if (identical(active_tab(), "Korea Rates & Funding") && input$kr_subtab %in% historical_tabs && is.null(derived_store())) {
      derived_store(load_store(derived_path))
    }
  }, ignoreInit = TRUE)

  latest_data <- reactive({
    req(identical(active_tab(), "Korea Rates & Funding"), !is.null(latest_store()))
    latest_store()
  })

  full_data <- reactive({
    req(identical(active_tab(), "Korea Rates & Funding"), !is.null(derived_store()))
    derived_store()
  })

  observeEvent(latest_data(), {
    d <- latest_data()
    latest_date <- max(d$observation_date, na.rm = TRUE)
    date_start <- latest_date %m-% years(5)
    for (id in c("kr_spread_range", "kr_us_range", "kr_fx_range")) {
      updateDateRangeInput(session, id, start = date_start, end = latest_date, max = latest_date)
    }
    spread_choices <- d %>%
      filter(metric_group %in% c("funding_spread", "credit_spread")) %>%
      distinct(metric_id) %>% arrange(metric_id) %>% pull(metric_id)
    updateSelectInput(session, "kr_spread_metric", choices = spread_choices, selected = spread_choices[[1]])
    tenor_choices <- d %>% filter(metric_group == "yield_curve") %>% distinct(tenor_years) %>% arrange(tenor_years) %>% pull(tenor_years)
    updateSelectizeInput(session, "kr_curve_tenors", choices = tenor_choices, selected = tenor_choices, server = TRUE)
    change_choices <- d %>% filter(metric_group == "rate_change") %>% distinct(series_id) %>% arrange(series_id) %>% pull(series_id)
    major <- intersect(c("BOK_BASE_RATE", "KTB_02Y", "KTB_03Y", "KTB_05Y", "KTB_10Y", "KTB_30Y"), change_choices)
    updateSelectizeInput(session, "kr_change_series", choices = change_choices, selected = major, server = TRUE)
  }, once = TRUE)

  output$kr_status_text <- renderText({
    d <- latest_data()
    curve <- d %>% filter(grepl("^CURVE_CURRENT_", metric_id))
    quality <- d %>% filter(metric_group == "data_quality")
    paste0(
      "curve as of ", format(max(curve$observation_date)),
      " | source ECOS | unit % | pending ", sum(quality$quality_status == "PENDING_SOURCE"),
      " | delayed ", sum(quality$quality_status == "DELAYED")
    )
  })

  output$kr_build_text <- renderText({
    d <- latest_data()
    paste0(unique(d$calculation_version)[[1]], " | ", max(d$collected_at))
  })

  curve_data <- reactive({
    req(identical(input$kr_subtab, "Yield Curve"), input$kr_curve_tenors)
    latest_data() %>%
      filter(metric_group == "yield_curve", tenor_years %in% as.numeric(input$kr_curve_tenors)) %>%
      mutate(
        snapshot = case_when(
          grepl("^CURVE_CURRENT_", metric_id) ~ "Current",
          grepl("^CURVE_1D_", metric_id) ~ "1 business observation ago",
          grepl("^CURVE_1W_", metric_id) ~ "1 week",
          TRUE ~ "1 month"
        ),
        snapshot = factor(snapshot, levels = c("Current", "1 business observation ago", "1 week", "1 month"))
      )
  })

  output$kr_curve_meta <- renderText({
    d <- curve_data()
    current <- d %>% filter(snapshot == "Current")
    req(nrow(current))
    paste0(
      "Basis ", format(unique(current$observation_date)),
      " | source ", unique(current$source), " | unit ", unique(current$unit),
      " | freshness ", unique(current$data_freshness_days), " day(s) | ", unique(current$alignment_rule)
    )
  })

  output$kr_curve_plot <- renderPlotly({
    d <- curve_data()
    req(nrow(d))
    p <- ggplot(d, aes(
      tenor_years, value, color = snapshot, group = snapshot,
      text = paste0(snapshot, "<br>", series_id, "<br>as of ", observation_date, "<br>", round(value, 3), "%")
    )) +
      geom_line(linewidth = 0.8) + geom_point(size = 2) +
      scale_x_continuous(breaks = c(1, 2, 3, 5, 10, 20, 30, 50)) +
      scale_color_manual(values = c("#0b6e75", "#64748b", "#b7791f", "#8b5e83"), drop = FALSE) +
      labs(x = "Maturity (years)", y = "Yield (%)", color = "Curve") + theme_minimal(base_size = 12)
    ggplotly(p, tooltip = "text")
  })

  output$kr_curve_table <- renderDT({
    req(identical(input$kr_subtab, "Yield Curve"), isTRUE(input$kr_show_curve_table))
    d <- curve_data() %>%
      select(series_id, tenor_years, snapshot, observation_date, value, quality_status) %>% arrange(tenor_years, snapshot)
    datatable(d, rownames = FALSE, options = list(dom = "tip", pageLength = 8, scrollX = TRUE)) %>% formatRound("value", 3)
  })

  make_change_table <- function(d, selected_series = NULL) {
    if (!is.null(selected_series)) d <- d %>% filter(series_id %in% selected_series)
    d <- d %>%
      filter(metric_group == "rate_change") %>%
      mutate(period = sub("^CHANGE_([^_]+)_.*$", "\\1", metric_id)) %>%
      select(series_id, observation_date, period, value, reference_date, quality_status) %>%
      tidyr::pivot_wider(names_from = period, values_from = c(value, reference_date, quality_status), names_glue = "{period}_{.value}") %>%
      arrange(match(series_id, c("BOK_BASE_RATE", "CALL_01D", "CD_091D", "CP_091D", "KTB_01Y", "KTB_02Y", "KTB_03Y", "KTB_05Y", "KTB_10Y", "KTB_20Y", "KTB_30Y", "KTB_50Y", "CORP_AAM_03Y", "CORP_BBBM_03Y")))
    period_order <- c("1D", "5D", "1M", "3M", "YTD")
    display_order <- c("series_id", "observation_date", paste0(period_order, "_value"), paste0(period_order, "_reference_date"), paste0(period_order, "_quality_status"))
    d %>% select(any_of(display_order), everything())
  }

  output$kr_rate_summary_table <- renderDT({
    req(identical(input$kr_subtab, "Yield Curve"))
    major <- c("BOK_BASE_RATE", "KTB_02Y", "KTB_03Y", "KTB_05Y", "KTB_10Y", "KTB_30Y")
    d <- make_change_table(latest_data(), major) %>% select(series_id, ends_with("_value"))
    value_cols <- grep("_value$", names(d), value = TRUE)
    datatable(d, rownames = FALSE, options = list(dom = "t", paging = FALSE, scrollX = TRUE)) %>%
      formatRound(value_cols, 1) %>% formatStyle(value_cols, color = styleInterval(0, c("#b23b3b", "#16705e")))
  })

  output$kr_spread_summary_table <- renderDT({
    req(identical(input$kr_subtab, "Yield Curve"))
    d <- latest_data() %>%
      filter(metric_group %in% c("funding_spread", "credit_spread")) %>%
      transmute(metric_id, observation_date, value_bp = round(value, 1), quality_status) %>% arrange(metric_id)
    datatable(d, rownames = FALSE, options = list(dom = "t", paging = FALSE, scrollX = TRUE))
  })

  output$kr_change_meta <- renderText({
    req(identical(input$kr_subtab, "Rate Changes"))
    d <- latest_data() %>% filter(metric_group == "rate_change")
    paste0("Current and reference values are actual ECOS observations; no LOCF | source ECOS | unit bp | as of ", format(max(d$observation_date)))
  })

  output$kr_change_table <- renderDT({
    req(identical(input$kr_subtab, "Rate Changes"), input$kr_change_series)
    d <- make_change_table(latest_data(), input$kr_change_series)
    value_cols <- grep("_value$", names(d), value = TRUE)
    datatable(d, rownames = FALSE, options = list(pageLength = 20, scrollX = TRUE, dom = "tip")) %>%
      formatRound(value_cols, 1) %>% formatStyle(value_cols, color = styleInterval(0, c("#b23b3b", "#16705e")))
  })

  spread_data <- reactive({
    req(identical(input$kr_subtab, "Funding & Credit Spreads"), input$kr_spread_metric, input$kr_spread_range)
    full_data() %>% filter(
      metric_id == input$kr_spread_metric,
      observation_date >= input$kr_spread_range[[1]], observation_date <= input$kr_spread_range[[2]]
    )
  })

  output$kr_spread_meta <- renderText({
    d <- spread_data()
    req(nrow(d))
    paste0(unique(d$component_a), " - ", unique(d$component_b), " | exact same observation date | source ECOS | unit bp | latest ", format(max(d$observation_date)))
  })

  output$kr_spread_plot <- renderPlotly({
    d <- spread_data()
    req(nrow(d))
    p <- ggplot(d, aes(observation_date, value, group = 1, text = paste0(observation_date, "<br>", round(value, 1), " bp"))) +
      geom_hline(yintercept = 0, color = "#64748b", linewidth = 0.4) + geom_line(color = "#0b6e75", linewidth = 0.75) +
      labs(x = NULL, y = "Spread (bp)") + theme_minimal(base_size = 12)
    ggplotly(p, tooltip = "text")
  })

  us_history <- reactive({
    req(identical(input$kr_subtab, "Korea-US Link"), input$kr_us_range)
    full_data() %>% filter(observation_date >= input$kr_us_range[[1]], observation_date <= input$kr_us_range[[2]])
  })

  output$kr_us_meta <- renderText({
    d <- us_history() %>% filter(grepl(paste0("^", input$kr_us_pair, "_.*_LEVEL$"), metric_id))
    req(nrow(d))
    paste0("Exact same-calendar observations only | sources ECOS and FRED | unit % | latest common date ", format(max(d$observation_date)))
  })

  output$kr_us_plot <- renderPlotly({
    d <- us_history() %>%
      filter(grepl(paste0("^", input$kr_us_pair, "_.*_LEVEL$"), metric_id)) %>%
      mutate(label = ifelse(grepl("_KR_LEVEL$", metric_id), "Korea", "US"))
    req(nrow(d))
    p <- ggplot(d, aes(observation_date, value, color = label, group = label, text = paste0(label, "<br>", observation_date, "<br>", round(value, 3), "%"))) +
      geom_line(linewidth = 0.7) + scale_color_manual(values = c(Korea = "#0b6e75", US = "#b7791f")) +
      labs(x = NULL, y = "Yield (%)", color = NULL) + theme_minimal(base_size = 12)
    ggplotly(p, tooltip = "text")
  })

  output$kr_roll_meta <- renderText({
    req(identical(input$kr_subtab, "Korea-US Link"))
    "US close t -> first later Korean business observation | changes in bp | windows 20/60/120 observations | no value until a full window exists"
  })

  output$kr_rolling_plot <- renderPlotly({
    d <- us_history() %>%
      filter(metric_group == "rolling_correlation", grepl(input$kr_roll_relation, metric_id, fixed = TRUE)) %>%
      mutate(window_label = paste0(window, " observations"))
    req(nrow(d))
    p <- ggplot(d, aes(kr_effective_date, value, color = window_label, group = window_label, text = paste0(window_label, "<br>US ", us_observation_date, " -> KR ", kr_effective_date, "<br>corr ", round(value, 3), "<br>n=", observation_count))) +
      geom_hline(yintercept = 0, color = "#64748b", linewidth = 0.4) + geom_line(linewidth = 0.7) + coord_cartesian(ylim = c(-1, 1)) +
      labs(x = NULL, y = "Rolling correlation", color = NULL) + theme_minimal(base_size = 12)
    ggplotly(p, tooltip = "text")
  })

  output$kr_alignment_table <- renderDT({
    req(identical(input$kr_subtab, "Korea-US Link"))
    d <- full_data() %>%
      filter(metric_id == input$kr_roll_relation) %>%
      arrange(desc(kr_effective_date), desc(us_observation_date)) %>%
      transmute(us_observation_date, kr_effective_date, us_change_bp = round(auxiliary_value, 1), kr_change_bp = round(value, 1), alignment_rule) %>% head(20)
    datatable(d, rownames = FALSE, options = list(pageLength = 10, dom = "tip", scrollX = TRUE))
  })

  fx_history <- reactive({
    req(identical(input$kr_subtab, "FX Link"), input$kr_fx_range)
    full_data() %>% filter(metric_group == "fx_rate_link", observation_date >= input$kr_fx_range[[1]], observation_date <= input$kr_fx_range[[2]])
  })

  output$kr_fx_meta <- renderText({
    d <- fx_history()
    req(nrow(d))
    paste0("ECOS_USDKRW official reference; never merged with Yahoo USDKRW=X | exact-date link | latest ", format(max(d$observation_date)))
  })

  output$kr_fx_plot <- renderPlotly({
    d <- fx_history()
    fx <- d %>% filter(metric_id == "FX_ECOS_USDKRW")
    spread <- d %>% filter(metric_id == "FX_LINK_KR_US_10Y_SPREAD_BP")
    req(nrow(fx), nrow(spread))
    plot_ly() %>%
      add_lines(data = fx, x = ~observation_date, y = ~value, name = "ECOS USD/KRW", line = list(color = "#0b6e75"), hovertemplate = "%{x}<br>%{y:.1f} KRW/USD<extra></extra>") %>%
      add_lines(data = spread, x = ~observation_date, y = ~value, name = "KR-US 10Y spread", yaxis = "y2", line = list(color = "#b7791f"), hovertemplate = "%{x}<br>%{y:.1f} bp<extra></extra>") %>%
      layout(xaxis = list(title = ""), yaxis = list(title = "KRW per USD"), yaxis2 = list(title = "Spread (bp)", overlaying = "y", side = "right"), legend = list(orientation = "h", x = 0, y = 1.1))
  })

  output$kr_quality_table <- renderDT({
    req(identical(input$kr_subtab, "Data Quality"))
    d <- latest_data() %>%
      filter(metric_group == "data_quality") %>% select(series_id, observation_date, data_freshness_days, quality_status) %>%
      arrange(desc(data_freshness_days), series_id)
    datatable(d, rownames = FALSE, options = list(pageLength = 8, dom = "tip", scrollX = TRUE))
  })

  output$kr_special_status <- renderText({
    req(identical(input$kr_subtab, "Data Quality"))
    "SPECIAL_AAA_03Y: official ECOS representative series is unavailable (SOURCE_NOT_AVAILABLE). No replacement series is used."
  })

  output$download_korea_rates <- downloadHandler(
    filename = function() paste0("korea_rates_", input$kr_download_group, "_", Sys.Date(), ".csv"),
    content = function(file) {
      d <- if (is.null(derived_store())) load_store(derived_path) else derived_store()
      if (!identical(input$kr_download_group, "all")) d <- d %>% filter(metric_group == input$kr_download_group)
      readr::write_csv(d, file, na = "")
    }
  )

  output_ids <- c(
    "kr_status_text", "kr_build_text", "kr_curve_meta", "kr_curve_plot", "kr_curve_table",
    "kr_rate_summary_table", "kr_spread_summary_table", "kr_change_meta", "kr_change_table",
    "kr_spread_meta", "kr_spread_plot", "kr_us_meta", "kr_us_plot", "kr_roll_meta",
    "kr_rolling_plot", "kr_alignment_table", "kr_fx_meta", "kr_fx_plot", "kr_quality_table", "kr_special_status"
  )
  lapply(output_ids, function(id) outputOptions(output, id, suspendWhenHidden = TRUE))

  invisible(list(latest_store = latest_store, derived_store = derived_store))
}
