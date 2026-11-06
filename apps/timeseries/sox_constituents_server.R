sox_constituents_ui <- function() {
  tagList(
    div(class = "panel-note",
        "SOX membership is the official Nasdaq snapshot. Weights are SOXQ proxy weights, not official index weights. Constituent breadth and value-chain history starts with the first complete official snapshot, so these views currently describe the latest cross-section rather than a long backtest."),
    tabsetPanel(
      id = "sox_subtab",
      tabPanel("Overview", uiOutput("sox_status"), h4("Current 5-Year Return Comparison"),
               div(class = "panel-note", "Common-start return index: each series equals 100 at the beginning of the shared five-year window. A value of 180 means an 80% cumulative return."),
               imageOutput("sox_benchmark_plot", height = "360px")),
      tabPanel("Breadth",
               div(class = "panel-note", "Breadth is the share of the 30 SOX constituents with a positive daily return. The table also shows advancing, declining, and unchanged counts."),
               plotlyOutput("sox_breadth_plot", height = "360px"), DTOutput("sox_daily_table")),
      tabPanel("Contribution",
               div(class = "panel-note", "Contribution equals each stock's daily return multiplied by its normalized SOXQ proxy weight. Click a bar to see the company's constituent description."),
               dateInput("sox_contribution_date", "Contribution date", value = Sys.Date()),
               div(style = "display:none", textInput("sox_selected_ticker", NULL, value = "")),
               plotlyOutput("sox_contribution_plot", height = "700px"),
               uiOutput("sox_selected_company")),
      tabPanel("Value Chain",
               div(class = "panel-note", "Latest one-day proxy-weighted return by semiconductor value-chain group. It is a cross-sectional snapshot until additional official membership dates accumulate."),
               plotlyOutput("sox_chain_plot", height = "430px")),
      tabPanel("Korea Link",
               div(class = "panel-note", "Rolling correlation maps each US semiconductor close to the next KOSPI trading session. This is association, not a causal forecast."),
               dateRangeInput("sox_link_range", "Analysis range", start = Sys.Date() - lubridate::years(5), end = Sys.Date()),
               selectInput("sox_link_metric", "Relation", choices = character()),
               plotlyOutput("sox_korea_plot", height = "390px")),
      tabPanel("Constituents",
               div(class = "panel-note", "Select a row to inspect the company's products, end markets, and Korea linkage."),
               DTOutput("sox_constituents_table"), uiOutput("sox_selected_company_table")),
      tabPanel("Data Quality", DTOutput("sox_quality_table"), downloadButton("download_sox_data", "Download derived CSV", icon = icon("download")))
    )
  )
}

