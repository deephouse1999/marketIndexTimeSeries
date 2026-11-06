# Semiconductor and Korea linkage server module.
register_link_server <- function(input, output, session, full_data, link_catalog) {
  link_data <- shiny::reactive({
    shiny::req(input$link_range)
    full_data() %>% dplyr::filter(series_id %in% link_catalog$series_id, date >= input$link_range[1], date <= input$link_range[2])
  })
  shiny::observe({
    predictors <- link_catalog %>% dplyr::filter(link_role %in% c("us_korea_proxy", "us_hynix"))
    choices <- stats::setNames(predictors$series_id, predictors$display_name)
    selected <- if (!is.null(input$link_predictor) && input$link_predictor %in% predictors$series_id) input$link_predictor else predictors$series_id[1]
    shiny::updateSelectInput(session, "link_predictor", choices = choices, selected = selected)
  })
  output$link_performance <- DT::renderDT({
    ids <- input$link_series
    shiny::req(length(ids))
    benchmark_id <- unique(stats::na.omit(link_catalog$benchmark_series))[1]
    metrics <- performance_metrics(link_data() %>% dplyr::filter(series_id %in% unique(c(ids, benchmark_id))), input$link_range[2])
    benchmark <- metrics %>% dplyr::filter(series_id == benchmark_id)
    shiny::req(nrow(benchmark) == 1L)
    d <- metrics %>% dplyr::filter(series_id %in% ids) %>%
      dplyr::mutate(Excess1M = Return1M - benchmark$Return1M, Excess3M = Return3M - benchmark$Return3M) %>%
      dplyr::select(series_id, display_name, LastDate, Return1W, Return1M, Return3M, Return6M, YTD, Excess1M, Excess3M) %>%
      dplyr::mutate(dplyr::across(where(is.numeric), ~ round(.x, 2)))
    DT::datatable(d, rownames = FALSE, colnames = c("Ticker", "Series", "Last Date", "1W", "1M", "3M", "6M", "YTD", "1M vs SOXX", "3M vs SOXX"), options = list(pageLength = 15, dom = "tip", scrollX = TRUE))
  })
  output$link_cumulative_plot <- plotly::renderPlotly({
    shiny::req(length(input$link_series))
    d <- link_data() %>% dplyr::filter(series_id %in% input$link_series, is.finite(effective_value)) %>%
      dplyr::group_by(series_id, display_name) %>% dplyr::arrange(date, .by_group = TRUE) %>%
      dplyr::mutate(Return = (effective_value / dplyr::first(effective_value) - 1) * 100) %>%
      dplyr::ungroup() %>% dplyr::filter(is.finite(Return))
    shiny::req(nrow(d) > 0L)
    p <- plotly::plot_ly()
    for (nm in unique(d$display_name)) {
      z <- d %>% dplyr::filter(display_name == nm)
      p <- plotly::add_lines(p, data = z, x = ~date, y = ~Return, name = nm,
                             text = ~paste0(nm, "<br>", date, "<br>", round(Return, 2), "%"),
                             hoverinfo = "text")
    }
    p %>% plotly::layout(yaxis = list(title = "Cumulative return (%)", zeroline = TRUE),
                         xaxis = list(title = ""), legend = list(title = list(text = "Series")))
  })
  output$link_spread_plot <- plotly::renderPlotly({
    roles <- link_catalog %>% dplyr::filter(link_role %in% c("semi_benchmark", "semi_breadth", "ai_signal", "memory_signal")) %>% dplyr::select(series_id, link_role)
    wide <- link_data() %>% dplyr::filter(series_id %in% roles$series_id) %>% dplyr::group_by(series_id) %>% dplyr::arrange(date, .by_group = TRUE) %>%
      dplyr::mutate(cumulative = (effective_value / dplyr::first(effective_value[is.finite(effective_value)]) - 1) * 100) %>% dplyr::ungroup() %>%
      dplyr::select(date, series_id, cumulative) %>% tidyr::pivot_wider(names_from = series_id, values_from = cumulative)
    role_id <- function(role) roles$series_id[match(role, roles$link_role)]
    semi_a <- role_id("semi_benchmark"); semi_b <- role_id("semi_breadth"); stock_a <- role_id("ai_signal"); stock_b <- role_id("memory_signal")
    shiny::req(all(c(semi_a, semi_b, stock_a, stock_b) %in% names(wide)))
    spread <- tibble::tibble(date = wide$date, SemiSpread = wide[[semi_a]] - wide[[semi_b]], StockSpread = wide[[stock_a]] - wide[[stock_b]]) %>%
      tidyr::pivot_longer(-date, names_to = "Spread", values_to = "value") %>%
      dplyr::mutate(Spread = dplyr::recode(Spread, SemiSpread = "SOXX - XSD", StockSpread = "NVDA - MU")) %>%
      dplyr::filter(is.finite(value))
    shiny::req(nrow(spread) > 0L)
    p <- plotly::plot_ly()
    for (nm in unique(spread$Spread)) {
      z <- spread %>% dplyr::filter(Spread == nm)
      p <- plotly::add_lines(p, data = z, x = ~date, y = ~value, name = nm,
                             text = ~paste0(nm, "<br>", date, "<br>", round(value, 2), " pp"),
                             hoverinfo = "text")
    }
    p %>% plotly::layout(yaxis = list(title = "Cumulative return spread (pp)", zeroline = TRUE),
                         xaxis = list(title = ""), legend = list(title = list(text = "Spread")))
  })
  make_returns <- function(ids) {
    link_data() %>% dplyr::filter(series_id %in% ids) %>% dplyr::group_by(series_id) %>% dplyr::arrange(date, .by_group = TRUE) %>%
      dplyr::mutate(ret = effective_value / dplyr::lag(effective_value) - 1) %>% dplyr::ungroup()
  }
  aligned_returns <- shiny::reactive({
    shiny::req(input$link_predictor)
    kr_id <- link_catalog$series_id[match("kr_market", link_catalog$link_role)]
    shiny::req(length(kr_id) == 1L, !is.na(kr_id))
    returns <- make_returns(c(input$link_predictor, kr_id))
    align_us_kr_returns(returns %>% dplyr::filter(series_id == input$link_predictor) %>% dplyr::select(date, ret), returns %>% dplyr::filter(series_id == kr_id) %>% dplyr::select(date, ret), input$link_alignment)
  })
  output$link_relation_table <- DT::renderDT({
    predictors <- link_catalog %>% dplyr::filter(link_role %in% c("us_korea_proxy", "us_hynix"))
    kr_id <- link_catalog$series_id[match("kr_market", link_catalog$link_role)]
    result <- purrr::map_dfr(predictors$series_id, function(predictor_id) {
      returns <- make_returns(c(predictor_id, kr_id))
      aligned <- align_us_kr_returns(returns %>% dplyr::filter(series_id == predictor_id) %>% dplyr::select(date, ret), returns %>% dplyr::filter(series_id == kr_id) %>% dplyr::select(date, ret), input$link_alignment)
      ok <- stats::complete.cases(aligned$us_ret, aligned$kr_ret); n_obs <- sum(ok)
      if (n_obs < 20L) return(tibble::tibble(Predictor = predictor_id, Observations = n_obs, Correlation = NA_real_, Beta = NA_real_, R2 = NA_real_))
      fit <- stats::lm(aligned$kr_ret[ok] ~ aligned$us_ret[ok])
      tibble::tibble(Predictor = predictor_id, Observations = n_obs, Correlation = stats::cor(aligned$us_ret[ok], aligned$kr_ret[ok]), Beta = unname(stats::coef(fit)[2]), R2 = summary(fit)$r.squared)
    }) %>% dplyr::mutate(dplyr::across(c(Correlation, Beta, R2), ~ round(.x, 3)))
    DT::datatable(result, rownames = FALSE, options = list(dom = "t"))
  })
  output$link_rolling_plot <- plotly::renderPlotly({
    d <- aligned_returns() %>% dplyr::mutate(Corr20 = rolling_correlation(us_ret, kr_ret, 20L), Corr60 = rolling_correlation(us_ret, kr_ret, 60L), Corr120 = rolling_correlation(us_ret, kr_ret, 120L)) %>%
      dplyr::select(kr_date, dplyr::starts_with("Corr")) %>% tidyr::pivot_longer(-kr_date, names_to = "Window", values_to = "Correlation") %>%
      dplyr::filter(is.finite(Correlation))
    shiny::req(nrow(d) > 0L)
    p <- plotly::plot_ly()
    for (nm in unique(d$Window)) {
      z <- d %>% dplyr::filter(Window == nm)
      p <- plotly::add_lines(p, data = z, x = ~kr_date, y = ~Correlation, name = nm,
                             text = ~paste0(nm, "<br>", kr_date, "<br>", round(Correlation, 3)),
                             hoverinfo = "text")
    }
    p %>% plotly::layout(yaxis = list(title = "Rolling correlation", range = c(-1, 1), zeroline = TRUE),
                         xaxis = list(title = ""), legend = list(title = list(text = "Window")))
  })
}
