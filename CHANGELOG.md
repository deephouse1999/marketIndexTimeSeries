# Changelog

## 2026-11-06

- Added Gate 4.5 Physical Indicators: official ECOS `KR_DRAM_PPI` (381 monthly rows), `KR_FLASH_MEMORY_PPI` (261 monthly rows), and Yahoo `BWET_VLCC_PROXY` (882 daily rows), all with zero duplicate keys.
- Added point-in-time metadata, six PPI change/streak measures, monthly -6..+6 lead/lag comparisons, and BWET return/correlation/regime/volatility/drawdown metrics in `derived_physical_indicators.fst`.
- Added lazy DRAM/Flash views under Semiconductor & Korea Link and a Physical Indicators Series Explorer group with explicit PPI and ETF-proxy interpretation warnings.
- Integrated physical builds into Gate 5 publication and deployment; Gate 4.5 validation passed 18/18, browser checks 11/11, existing UI remediation 9/9, legacy outputs 15/15, and worst-case session RSS 415MB.
- Remediated the first independent Gate 4.5 audit: ECOS `source_updated_at` is now explicitly unavailable instead of using the collector clock; PPI lag output is labeled reference-month exploratory; BWET oil-regime relative performance now subtracts XLE; integrated validation passes 21/21 and both Gate 5 staging paths pass without publication.
- Fixed Series Explorer Raw Source Level rendering by replacing the broken faceted ggplotly conversion with direct Plotly line panels and correcting raw-column vector selection.
- Fixed the Monthly Return Distribution DT failure caused by the invalid `row.names` argument; the BAMLH0A0HYM2 regression case now passes with 526 varying raw observations and a rendered monthly table.
- Remediated the reviewed UI: documented cyclical/defensive sector membership and calculation meaning; labeled the SOX Overview as a current five-year common-start return comparison.
- Replaced the one-day SOX Breadth and Value Chain time-series treatments with visible snapshot bars and added click-through constituent product, end-market, and Korea-link descriptions.
- Simplified the SOX Korea Link view to KOSPI (`^KS11`), restored its full rolling-correlation history with Adjusted Close preferred and Close fallback for the benchmark, and removed duplicate Samsung/SK hynix relations from that view.
- Rebuilt the semiconductor linkage charts with finite-value Plotly line traces; UI remediation passed 9/9 browser checks and Gate 4 validation remained 28/28.
- Completed Gate 6 final regression, performance, release, and handoff validation.
- Added the 772,471-row lazy `derived_series_explorer.fst`; Series Explorer first render improved from 3.42 seconds to 1.92 seconds while retaining raw-level values.
- Passed 28/28 real-browser functional checks across all five main tabs and all three CSV downloads.
- Final performance passed: cold max 0.078s, warm p95 0.291s, filter p95 0.153s, startup max 3.145s, and session RSS 434.6MB.
- Deployed shinyapps.io bundle `12786763` and verified Sector, Series Explorer, Korea Rates, and SOX screens at the public URL.
- Closed Gate 5 after 30/30 validation of staged collection, duplicate checks, atomic publication, rollback, last-good preservation, state contracts, and scheduler readback.
- Added US close scheduling at 18:05 New York time through guarded 07:05/08:05 KST tasks and KR close scheduling at 16:05 KST.
- Added explicit US/KR holiday NOOP, ECOS `PENDING_SOURCE`, batch locks, transaction backups, and atomic batch-state JSON.
- Completed live US and KR batch runs with zero missing critical series; final states reconcile to US `154 = 115 updated + 22 no-new + 17 pending` and KR `22 = 1 updated + 4 no-new + 17 pending`.
- Detected and remediated an initial FRED legacy-key collapse before Gate 5 closure; restored the Gate 4 backup, changed normalization to `(source, series_id, date)`, and preserved all 246,950 legacy unknown-source rows.
- Final sources: FRED 503,123 rows/48 series, Yahoo 473,230/65, ECOS 125,645/18, SOX components 207,906/30; contracted duplicate keys are zero.
- Remediated all findings from the first Gate 4 independent audit without starting Gate 5.
- Separated legacy Yahoo ownership (`NVDA`, `MU`) from 30 Gate 4-owned series and disabled legacy collection for the latter.
- Enforced positive finite Adjusted Close, removed Close fallback, excluded 778 invalid SK Hynix adjusted prices, and blocked extreme daily returns.
- Corrected US-to-next-Korea alignment to retain the latest eligible US close.
- Added reproducible browser performance, four-screen legacy regression, ownership, quality-exclusion, hash, and final screenshot evidence.
- After the first re-audit, added append-only proxy-weight history and strict prior-date weight use; the unavailable 2026-11-03 pre-EOD snapshot is transparently reconstructed from the preserved 2026-11-04 EOD snapshot and Adjusted Close drift.
- Blocked incomplete member dates from breadth, contribution, value-chain, and daily aggregates; 2026-11-05 remains quality evidence at 28/30 and 80.29% weight coverage.
- Rebuilt Overview on the shared 2021-06-11 to 2026-11-04 trading-date intersection with every series starting exactly at 100, and removed the unused Overview FST session preload.
- Rebuilt 143,438 derived rows with zero duplicate keys and retained all three approved legacy source hashes.
- Final internal results: 28/28 validation, 15/15 legacy outputs, cold max 0.070s, warm p95 0.289s, filter p95 0.079s, startup max 3.155s, RSS 365.5 MB.
- Claude's second independent read-only re-audit found no HIGH or MEDIUM issues and recorded `GATE_4_SECOND_INDEPENDENT_REAUDIT_PASS / GATE_4_CLOSED_PASS / GATE_5_APPROVED_TO_START`.