register_sox_constituents_server <- function(input, output, session, active_tab, derived_path, latest_path, overview_image_path, constituent_path) {
  latest_store <- reactiveVal(NULL)
  full_store <- reactiveVal(NULL)
  constituent_store <- reactiveVal(NULL)

  read_sox_fst <- function(path) {
    read.fst(path, as.data.table = FALSE) %>% as_tibble() %>% mutate(date = as.Date(date))
  }
  ensure_latest <- function() {
    if (is.null(latest_store())) latest_store(read_sox_fst(latest_path))
    latest_store()
  }
  ensure_full <- function() {
    if (is.null(full_store())) full_store(read_sox_fst(derived_path))
    full_store()
  }
  ensure_constituents <- function() {
    if (is.null(constituent_store())) constituent_store(readr::read_csv(constituent_path, show_col_types = FALSE))
    constituent_store()
  }

  # Preload only the small first-view indexes; the full derived history stays lazy.
  latest_store(read_sox_fst(latest_path))
  constituent_store(readr::read_csv(constituent_path, show_col_types = FALSE))

  observeEvent(active_tab(), {
    if (identical(active_tab(), "SOX Constituents")) {
      ensure_latest()
      ensure_constituents()
    }
  }, ignoreInit = TRUE)
  observeEvent(input$sox_subtab, {
    req(identical(active_tab(), "SOX Constituents"))
    if (input$sox_subtab %in% c("Breadth", "Contribution", "Value Chain", "Korea Link", "Data Quality")) ensure_full()
  }, ignoreInit = TRUE)

  output$sox_status <- renderUI({
    d <- ensure_latest()
    cst <- ensure_constituents()
    last_date <- max(d$date, na.rm = TRUE)
    aggregate_date <- max(d$date[d$metric_group == "daily_summary"], na.rm = TRUE)
    tagList(
      div(class = "kr-status-band",
          strong("Membership"), span(paste(nrow(cst), "official Nasdaq components as of", max(cst$membership_as_of))),
          span(class = "kr-status-separator", "|"), strong("Weight"), span(paste("SOXQ proxy as of", max(cst$weight_as_of))),
          span(class = "kr-status-separator", "|"), strong("Derived"), span(as.character(last_date)),
          span(class = "kr-status-separator", "|"), strong("Member aggregate"), span(paste(aggregate_date, "(latest complete 30/30)")))
    )
  })

  output$sox_benchmark_plot <- renderImage({
    list(src = overview_image_path, contentType = "image/png", alt = "SOX benchmark adjusted return index comparison")
  }, deleteFile = FALSE)

  daily_wide <- reactive({
    ensure_full() %>% filter(metric_group == "daily_summary") %>%
      select(date, metric_id, value, quality_flag) %>% pivot_wider(names_from = metric_id, values_from = value)
  })
  output$sox_breadth_plot <- renderPlotly({
    d <- daily_wide() %>% arrange(date) %>% mutate(date_label = format(date, "%Y-%m-%d"))
    plot_ly(d, x = ~date_label, y = ~breadth_pct, type = "bar",
            marker = list(color = "#2878b5"),
            text = ~paste0(date, "<br>Advancing: ", advancing, "/", member_count, "<br>Breadth: ", round(breadth_pct, 1), "%"), hoverinfo = "text") %>%
      layout(title = "SOX constituent breadth", bargap = 0.35,
             yaxis = list(title = "Advancing members (%)", range = c(0, 100)),
             xaxis = list(title = "Trading date", type = "category"))
  })
  output$sox_daily_table <- renderDT({
    daily_wide() %>% arrange(desc(date)) %>% mutate(across(where(is.numeric), ~round(.x, 6))) %>%
      datatable(rownames = FALSE, options = list(pageLength = 25, scrollX = TRUE))
  })

  output$sox_contribution_plot <- renderPlotly({
    cutoff <- if (is.null(input$sox_contribution_date)) Sys.Date() else as.Date(input$sox_contribution_date)
    all_d <- ensure_full() %>% filter(metric_group == "constituent_contribution", date <= cutoff)
    req(nrow(all_d) > 0L)
    selected_date <- max(all_d$date)
    d <- all_d %>% filter(date == selected_date) %>%
      group_by(metric_id) %>% summarize(value = sum(value, na.rm = TRUE), .groups = "drop") %>% arrange(value)
    p <- plot_ly(d, x = ~value, y = ~reorder(metric_id, value), key = ~metric_id, customdata = ~metric_id,
                 source = "sox_contribution", type = "bar", orientation = "h",
                 marker = list(color = ifelse(d$value >= 0, "#2878b5", "#c44e52")),
                 text = ~paste0(metric_id, ": ", round(100 * value, 3), " pp"), hoverinfo = "text") %>%
      layout(title = paste("SOXQ proxy contribution", selected_date),
             xaxis = list(title = "Contribution (decimal return)"), yaxis = list(title = ""), margin = list(l = 70))
    htmlwidgets::onRender(p, "function(el) { el.on('plotly_click', function(e) { if (!e.points || !e.points.length) return; var p=e.points[0]; var ticker=p.customdata || p.key || p.y; Shiny.setInputValue('sox_selected_ticker', String(ticker), {priority:'event'}); }); }")
  })

  output$sox_chain_plot <- renderPlotly({
    all_d <- ensure_full() %>% filter(metric_group == "value_chain_return", is.finite(value))
    req(nrow(all_d) > 0L)
    selected_date <- max(all_d$date)
    d <- all_d %>% filter(date == selected_date) %>% arrange(value)
    plot_ly(d, x = ~value * 100, y = ~reorder(metric_id, value), type = "bar", orientation = "h",
            marker = list(color = ifelse(d$value >= 0, "#23846b", "#c94f4f")),
            text = ~paste0(metric_id, "<br>", date, "<br>Proxy-weighted return: ", round(100 * value, 2), "%<br>Members: ", as.integer(aux_value)),
            hoverinfo = "text") %>%
      layout(title = paste("Value-chain return snapshot", selected_date),
             yaxis = list(title = ""), xaxis = list(title = "One-day return (%)"), margin = list(l = 150))
  })

  observeEvent(list(active_tab(), input$sox_subtab), {
    req(identical(active_tab(), "SOX Constituents"), identical(input$sox_subtab, "Korea Link"))
    d <- ensure_latest() %>% filter(metric_group == "us_next_korea")
    choices <- sort(unique(d$metric_id))
    labels <- vapply(strsplit(choices, "\\|", fixed = FALSE), function(x) {
      if (length(x) != 3L) return(paste(x, collapse = " | "))
      paste0(x[1], " to next-session KOSPI, ", sub("D_CORR$", "-day correlation", x[3]))
    }, character(1))
    updateSelectInput(session, "sox_link_metric", choices = stats::setNames(choices, labels), selected = choices[1])
  })
  output$sox_korea_plot <- renderPlotly({
    req(input$sox_link_metric)
    d <- ensure_full() %>% filter(metric_group == "us_next_korea", metric_id == input$sox_link_metric,
                                  date >= input$sox_link_range[1], date <= input$sox_link_range[2], is.finite(value))
    req(nrow(d) > 0L)
    plot_ly(d, x = ~date, y = ~value, type = "scatter", mode = "lines",
            text = ~paste0(date, "<br>Rolling correlation: ", round(value, 3), "<br>", quality_flag), hoverinfo = "text") %>%
      layout(yaxis = list(title = "Rolling correlation", range = c(-1, 1)), xaxis = list(title = "Korea trading date"))
  })

  output$sox_constituents_table <- renderDT({
    ensure_constituents() %>%
      select(ticker, company_name, country, value_chain, core_products, end_market, korea_link,
             proxy_weight_decimal, weight_source, weight_as_of, effective_from, quality_flag) %>%
      mutate(proxy_weight_pct = round(100 * proxy_weight_decimal, 3)) %>%
      select(-proxy_weight_decimal) %>%
      datatable(rownames = FALSE, selection = "single", options = list(pageLength = 30, scrollX = TRUE))
  })

  company_detail <- function(ticker) {
    d <- ensure_constituents() %>% filter(.data$ticker == ticker) %>% slice_head(n = 1)
    if (!nrow(d)) return(NULL)
    div(class = "company-detail",
        h4(paste0(d$company_name, " (", d$ticker, ")")),
        tags$dl(
          tags$dt("Value chain"), tags$dd(d$value_chain),
          tags$dt("Core products"), tags$dd(d$core_products),
          tags$dt("End markets"), tags$dd(d$end_market),
          tags$dt("Korea linkage"), tags$dd(d$korea_link)
        ))
  }
  output$sox_selected_company <- renderUI({
    req(input$sox_selected_ticker)
    company_detail(as.character(input$sox_selected_ticker))
  })
  output$sox_selected_company_table <- renderUI({
    idx <- input$sox_constituents_table_rows_selected
    req(length(idx) == 1L)
    d <- ensure_constituents() %>%
      select(ticker, company_name, country, value_chain, core_products, end_market, korea_link,
             proxy_weight_decimal, weight_source, weight_as_of, effective_from, quality_flag)
    company_detail(d$ticker[[idx]])
  })
  output$sox_quality_table <- renderDT({
    ensure_constituents() %>% count(membership_source, weight_source, membership_as_of, weight_as_of, quality_flag, name = "series") %>%
      mutate(historical_membership_before_2026_11_04 = "NOT_AVAILABLE") %>%
      datatable(rownames = FALSE, options = list(dom = "t", scrollX = TRUE))
  })
  output$download_sox_data <- downloadHandler(
    filename = function() paste0("derived_sox_daily_summary_", Sys.Date(), ".csv"),
    content = function(file) write.csv(ensure_full(), file, row.names = FALSE, na = "")
  )

  outputOptions(output, "sox_status", suspendWhenHidden = FALSE)
  outputOptions(output, "sox_benchmark_plot", suspendWhenHidden = FALSE)
  for (id in c("sox_breadth_plot", "sox_daily_table", "sox_contribution_plot",
               "sox_chain_plot", "sox_korea_plot", "sox_constituents_table", "sox_quality_table")) {
    outputOptions(output, id, suspendWhenHidden = TRUE)
  }
  invisible(list(latest_store = latest_store, full_store = full_store, constituent_store = constituent_store))
}
