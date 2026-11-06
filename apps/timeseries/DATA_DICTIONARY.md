# Timeseries Data Dictionary

## Series catalog

series_catalog.csv is the only registration point for collection and display metadata. The primary catalog key is source + series_id.

- source: FRED, YAHOO, or ECOS.
- series_id: stable application-level series identifier.
- stat_code, cycle, item_code1-item_code4: ECOS request coordinates. They remain blank for FRED/Yahoo.
- unit: source unit recorded for display and validation.
- transform: display transform such as `yoy`; raw stored values are not overwritten.
- collect_flag: controls whether the collector requests new observations.
- default_visible: controls whether the series appears in the default explorer list.
- active: lifecycle status. It is independent from collection and default visibility and never purges history.
- benchmark_series: benchmark used by analysis tabs.
- price_policy: adjusted or close.
- notes: semicolon-delimited analysis tags such as rotation_bucket, analysis_group, and link_role.

Physical deletion is not part of normal catalog maintenance. To retire a series while preserving history, set `collect_flag=FALSE` and `default_visible=FALSE`; keep `active=TRUE` unless a separately approved lifecycle change requires otherwise.

## Yahoo time series

Primary key: source + series_id + date.

- date: exchange observation date.
- series_id: Yahoo symbol.
- close_value: unadjusted closing level used by absolute-level views.
- adjusted_value: split/distribution-adjusted close used by return analysis.
- volume: Yahoo volume when available.
- source: YAHOO.
- collected_at: collection timestamp.
- observation_date: exchange observation date, preserved separately for point-in-time joins.
- available_at: regular US close availability timestamp converted to Asia/Seoul for Yahoo rows.
- source_updated_at: provider revision timestamp when available; Yahoo leaves this blank.
- vintage: source observation vintage.
- quality_status: source-level quality classification.
- calculation_version: raw schema version.

## ECOS time series

File: `original_ts_ecos.fst`.

Primary key: `source + series_id + date`.

- date: ECOS observation date; the collector does not manufacture weekends or holidays.
- value: numeric value exactly parsed from `DATA_VALUE`.
- series_id: stable internal identifier such as `KTB_03Y` or `ECOS_USDKRW`.
- source: ECOS.
- collected_at: collector timestamp in Asia/Seoul.
- source_updated_at: ECOS `TIME` value associated with the observation.

The catalog keeps ECOS `stat_code`, `cycle`, and `item_code1` separate from the internal `series_id`. Every collectable row must match the official `StatisticItemList` item name, cycle, and unit before collection. `ECOS_USDKRW` is an official domestic reference series and is never merged with Yahoo `USDKRW=X`.

`SPECIAL_AAA_03Y` is registered as `SOURCE_NOT_AVAILABLE`; it is inactive and not collected because the verified ECOS table did not contain an approved representative special-bond AAA series.

When adjusted_value is unavailable, return analysis falls back to close_value. Supplemental pre-Yahoo DJIA rows keep adjusted_value as NA.

## Korea Rates derived store

File: `derived_korea_rates_summary.fst`.

Primary key: `metric_id + observation_date + reference_date`.

- metric_group: `yield_curve`, `rate_change`, `funding_spread`, `credit_spread`, `kr_us_spread`, `rolling_correlation`, `fx_rate_link`, or `data_quality`.
- metric_id: stable derived-series identifier.
- observation_date: actual ECOS or FRED observation date used by the metric.
- reference_date: actual comparison date where a change or alignment requires one; never a generated date.
- value: curve level, bp change/spread, FX level, or correlation according to `unit`.
- component_a, component_b: source series used by a spread, comparison, or relationship.
- tenor_years: curve tenor where applicable.
- quality_status: `OK`, `PENDING_SOURCE`, or an explicit disabled/error status.
- calculation_version: formula contract version, currently `gate3_v1`.
- built_at: derived build timestamp in Asia/Seoul.

Formula conventions:

- Rate change (bp): `(current rate - actual reference rate) * 100`.
- Spread (bp): `(component A - component B) * 100` on the same observation date.
- Korea-US levels and 10Y spread: exact same-calendar observations only.
- Transmission alignment: US observation at t to the first Korean observation strictly after t.
- Rolling correlation: complete 20, 60, or 120 aligned observations; partial windows are omitted.

The Shiny application reads this file lazily and never executes the builder or an external API.

## Physical indicators

Raw files: `original_ts_ecos.fst` and `original_ts_yahoo.fst`. Derived file: `derived_physical_indicators.fst`.

- `KR_DRAM_PPI`: official Bank of Korea ECOS DRAM domestic producer price index, monthly, `2020=100`.
- `KR_FLASH_MEMORY_PPI`: official Bank of Korea ECOS flash-memory domestic producer price index, monthly, `2020=100`.
- `BWET_VLCC_PROXY`: Yahoo `BWET` tanker-freight futures ETF market-price proxy; stored under a stable internal ID.
- PPI metrics: level, MoM, YoY, 3-month and 6-month change, and signed monthly streak.
- PPI lead/lag: exploratory reference-month correlation at lags -6 through +6 against approved semiconductor market series. ECOS does not provide historical release timestamps through the item/search response used here, so this output is not a point-in-time release-lag trading signal. Monthly observations are never expanded to daily rows with LOCF.
- BWET metrics: 1D/1W/1M/3M adjusted returns, 20-day volatility, maximum drawdown, WTI/XLE/XOP correlations, and WTI up/down regime mean returns.

The two PPI series are not TrendForce or DRAMeXchange spot/contract prices. BWET is not a VLCC spot rate or an official Baltic freight index; its return can include futures roll, fees, and tracking error.

For ECOS physical rows, `available_at` is a conservative collection-availability timestamp. `source_updated_at` remains `NA` because the API response does not provide a historical publication/revision timestamp; the collector clock is never substituted for that field.

### Korea Rates UI index

File: `derived_korea_rates_latest.fst`.

This 141-row index retains the full schema but contains only yield-curve snapshots, current rate-change rows, data-quality rows, and the latest value of each funding/credit spread. It powers the initial visible screen. It does not replace or truncate `derived_korea_rates_summary.fst`.

### Market UI core index

File: `derived_market_ui_core.fst`.

This read-only startup index contains the active Sector Rotation and Semiconductor/Korea Link series plus required benchmarks. The full Yahoo/FRED data remains unchanged and loads only when Series Explorer is opened.

### Series Explorer index

File: `derived_series_explorer.fst`.

Primary key: `source + series_id + date`.

This lazy-loaded index combines the display copy of Yahoo and FRED observations, catalog display names, precomputed CPI/PPI YoY transforms, and `effective_value`. `raw_close_value` and `raw_adjusted_value` retain the untransformed values for the raw-level plot. It is rebuilt after every successful scheduled collection and does not replace either source FST.

## Scheduled batch state

Files: `batch_state/us_close_latest.json` and `batch_state/kr_close_latest.json`.

Each state contains `batch_id`, `expected_session`, start/completion timestamps, status, configured/updated/no-new-data counts, `missing_critical`, `pending_source`, and `published`. `PENDING_SOURCE` means the official provider has not yet posted the expected observation and is not treated as a fabricated value or a batch failure. Holiday runs use `US_MARKET_HOLIDAY_NOOP` or `KR_MARKET_HOLIDAY_NOOP` and do not publish partial files.
