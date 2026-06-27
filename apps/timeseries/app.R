### app.R -------------------------------------------------------------------
library(shiny)
library(fst)
library(dplyr)
library(lubridate)
library(quantmod)
library(DT)
library(ggplot2)
library(plotly)
library(tidyr)
library(viridis)
library(zoo)

get_local_data_dir <- function() {
  candidates <- unique(c(
    getwd(),
    file.path(getwd(), "us_dat_extract", "data"),
    file.path(getwd(), "econ", "us_dat_extract", "data"),
    "C:/app/econ_ts/us_dat_extract/data"
  ))

  for (candidate in candidates) {
    if (file.exists(file.path(candidate, "app.R"))) {
      return(normalizePath(candidate, winslash = "/", mustWork = TRUE))
    }
  }

  normalizePath(getwd(), winslash = "/", mustWork = TRUE)
}

### 1 Yahoo Series ? -------------------------------------------------
series_interface_yahoo <- data.frame(
  series_id=c('2YY=F','^TNX','^TYX','AGGG.L',
              '^DJI','^GSPC','^IXIC','^VIX','^TOPX','^FTSE','^GDAXI','^HSI','^KS11','EWY','ACWI','URTH','EEM',
              'USDKRW=X','USDJPY=X','USDCNY=X','USDEUR=X','USDGBP=X','DX-Y.NYB',
              'AAPL','GOOG','TSLA','META','NVDA','LLY',
              'ZC=F','HE=F','CL=F','NG=F','GC=F','BTC-USD'),
  stringsAsFactors = FALSE
)

###  ? ? ? ---------------------------------------------------
yahoo_start_date <- ymd("1976-01-01")

safe_yahoo <- purrr::possibly(function(x, beg_dy = yahoo_start_date){
  beg_dy <- as.Date(beg_dy)
  if (is.na(beg_dy) || beg_dy > Sys.Date()) return(tibble())

  tmp <- suppressWarnings(getSymbols(x, src = "yahoo", from = beg_dy, auto.assign = FALSE))
  tmp_df <- data.frame(date = index(tmp), coredata(tmp))

  close_col <- grep("\\.Close$", names(tmp_df), value = TRUE)
  if (length(close_col) == 0) {
    close_col <- grep("Close", names(tmp_df), value = TRUE)
  }
  if (length(close_col) == 0) return(tibble())

  tmp_df %>%
    transmute(
      date = as.Date(date),
      value = as.numeric(.data[[close_col[1]]]),
      series_id = x
    ) %>%
    filter(!is.na(date), !is.na(value))
}, otherwise = tibble())


# ---  ??? (?)

data_dir <- get_local_data_dir()
data_path <- file.path(data_dir, "original_ts_yahoo.fst")

if (!dir.exists(data_dir)) {
  dir.create(data_dir, recursive = TRUE)
}

download_full_yahoo_series <- function(series_ids) {
  purrr::map_dfr(
    series_ids,
    ~ safe_yahoo(.x, beg_dy = yahoo_start_date)
  )
}

load_yahoo_data <- function() {
  if (!file.exists(data_path)) {
    message("No Yahoo data file found. Downloading full history...")
    yahoo_data <- download_full_yahoo_series(series_interface_yahoo$series_id)
    write.fst(yahoo_data, data_path, compress = 50)
    yahoo_data
  } else {
    read.fst(data_path) %>%
      mutate(date = as.Date(date))
  }
}

