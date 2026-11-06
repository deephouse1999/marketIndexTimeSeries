# Market Timeseries Integrity

Required checks after catalog or collector changes:

1. Catalog parses to the exact 25-column schema with no duplicate `source + series_id` key.
2. `source`, `cycle`, `price_policy`, and `series_cls` values pass their controlled-domain checks.
3. `collect_flag`, `default_visible`, and `active` are evaluated independently.
4. Retired collection rows remain in catalog and storage; no physical purge occurs without explicit approval.
5. Existing FRED/Yahoo row counts, date ranges, and SHA-256 hashes remain unchanged during catalog-only gates.
6. All 11 active sector ETFs exist in the Yahoo FST.
7. All `semiconductor_korea` analysis members with collected history exist in the Yahoo FST.
8. Stored `source + series_id + date` keys are unique.
9. DJIA supplemental history starts on 1919-12-31 and overlaps Yahoo without duplicate dates.
10. New symbols with zero rows are reported as `empty_new_series` and included in the failure summary when collection begins.
11. The collector parser and Shiny application source successfully load the current catalog.

Validated on 2026-09-01: 11 sector metrics, 8 link metrics, and all new-tab server outputs passed.

Gate 1 validated on 2026-11-05: 22/22 checks passed. See `docs/gate1/GATE1_VALIDATION_REPORT.md`.

Gate 1 reconciliation closed on 2026-11-05: 25/25 checks passed, with `116 = 102 + 13 + 1` fully classified.

Gate 2 validated on 2026-11-05: 20/20 checks passed. ECOS has 125,625 rows, 18 series, and zero duplicate keys. See `docs/gate2/GATE2_VALIDATION_REPORT.md`.

ECOS integrity rules:

1. Never collect a row unless official item code, item name, cycle, and unit all match the catalog contract.
2. `INFO-200` for current/future publication is `PENDING_SOURCE`, not a fabricated observation or hard batch failure.
3. Incremental collection starts five business days before the stored endpoint and overwrites only matching keys with newer source values.
4. Publication must pass staging schema, duplicate-key, row-count, and independent readback checks.
5. Failed staging leaves `original_ts_ecos.fst` and its last-good snapshot intact.
6. `USDKRW=X` and `ECOS_USDKRW` remain separate.

Gate 3 validated on 2026-11-05: 28/28 checks passed after preserving and remediating the original 4.874-second performance finding. The derived store contains 153,329 rows, 156 metrics, and zero duplicate `metric_id + observation_date + reference_date` keys. Cold max was 1.306s, warm p95 0.423s, filter p95 0.365s, startup max 2.873s, and session RSS max 361.2 MB. See `docs/gate3/GATE3_VALIDATION_REPORT.md`.

Korea Rates derived integrity rules:

1. ECOS, FRED, and Yahoo source FST files are read-only during derived builds and validation.
2. Curves and spreads use common exact source observation dates; no LOCF or synthetic non-business observations are permitted.
3. Rate changes are basis-point differences between actual current and reference observations.
4. US close at t aligns only to the first later Korean business observation.
5. Rolling correlations require complete 20, 60, or 120-observation windows.
6. `SPECIAL_AAA_03Y` remains disabled unless a separately approved official source is verified.
7. ECOS USD/KRW remains distinct from Yahoo `USDKRW=X`.
8. Derived publication must pass staging, duplicate-key, independent-readback, last-good, and atomic-replacement checks.
