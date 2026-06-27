local_lib <- file.path("C:/app/econ_ts", "R", "library")
if (dir.exists(local_lib)) {
  .libPaths(c(local_lib, .libPaths()))
}

library(shiny)
library(dplyr)
library(DT)
library(lubridate)

data_file <- file.path(getwd(), "econ_us_processed_latest.rda")
if (!file.exists(data_file)) {
  stop("Missing econ_us_processed_latest.rda. Run us_dat_extract/update_bl_dashboard_data.R first.")
}

load(data_file)

breakdown_data_file <- file.path(getwd(), "us_econ_breakdown_data.rda")
if (file.exists(breakdown_data_file)) {
  load(breakdown_data_file)
}

shelter_lag_data_file <- file.path(getwd(), "shelter_lag_correlation_data.rda")
if (file.exists(shelter_lag_data_file)) {
  load(shelter_lag_data_file)
}

inflation_transmission_data_file <- file.path(getwd(), "inflation_transmission_data.rda")
if (file.exists(inflation_transmission_data_file)) {
  load(inflation_transmission_data_file)
}

empty_breakdown_ts <- data.frame(
  date = as.Date(character()),
  series_id = character(),
  series_name = character(),
  category_lv1 = character(),
  category_lv2 = character(),
  value = numeric(),
  stringsAsFactors = FALSE
)

if (!exists("tab_cpi_series_map")) tab_cpi_series_map <- empty_breakdown_ts[0, c("series_id", "series_name", "category_lv1", "category_lv2")]
if (!exists("data_cpi_element_ts")) data_cpi_element_ts <- empty_breakdown_ts
if (!exists("data_cpi_element_weight")) data_cpi_element_weight <- data.frame(date = as.Date(character()), series_id = character(), series_name = character(), weight_pct = numeric(), source = character())
if (!exists("data_cpi_element_contribution")) data_cpi_element_contribution <- data.frame(date = as.Date(character()), series_id = character(), series_name = character(), category_lv1 = character(), category_lv2 = character(), weight_pct = numeric(), mom_pct = numeric(), yoy_pct = numeric(), contribution_mom = numeric(), contribution_yoy = numeric())
if (!exists("tab_emp_series_map")) tab_emp_series_map <- empty_breakdown_ts[0, c("series_id", "series_name", "category_lv1", "category_lv2")]
if (!exists("data_emp_breakdown_ts")) data_emp_breakdown_ts <- empty_breakdown_ts
if (!exists("data_emp_contribution")) data_emp_contribution <- data.frame(date = as.Date(character()), series_id = character(), series_name = character(), category_lv1 = character(), category_lv2 = character(), value = numeric(), mom_chg = numeric(), yoy_chg = numeric(), mom_chg_3m_avg = numeric(), yoy_pct = numeric(), share_of_total_mom = numeric())
if (!exists("tab_shelter_lag_series_map")) tab_shelter_lag_series_map <- data.frame(series_group = character(), side = character(), category_lv1 = character(), category_lv2 = character(), series_name = character(), series_id = character(), unit = character(), transform_type = character(), display_order = integer(), use_yn = character(), stringsAsFactors = FALSE)
if (!exists("data_shelter_lag_ts")) data_shelter_lag_ts <- data.frame(date = as.Date(character()), side = character(), series_id = character(), series_name = character(), category_lv1 = character(), category_lv2 = character(), value = numeric(), mom_pct = numeric(), yoy_pct = numeric(), mom_chg = numeric(), yoy_chg = numeric(), latest_yn = character(), stringsAsFactors = FALSE)
if (!exists("data_shelter_lag_corr")) data_shelter_lag_corr <- data.frame(x_series_id = character(), x_series_name = character(), y_series_id = character(), y_series_name = character(), lag_month = integer(), n_obs = integer(), corr = numeric(), r_squared = numeric(), start_date = as.Date(character()), end_date = as.Date(character()), stringsAsFactors = FALSE)
if (!exists("tab_shelter_lag_best_corr")) tab_shelter_lag_best_corr <- data.frame(x_series_id = character(), x_series_name = character(), y_series_id = character(), y_series_name = character(), best_lag_month = integer(), best_corr = numeric(), best_r_squared = numeric(), n_obs = integer(), interpretation = character(), stringsAsFactors = FALSE)
if (!exists("data_shelter_rolling_corr")) data_shelter_rolling_corr <- data.frame(date = as.Date(character()), x_series_id = character(), x_series_name = character(), y_series_id = character(), y_series_name = character(), lag_month = integer(), rolling_window = integer(), rolling_corr = numeric(), stringsAsFactors = FALSE)
if (!exists("tab_pce_series_map")) tab_pce_series_map <- data.frame(series_group = character(), series_type = character(), category_lv1 = character(), category_lv2 = character(), series_name = character(), series_id = character(), unit = character(), display_order = integer(), use_yn = character(), stringsAsFactors = FALSE)
if (!exists("data_pce_nowcast_input")) data_pce_nowcast_input <- data.frame(date = as.Date(character()), series_id = character(), series_name = character(), category_lv1 = character(), category_lv2 = character(), value = numeric(), mom_pct = numeric(), yoy_pct = numeric(), latest_yn = character(), stringsAsFactors = FALSE)
if (!exists("data_pce_official")) data_pce_official <- data.frame(date = as.Date(character()), pce_yoy = numeric(), core_pce_yoy = numeric(), pce_mom = numeric(), core_pce_mom = numeric(), estimated_core_pce_yoy = numeric(), estimated_error = numeric(), pressure_score = numeric(), pressure_level = character(), stringsAsFactors = FALSE)
if (!exists("data_pce_model_coef")) data_pce_model_coef <- data.frame(date = as.Date(character()), intercept = numeric(), beta_core_cpi = numeric(), beta_core_ppi = numeric(), beta_shelter = numeric(), beta_import_price = numeric(), n_obs = integer(), stringsAsFactors = FALSE)
if (!exists("data_inflation_corr")) data_inflation_corr <- data.frame(source_series = character(), source_series_id = character(), target_series = character(), target_series_id = character(), lag_month = integer(), corr = numeric(), r_squared = numeric(), n_obs = integer(), stringsAsFactors = FALSE)
if (!exists("tab_inflation_best_lag")) tab_inflation_best_lag <- data.frame(source_series = character(), source_series_id = character(), target_series = character(), target_series_id = character(), best_lag = integer(), best_corr = numeric(), best_r_squared = numeric(), n_obs = integer(), stringsAsFactors = FALSE)
if (!exists("data_inflation_heatmap")) data_inflation_heatmap <- data.frame(source_series = character(), target_series = character(), corr = numeric(), best_lag = integer(), stringsAsFactors = FALSE)

if (!exists("key_market_events")) {
  key_market_events <- tibble::tibble(
    released_dy = as.Date(character()),
    released_at = character(),
    event_group = character(),
    event_nm_withunit = character(),
    measure_period = character(),
    released_val = numeric(),
    surv_med_val = numeric(),
    surprise_val = numeric(),
    material_score = numeric(),
    spx_ret_pct = numeric(),
    spx_next_ret_pct = numeric(),
    spx_5d_ret_pct = numeric(),
    tnx_ret_pct = numeric(),
    tnx_value = numeric(),
    spx_close = numeric()
  )
}

add_row_heat_columns <- function(df, value_cols) {
  heat_cols <- paste0("heat_", value_cols)
  values <- as.matrix(df[value_cols])
  storage.mode(values) <- "numeric"

  heat_values <- t(apply(values, 1, function(row_values) {
    finite <- is.finite(row_values)
    if (!any(finite)) {
      return(rep(NA_real_, length(row_values)))
    }

    row_range <- range(row_values[finite], na.rm = TRUE)
    if ((row_range[2] - row_range[1]) == 0) {
      out <- rep(0.5, length(row_values))
      out[!finite] <- NA_real_
      return(out)
    }

    out <- (row_values - row_range[1]) / (row_range[2] - row_range[1])
    out[!finite] <- NA_real_
    out
  }))

  df[heat_cols] <- as.data.frame(round(heat_values, 3))
  names(df)[(ncol(df) - length(heat_cols) + 1):ncol(df)] <- heat_cols
  df
}

add_column_heat <- function(df, value_col, heat_col) {
  values <- suppressWarnings(as.numeric(df[[value_col]]))
  finite <- is.finite(values)

  heat <- rep(NA_real_, length(values))
  if (any(finite)) {
    max_abs <- max(abs(values[finite]), na.rm = TRUE)
    if (is.finite(max_abs) && max_abs > 0) {
      heat[finite] <- pmax(-1, pmin(1, values[finite] / max_abs))
    } else {
      heat[finite] <- 0
    }
  }

  df[[heat_col]] <- round(heat, 3)
  df
}

surprise_palette <- c(
  "#f3b1b8", "#f5bdc2", "#f8cace", "#fad6d9", "#fce3e4",
  "#ffffff",
  "#e4f6e9", "#caefd3", "#afe8bc", "#95e1a6", "#7bd98f"
)

has_plotly <- requireNamespace("plotly", quietly = TRUE)

latest_series_row <- function(df, series_id_value) {
  df %>%
    filter(series_id == series_id_value) %>%
    arrange(date) %>%
    slice_tail(n = 1)
}