## 2026-11-05

- Completed Gate 1 of the ECOS/SOX integration work order.
- Expanded `series_catalog.csv` from 15 to 25 columns, separating collection, default visibility, and lifecycle status.
- Corrected FRED rate, credit, inflation, investment, and WTI metadata and reclassified Bovespa as an emerging-market comparison index.
- Registered 5 FRED and 8 Yahoo series for later collection without rewriting existing FST data.
- Retained legacy history while disabling collection/default display for 7 rows; kept 4 global rows collectable but hidden by default.
- Added repeatable migration and validation scripts; Gate 1 passed 22/22 integrity checks.
- Reconciled the Gate 1 catalog inventory: 116 legacy rows = 102 stored + 13 pending collection + 1 intentional catalog-only (`^TOPX`).
- Moved Bovespa into `regional_comparison` with Regional View-only semantics and no standalone module.
- Added the Gate 2 ECOS adapter with environment-only authentication, official table/item/meta readback, pagination, error states, and `PENDING_SOURCE` handling.
- Registered 18 officially verified ECOS series and one `SOURCE_NOT_AVAILABLE` special-bond placeholder without substituting an unverified series.
- Published 125,625 ECOS observations across 18 series after full-history and five-business-day overlap validation; duplicate keys remain zero and Gate 2 passed 20/20 checks.
- Added staging validation, independent FST readback, last-good preservation, and atomic publication checks.
- Completed Gate 3 Korea Rates & Funding with a read-only derived builder and lazy-loaded Shiny tab.
- Added exact-date ECOS yield curves, actual-observation rate changes, funding and credit spreads, Korea-US rate comparisons, official ECOS USD/KRW linkage, and full-window 20/60/120-observation rolling correlations.
- Kept `SPECIAL_AAA_03Y` disabled as `SOURCE_NOT_AVAILABLE` with no substitute or empty chart.
- Published 153,329 derived rows across 156 metrics with zero duplicate keys; Gate 3 passed 22/22 integrity checks and browser-based UI verification.
- Reopened the Gate 3 performance finding because the original 4.874-second all-output render exceeded the unchanged 2-second tab contract.
- Added a 141-row Korea Rates latest index, six lazy-rendered subtabs, hidden-output suspension, and a 20-series market UI core index without changing formulas or historical derived results.
- Re-measured five independent cold renders, ten warm transitions, and twelve filter responses using browser click-to-visible-idle timing; cold max 1.306s, warm p95 0.423s, and filter p95 0.365s passed.
- Reduced maximum app startup to 2.873s and Korea Rates session RSS to 361.2 MB; all Gate 3 remediation gates passed.
- Reconstructed the Gate 2 ECOS SHA baseline from the final published artifact and confirmed the Gate 3 SHA remained `6245DA33D871B5A8ED264238EA9AE8FDBF4A5E8A0F5D814A9793EEDAA33447F5` with 125,625 rows, 18 series, and zero duplicate keys.

## 2026-09-01

- Added a validated single series catalog for FRED and Yahoo.
- Added all 11 US sector ETFs and strategic industry/Korea signal series.
- Migrated Yahoo storage to Close, Adjusted Close, volume, source, and collection time.
- Added first-load full history, incremental updates, failure logs, and optional full adjusted-history resync.
- Preserved inactive series and the supplemental DJIA history from 1919.
- Added Sector Rotation and Semiconductor & Korea Link tabs.
- Corrected YTD, period return, correlation, beta, and drawdown definitions.
# 2026-11-05 - Gate 4 SOX Constituents implementation

- Added official Nasdaq SOX current-membership snapshot and explicit SOXQ proxy weights.
- Added 30 new Yahoo histories without duplicating NVDA or MU from the legacy Yahoo store.
- Added `original_ts_sox_components.fst`, atomic publication, last-good recovery, and independent readback checks.
- Added `derived_sox_daily_summary.fst` with breadth, returns, concentration, contribution, residual, value-chain, benchmark, and next-Korea metrics.
- Added the lazy `SOX Constituents` app tab with seven subviews and CSV download.
- Preserved legacy FRED, Yahoo, and ECOS file hashes.
- Gate status: implementation complete; independent audit required; Gate 5 remains on hold.