update_yahoo_data <- function(existing_df) {
  configured_series <- unique(series_interface_yahoo$series_id)
  existing_df <- existing_df %>%
    mutate(date = as.Date(date)) %>%
    filter(series_id %in% configured_series)

  existing_series <- unique(existing_df$series_id)
  new_series <- setdiff(configured_series, existing_series)
  new_series_history <- download_full_yahoo_series(new_series)

  message("Starting Yahoo data update...")
  ts_series_last_dy <- existing_df %>%
    group_by(series_id) %>%
    summarize(most_recent_dy = max(date), .groups = "drop")
  
  yahoo_series_last_day <- purrr::map2_dfr(
    ts_series_last_dy$series_id,
    ts_series_last_dy$most_recent_dy,
    ~ safe_yahoo(.x, beg_dy = .y + 1)
  )
  
  downloaded <- bind_rows(new_series_history, yahoo_series_last_day)

  if (nrow(downloaded) > 0) {
    combined <- bind_rows(existing_df, downloaded) %>%
      distinct(series_id, date, .keep_all = TRUE) %>%
      arrange(series_id, date)
    write.fst(combined, data_path, compress = 50)
    downloaded_series <- dplyr::n_distinct(downloaded$series_id)
    failed_new_series <- setdiff(new_series, unique(new_series_history$series_id))
    if (length(failed_new_series) > 0) {
      message("Yahoo skipped unavailable new series: ", paste(failed_new_series, collapse = ", "))
    }
    message(sprintf(
      "Yahoo update complete: %s downloaded series, %s new rows saved to %s",
      downloaded_series,
      nrow(downloaded),
      data_path
    ))
    return(combined)
  } else {
    write.fst(existing_df, data_path, compress = 50)
    message("No new Yahoo rows found. Existing data saved unchanged.")
    return(existing_df)
  }
}

### 4 ???  (??? --------------------------------------
series_name_map <- data.frame(
  series_id=c('2YY=F','^TNX','^TYX','AGGG.L',
              '^DJI','^GSPC','^IXIC','^VIX','^TOPX','^FTSE','^GDAXI','^HSI','^KS11','EWY','ACWI','URTH','EEM',
              'USDKRW=X','USDJPY=X','USDCNY=X','USDEUR=X','USDGBP=X','DX-Y.NYB',
              'AAPL','GOOG','TSLA','META','NVDA','LLY',
              'ZC=F','HE=F','CL=F','NG=F','GC=F','BTC-USD'),
  display_name = c("US 2Y Yield","US 10Y Yield","US 30Y Yield","Core Global Aggregate Bond UCITS ETF USD(ETF)",
                   "Dow Jones Industrial","S&P 500","Nasdaq Composite","VIX",
                   "TOPIX","FTSE",'DAX','Hang Seng Index','KOSPI','MSCI Korea(ETF)','MSCI ACWI(ETF)','MSCI GLOBE(ETF)','MSCI EMERGING(ETF)',
                   "USD/KRW","USD/JPY","USD/CNY","USD/EUR","USD/GBP","DXY",
                   "Apple","Google","Tesla","Meta","Nvidia","Eli Lilly",
                   "Corn Futures","Lean Hogs","WTI Crude","Natural Gas","Gold","Bitcoin")
)

format_scale_factor <- function(scale_factor) {
  vapply(scale_factor, function(x) {
    if (is.na(x) || x == 0 || abs(x - 1) < 1e-8) return("")

    factor <- if (abs(x) >= 1000 || abs(x) < 0.01) {
      formatC(x, format = "e", digits = 2)
    } else if (abs(x) >= 10) {
      formatC(x, format = "f", digits = 1)
    } else {
      formatC(x, format = "f", digits = 3)
    }

    paste0(" (/", factor, ")")
  }, character(1))
}

scale_to_endpoint_band <- function(d) {
  endpoints <- d %>%
    arrange(series_id, date) %>%
    group_by(series_id, display_name) %>%
    summarize(endpoint_value = dplyr::last(value[!is.na(value)]), .groups = "drop") %>%
    filter(!is.na(endpoint_value), endpoint_value != 0)

  if (nrow(endpoints) == 0) {
    return(
      d %>%
        mutate(
          scale_factor = 1,
          scaled_display_name = display_name,
          scaled_value = value
        )
    )
  }

  endpoints <- endpoints %>%
    mutate(
      scale_factor = abs(endpoint_value) / 100,
      scale_factor = ifelse(is.na(scale_factor) | scale_factor == 0, 1, scale_factor),
      scale_suffix = format_scale_factor(scale_factor),
      scaled_display_name = paste0(display_name, scale_suffix)
    ) %>%
    select(series_id, display_name, scale_factor, scaled_display_name)

  d %>%
    left_join(endpoints, by = c("series_id", "display_name")) %>%
    mutate(
      scale_factor = ifelse(is.na(scale_factor) | scale_factor == 0, 1, scale_factor),
      scaled_display_name = ifelse(is.na(scaled_display_name), display_name, scaled_display_name),
      scaled_value = value / scale_factor
    )
}