metric_column <- function(metric, type) {
  if (type == "cpi") {
    switch(
      metric,
      "Index" = "value",
      "MoM" = "mom_pct",
      "YoY" = "yoy_pct",
      "3M Annualized" = "chg_3m_ann",
      "6M Annualized" = "chg_6m_ann",
      "value"
    )
  } else {
    switch(
      metric,
      "Level" = "value",
      "MoM Change" = "mom_chg",
      "YoY Change" = "yoy_chg",
      "3M Avg MoM Change" = "mom_chg_3m_avg",
      "YoY %" = "yoy_pct",
      "value"
    )
  }
}

shelter_metric_column <- function(metric) {
  switch(
    metric,
    "MoM %" = "mom_pct",
    "YoY change" = "yoy_chg",
    "YoY %" = "yoy_pct",
    "yoy_pct"
  )
}

z_score <- function(x) {
  finite <- is.finite(x)
  out <- rep(NA_real_, length(x))
  if (!any(finite)) return(out)
  s <- stats::sd(x[finite], na.rm = TRUE)
  if (!is.finite(s) || s == 0) return(out)
  out[finite] <- (x[finite] - mean(x[finite], na.rm = TRUE)) / s
  out
}

value_box_html <- function(title, value, suffix = "") {
  value_txt <- if (length(value) == 0 || is.na(value)) "NA" else paste0(round(value, 2), suffix)
  HTML(paste0(
    "<div style='display:inline-block; min-width:180px; margin:0 10px 10px 0; padding:10px 12px;",
    "background:#ffffff; border:1px solid #d8dde6; border-radius:6px;'>",
    "<div style='font-size:12px; color:#6b7280;'>", title, "</div>",
    "<div style='font-size:20px; font-weight:700; color:#111827;'>", value_txt, "</div>",
    "</div>"
  ))
}

pressure_badge_html <- function(level, score) {
  level_txt <- if (length(level) == 0 || is.na(level)) "NA" else level
  score_txt <- if (length(score) == 0 || is.na(score)) "NA" else round(score, 2)
  color <- switch(level_txt, Low = "#16a34a", Moderate = "#ca8a04", High = "#ea580c", Extreme = "#dc2626", "#6b7280")
  HTML(paste0(
    "<div style='display:inline-block; min-width:220px; margin:0 10px 10px 0; padding:10px 12px;",
    "background:#ffffff; border:1px solid #d8dde6; border-radius:6px;'>",
    "<div style='font-size:12px; color:#6b7280;'>Inflation Pressure Score</div>",
    "<div style='font-size:20px; font-weight:750; color:", color, ";'>", level_txt, " <span style='font-size:13px; color:#4b5563;'>", score_txt, "</span></div>",
    "</div>"
  ))
}

