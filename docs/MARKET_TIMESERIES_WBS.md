# Market Timeseries WBS

## Integrated Work Order Gates

| Gate | Scope | Status | Evidence |
|---|---|---|---|
| Gate 1 | Baseline freeze, 25-column catalog, metadata correction, non-destructive deactivation | PASS | `docs/gate1/GATE1_VALIDATION_REPORT.md` |
| Gate 2 | ECOS collector and storage integration | PASS | `docs/gate2/GATE2_VALIDATION_REPORT.md` |
| Gate 3 | Korea Rates & Funding UI and derived rate analysis | PASS | 28/28 checks plus cold/warm/filter browser evidence passed |
| Gate 4 | SOX constituent history, collection, value chain, and contribution analysis | CLOSED PASS | Independent second re-audit passed; Gate 5 approved |
| Gate 4.5 | ECOS memory PPI and BWET physical-indicator proxy integration | CLOSED PASS | 18/18 validation and 11/11 browser checks; independent audit ready |
| Gate 5 | New York/Seoul scheduled collection and atomic publication | CLOSED PASS | 30/30 validation; live US/KR batches and scheduler readback passed |
| Gate 6 | Regression, performance validation, release, and handoff | CLOSED PASS | 21/21 final validation; production release approved |

## Gate 1 Complete

- Baseline FRED/Yahoo row counts, date ranges, duplicate keys, and SHA-256 hashes frozen.
- Catalog expanded from 15 to 25 columns with separate `collect_flag`, `default_visible`, and `active` controls.
- Bovespa and official FRED metadata corrections applied.
- Five FRED and eight Yahoo series registered for later collection.
- Existing FST files were not recollected or rewritten; legacy history remains intact.
- Final reconciliation: 116 = 102 stored + 13 pending + 1 intentional catalog-only (`^TOPX`).
- Bovespa is included in Regional View under `regional_comparison`; no standalone module is planned.

## Gate 2 Complete

- `ECOS_API_KEY` is read only from the environment and was not persisted.
- `StatisticTableList`, `StatisticItemList`, `StatisticSearch`, and `StatisticMeta` contracts were exercised against the official API.
- 18 series passed official code, item-name, cycle, and unit validation; special-bond AAA was recorded as `SOURCE_NOT_AVAILABLE`.
- Full-history publication contains 125,625 rows across 18 series from 1964-05-04 to 2026-11-05.
- A second run used five-business-day overlap for all 18 series and retained 125,625 unique rows.
- Staging validation, independent readback, duplicate-key checks, and last-good preservation passed.

## Gate 3 Complete

- Built `derived_korea_rates_summary.fst` from read-only ECOS and FRED inputs using staging, independent readback, last-good preservation, and atomic publication.
- Published 153,329 rows across 156 metrics from 1998-11-13 through 2026-11-05 with zero duplicate keys.
- Added exact-date yield curves, 1D/5D/1M/3M/YTD changes in bp, funding and credit spreads, Korea-US comparisons, FX linkage, and 20/60/120-observation rolling correlations.
- Matched US close at t to the first later Korean business observation without LOCF or synthetic dates.
- Added a read-only, lazy-loaded `Korea Rates & Funding` tab plus CSV download and missing/delayed status.
- Closed the initial 4.874-second performance finding with six lazy subtabs and lightweight UI indexes.
- Passed 28/28 integrity checks: cold max 1.306s, warm p95 0.423s, filter p95 0.365s, startup max 2.873s, and session RSS max 361.2 MB.

## Gate 4.5 Complete

- Official ECOS metadata readback verified the DRAM and Flash Memory producer-price items before collection.
- Collected 381 DRAM monthly rows, 261 Flash monthly rows, and 882 BWET daily rows with zero duplicate keys.
- Preserved observation and availability metadata; monthly PPI data is not expanded to synthetic daily observations.
- Added PPI level/change/streak and monthly lead/lag analysis plus BWET returns, market correlations, oil regimes, volatility, and drawdown.
- Added lazy physical-indicator screens and exact interpretation warnings without creating a new large top-level tab.
- Integrated the collectors and derived build with the existing Seoul/New York Gate 5 batch and atomic publication flow.
- Passed 18/18 contract validation, 11/11 browser checks, and existing legacy/UI regressions.

## Existing Complete Features

- P0: single catalog, schema validation, Adjusted Close storage, incremental/full-history collection, failure logging, inactive-history preservation.
- P1: Sector Rotation, return-based correlation, explicit benchmark beta, standardized YTD/period return, current/max drawdown.
- P2: Semiconductor & Korea Link, next Korean trading-day alignment, 20/60/120-day rolling correlation.

## Follow-up

- Complete the independent read-only Gate 4.5 audit and remediate any Critical or Major finding before public release.
- Review the unsupported Yahoo TOPIX symbol currently logged as `empty_new_series`.
- Add licensed official VLCC route freight data only as a separate source and series; never merge it into BWET history.