### 5 UI --------------------------------------------------------------
ui <- fluidPage(
  titlePanel("Market Dashboard (Yahoo Data)"),
  actionButton("update_data", "Update Data (Yahoo)", class = "btn-primary"),
  dateRangeInput("date_range",
                 "Date range:",
                 start = ceiling_date(Sys.Date() - years(1), "year"),
                 end   = Sys.Date(),
                 format = "yyyy-mm-dd"),
  h3("Current Change (YTD / DoD / MDD / MDU)"),
  DTOutput("currentChangeTable"),
  br(),
  conditionalPanel(
    condition = "output.table_has_selection",
    downloadButton("download_selected_csv", "Download Selected CSV"),
    h3("Selected Series Time Series (Pct change from Day 0)"),
    plotlyOutput("tsPlot", height = "420px"),
    h3("Selected Series Absolute Level (Endpoint-scaled)"),
    plotlyOutput("levelPlot", height = "460px")

  ),
  br(),
  h3("Correlation Matrix"),
  DTOutput("corrMatrix"),
  
  br(),
  h3("Beta Matrix (vs first selected series)"),
  DTOutput("betaMatrix"),
  
  br(),
  h3("Monthly Return Distribution (Selected series)"),
  DTOutput("momStatsTable")
  
  
)
  


