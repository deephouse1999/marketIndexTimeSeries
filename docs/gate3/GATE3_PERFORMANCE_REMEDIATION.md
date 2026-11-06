# Gate 3 Performance Remediation

## Status

The original functional result remains valid. The initial performance finding is retained and remediated under the unchanged performance contract.

## Original Finding

- Pre-remediation app source/startup evaluation: 1.8 seconds.
- Pre-remediation all-output Korea Rates render: 4.874 seconds.
- The 4.874-second result exceeded the 2.0-second normal tab-render limit and was not accepted as `PERFORMANCE_GATE_PASS`.
- Interim decision: `GATE_3_FUNCTIONAL_PASS`, `GATE_3_PERFORMANCE_FINDING_OPEN`, `GATE_4_START_HOLD`.

## Measurement Contract

- Start: the browser clicks `Korea Rates & Funding`.
- End: data status, build status, current yield curve, major maturity-change summary, and latest spread summary are visible; no visible output is recalculating; Shiny is idle.
- Cold runs use a new R/Shiny process, a new Chrome session, and a cleared browser cache.
- Warm runs alternate another top-level tab with Korea Rates in one session.
- Filter runs mutate real maturity, spread, Korea-US pair, transmission-relation, and date-range controls and wait for the visible target to mutate and Shiny to return idle.
- Hidden suspended outputs do not count as complete and are not allowed to continue unnecessary computation.

## Remediation

- Added the 141-row `derived_korea_rates_latest.fst` index for the initial screen.
- Kept the complete 153,329-row derived store unchanged in scope and lazy-loaded it only for history-dependent subtabs.
- Split the UI into `Yield Curve`, `Rate Changes`, `Funding & Credit Spreads`, `Korea-US Link`, `FX Link`, and `Data Quality`.
- Added subtab guards and explicit `suspendWhenHidden = TRUE` for Plotly, DT, and status outputs.
- Preserved all original 18 Korea Rates outputs and added compact initial summaries.
- Added `derived_market_ui_core.fst` so app startup loads only Sector/Link core series; the full Yahoo/FRED explorer store loads only when `Series Explorer` is opened.
- Reduced the shared analysis join to the required display columns.
- No rate formula, date alignment, quality rule, source separation, or derived history was removed or relaxed.

## Results

| Metric | Result | Limit | Status |
|---|---:|---:|---|
| Cold render p50 | 1.184 s | 2.0 s | PASS |
| Cold render max | 1.306 s | 2.0 s | PASS |
| Warm render p50 | 0.323 s | 2.0 s | PASS |
| Warm render p95 | 0.423 s | 2.0 s | PASS |
| Warm render max | 0.477 s | 2.0 s | PASS |
| Filter response p50 | 0.233 s | 2.0 s | PASS |
| Filter response p95 | 0.365 s | 2.0 s | PASS |
| Filter response max | 0.405 s | 2.0 s | PASS |
| App server startup max | 2.873 s | 5.0 s | PASS |
| Session RSS max | 361.2 MB | 500 MB | PASS |

Raw evidence:

- `performance_cold_runs.csv`: 5 independent cold runs.
- `performance_warm_runs.csv`: 10 warm transitions.
- `performance_filter_runs.csv`: 12 representative filter changes.
- `performance_summary.csv`: p50, p95, maximum, startup, and memory gates.
- `ui_regression_retest.md`: 18 Korea Rates outputs and legacy regression.
- `ecos_sha_comparison.txt`: Gate 2 and Gate 3 ECOS source comparison.

## Decision

```text
COLD_RENDER_LE_2S
WARM_RENDER_P95_LE_2S
FILTER_RESPONSE_P95_LE_2S
ECOS_GATE2_SHA_UNCHANGED
KOREA_RATES_FUNCTIONAL_REPASS
LEGACY_REGRESSION_REPASS
SESSION_MEMORY_LE_500MB
DOCUMENTATION_UPDATED
GATE_3_CLOSED_PASS
GATE_4_APPROVED_TO_START
```
