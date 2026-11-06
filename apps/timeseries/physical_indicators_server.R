physical_indicators_ui <- function() {
  tagList(
    div(class = "panel-note",
        strong("Data definition: "),
        "These are Bank of Korea ECOS producer price indexes. They are not TrendForce or DRAMeXchange global spot or contract prices."),
    uiOutput("physical_status"),
    fluidRow(
      column(3, selectInput(
        "physical_measure", "View",
        choices = c("Index level" = "LEVEL", "Month-over-month" = "MOM", "Year-over-year" = "YOY",
                    "3-month change" = "CHANGE_3M", "6-month change" = "CHANGE_6M",
                    "Rise/fall streak" = "STREAK_MONTHS"), selected = "LEVEL"
      ))
    ),
    h4("DRAM Producer Price"),
    plotlyOutput("dram_physical_plot", height = "320px"),
    h4("Flash Memory Producer Price"),
    plotlyOutput("flash_physical_plot", height = "320px"),
    h4("Latest physical indicator summary"),
    DTOutput("physical_summary_table"),
    h4("Reference-month lead/lag correlation"),
    div(class = "panel-note",
        "Positive lag means the market return occurs after the PPI reference month. This is exploratory reference-month alignment, not a point-in-time release-lag signal: ECOS does not provide historical release timestamps for these observations. Monthly data is not expanded with daily LOCF."),
    DTOutput("physical_correlation_table")
  )
}

register_physical_indicators_server <- function(input, output, session, active_tab, raw_path, derived_path, physical_catalog) {
  raw_store <- reactiveVal(NULL)
  derived_store <- reactiveVal(NULL)

  ensure_loaded <- function() {
    if (is.null(raw_store())) {
      raw_store(read.fst(raw_path, as.data.table = FALSE) %>% as_tibble() %>%
                  mutate(date = as.Date(date), observation_date = as.Date(observation_date)) %>%
                  filter(series_id %in% c("KR_DRAM_PPI", "KR_FLASH_MEMORY_PPI")))
    }
    if (is.null(derived_store())) {
      derived_store(read.fst(derived_path, as.data.table = FALSE) %>% as_tibble() %>%
                      mutate(date = as.Date(date), reference_date = as.Date(reference_date)))
    }
    invisible(TRUE)
  }
  observeEvent(list(active_tab(), input$link_subtab), {
    if (identical(active_tab(), "Semiconductor & Korea Link") && identical(input$link_subtab, "Physical Indicators")) ensure_loaded()
  }, ignoreInit = TRUE)

  output$physical_status <- renderUI({
    ensure_loaded()
    latest <- raw_store() %>% group_by(series_id) %>% slice_max(date, n = 1, with_ties = FALSE) %>% ungroup() %>%
      left_join(physical_catalog %>% select(series_id, display_name, frequency, unit, source_definition), by = "series_id")
    tagList(lapply(seq_len(nrow(latest)), function(i) {
      x <- latest[i, ]
      div(class = "kr-status-band",
          strong(x$display_name), span(paste("reference month", format(x$date, "%Y-%m"))),
          span(class = "kr-status-separator", "|"), strong("Conservative availability (collected)"), span(x$available_at),
          span(class = "kr-status-separator", "|"), strong("Source"), span("Bank of Korea ECOS"),
          span(class = "kr-status-separator", "|"), strong("Frequency / unit"), span(paste(x$frequency, x$unit)),
          span(class = "kr-status-separator", "|"), strong("Quality"), span(x$quality_status))
    }))
  })

  physical_plot <- function(series_id) {
    ensure_loaded()
    measure <- input$physical_measure
    if (is.null(measure) || !nzchar(measure)) measure <- "LEVEL"
    d <- derived_store() %>% filter(metric_group == "physical_change", .data$series_id == .env$series_id,
                                    .data$measure == .env$measure, is.finite(value))
    if (nrow(d)) d <- d %>% filter(date >= max(date, na.rm = TRUE) %m-% years(10))
    req(nrow(d) > 0L)
    title <- physical_catalog$display_name[match(series_id, physical_catalog$series_id)]
    plot_ly(d, x = ~date, y = ~value, type = "scatter", mode = "lines+markers",
            line = list(width = 2, color = if (series_id == "KR_DRAM_PPI") "#2878b5" else "#23846b"),
            marker = list(size = 5),
            text = ~paste0(title, "<br>Reference: ", format(date, "%Y-%m"), "<br>", measure, ": ", round(value, 3), " ", unit,
                           "<br>Available at: ", available_at, "<br>Quality: ", quality_status), hoverinfo = "text") %>%
      layout(xaxis = list(title = "Reference month"), yaxis = list(title = unique(d$unit)), showlegend = FALSE)
  }
  output$dram_physical_plot <- renderPlotly(physical_plot("KR_DRAM_PPI"))
  output$flash_physical_plot <- renderPlotly(physical_plot("KR_FLASH_MEMORY_PPI"))

  output$physical_summary_table <- renderDT({
    ensure_loaded()
    d <- derived_store() %>% filter(metric_group == "physical_change", is.finite(value)) %>%
      group_by(series_id, measure) %>% slice_max(date, n = 1, with_ties = FALSE) %>% ungroup() %>%
      select(series_id, reference_month = date, measure, value, unit, available_at, quality_status) %>%
      pivot_wider(names_from = measure, values_from = c(value, unit)) %>%
      left_join(physical_catalog %>% select(series_id, display_name), by = "series_id") %>%
      select(display_name, everything(), -series_id)
    datatable(d, rownames = FALSE, options = list(dom = "t", scrollX = TRUE)) %>%
      formatRound(columns = grep("^value_", names(d), value = TRUE), digits = 3)
  })

  output$physical_correlation_table <- renderDT({
    ensure_loaded()
    d <- derived_store() %>% filter(metric_group == "physical_reference_month_correlation", quality_status == "REFERENCE_MONTH_ONLY") %>%
      tidyr::separate(metric_id, into = c("Indicator", "Market", "Lag"), sep = "\\|", remove = FALSE) %>%
      mutate(Correlation = round(value, 3), Observations = as.integer(aux_value)) %>%
      arrange(Indicator, desc(abs(Correlation))) %>%
      select(Indicator, Market, Lag, Correlation, Observations, quality_status)
    datatable(d, rownames = FALSE, options = list(pageLength = 20, scrollX = TRUE))
  })

  for (id in c("physical_status", "dram_physical_plot", "flash_physical_plot", "physical_summary_table", "physical_correlation_table")) {
    outputOptions(output, id, suspendWhenHidden = TRUE)
  }
  invisible(list(raw_store = raw_store, derived_store = derived_store))
}
