# Gate 3 Validation Report

**Result: PASS**

Validated: 2026-11-05 17:48:33 KST

## Inputs

| Dataset | Rows | Series | Start | End | SHA-256 |
|---|---:|---:|---|---|---|
| ECOS | 125625 | 18 | 1964-05-04 | 2026-11-05 | `6245DA33D871B5A8ED264238EA9AE8FDBF4A5E8A0F5D814A9793EEDAA33447F5` |
| FRED | 456067 | 43 | 1901-06-30 | 2026-11-04 | `67CBDA72DEB4ED07A559584711F8AB71F83D1C578CC9F719774438F96DE53884` |
| YAHOO | 437232 | 59 | 1919-12-31 | 2026-11-04 | `D9431E63A096991AEA2B03FDE34116155572F52F6FCA1A3F318EE7B8A3671972` |

## Derived Store

- Rows: 153,329.
- Metrics: 156.
- Date range: 1998-11-13 to 2026-11-05.
- Duplicate keys: 0.
- Common current curve date: 2026-11-04.

## Performance Remediation

- Initial finding retained: the pre-remediation all-output test took 4.874 seconds and exceeded the 2-second tab-render contract.
- Measurement start: browser click on `Korea Rates & Funding`.
- Measurement end: all initially visible required outputs exist, no visible output is recalculating, and Shiny is idle.
- Cold render: p50 1.184s; max 1.306s across 5 independent processes.
- Warm render: p50 0.323s; p95 0.423s; max 0.477s across 10 transitions.
- Filter response: p50 0.233s; p95 0.365s; max 0.405s across 12 changes.
- App startup max: 2.873s. Session RSS max: 361.2 MB.

## Checks

| Check | Status | Detail |
|---|---|---|
| ecos_input_unchanged | PASS | 125625 rows |
| fred_input_unchanged | PASS | 456067 rows |
| yahoo_input_unchanged | PASS | 437232 rows |
| ecos_gate2_sha_unchanged | PASS | Gate 2 SHA = Gate 3 SHA; rows=125625; series=18; duplicates=0 |
| derived_schema | PASS | 12 required columns present |
| derived_independent_readback | PASS | 153329 rows, 156 metrics |
| derived_duplicate_keys | PASS | duplicate metric_id + observation_date + reference_date = 0 |
| derived_last_good | PASS | 153329 readable last-good rows |
| yield_curve_common_date | PASS | curve as of 2026-11-04 |
| yield_curve_complete | PASS | 8 required tenors present |
| rate_change_bp | PASS | 85 validated bp rows |
| rate_change_no_locf | PASS | Current/reference dates are actual source observations |
| funding_spread | PASS | 39776 same-date spread rows |
| special_aaa_disabled | PASS | No SPECIAL_AAA_03Y derived value exists |
| kr_us_alignment | PASS | 28796 US-to-next-KR aligned rows |
| rolling_full_windows | PASS | 40398 full-window correlations |
| no_generated_nonbusiness_observations | PASS | All derived dates trace to ECOS or FRED observations |
| fx_source_separation | PASS | ECOS_USDKRW remains separate from Yahoo USDKRW=X |
| derived_atomic_publication | PASS | Invalid duplicate staging rejected; published target remained unchanged |
| korea_rates_ui | PASS | Lazy-load and 18 Korea Rates outputs passed |
| legacy_regression | PASS | Existing Sector Rotation outputs passed |
| cold_render_le_2s | PASS | cold max 1.306s |
| warm_render_p95_le_2s | PASS | warm p95 0.423s |
| filter_response_p95_le_2s | PASS | filter p95 0.365s |
| app_startup_le_5s | PASS | startup max 2.873s |
| session_memory_le_500mb | PASS | session RSS max 361.2 MB |
| app_startup_no_external_api | PASS | No ECOS API adapter or key reference in Shiny sources |
| documentation_updated | PASS | Required remediation evidence exists |

## Missing, Delayed, and Disabled

- `PENDING_SOURCE` means the official ECOS observation has not yet been published; it is not treated as a collector failure.
- `SPECIAL_AAA_03Y` remains `SOURCE_NOT_AVAILABLE`; no empty chart or replacement series is generated.
- Curves use common exact observation dates. No LOCF or synthetic business-day rows are created.
- ECOS official USD/KRW and Yahoo market proxy remain separate.

## Decision

- `KOREA_YIELD_CURVE_PASS`
- `RATE_CHANGE_BP_PASS`
- `FUNDING_SPREAD_PASS`
- `SPECIAL_AAA_DISABLED_PASS`
- `KR_US_ALIGNMENT_PASS`
- `FX_SOURCE_SEPARATION_PASS`
- `DERIVED_ATOMIC_PUBLICATION_PASS`
- `KOREA_RATES_UI_PASS`
- `LEGACY_REGRESSION_PASS`
- `COLD_RENDER_LE_2S`
- `WARM_RENDER_P95_LE_2S`
- `FILTER_RESPONSE_P95_LE_2S`
- `ECOS_GATE2_SHA_UNCHANGED`
- `SESSION_MEMORY_LE_500MB`
- `DOCUMENTATION_UPDATED`
- `GATE_3_CLOSED_PASS`
- `GATE_4_APPROVED_TO_START`