### 6 SERVER ----------------------------------------------------------
server <- function(input, output, session) {
  initial_yahoo_data <- load_yahoo_data()
  initial_yahoo_data <- update_yahoo_data(initial_yahoo_data)
  yahoo_data <- reactiveVal(initial_yahoo_data)
  
  observeEvent(input$update_data, {
    updated <- update_yahoo_data(yahoo_data())
    yahoo_data(updated)   # ?
  })
  
  
  filteredData <- reactive({
    yahoo_data() %>%
      left_join(series_name_map, by = "series_id") %>%
      mutate(display_name = ifelse(is.na(display_name), series_id, display_name)) %>%
      filter(!is.na(value),
             date >= input$date_range[1],
             date <= input$date_range[2])
  })
  
  currentTableData <- reactive({
    d <- filteredData()
    d %>%
      group_by(display_name, series_id) %>%
      arrange(date) %>%
      summarise(
        current_value = last(value),
        first_val = first(value),
        prev_val  = nth(value, n()-1),
        max_val   = max(value, na.rm = TRUE),
        min_val   = min(value, na.rm = TRUE),
        .groups = "drop"
      ) %>%
      mutate(
        YTD = (current_value / first_val - 1) * 100,
        DoD = (current_value / prev_val - 1) * 100,
        MDD = (current_value / max_val - 1) * 100,
        MDU = (current_value / min_val - 1) * 100
      ) %>%
      select(series_id, display_name, current_value,first_val, YTD, DoD, MDD, MDU) %>%
      mutate(across(-c(series_id, display_name), ~round(.x, 2)))
  })

  # 1) ???? ???(??? ?)
  currentTableData_sorted <- reactive({
    currentTableData() %>%
      arrange(match(series_id, series_name_map$series_id))
  })
  
  
    
  output$currentChangeTable <- renderDT({
    datatable(
      currentTableData_sorted(),
      rownames  = FALSE,
      selection = "multiple",
      options   = list(pageLength = 50)   #  ????, order ? ? ?
    ) %>%
      formatStyle(
        columns = c("current_value", "first_val","YTD", "DoD", "MDD", "MDU"),
        color = styleInterval(0, c("red", "green")),
        fontWeight = "bold"
      )
  })
  
  
  output$corrMatrix <- renderDT({
    # ??? ?? ??????(? ?)
    sel_ids <- selectedSeries()
    if (is.null(sel_ids) || length(sel_ids) < 2) return(NULL)
    
    d <- filteredData() %>%
      filter(series_id %in% sel_ids)
    
    # display_name??2?? ??? ?? ?
    if (n_distinct(d$display_name) < 2) return(NULL)
    
    d_wide <- d %>%
      select(date, display_name, value) %>%
      pivot_wider(names_from = display_name, values_from = value)
    
    corr_mat <- round(cor(d_wide[,-1], use = "pairwise.complete.obs"), 3)
    corr_df  <- as.data.frame(corr_mat) %>%
      tibble::rownames_to_column("Series")
    
    datatable(corr_df, rownames = FALSE, options = list(scrollX = TRUE)) %>%
      formatStyle(
        columns = colnames(corr_df)[-1],
        backgroundColor = styleInterval(
          c(-0.5, 0, 0.5),
          c("#d73027","#ffffbf","#1a9850","#006837")
        )
      )
  })
  
  selectedSeries <- reactive({
    sel <- input$currentChangeTable_rows_selected
    cur <- input$currentChangeTable_rows_current
    if (is.null(sel) || length(sel) == 0) return(NULL)

    current_view <- if (!is.null(cur)) currentTableData_sorted()[cur, , drop = FALSE]
    else currentTableData_sorted()

    current_view$series_id[sel]
  })

  output$table_has_selection <- reactive({ !is.null(selectedSeries()) })
  outputOptions(output, "table_has_selection", suspendWhenHidden = FALSE)

  selectedDataForDownload <- reactive({
    req(selectedSeries())

    filteredData() %>%
      filter(series_id %in% selectedSeries()) %>%
      arrange(series_id, date) %>%
      select(date, series_id, display_name, value)
  })

  output$download_selected_csv <- downloadHandler(
    filename = function() {
      paste0(
        "selected_yahoo_series_",
        format(input$date_range[1], "%Y%m%d"),
        "_",
        format(input$date_range[2], "%Y%m%d"),
        ".csv"
      )
    },
    content = function(file) {
      write.csv(selectedDataForDownload(), file, row.names = FALSE, na = "")
    }
  )
  
  # ??Day0??pct change(%)????plot
  output$tsPlot <- renderPlotly({
    req(selectedSeries())
    
    d <- filteredData() %>%
      filter(series_id %in% selectedSeries()) %>%
      arrange(series_id, date) %>%
      group_by(series_id, display_name) %>%
      mutate(
        base_val = first(value),
        pct_chg_from_day0 = (value / base_val - 1) * 100
      ) %>%
      ungroup()
    
    p <- ggplot(d, aes(x = date, y = pct_chg_from_day0, color = display_name)) +
      geom_hline(yintercept = 0, linewidth = 0.4, linetype = "dashed") +
      geom_line(linewidth = 0.6) +
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
      filter(any(!is.na(value))) %>%
      ungroup() %>%
      scale_to_endpoint_band() %>%
      mutate(
        hover_text = paste0(
          display_name,
          "<br>Date: ", date,
          "<br>Original value: ", round(value, 4),
          "<br>Shown value: ", round(scaled_value, 4),
          ifelse(scale_factor == 1, "", paste0("<br>Scale: ", format_scale_factor(scale_factor)))
        )
      )

    if (nrow(d) == 0) return(NULL)

    plot_ly(
      d,
      x = ~date,
      y = ~scaled_value,
      color = ~scaled_display_name,
      text = ~hover_text,
      type = "scatter",
      mode = "lines+markers",
      hoverinfo = "text",
      line = list(width = 2),
      marker = list(size = 4)
    ) %>%
      layout(
        xaxis = list(title = "Date"),
        yaxis = list(title = "Endpoint-normalized level (last value = 100)"),
        legend = list(title = list(text = "Series"))
      )
  })
  
  output$betaMatrix <- renderDT({
    sel_ids <- selectedSeries()
    
    #  2?? (benchmark + ???
    if (is.null(sel_ids) || length(sel_ids) < 2) return(NULL)
    
    benchmark_id <- sel_ids[1]
    
    # 1 ? ??
    ret_df <- filteredData() %>%
      filter(series_id %in% sel_ids) %>%
      arrange(series_id, date) %>%
      group_by(series_id) %>%
      mutate(
        ret = (value / lag(value) - 1)
      ) %>%
      ungroup() %>%
      filter(!is.na(ret))
    
    # 2 wide ????( ??? ?)
    ret_wide <- ret_df %>%
      select(date, series_id, ret) %>%
      tidyr::pivot_wider(names_from = series_id, values_from = ret)
    
    rb <- ret_wide[[benchmark_id]]
    
    if (all(is.na(rb))) return(NULL)
    
    # 3 ? 
    beta_vec <- sapply(sel_ids, function(x) {
      ri <- ret_wide[[x]]
      idx <- complete.cases(ri, rb)
      if (sum(idx) < 20) return(NA_real_)
      cov(ri[idx], rb[idx]) / var(rb[idx])
    })
    
    beta_df <- tibble::tibble(
      series_id = sel_ids,
      beta_vs_benchmark = round(beta_vec, 4)
    ) %>%
      left_join(series_name_map, by = "series_id") %>%
      mutate(
        display_name = ifelse(is.na(display_name), series_id, display_name),
        role = ifelse(series_id == benchmark_id, "Benchmark", "Asset")
      ) %>%
      select(role, display_name, beta_vs_benchmark)
    
    datatable(
      beta_df,
      rownames = FALSE,
      options = list(dom = "t", pageLength = 50)
    ) %>%
      formatStyle(
        "beta_vs_benchmark",
        backgroundColor = styleInterval(
          c(0.5, 1, 1.5),
          c("#d9f0a3", "#addd8e", "#78c679", "#238443")
        ),
        fontWeight = "bold"
      )
  })
  
  
  #####rolling beta
  output$momStatsTable <- renderDT({
    sel_ids <- selectedSeries()
    if (is.null(sel_ids) || length(sel_ids) == 0) return(NULL)
    
    # ? ??
    d <- filteredData() %>%
      filter(series_id %in% sel_ids) %>%
      arrange(series_id, date) %>%
      mutate(month = lubridate::floor_date(date, unit = "month"))
    
    if (nrow(d) == 0) return(NULL)
    
    # ? ?(????? ??
    mom <- d %>%
      group_by(series_id, display_name, month) %>%
      summarise(
        month_end_date = max(date),
        month_end_val  = dplyr::last(value),
        .groups = "drop"
      ) %>%
      arrange(series_id, month_end_date) %>%
      group_by(series_id, display_name) %>%
      mutate(
        mom_ret_pct = (month_end_val / dplyr::lag(month_end_val) - 1) * 100
      ) %>%
      ungroup() %>%
      filter(!is.na(mom_ret_pct), is.finite(mom_ret_pct))
    
    if (nrow(mom) == 0) return(NULL)
    
    # ? ?
    stats <- mom %>%
      group_by(series_id, display_name) %>%
      summarise(
        n_months = dplyr::n(),
        mean   = mean(mom_ret_pct, na.rm = TRUE),
        median = median(mom_ret_pct, na.rm = TRUE),
        p05 = as.numeric(quantile(mom_ret_pct, 0.05, na.rm = TRUE, type = 7)),
        p25 = as.numeric(quantile(mom_ret_pct, 0.25, na.rm = TRUE, type = 7)),
        p75 = as.numeric(quantile(mom_ret_pct, 0.75, na.rm = TRUE, type = 7)),
        p95 = as.numeric(quantile(mom_ret_pct, 0.95, na.rm = TRUE, type = 7)),
        .groups = "drop"
      ) %>%
      mutate(.order = match(series_id, sel_ids)) %>%
      arrange(.order) %>%
      select(-.order) %>%
      mutate(across(c(mean, median, p05, p25, p75, p95), ~round(.x, 3)))
    
    datatable(
      stats,
      rownames = FALSE,
      options = list(pageLength = 50, scrollX = TRUE)
    ) %>%
      formatStyle(
        columns = c("mean", "median"),
        fontWeight = "bold"
      )
  })
  
 
}

shinyApp(ui, server)

