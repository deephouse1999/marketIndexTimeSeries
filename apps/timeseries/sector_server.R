# Sector Rotation server module.
register_sector_server <- function(input, output, session, full_data, sector_catalog) {
  sector_data <- shiny::reactive({
    benchmarks <- unique(stats::na.omit(sector_catalog$benchmark_series))
    full_data() %>% dplyr::filter(series_id %in% c(sector_catalog$series_id, benchmarks))
  })
  latest_sector_date <- shiny::reactive({
    dates <- as.Date(sector_data()$date)
    dates <- dates[!is.na(dates)]
    shiny::req(length(dates) > 0L)
    max(dates)
  })
  shiny::observeEvent(latest_sector_date(), {
    latest <- latest_sector_date()
    shiny::updateDateInput(session, "sector_asof", value = latest, max = latest)
  }, ignoreInit = FALSE)
  sector_metrics <- shiny::reactive({
    metrics <- performance_metrics(sector_data(), input$sector_asof)
    benchmark_id <- unique(stats::na.omit(sector_catalog$benchmark_series))[1]
    benchmark <- metrics %>% dplyr::filter(series_id == benchmark_id)
    shiny::req(nrow(benchmark) == 1L)
    metrics %>%
      dplyr::filter(series_id %in% sector_catalog$series_id) %>%
      dplyr::left_join(sector_catalog %>% dplyr::select(series_id, sector, rotation_bucket), by = "series_id") %>%
      dplyr::left_join(monthly_rank_change(sector_data() %>% dplyr::filter(series_id %in% sector_catalog$series_id), input$sector_asof), by = "series_id") %>%
      dplyr::mutate(Excess1M = Return1M - benchmark$Return1M, BeatsSPY = Excess1M > 0) %>%
      dplyr::arrange(dplyr::desc(.data[[input$sector_sort]]))
  })
  output$sector_beating <- shiny::renderText(sum(sector_metrics()$BeatsSPY, na.rm = TRUE))
  output$cyclical_excess <- shiny::renderText(sprintf("%.2f%%", mean(sector_metrics()$Excess1M[sector_metrics()$rotation_bucket == "cyclical"], na.rm = TRUE)))
  output$defensive_excess <- shiny::renderText(sprintf("%.2f%%", mean(sector_metrics()$Excess1M[sector_metrics()$rotation_bucket == "defensive"], na.rm = TRUE)))
  output$sector_latest <- shiny::renderText(format(max(sector_metrics()$LastDate, na.rm = TRUE), "%Y-%m-%d"))
  output$sector_excess_plot <- plotly::renderPlotly({
    d <- sector_metrics() %>% dplyr::arrange(Excess1M)
    p <- ggplot2::ggplot(d, ggplot2::aes(reorder(display_name, Excess1M), Excess1M, fill = Excess1M > 0, text = paste0(display_name, "<br>1M excess: ", round(Excess1M, 2), "%"))) +
      ggplot2::geom_col(width = 0.72) + ggplot2::coord_flip() +
      ggplot2::geom_hline(yintercept = 0, color = "#5d6975", linewidth = 0.4) +
      ggplot2::scale_fill_manual(values = c("#c94f4f", "#23846b"), guide = "none") +
      ggplot2::labs(x = NULL, y = "1M excess return vs SPY (%)") + ggplot2::theme_minimal(base_size = 12)
    plotly::ggplotly(p, tooltip = "text")
  })
  output$sector_table <- DT::renderDT({
    d <- sector_metrics() %>% dplyr::select(series_id, sector, LastDate, Return1W, Return1M, Return3M, Return6M, YTD, Excess1M, RankChange, Vol20, Vol60, Vol120) %>% dplyr::mutate(dplyr::across(where(is.numeric), ~ round(.x, 2)))
    DT::datatable(d, rownames = FALSE, colnames = c("Ticker", "Sector", "Last Date", "1W", "1M", "3M", "6M", "YTD", "1M Excess", "Rank Change", "Vol 20D", "Vol 60D", "Vol 120D"), options = list(pageLength = 15, dom = "tip", order = list(list(8, "desc")), scrollX = TRUE)) %>%
      DT::formatStyle(c("Return1W", "Return1M", "Return3M", "Return6M", "YTD", "Excess1M", "RankChange"), color = DT::styleInterval(0, c("#b23b3b", "#16705e")))
  })
}