ui <- fluidPage(
  tags$head(
    tags$style(HTML("
      body {
        background: #f7f8fa;
        color: #17202a;
        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
      }
      .container-fluid {
        max-width: 1520px;
        margin: 0 auto;
        padding: 18px 24px 32px;
      }
      h2 {
        margin: 2px 0 16px;
        font-size: 22px;
        font-weight: 650;
      }
      h4 {
        margin-top: 16px;
        font-size: 15px;
        font-weight: 650;
      }
      .nav-tabs {
        border-bottom-color: #d8dde6;
        margin-bottom: 14px;
      }
      .nav-tabs > li > a {
        color: #384252;
        border-radius: 6px 6px 0 0;
      }
      .nav-tabs > li.active > a,
      .nav-tabs > li.active > a:focus,
      .nav-tabs > li.active > a:hover {
        color: #111827;
        background: #ffffff;
        border-color: #d8dde6 #d8dde6 transparent;
      }
      .form-control {
        border-radius: 6px;
        border-color: #cfd6df;
        box-shadow: none;
      }
      .legend-note {
        display: inline-flex;
        align-items: center;
        gap: 10px;
        padding: 8px 10px;
        margin: 4px 0 12px;
        border: 1px solid #d8dde6;
        border-radius: 6px;
        background: #ffffff;
        color: #4b5563;
        font-size: 12px;
      }
      .heatbar {
        width: 120px;
        height: 10px;
        border-radius: 999px;
        border: 1px solid #d8dde6;
        background: linear-gradient(90deg, #f6b7bd 0%, #fff7e6 50%, #6fd58a 100%);
      }
      .surprisebar {
        width: 120px;
        height: 10px;
        border-radius: 999px;
        border: 1px solid #d8dde6;
        background: linear-gradient(90deg, #f6b7bd 0%, #ffffff 50%, #6fd58a 100%);
      }
      table.dataTable {
        width: 100% !important;
        border-collapse: collapse !important;
        background: #ffffff;
        font-size: 12px;
      }
      .dataTables_wrapper {
        width: 100%;
      }
      .dataTables_scrollHeadInner,
      .dataTables_scrollHeadInner table {
        width: 100% !important;
      }
      table.dataTable thead th {
        background: #f1f4f8;
        color: #374151;
        border-bottom: 1px solid #cfd6df !important;
        font-weight: 650;
        white-space: nowrap;
      }
      table.dataTable tbody td {
        border-top: 1px solid #e5e9ef;
        vertical-align: middle;
        white-space: nowrap;
      }
      table.dataTable.stripe tbody tr.odd,
      table.dataTable.display tbody tr.odd {
        background-color: #fbfcfe;
      }
      table.dataTable.display tbody tr:hover > .sorting_1,
      table.dataTable.order-column.hover tbody tr:hover > .sorting_1,
      table.dataTable.hover tbody tr:hover,
      table.dataTable.display tbody tr:hover {
        background-color: #eef4ff !important;
      }
      table.dataTable tbody tr.selected,
      table.dataTable tbody tr.selected > * {
        box-shadow: none !important;
        color: inherit !important;
      }
      .dt-right,
      table.dataTable tbody td.dt-right,
      table.dataTable thead th.dt-right {
        font-variant-numeric: tabular-nums;
        text-align: right;
      }
    "))
  ),
  titlePanel("US Economic Indicators Dashboard"),
  tabsetPanel(
    tabPanel(
      "MoM Summary",
      dateInput(
        "reference_date",
        "Reference date:",
        value = Sys.Date(),
        max = Sys.Date(),
        format = "yyyy-mm-dd"
      ),
      h4("Monthly Change Summary Table"),
      htmlOutput("table1Legend"),
      DTOutput("coloredTTable")
    ),
    tabPanel(
      "Release Schedule",
      h4("Economic Surprise Table"),
      selectInput(
        "release_window",
        "Date window:",
        choices = c(
          "Today and later" = "future",
          "Past + today and later" = "all"
        ),
        selected = "future",
        width = "240px"
      ),
      htmlOutput("table2Legend"),
      DTOutput("econScheduleTable")
    ),
    tabPanel(
      "Key Event Moves",
      h4("CPI / Nonfarm Payrolls vs S&P500"),
      fluidRow(
        column(
          3,
          selectInput(
            "key_event_group",
            "Event:",
            choices = c("All" = "all", "CPI" = "CPI", "Nonfarm Payrolls" = "Nonfarm Payrolls"),
            selected = "all"
          )
        ),
        column(
          3,
          numericInput(
            "min_abs_surprise",
            "Minimum abs surprise:",
            value = 0,
            min = 0,
            step = 0.5
          )
        ),
        column(
          3,
          checkboxInput(
            "spx_down_only",
            "S&P500 down days only",
            value = FALSE
          )
        )
      ),
      htmlOutput("keyEventLegend"),
      DTOutput("keyEventTable")
    ),
    tabPanel(
      "CPI Breakdown",
      h4("CPI Breakdown"),
      htmlOutput("cpiValueBoxes"),
      fluidRow(
        column(
          3,
          selectInput(
            "cpi_category",
            "CPI Category:",
            choices = sort(unique(tab_cpi_series_map$category_lv1)),
            selected = if (nrow(tab_cpi_series_map) > 0) sort(unique(tab_cpi_series_map$category_lv1))[1] else NULL
          )
        ),
        column(
          3,
          selectInput(
            "cpi_series",
            "CPI Component:",
            choices = sort(unique(tab_cpi_series_map$series_name)),
            selected = if (nrow(tab_cpi_series_map) > 0) tab_cpi_series_map$series_name[1] else NULL
          )
        ),
        column(
          4,
          radioButtons(
            "cpi_metric",
            "Metric:",
            choices = c("Index", "MoM", "YoY", "3M Annualized", "6M Annualized"),
            selected = "YoY",
            inline = TRUE
          )
        )
      ),
      uiOutput("cpiPlotUi"),
      h4("Latest CPI Components"),
      DTOutput("table_cpi_latest_breakdown"),
      h4("Weight-based approximate contribution"),
      DTOutput("table_cpi_contribution")
    ),
    tabPanel(
      "Employment Breakdown",
      h4("Employment Breakdown"),
      htmlOutput("empValueBoxes"),
      fluidRow(
        column(
          3,
          selectInput(
            "emp_category",
            "Employment Category:",
            choices = sort(unique(tab_emp_series_map$category_lv1)),
            selected = if (nrow(tab_emp_series_map) > 0) sort(unique(tab_emp_series_map$category_lv1))[1] else NULL
          )
        ),
        column(
          3,
          selectInput(
            "emp_series",
            "Employment Component:",
            choices = sort(unique(tab_emp_series_map$series_name)),
            selected = if (nrow(tab_emp_series_map) > 0) tab_emp_series_map$series_name[1] else NULL
          )
        ),
        column(
          5,
          radioButtons(
            "emp_metric",
            "Metric:",
            choices = c("Level", "MoM Change", "YoY Change", "3M Avg MoM Change", "YoY %"),
            selected = "MoM Change",
            inline = TRUE
          )
        )
      ),
      uiOutput("empPlotUi"),
      h4("Latest Employment Components"),
      DTOutput("table_emp_latest_breakdown"),
      h4("Monthly employment contribution"),
      DTOutput("table_emp_contribution")
    ),
    tabPanel(
      "Shelter Lag Correlation",
      h4("Shelter Lag Correlation"),
      fluidRow(
        column(
          3,
          selectInput(
            "shelter_x_series",
            "Leading indicator:",
            choices = tab_shelter_lag_series_map %>%
              filter(side == "X") %>%
              arrange(display_order) %>%
              pull(series_name),
            selected = if (nrow(tab_shelter_lag_series_map %>% filter(side == "X")) > 0) {
              tab_shelter_lag_series_map %>%
                filter(side == "X") %>%
                arrange(display_order) %>%
                pull(series_name) %>%
                .[1]
            } else {
              NULL
            }
          )
        ),
        column(
          3,
          selectInput(
            "shelter_y_series",
            "Shelter component:",
            choices = tab_shelter_lag_series_map %>%
              filter(side == "Y") %>%
              arrange(display_order) %>%
              pull(series_name),
            selected = if (nrow(tab_shelter_lag_series_map %>% filter(side == "Y")) > 0) {
              tab_shelter_lag_series_map %>%
                filter(side == "Y") %>%
                arrange(display_order) %>%
                pull(series_name) %>%
                .[1]
            } else {
              NULL
            }
          )
        ),
        column(
          3,
          sliderInput("shelter_lag_range", "Lag months:", min = 0, max = 24, value = c(0, 24), step = 1)
        ),
        column(
          3,
          radioButtons(
            "shelter_transform",
            "Transform:",
            choices = c("YoY %", "MoM %", "YoY change"),
            selected = "YoY %",
            inline = TRUE
          )
        )
      ),
      uiOutput("shelterLagCorrPlotUi"),
      uiOutput("shelterOverlayPlotUi"),
      h4("Best lag summary"),
      DTOutput("table_shelter_lag_best"),
      h4("Full lag correlation"),
      DTOutput("table_shelter_lag_corr"),
      div(
        class = "legend-note",
        "Note: Lag correlation is descriptive and does not prove causality. A positive lag means the selected leading indicator is shifted forward to compare with later Shelter/Rent/OER CPI movements. The overlay keeps the shifted leading indicator beyond the latest Shelter date when source data is available."
      )
    ),
    tabPanel(
      "Inflation Transmission",
      h4("Official Inflation"),
      htmlOutput("inflationValueBoxes"),
      h4("Inflation Flow Chart"),
      radioButtons(
        "inflation_flow_path",
        "Transmission path:",
        choices = c(
          "Goods / PPI path" = "goods",
          "Labor / Shelter path" = "shelter",
          "All paths" = "all"
        ),
        selected = "all",
        inline = TRUE
      ),
      htmlOutput("inflationFlowChart"),
      h4("Official vs Estimated Core PCE"),
      div(class = "legend-note", "Estimated Core PCE is a rolling 120-month bridge model anchored on Core CPI. Use it as a directional monitor, not a release replacement."),
      htmlOutput("pceNowcastMetrics"),
      uiOutput("pceNowcastPlotUi"),
      h4("Lag Correlation Heatmap"),
      div(class = "legend-note", "Each colored cell shows the strongest historical YoY correlation for the selected transmission path. Green is positive, pink is negative, white is near zero; missing cells mean that source-target pair is not part of the current matrix. Hover for best lag in months."),
      uiOutput("inflationHeatmapUi"),
      h4("Correlation Explorer"),
      div(class = "legend-note", "The explorer recalculates the lag curve for a selected source and target. The overlay shifts the source forward by the best lag and keeps forward-looking source data visible."),
      fluidRow(
        column(
          3,
          selectInput(
            "inflation_source_series",
            "Source series:",
            choices = sort(unique(data_inflation_corr$source_series)),
            selected = if (nrow(data_inflation_corr) > 0) sort(unique(data_inflation_corr$source_series))[1] else NULL
          )
        ),
        column(
          3,
          selectInput(
            "inflation_target_series",
            "Target series:",
            choices = sort(unique(data_inflation_corr$target_series)),
            selected = if (nrow(data_inflation_corr) > 0) sort(unique(data_inflation_corr$target_series))[1] else NULL
          )
        )
      ),
      htmlOutput("inflationPairSummary"),
      uiOutput("inflationCorrCurveUi"),
      uiOutput("inflationOverlayUi"),
      h4("Selected Pair Lag Table"),
      DTOutput("table_inflation_pair_lags"),
      h4("PCE Risk Monitor"),
      div(class = "legend-note", "Pressure score is the average z-score of Core CPI, Core PPI, Shelter, and Import Prices. Higher scores mean broader inflation pressure versus history."),
      htmlOutput("inflationPressureBadge"),
      DTOutput("table_pce_nowcast"),
      h4("Best Lag Table"),
      div(class = "legend-note", "Best lag is the lag month with the largest absolute correlation. Positive lag means the source historically leads the target."),
      DTOutput("table_inflation_best_lag")
    )
  )
)

server <- function(input, output, session) {
  reactive_summary <- reactive({
    req(input$reference_date)
    ref_date <- as.Date(input$reference_date)

    df_latest <- data_mom_chg %>%
      filter(released_dy <= ref_date) %>%
      group_by(event_nm_withunit) %>%
      slice_max(order_by = released_dy, n = 1, with_ties = FALSE) %>%
      ungroup() %>%
      mutate(series_seq = 0L)

    df_history <- data_mom_chg %>%
      semi_join(df_latest, by = "event_nm_withunit") %>%
      inner_join(
        df_latest %>% select(event_nm_withunit, latest_release = released_dy),
        by = "event_nm_withunit"
      ) %>%
      filter(released_dy < latest_release) %>%
      group_by(event_nm_withunit) %>%
      arrange(desc(released_dy), .by_group = TRUE) %>%
      mutate(series_seq = row_number()) %>%
      filter(series_seq <= 24) %>%
      ungroup() %>%
      select(-latest_release)

    df_combined <- bind_rows(df_latest, df_history)

    recent_events <- df_combined %>%
      filter(series_seq == 0L) %>%
      group_by(event_nm_withunit) %>%
      summarise(last_release = max(released_dy, na.rm = TRUE), .groups = "drop") %>%
      filter(last_release > (ref_date %m-% months(12)))

    df_combined %>%
      semi_join(recent_events, by = "event_nm_withunit") %>%
      group_by(sub_category, event_nm_withunit) %>%
      reframe(
        Frequency = frequency[1],
        Importance = material_score[1],
        T0_Date = format(released_dy[series_seq == 0][1], "%Y-%m-%d"),
        T0 = released_val[series_seq == 0][1],
        T1 = released_val[series_seq == 1][1],
        T2 = released_val[series_seq == 2][1],
        T3 = released_val[series_seq == 3][1],
        T4 = released_val[series_seq == 4][1],
        T5 = released_val[series_seq == 5][1],
        T6 = released_val[series_seq == 6][1],
        avg_T7T12 = mean(released_val[series_seq %in% 7:12], na.rm = TRUE),
        avg_T13T24 = mean(released_val[series_seq %in% 13:24], na.rm = TRUE),
        diff_T0 = mom_val[series_seq == 0][1],
        diff_T1 = mom_val[series_seq == 1][1],
        diff_T2 = mom_val[series_seq == 2][1],
        diff_T3 = mom_val[series_seq == 3][1],
        diff_T4 = mom_val[series_seq == 4][1],
        diff_T5 = mom_val[series_seq == 5][1],
        diff_T6 = mom_val[series_seq == 6][1],
        diff_avg_T7T12 = mean(mom_val[series_seq %in% 7:12], na.rm = TRUE),
        diff_avg_T13T24 = mean(mom_val[series_seq %in% 13:24], na.rm = TRUE)
      ) %>%
      ungroup() %>%
      filter(is.na(Importance) | Importance >= 60) %>%
      group_by(sub_category) %>%
      slice_max(order_by = coalesce(Importance, 0), n = 5, with_ties = FALSE) %>%
      ungroup() %>%
      mutate(across(where(is.numeric), ~ round(.x, 2)))
  })

  output$table1Legend <- renderUI({
    HTML("
      <div class='legend-note'>
        <span>Row-level heatmap</span>
        <span class='heatbar'></span>
        <span>lower level</span>
        <span>higher level</span>
      </div>
    ")
  })

  output$coloredTTable <- renderDT({
    df1 <- reactive_summary()
    req(nrow(df1) > 0)

    t_cols <- c(paste0("T", 0:6), "avg_T7T12", "avg_T13T24")
    diff_cols <- paste0("diff_", t_cols)
    heat_cols <- paste0("heat_", t_cols)
    df1 <- add_row_heat_columns(df1, t_cols)
    hide_cols <- which(names(df1) %in% c(diff_cols, heat_cols)) - 1
    numeric_cols <- which(names(df1) %in% c("Importance", t_cols)) - 1
    heat_pairs <- lapply(t_cols, function(col_name) {
      list(
        value = which(names(df1) == col_name) - 1,
        heat = which(names(df1) == paste0("heat_", col_name)) - 1
      )
    })

    dt_out <- datatable(
      df1,
      rownames = FALSE,
      selection = "none",
      class = "compact stripe hover row-border",
      width = "100%",
      options = list(
        ordering = TRUE,
        pageLength = 50,
        autoWidth = FALSE,
        scrollX = TRUE,
        dom = "tip",
        initComplete = JS("function(settings, json) { this.api().columns.adjust(); }"),
        rowCallback = JS(
          sprintf(
            "
            function(row, data) {
              var pairs = %s;
              function heatColor(x) {
                if (x === null || x === '' || isNaN(x)) {
                  return '#f7f8fa';
                }
                x = Math.max(0, Math.min(1, parseFloat(x)));
                var low = [246, 183, 189];
                var mid = [255, 247, 230];
                var high = [111, 213, 138];
                var a = x <= 0.5 ? low : mid;
                var b = x <= 0.5 ? mid : high;
                var t = x <= 0.5 ? x * 2 : (x - 0.5) * 2;
                var r = Math.round(a[0] + (b[0] - a[0]) * t);
                var g = Math.round(a[1] + (b[1] - a[1]) * t);
                var bl = Math.round(a[2] + (b[2] - a[2]) * t);
                return 'rgb(' + r + ',' + g + ',' + bl + ')';
              }
              pairs.forEach(function(pair) {
                var cell = $('td:eq(' + pair.value + ')', row);
                var heat = data[pair.heat];
                cell.css({
                  'background-color': heatColor(heat),
                  'color': '#17202a',
                  'font-weight': heat >= 0.82 || heat <= 0.18 ? '650' : '400'
                });
              });
            }
            ",
            jsonlite::toJSON(heat_pairs, auto_unbox = TRUE)
          )
        ),
        columnDefs = list(
          list(targets = hide_cols, visible = FALSE),
          list(targets = numeric_cols, className = "dt-right"),
          list(targets = which(names(df1) == "T0_Date") - 1, width = "100px")
        )
      )
    )

    dt_out
  })

  output$table2Legend <- renderUI({
    HTML("
      <div class='legend-note'>
        <span>Surprise intensity</span>
        <span class='surprisebar'></span>
        <span>below consensus</span>
        <span>above consensus</span>
      </div>
    ")
  })

  output$econScheduleTable <- renderDT({
    req(input$release_window)

    df1 <- tab_econ_us_schedule_release %>%
      arrange(event_nm_withunit, desc(released_dy)) %>%
      group_by(event_nm_withunit) %>%
      mutate(seq = row_number()) %>%
      filter(seq <= 5 | cls %in% c("this", "next", "next2", "next3", "next4")) %>%
      ungroup() %>%
      filter(input$release_window == "all" | released_dy >= Sys.Date()) %>%
      mutate(
        released_time = if ("released_time" %in% names(.)) as.character(released_time) else "",
        released_dy = if_else(
          !is.na(released_time) & released_time != "",
          paste(format(released_dy, "%Y-%m-%d"), substr(released_time, 1, 5)),
          format(released_dy, "%Y-%m-%d")
        ),
        cls = factor(
          cls,
          levels = c("past", "this", "next", "next2", "next3", "next4"),
          labels = c("Past", "This week", "+1 week", "+2 weeks", "+3 weeks", "+4 weeks")
        )
      ) %>%
      select(
        released_dy,
        cls,
        sub_category,
        event_nm_withunit,
        released_val,
        surv_med_val,
        surprise_val,
        material_score
      ) %>%
      mutate(across(c(released_val, surv_med_val, surprise_val, material_score), ~ round(.x, 2))) %>%
      add_column_heat("surprise_val", "heat_surprise")

    dt_out <- datatable(
      df1,
      rownames = FALSE,
      selection = "none",
      class = "compact stripe hover row-border",
      width = "100%",
      options = list(
        ordering = TRUE,
        pageLength = 50,
        autoWidth = FALSE,
        scrollX = FALSE,
        dom = "tip",
        initComplete = JS("function(settings, json) { this.api().columns.adjust(); }"),
        columnDefs = list(
          list(targets = which(names(df1) == "heat_surprise") - 1, visible = FALSE),
          list(targets = which(names(df1) %in% c("released_val", "surv_med_val", "surprise_val", "material_score")) - 1, className = "dt-right"),
          list(targets = which(names(df1) == "released_dy") - 1, width = "90px"),
          list(targets = which(names(df1) == "cls") - 1, width = "90px")
        )
      )
    )

    dt_out %>%
      formatStyle(
        "surprise_val",
        valueColumns = "heat_surprise",
        backgroundColor = styleInterval(
          c(-0.8, -0.6, -0.4, -0.2, -0.01, 0.01, 0.2, 0.4, 0.6, 0.8),
          surprise_palette
        ),
        fontWeight = styleInterval(c(-0.65, 0.65), c("650", "400", "650")),
        color = "#17202a"
      ) %>%
      formatStyle(
        "cls",
        target = "cell",
        backgroundColor = styleEqual(
          c("Past", "This week", "+1 week", "+2 weeks", "+3 weeks", "+4 weeks"),
          c("#f1f4f8", "#dff7e7", "#ecf9f0", "#f7fbf8", "#ffffff", "#ffffff")
        ),
        color = styleEqual(
          c("Past", "This week", "+1 week", "+2 weeks", "+3 weeks", "+4 weeks"),
          c("#4b5563", "#166534", "#166534", "#374151", "#374151", "#374151")
        )
      )
  })

  output$keyEventLegend <- renderUI({
    HTML("
      <div class='legend-note'>
        <span>Market surprise / S&P500 move</span>
        <span class='surprisebar'></span>
        <span>negative</span>
        <span>positive</span>
      </div>
    ")
  })

  output$keyEventTable <- renderDT({
    req(input$key_event_group, input$min_abs_surprise)

    df1 <- key_market_events %>%
      filter(!is.na(surprise_val)) %>%
      filter(input$key_event_group == "all" | event_group == input$key_event_group) %>%
      filter(abs(surprise_val) >= input$min_abs_surprise) %>%
      filter(!isTRUE(input$spx_down_only) | (!is.na(spx_ret_pct) & spx_ret_pct < 0)) %>%
      transmute(
        released_at,
        event_group,
        event_nm_withunit,
        measure_period,
        actual = released_val,
        survey = surv_med_val,
        market_surprise = surprise_val,
        spx_ret_pct,
        spx_next_ret_pct,
        spx_5d_ret_pct,
        tnx_ret_pct,
        tnx_value,
        spx_close
      ) %>%
      mutate(
        across(c(actual, survey, market_surprise, spx_ret_pct, spx_next_ret_pct, spx_5d_ret_pct, tnx_ret_pct, tnx_value, spx_close), ~ round(.x, 2))
      ) %>%
      add_column_heat("market_surprise", "heat_surprise") %>%
      add_column_heat("spx_ret_pct", "heat_spx") %>%
      add_column_heat("spx_5d_ret_pct", "heat_spx_5d") %>%
      add_column_heat("tnx_ret_pct", "heat_tnx")

    dt_out <- datatable(
      df1,
      rownames = FALSE,
      selection = "none",
      class = "compact stripe hover row-border",
      width = "100%",
      options = list(
        ordering = TRUE,
        pageLength = 50,
        autoWidth = FALSE,
        scrollX = FALSE,
        dom = "tip",
        initComplete = JS("function(settings, json) { this.api().columns.adjust(); }"),
        columnDefs = list(
          list(targets = which(names(df1) %in% c("heat_surprise", "heat_spx", "heat_spx_5d", "heat_tnx")) - 1, visible = FALSE),
          list(targets = which(names(df1) %in% c("actual", "survey", "market_surprise", "spx_ret_pct", "spx_next_ret_pct", "spx_5d_ret_pct", "tnx_ret_pct", "tnx_value", "spx_close")) - 1, className = "dt-right"),
          list(targets = which(names(df1) == "released_at") - 1, width = "115px")
        )
      )
    )

    dt_out %>%
      formatStyle(
        "market_surprise",
        valueColumns = "heat_surprise",
        backgroundColor = styleInterval(
          c(-0.8, -0.6, -0.4, -0.2, -0.01, 0.01, 0.2, 0.4, 0.6, 0.8),
          surprise_palette
        ),
        fontWeight = styleInterval(c(-0.65, 0.65), c("650", "400", "650")),
        color = "#17202a"
      ) %>%
      formatStyle(
        "spx_ret_pct",
        valueColumns = "heat_spx",
        backgroundColor = styleInterval(
          c(-0.8, -0.6, -0.4, -0.2, -0.01, 0.01, 0.2, 0.4, 0.6, 0.8),
          surprise_palette
        ),
        fontWeight = styleInterval(c(-0.65, 0.65), c("650", "400", "650")),
        color = "#17202a"
      ) %>%
      formatStyle(
        "spx_5d_ret_pct",
        valueColumns = "heat_spx_5d",
        backgroundColor = styleInterval(
          c(-0.8, -0.6, -0.4, -0.2, -0.01, 0.01, 0.2, 0.4, 0.6, 0.8),
          surprise_palette
        ),
        fontWeight = styleInterval(c(-0.65, 0.65), c("650", "400", "650")),
        color = "#17202a"
      ) %>%
      formatStyle(
        "tnx_ret_pct",
        valueColumns = "heat_tnx",
        backgroundColor = styleInterval(
          c(-0.8, -0.6, -0.4, -0.2, -0.01, 0.01, 0.2, 0.4, 0.6, 0.8),
          surprise_palette
        ),
        fontWeight = styleInterval(c(-0.65, 0.65), c("650", "400", "650")),
        color = "#17202a"
      )
  })

  observeEvent(input$cpi_category, {
    choices <- tab_cpi_series_map %>%
      filter(category_lv1 == input$cpi_category) %>%
      arrange(display_order, series_name) %>%
      pull(series_name)
    updateSelectInput(session, "cpi_series", choices = choices, selected = choices[1])
  }, ignoreInit = FALSE)

  observeEvent(input$emp_category, {
    choices <- tab_emp_series_map %>%
      filter(category_lv1 == input$emp_category) %>%
      arrange(display_order, series_name) %>%
      pull(series_name)
    updateSelectInput(session, "emp_series", choices = choices, selected = choices[1])
  }, ignoreInit = FALSE)

  observeEvent(input$inflation_source_series, {
    choices <- data_inflation_corr %>%
      filter(source_series == input$inflation_source_series) %>%
      distinct(target_series) %>%
      arrange(target_series) %>%
      pull(target_series)
    updateSelectInput(session, "inflation_target_series", choices = choices, selected = choices[1])
  }, ignoreInit = FALSE)

  output$cpiValueBoxes <- renderUI({
    headline <- latest_series_row(data_cpi_element_ts, "CPIAUCSL")
    core <- latest_series_row(data_cpi_element_ts, "CPILFESL")
    shelter <- latest_series_row(data_cpi_element_ts, "CUSR0000SAH1")
    oer <- latest_series_row(data_cpi_element_ts, "CUSR0000SEHC")

    tagList(
      value_box_html("Headline CPI YoY", headline$yoy_pct, "%"),
      value_box_html("Core CPI YoY", core$yoy_pct, "%"),
      value_box_html("Shelter CPI MoM", shelter$mom_pct, "%"),
      value_box_html("OER CPI MoM", oer$mom_pct, "%")
    )
  })

  output$empValueBoxes <- renderUI({
    total <- latest_series_row(data_emp_breakdown_ts, "PAYEMS")
    private <- latest_series_row(data_emp_breakdown_ts, "USPRIV")
    government <- latest_series_row(data_emp_breakdown_ts, "USGOVT")

    tagList(
      value_box_html("Total nonfarm MoM", total$mom_chg),
      value_box_html("Private payroll MoM", private$mom_chg),
      value_box_html("Government payroll MoM", government$mom_chg),
      value_box_html("Total 3M avg gain", total$mom_chg_3m_avg)
    )
  })

  cpi_plot_data <- reactive({
    req(input$cpi_series, input$cpi_metric)
    metric <- metric_column(input$cpi_metric, "cpi")
    data_cpi_element_ts %>%
      filter(series_name == input$cpi_series) %>%
      arrange(date) %>%
      mutate(plot_value = .data[[metric]])
  })

  emp_plot_data <- reactive({
    req(input$emp_series, input$emp_metric)
    metric <- metric_column(input$emp_metric, "emp")
    data_emp_breakdown_ts %>%
      filter(series_name == input$emp_series) %>%
      arrange(date) %>%
      mutate(plot_value = .data[[metric]])
  })

  shelter_selected_ids <- reactive({
    req(input$shelter_x_series, input$shelter_y_series)
    x_id <- tab_shelter_lag_series_map %>%
      filter(series_name == input$shelter_x_series, side == "X") %>%
      pull(series_id) %>%
      .[1]
    y_id <- tab_shelter_lag_series_map %>%
      filter(series_name == input$shelter_y_series, side == "Y") %>%
      pull(series_id) %>%
      .[1]
    list(x_id = x_id, y_id = y_id)
  })

  shelter_lag_corr_selected <- reactive({
    ids <- shelter_selected_ids()
    req(ids$x_id, ids$y_id, input$shelter_lag_range, input$shelter_transform)
    metric <- shelter_metric_column(input$shelter_transform)

    x_meta <- data_shelter_lag_ts %>% filter(series_id == ids$x_id) %>% slice_head(n = 1)
    y_meta <- data_shelter_lag_ts %>% filter(series_id == ids$y_id) %>% slice_head(n = 1)
    x <- data_shelter_lag_ts %>% filter(series_id == ids$x_id) %>% select(date, x_value = all_of(metric))
    y <- data_shelter_lag_ts %>% filter(series_id == ids$y_id) %>% select(date, y_value = all_of(metric))

    bind_rows(lapply(seq(input$shelter_lag_range[1], input$shelter_lag_range[2]), function(k) {
      joined <- y %>%
        inner_join(x %>% mutate(date = date %m+% months(k)), by = "date") %>%
        filter(!is.na(x_value), !is.na(y_value))

      corr_val <- if (nrow(joined) >= 36) suppressWarnings(cor(joined$x_value, joined$y_value)) else NA_real_
      if (!is.finite(corr_val)) corr_val <- NA_real_

      data.frame(
        x_series_id = ids$x_id,
        x_series_name = x_meta$series_name[1],
        y_series_id = ids$y_id,
        y_series_name = y_meta$series_name[1],
        lag_month = k,
        n_obs = nrow(joined),
        corr = corr_val,
        r_squared = ifelse(is.na(corr_val), NA_real_, corr_val ^ 2),
        start_date = if (nrow(joined) > 0) min(joined$date, na.rm = TRUE) else as.Date(NA),
        end_date = if (nrow(joined) > 0) max(joined$date, na.rm = TRUE) else as.Date(NA),
        stringsAsFactors = FALSE
      )
    }))
  })

  shelter_best_selected <- reactive({
    d <- shelter_lag_corr_selected() %>% filter(!is.na(corr))
    req(nrow(d) > 0)
    d %>%
      slice_max(order_by = abs(corr), n = 1, with_ties = FALSE) %>%
      transmute(
        x_series_name,
        y_series_name,
        best_lag_month = lag_month,
        best_corr = corr,
        best_r_squared = r_squared,
        n_obs,
        interpretation = paste0(
          x_series_name,
          " ",
          input$shelter_transform,
          " leads ",
          y_series_name,
          " ",
          input$shelter_transform,
          " by ",
          best_lag_month,
          " months with correlation ",
          round(best_corr, 2),
          "."
        )
      )
  })

  shelter_overlay_data <- reactive({
    ids <- shelter_selected_ids()
    best <- shelter_best_selected()
    metric <- shelter_metric_column(input$shelter_transform)
    best_lag <- best$best_lag_month[1]

    x <- data_shelter_lag_ts %>%
      filter(series_id == ids$x_id) %>%
      transmute(date = date %m+% months(best_lag), x_value = .data[[metric]])
    y <- data_shelter_lag_ts %>%
      filter(series_id == ids$y_id) %>%
      transmute(date, y_value = .data[[metric]])

    y_latest_date <- if (nrow(y) > 0) max(y$date[is.finite(y$y_value)], na.rm = TRUE) else as.Date(NA)

    full_join(y, x, by = "date") %>%
      arrange(date) %>%
      mutate(
        x_z = z_score(x_value),
        y_z = z_score(y_value),
        y_latest_date = y_latest_date,
        shifted_x_future_yn = if_else(!is.na(y_latest_date) & date > y_latest_date & !is.na(x_value), "Y", "N")
      )
  })

  inflation_pair_corr <- reactive({
    req(input$inflation_source_series, input$inflation_target_series)
    data_inflation_corr %>%
      filter(source_series == input$inflation_source_series, target_series == input$inflation_target_series) %>%
      arrange(lag_month)
  })

  inflation_pair_best <- reactive({
    d <- inflation_pair_corr() %>% filter(!is.na(corr))
    req(nrow(d) > 0)
    d %>% slice_max(order_by = abs(corr), n = 1, with_ties = FALSE)
  })

  inflation_overlay_data <- reactive({
    best <- inflation_pair_best()
    req(nrow(best) > 0)
    source_id <- best$source_series_id[1]
    target_id <- best$target_series_id[1]
    best_lag <- best$lag_month[1]

    x <- data_pce_nowcast_input %>%
      filter(series_id == source_id) %>%
      transmute(date = date %m+% months(best_lag), x_value = yoy_pct)
    y <- data_pce_nowcast_input %>%
      filter(series_id == target_id) %>%
      transmute(date, y_value = yoy_pct)

    y_latest_date <- if (nrow(y) > 0) max(y$date[is.finite(y$y_value)], na.rm = TRUE) else as.Date(NA)

    full_join(y, x, by = "date") %>%
      arrange(date) %>%
      mutate(
        x_z = z_score(x_value),
        y_z = z_score(y_value),
        y_latest_date = y_latest_date,
        shifted_x_future_yn = if_else(!is.na(y_latest_date) & date > y_latest_date & !is.na(x_value), "Y", "N")
      )
  })

  inflation_path_filter <- reactive({
    path <- if (is.null(input$inflation_flow_path)) "all" else input$inflation_flow_path
    if (path == "goods") {
      list(
        sources = c("Final Demand PPI", "Final Demand Less Food Energy", "Commodities PPI", "Import Price Index"),
        targets = c("Energy CPI", "CPI Headline", "CPI Core", "Core PCE Price Index")
      )
    } else if (path == "shelter") {
      list(
        sources = c("Total nonfarm payrolls", "Average hourly earnings", "Shelter CPI", "OER CPI"),
        targets = c("OER CPI", "Shelter CPI", "Core PCE Price Index", "PCE Price Index")
      )
    } else {
      list(sources = NULL, targets = NULL)
    }
  })

  inflation_heatmap_filtered <- reactive({
    filt <- inflation_path_filter()
    d <- data_inflation_heatmap
    if (!is.null(filt$sources)) d <- d %>% filter(source_series %in% filt$sources)
    if (!is.null(filt$targets)) d <- d %>% filter(target_series %in% filt$targets)
    d
  })

  inflation_best_filtered <- reactive({
    filt <- inflation_path_filter()
    d <- tab_inflation_best_lag
    if (!is.null(filt$sources)) d <- d %>% filter(source_series %in% filt$sources)
    if (!is.null(filt$targets)) d <- d %>% filter(target_series %in% filt$targets)
    d
  })

  output$cpiPlotUi <- renderUI({
    if (has_plotly) plotly::plotlyOutput("plot_cpi_breakdown_ts", height = "360px")
    else plotOutput("plot_cpi_breakdown_ts", height = "360px")
  })

  output$empPlotUi <- renderUI({
    if (has_plotly) plotly::plotlyOutput("plot_emp_breakdown_ts", height = "360px")
    else plotOutput("plot_emp_breakdown_ts", height = "360px")
  })

  output$shelterLagCorrPlotUi <- renderUI({
    if (has_plotly) plotly::plotlyOutput("plot_shelter_lag_corr", height = "340px")
    else plotOutput("plot_shelter_lag_corr", height = "340px")
  })

  output$shelterOverlayPlotUi <- renderUI({
    if (has_plotly) plotly::plotlyOutput("plot_shelter_lag_overlay", height = "360px")
    else plotOutput("plot_shelter_lag_overlay", height = "360px")
  })

  output$pceNowcastPlotUi <- renderUI({
    if (has_plotly) plotly::plotlyOutput("plot_pce_nowcast", height = "360px")
    else plotOutput("plot_pce_nowcast", height = "360px")
  })

  output$inflationHeatmapUi <- renderUI({
    if (has_plotly) plotly::plotlyOutput("plot_inflation_heatmap", height = "420px")
    else DTOutput("table_inflation_heatmap")
  })

  output$inflationCorrCurveUi <- renderUI({
    if (has_plotly) plotly::plotlyOutput("plot_inflation_corr_curve", height = "320px")
    else plotOutput("plot_inflation_corr_curve", height = "320px")
  })

  output$inflationOverlayUi <- renderUI({
    if (has_plotly) plotly::plotlyOutput("plot_inflation_overlay", height = "360px")
    else plotOutput("plot_inflation_overlay", height = "360px")
  })

  if (has_plotly) {
    output$plot_cpi_breakdown_ts <- plotly::renderPlotly({
      d <- cpi_plot_data()
      req(nrow(d) > 0)
      plotly::plot_ly(
        d,
        x = ~date,
        y = ~plot_value,
        type = "scatter",
        mode = "lines",
        text = ~paste0(
          series_name,
          "<br>Date: ", date,
          "<br>Value: ", round(value, 3),
          "<br>MoM: ", round(mom_pct, 3), "%",
          "<br>YoY: ", round(yoy_pct, 3), "%",
          "<br>3M ann: ", round(chg_3m_ann, 3), "%"
        ),
        hoverinfo = "text",
        line = list(width = 2, color = "#2563eb")
      ) %>%
        plotly::layout(
          title = paste(input$cpi_series, "-", input$cpi_metric),
          xaxis = list(title = "Date"),
          yaxis = list(title = input$cpi_metric)
        )
    })

    output$plot_emp_breakdown_ts <- plotly::renderPlotly({
      d <- emp_plot_data()
      req(nrow(d) > 0)
      plotly::plot_ly(
        d,
        x = ~date,
        y = ~plot_value,
        type = "scatter",
        mode = "lines",
        text = ~paste0(
          series_name,
          "<br>Date: ", date,
          "<br>Value: ", round(value, 3),
          "<br>MoM chg: ", round(mom_chg, 3),
          "<br>YoY chg: ", round(yoy_chg, 3),
          "<br>YoY %: ", round(yoy_pct, 3), "%"
        ),
        hoverinfo = "text",
        line = list(width = 2, color = "#047857")
      ) %>%
        plotly::layout(
          title = paste(input$emp_series, "-", input$emp_metric),
          xaxis = list(title = "Date"),
          yaxis = list(title = input$emp_metric)
        )
    })

    output$plot_shelter_lag_corr <- plotly::renderPlotly({
      d <- shelter_lag_corr_selected()
      best <- shelter_best_selected()
      req(nrow(d) > 0)

      plotly::plot_ly(
        d,
        x = ~lag_month,
        y = ~corr,
        type = "scatter",
        mode = "lines+markers",
        text = ~paste0(
          "Lag: ", lag_month, " months",
          "<br>Corr: ", round(corr, 3),
          "<br>R-squared: ", round(r_squared, 3),
          "<br>N: ", n_obs
        ),
        hoverinfo = "text",
        line = list(width = 2, color = "#7c3aed"),
        marker = list(size = 7)
      ) %>%
        plotly::layout(
          title = paste(input$shelter_x_series, "vs", input$shelter_y_series, "lag correlation"),
          xaxis = list(title = "Lag months"),
          yaxis = list(title = "Correlation", range = c(-1, 1)),
          shapes = list(list(
            type = "line",
            x0 = best$best_lag_month[1],
            x1 = best$best_lag_month[1],
            y0 = -1,
            y1 = 1,
            line = list(color = "#111827", dash = "dot")
          ))
        )
    })

    output$plot_shelter_lag_overlay <- plotly::renderPlotly({
      d <- shelter_overlay_data()
      best <- shelter_best_selected()
      req(nrow(d) > 0)
      y_latest_date <- d$y_latest_date[which(!is.na(d$y_latest_date))[1]]

      plotly::plot_ly(d, x = ~date) %>%
        plotly::add_lines(
          y = ~x_z,
          name = paste0(input$shelter_x_series, " shifted +", best$best_lag_month[1], "m"),
          text = ~paste0(
            "Date: ", date,
            "<br>Shifted X z: ", round(x_z, 3),
            "<br>Future vs Shelter latest: ", shifted_x_future_yn
          ),
          hoverinfo = "text",
          line = list(color = "#7c3aed", width = 2)
        ) %>%
        plotly::add_lines(y = ~y_z, name = input$shelter_y_series, line = list(color = "#dc2626", width = 2)) %>%
        plotly::layout(
          title = paste(input$shelter_x_series, "shifted by", best$best_lag_month[1], "months vs", input$shelter_y_series),
          xaxis = list(title = "Date"),
          yaxis = list(title = "Z-score"),
          shapes = if (!is.na(y_latest_date)) {
            list(list(
              type = "line",
              x0 = y_latest_date,
              x1 = y_latest_date,
              y0 = min(c(d$x_z, d$y_z), na.rm = TRUE),
              y1 = max(c(d$x_z, d$y_z), na.rm = TRUE),
              line = list(color = "#6b7280", dash = "dot")
            ))
          } else {
            list()
          }
        )
    })

    output$plot_pce_nowcast <- plotly::renderPlotly({
      d <- data_pce_official %>%
        filter(!is.na(core_pce_yoy) | !is.na(estimated_core_pce_yoy)) %>%
        arrange(date)
      req(nrow(d) > 0)

      plotly::plot_ly(d, x = ~date) %>%
        plotly::add_lines(y = ~core_pce_yoy, name = "Official Core PCE", line = list(color = "#dc2626", width = 2)) %>%
        plotly::add_lines(y = ~estimated_core_pce_yoy, name = "Estimated Core PCE", line = list(color = "#2563eb", width = 2)) %>%
        plotly::layout(title = "Official vs Estimated Core PCE YoY", xaxis = list(title = "Date"), yaxis = list(title = "YoY %"))
    })

    output$plot_inflation_heatmap <- plotly::renderPlotly({
      d <- inflation_heatmap_filtered() %>%
        filter(!is.na(corr))
      req(nrow(d) > 0)

      mat <- d %>%
        select(source_series, target_series, corr) %>%
        tidyr::pivot_wider(names_from = target_series, values_from = corr)
      y_labels <- mat$source_series
      x_labels <- names(mat)[-1]
      z <- as.matrix(mat[, -1, drop = FALSE])
      storage.mode(z) <- "numeric"

      lag_mat <- d %>%
        select(source_series, target_series, best_lag) %>%
        tidyr::pivot_wider(names_from = target_series, values_from = best_lag)
      lag_z <- as.matrix(lag_mat[, x_labels, drop = FALSE])

      text_z <- matrix("", nrow = nrow(z), ncol = ncol(z))
      for (i in seq_len(nrow(z))) {
        for (j in seq_len(ncol(z))) {
          text_z[i, j] <- if (is.na(z[i, j])) {
            paste0("Source: ", y_labels[i], "<br>Target: ", x_labels[j], "<br>No pair calculated")
          } else {
            paste0(
              "Source: ", y_labels[i],
              "<br>Target: ", x_labels[j],
              "<br>Best corr: ", round(z[i, j], 3),
              "<br>Best lag: ", lag_z[i, j], " months"
            )
          }
        }
      }

      plotly::plot_ly(
        x = x_labels,
        y = y_labels,
        z = z,
        type = "heatmap",
        zmin = -1,
        zmax = 1,
        colorscale = list(c(0, "#f3b1b8"), c(0.5, "#ffffff"), c(1, "#6fd58a")),
        text = text_z,
        hoverinfo = "text"
      ) %>%
        plotly::layout(xaxis = list(title = "Target"), yaxis = list(title = "Source"))
    })

    output$plot_inflation_corr_curve <- plotly::renderPlotly({
      d <- inflation_pair_corr()
      best <- inflation_pair_best()
      req(nrow(d) > 0)

      plotly::plot_ly(
        d,
        x = ~lag_month,
        y = ~corr,
        type = "scatter",
        mode = "lines+markers",
        text = ~paste0("Lag: ", lag_month, "m<br>Corr: ", round(corr, 3), "<br>R-squared: ", round(r_squared, 3), "<br>N: ", n_obs),
        hoverinfo = "text",
        line = list(color = "#7c3aed", width = 2)
      ) %>%
        plotly::layout(
          title = paste(input$inflation_source_series, "vs", input$inflation_target_series),
          xaxis = list(title = "Lag months"),
          yaxis = list(title = "Correlation", range = c(-1, 1)),
          shapes = list(list(type = "line", x0 = best$lag_month[1], x1 = best$lag_month[1], y0 = -1, y1 = 1, line = list(color = "#111827", dash = "dot")))
        )
    })

    output$plot_inflation_overlay <- plotly::renderPlotly({
      d <- inflation_overlay_data()
      best <- inflation_pair_best()
      req(nrow(d) > 0)
      y_latest_date <- d$y_latest_date[which(!is.na(d$y_latest_date))[1]]

      plotly::plot_ly(d, x = ~date) %>%
        plotly::add_lines(y = ~x_z, name = paste0(input$inflation_source_series, " shifted +", best$lag_month[1], "m"), line = list(color = "#7c3aed", width = 2)) %>%
        plotly::add_lines(y = ~y_z, name = input$inflation_target_series, line = list(color = "#dc2626", width = 2)) %>%
        plotly::layout(
          title = paste(input$inflation_source_series, "shifted by", best$lag_month[1], "months vs", input$inflation_target_series),
          xaxis = list(title = "Date"),
          yaxis = list(title = "Z-score"),
          shapes = if (!is.na(y_latest_date)) {
            list(list(type = "line", x0 = y_latest_date, x1 = y_latest_date, y0 = min(c(d$x_z, d$y_z), na.rm = TRUE), y1 = max(c(d$x_z, d$y_z), na.rm = TRUE), line = list(color = "#6b7280", dash = "dot")))
          } else {
            list()
          }
        )
    })
  } else {
    output$plot_cpi_breakdown_ts <- renderPlot({
      d <- cpi_plot_data()
      req(nrow(d) > 0)
      plot(d$date, d$plot_value, type = "l", col = "#2563eb", lwd = 2, xlab = "Date", ylab = input$cpi_metric, main = paste(input$cpi_series, "-", input$cpi_metric))
    })

    output$plot_emp_breakdown_ts <- renderPlot({
      d <- emp_plot_data()
      req(nrow(d) > 0)
      plot(d$date, d$plot_value, type = "l", col = "#047857", lwd = 2, xlab = "Date", ylab = input$emp_metric, main = paste(input$emp_series, "-", input$emp_metric))
    })

    output$plot_shelter_lag_corr <- renderPlot({
      d <- shelter_lag_corr_selected()
      best <- shelter_best_selected()
      req(nrow(d) > 0)
      plot(d$lag_month, d$corr, type = "b", pch = 16, col = "#7c3aed", lwd = 2, ylim = c(-1, 1), xlab = "Lag months", ylab = "Correlation", main = paste(input$shelter_x_series, "vs", input$shelter_y_series))
      abline(v = best$best_lag_month[1], lty = 2, col = "#111827")
      abline(h = 0, lty = 3, col = "#9ca3af")
    })

    output$plot_shelter_lag_overlay <- renderPlot({
      d <- shelter_overlay_data()
      best <- shelter_best_selected()
      req(nrow(d) > 0)
      plot(d$date, d$x_z, type = "l", col = "#7c3aed", lwd = 2, xlab = "Date", ylab = "Z-score", main = paste(input$shelter_x_series, "shifted by", best$best_lag_month[1], "months vs", input$shelter_y_series))
      lines(d$date, d$y_z, col = "#dc2626", lwd = 2)
      y_latest_date <- d$y_latest_date[which(!is.na(d$y_latest_date))[1]]
      if (!is.na(y_latest_date)) abline(v = y_latest_date, lty = 2, col = "#6b7280")
      legend("topleft", legend = c(paste0(input$shelter_x_series, " shifted"), input$shelter_y_series), col = c("#7c3aed", "#dc2626"), lwd = 2, bty = "n")
    })

    output$plot_pce_nowcast <- renderPlot({
      d <- data_pce_official %>% filter(!is.na(core_pce_yoy) | !is.na(estimated_core_pce_yoy)) %>% arrange(date)
      req(nrow(d) > 0)
      plot(d$date, d$core_pce_yoy, type = "l", col = "#dc2626", lwd = 2, xlab = "Date", ylab = "YoY %", main = "Official vs Estimated Core PCE YoY")
      lines(d$date, d$estimated_core_pce_yoy, col = "#2563eb", lwd = 2)
      legend("topleft", legend = c("Official Core PCE", "Estimated Core PCE"), col = c("#dc2626", "#2563eb"), lwd = 2, bty = "n")
    })

    output$plot_inflation_corr_curve <- renderPlot({
      d <- inflation_pair_corr()
      best <- inflation_pair_best()
      req(nrow(d) > 0)
      plot(d$lag_month, d$corr, type = "b", pch = 16, col = "#7c3aed", lwd = 2, ylim = c(-1, 1), xlab = "Lag months", ylab = "Correlation", main = paste(input$inflation_source_series, "vs", input$inflation_target_series))
      abline(v = best$lag_month[1], lty = 2, col = "#111827")
      abline(h = 0, lty = 3, col = "#9ca3af")
    })

    output$plot_inflation_overlay <- renderPlot({
      d <- inflation_overlay_data()
      best <- inflation_pair_best()
      req(nrow(d) > 0)
      plot(d$date, d$x_z, type = "l", col = "#7c3aed", lwd = 2, xlab = "Date", ylab = "Z-score", main = paste(input$inflation_source_series, "shifted by", best$lag_month[1], "months vs", input$inflation_target_series))
      lines(d$date, d$y_z, col = "#dc2626", lwd = 2)
      y_latest_date <- d$y_latest_date[which(!is.na(d$y_latest_date))[1]]
      if (!is.na(y_latest_date)) abline(v = y_latest_date, lty = 2, col = "#6b7280")
      legend("topleft", legend = c(paste0(input$inflation_source_series, " shifted"), input$inflation_target_series), col = c("#7c3aed", "#dc2626"), lwd = 2, bty = "n")
    })
  }

  output$table_cpi_latest_breakdown <- renderDT({
    latest_ts <- data_cpi_element_ts %>%
      group_by(series_id) %>%
      slice_max(order_by = date, n = 1, with_ties = FALSE) %>%
      ungroup()

    latest_contrib <- data_cpi_element_contribution %>%
      group_by(series_id) %>%
      slice_max(order_by = date, n = 1, with_ties = FALSE) %>%
      ungroup() %>%
      select(series_id, weight_pct, contribution_mom, contribution_yoy)

    df <- latest_ts %>%
      left_join(latest_contrib, by = "series_id") %>%
      select(series_name, category_lv1, weight_pct, mom_pct, yoy_pct, chg_3m_ann, chg_6m_ann, contribution_mom, contribution_yoy) %>%
      arrange(desc(abs(contribution_mom))) %>%
      mutate(across(where(is.numeric), ~round(.x, 2)))

    datatable(df, rownames = FALSE, selection = "none", class = "compact stripe hover row-border", options = list(pageLength = 50, dom = "tip", scrollX = TRUE))
  })

  output$table_cpi_contribution <- renderDT({
    df <- data_cpi_element_contribution %>%
      group_by(series_id) %>%
      slice_max(order_by = date, n = 1, with_ties = FALSE) %>%
      ungroup() %>%
      select(series_name, category_lv1, category_lv2, weight_pct, mom_pct, yoy_pct, contribution_mom, contribution_yoy) %>%
      arrange(desc(abs(contribution_mom))) %>%
      mutate(across(where(is.numeric), ~round(.x, 2)))

    datatable(df, rownames = FALSE, selection = "none", class = "compact stripe hover row-border", options = list(pageLength = 50, dom = "tip", scrollX = TRUE))
  })

  output$table_emp_latest_breakdown <- renderDT({
    latest_emp <- data_emp_breakdown_ts %>%
      group_by(series_id) %>%
      slice_max(order_by = date, n = 1, with_ties = FALSE) %>%
      ungroup()

    latest_contrib <- data_emp_contribution %>%
      group_by(series_id) %>%
      slice_max(order_by = date, n = 1, with_ties = FALSE) %>%
      ungroup() %>%
      select(series_id, share_of_total_mom)

    df <- latest_emp %>%
      left_join(latest_contrib, by = "series_id") %>%
      select(series_name, category_lv1, value, mom_chg, mom_chg_3m_avg, yoy_chg, yoy_pct, share_of_total_mom) %>%
      arrange(desc(abs(mom_chg))) %>%
      mutate(across(where(is.numeric), ~round(.x, 2)))

    datatable(df, rownames = FALSE, selection = "none", class = "compact stripe hover row-border", options = list(pageLength = 50, dom = "tip", scrollX = TRUE))
  })

  output$table_emp_contribution <- renderDT({
    df <- data_emp_contribution %>%
      group_by(series_id) %>%
      slice_max(order_by = date, n = 1, with_ties = FALSE) %>%
      ungroup() %>%
      select(series_name, category_lv1, category_lv2, value, mom_chg, mom_chg_3m_avg, yoy_chg, yoy_pct, share_of_total_mom) %>%
      arrange(desc(abs(mom_chg))) %>%
      mutate(across(where(is.numeric), ~round(.x, 2)))

    datatable(df, rownames = FALSE, selection = "none", class = "compact stripe hover row-border", options = list(pageLength = 50, dom = "tip", scrollX = TRUE))
  })

  output$table_shelter_lag_best <- renderDT({
    df <- shelter_best_selected() %>%
      mutate(
        best_corr = round(best_corr, 3),
        best_r_squared = round(best_r_squared, 3)
      )

    datatable(
      df,
      rownames = FALSE,
      selection = "none",
      class = "compact stripe hover row-border",
      options = list(pageLength = 10, dom = "tip", scrollX = TRUE)
    )
  })

  output$table_shelter_lag_corr <- renderDT({
    df <- shelter_lag_corr_selected() %>%
      select(lag_month, corr, r_squared, n_obs, start_date, end_date) %>%
      arrange(lag_month) %>%
      mutate(
        corr = round(corr, 3),
        r_squared = round(r_squared, 3)
      )

    datatable(
      df,
      rownames = FALSE,
      selection = "none",
      class = "compact stripe hover row-border",
      options = list(pageLength = 25, dom = "tip", scrollX = TRUE)
    )
  })

  output$inflationValueBoxes <- renderUI({
    headline_cpi <- latest_series_row(data_pce_nowcast_input, "CPIAUCSL")
    core_cpi <- latest_series_row(data_pce_nowcast_input, "CPILFESL")
    pce <- latest_series_row(data_pce_nowcast_input, "PCEPI")
    core_pce <- latest_series_row(data_pce_nowcast_input, "PCEPILFE")

    tagList(
      value_box_html("Headline CPI YoY", headline_cpi$yoy_pct, "%"),
      value_box_html("Core CPI YoY", core_cpi$yoy_pct, "%"),
      value_box_html("PCE YoY", pce$yoy_pct, "%"),
      value_box_html("Core PCE YoY", core_pce$yoy_pct, "%")
    )
  })

  output$inflationFlowChart <- renderUI({
    path <- if (is.null(input$inflation_flow_path)) "all" else input$inflation_flow_path
    box <- function(label, active = TRUE) {
      bg <- if (active) "#ffffff" else "#f3f4f6"
      color <- if (active) "#111827" else "#9ca3af"
      border <- if (active) "#b9c2d0" else "#e5e7eb"
      paste0(
        "<div style='padding:10px; background:", bg, "; border:1px solid ", border, "; border-radius:6px;",
        "text-align:center; font-weight:650; color:", color, ";'>", label, "</div>"
      )
    }
    arrow <- function(active = TRUE) {
      color <- if (active) "#4b5563" else "#d1d5db"
      paste0("<div style='display:flex; align-items:center; justify-content:center; color:", color, "; font-weight:700;'>-&gt;</div>")
    }
    goods_active <- path %in% c("goods", "all")
    shelter_active <- path %in% c("shelter", "all")

    HTML(paste0(
      "<div style='display:grid; grid-template-columns:minmax(130px,1fr) 32px minmax(130px,1fr) 32px minmax(130px,1fr) 32px minmax(130px,1fr); gap:8px; max-width:1050px;'>",
      box("PPI", goods_active), arrow(goods_active), box("CPI Goods", goods_active), arrow(goods_active), box("Core CPI", goods_active), arrow(goods_active), box("Core PCE", goods_active),
      box("Employment", shelter_active), arrow(shelter_active), box("Wage", shelter_active), arrow(shelter_active), box("OER / Shelter", shelter_active), arrow(shelter_active), box("Core PCE", shelter_active),
      "</div>"
    ))
  })

  output$pceNowcastMetrics <- renderUI({
    d <- data_pce_official %>%
      filter(is.finite(core_pce_yoy), is.finite(estimated_core_pce_yoy))
    err <- d$estimated_core_pce_yoy - d$core_pce_yoy
    rmse <- if (length(err) > 0) sqrt(mean(err ^ 2, na.rm = TRUE)) else NA_real_
    mae <- if (length(err) > 0) mean(abs(err), na.rm = TRUE) else NA_real_
    corr <- if (nrow(d) >= 12) suppressWarnings(cor(d$core_pce_yoy, d$estimated_core_pce_yoy, use = "complete.obs")) else NA_real_

    tagList(
      value_box_html("RMSE", rmse),
      value_box_html("MAE", mae),
      value_box_html("Correlation", corr)
    )
  })

  output$inflationPressureBadge <- renderUI({
    latest <- data_pce_official %>%
      filter(!is.na(pressure_score)) %>%
      arrange(date) %>%
      slice_tail(n = 1)
    pressure_badge_html(latest$pressure_level, latest$pressure_score)
  })

  output$inflationPairSummary <- renderUI({
    best <- inflation_pair_best()
    req(nrow(best) > 0)

    tagList(
      value_box_html("Best lag", best$lag_month[1], "m"),
      value_box_html("Best corr", best$corr[1]),
      value_box_html("Best R-squared", best$r_squared[1]),
      value_box_html("Observations", best$n_obs[1])
    )
  })

  output$table_inflation_heatmap <- renderDT({
    df <- inflation_heatmap_filtered() %>%
      mutate(corr = round(corr, 3)) %>%
      arrange(source_series, target_series)

    datatable(df, rownames = FALSE, selection = "none", class = "compact stripe hover row-border", options = list(pageLength = 50, dom = "tip", scrollX = TRUE))
  })

  output$table_pce_nowcast <- renderDT({
    df <- data_pce_official %>%
      select(date, core_pce_yoy, estimated_core_pce_yoy, estimated_error, pressure_score, pressure_level) %>%
      arrange(desc(date)) %>%
      mutate(across(where(is.numeric), ~round(.x, 3)))

    datatable(df, rownames = FALSE, selection = "none", class = "compact stripe hover row-border", options = list(pageLength = 25, dom = "tip", scrollX = TRUE))
  })

  output$table_inflation_pair_lags <- renderDT({
    df <- inflation_pair_corr() %>%
      select(lag_month, corr, r_squared, n_obs) %>%
      arrange(lag_month) %>%
      mutate(
        corr = round(corr, 3),
        r_squared = round(r_squared, 3)
      )

    datatable(df, rownames = FALSE, selection = "none", class = "compact stripe hover row-border", options = list(pageLength = 25, dom = "tip", scrollX = TRUE))
  })

  output$table_inflation_best_lag <- renderDT({
    df <- inflation_best_filtered() %>%
      select(source_series, target_series, best_lag, best_corr, best_r_squared, n_obs) %>%
      mutate(
        best_corr = round(best_corr, 3),
        best_r_squared = round(best_r_squared, 3)
      )

    datatable(df, rownames = FALSE, selection = "none", class = "compact stripe hover row-border", options = list(pageLength = 50, dom = "tip", scrollX = TRUE))
  })
}

shinyApp(ui = ui, server = server)
