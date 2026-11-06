# Market Timeseries Validation Report

Validated: 2026-11-05 KST

## Gate 4.5 Physical Indicators Addendum

**Result: `GATE_4_5_CLOSED_PASS / RELEASE_APPROVED`**

- Official ECOS readback verified DRAM `404Y016/30911201AA` and Flash Memory `404Y016/30911202AA`, monthly, `2020=100`.
- Raw inventory: DRAM 381 rows, Flash 261 rows, BWET 882 rows; duplicate source/series/date keys are zero.
- Monthly ECOS observations were not daily-expanded; point-in-time `available_at` validation passed for all 1,524 physical observations.
- Derived store contains 3,967 rows with six PPI measures, 104 monthly lead/lag rows, and eleven BWET metrics.
- Local browser validation passed 11/11, including both visible PPI lines, metadata/status text, Physical Indicators filtering, BWET warning, and Raw Source line rendering.
- Existing regression passed: 15 legacy outputs, Series Explorer plots 2/2, UI remediation 9/9; startup 1.857s and RSS 415MB after lazy physical loading.
- Public bundle `12787559` passed 9/9 direct smoke checks; release baseline `e001a21a15b51e81f84ffd809d84c90512e51503` matched `origin/main`.
- The second independent read-only re-audit closed all first-audit findings and approved release.
- Evidence: `docs/gate4_5/GATE4_5_VALIDATION_REPORT.md`.

Decision:

```text
ECOS_DRAM_METADATA_READBACK_PASS
ECOS_FLASH_METADATA_READBACK_PASS
PHYSICAL_COLLECTION_PASS
AVAILABLE_AT_CONTRACT_PASS
NO_DAILY_LOCF_PASS
BWET_PROXY_SEMANTICS_PASS
UI_VISIBILITY_PASS
SCHEDULE_INCLUSION_PASS
GATE_4_5_SELF_VALIDATION_PASS
GATE_4_5_SECOND_INDEPENDENT_REAUDIT_PASS
GIT_REPRODUCIBILITY_PASS
GATE_4_5_CLOSED_PASS
RELEASE_APPROVED
```

## Gate 6 Closure

**Result: `GATE_6_CLOSED_PASS / PRODUCTION_RELEASE_APPROVED`**

- Final integrated checks: 21/21 PASS.
- Real-browser functional checks: 28/28 PASS across all five main tabs.
- CSV downloads: Series Explorer 3 selected rows, Korea Rates 153,352 rows, SOX derived data 143,493 rows.
- Main-tab maximum: 1.923s; cold max: 0.078s; warm p95: 0.291s; filter p95: 0.153s.
- App startup max: 3.145s; session RSS: 434.6MB.
- Public shinyapps.io bundle `12786763` passed Sector, Series Explorer, Korea Rates, and SOX smoke tests.
- Source reconciliation: FRED 503,123 rows, Yahoo 473,230, ECOS 125,645, and SOX components 207,906; contracted duplicate keys are zero.
- Gate 4 FRED baseline and all 246,950 legacy unknown-source rows remain preserved after the Gate 5 remediation.

Final decision:

```text
DATA_SOURCE_CONTRACT_VERIFIED
ECOS_FULL_AND_INCREMENTAL_PASS
SOX_CONSTITUENT_HISTORY_PASS
US_DST_SCHEDULE_PASS
KR_CLOSE_SCHEDULE_PASS
ATOMIC_PUBLICATION_PASS
LEGACY_REGRESSION_PASS
PERFORMANCE_GATE_PASS
DOCUMENT_INTEGRITY_PASS
GATE_6_CLOSED_PASS
PRODUCTION_RELEASE_APPROVED
```

Evidence: `docs/gate6/GATE6_VALIDATION_REPORT.md`.

## Gate 5 Closure

**Result: `GATE_5_CLOSED_PASS`**

- Deterministic schedule and rollback tests: 7/7 PASS.
- Final integrated validation: 30/30 PASS.
- US close live batch: 154 configured, 115 updated, 22 no-new-data, 17 pending-source, zero missing critical.
- KR close live batch: 22 configured, 1 updated, 4 no-new-data, 17 pending-source, zero missing critical.
- FRED legacy-key remediation preserved 503,123 rows, including all 246,950 `source=NA` legacy rows; duplicate `(source, series_id, date)` keys remain zero.
- Yahoo: 473,230 rows / 65 series / zero duplicate keys.
- ECOS: 125,645 rows / 18 series / zero duplicate keys.
- SOX components: 207,906 rows / 30 series / zero duplicate keys.
- Three Windows tasks were registered and read back: US DST 07:05 KST, US standard 08:05 KST, and KR 16:05 KST.
- Evidence: `docs/gate5/GATE5_VALIDATION_REPORT.md`, `docs/gate5/gate5_validation_checks.csv`, and `docs/gate5/scheduled_tasks_readback.txt`.

Decision:

```text
US_CLOSE_SCHEDULE_PASS
KR_CLOSE_SCHEDULE_PASS
DST_RUNTIME_GUARD_PASS
HOLIDAY_NOOP_PASS
STAGING_ATOMIC_PUBLICATION_PASS
LAST_GOOD_AND_ROLLBACK_PASS
STATE_CONTRACT_PASS
LEGACY_FRED_HISTORY_PRESERVED
GATE_5_CLOSED_PASS
GATE_6_APPROVED_TO_START
```

## Gate 1 Closure

**Result: `GATE_1_CLOSED_PASS`**

The initial `PASS WITH MINOR RECONCILIATION` items are closed.

```text
legacy_catalog_total 116
= stored_series 102
+ pending_collection 13
+ intentional_catalog_only 1
```

- The additional catalog-only row is Yahoo `^TOPX`, classified as `INTENTIONALLY_CATALOG_ONLY` because Yahoo returned no supported history. Collection and default display are disabled; the mapping row is preserved.
- The 13 pending rows are listed in `docs/gate1/pending_collection_13.csv`.
- The complete anti-join is in `docs/gate1/catalog_fst_anti_join.csv`.
- Bovespa is `emerging_market_index / regional_comparison`, remains collectable and visible, and is included only in Regional View logic.
- FRED remains 456,067 rows with SHA-256 `67CBDA72DEB4ED07A559584711F8AB71F83D1C578CC9F719774438F96DE53884`.
- Yahoo remains 437,232 rows with SHA-256 `D9431E63A096991AEA2B03FDE34116155572F52F6FCA1A3F318EE7B8A3671972`.

Decision:

```text
CATALOG_INVENTORY_RECONCILED
BOVESPA_REGIONAL_CLASSIFICATION_PASS
LEGACY_FST_HASH_UNCHANGED
DOCUMENTATION_UPDATED
GATE_1_CLOSED_PASS
GATE_2_APPROVED_TO_START
```

Detailed evidence: `docs/gate1/GATE1_VALIDATION_REPORT.md`.

## Gate 2 ECOS Adapter

**Result: `GATE_2_CLOSED_PASS`**

- Authentication: `ECOS_API_KEY` environment binding confirmed; key value persisted in zero repository files.
- Official readback: 844 table rows, 53 metadata rows, and 128 item rows across `722Y001`, `817Y002`, and `731Y001`.
- Contract: 18/18 collectable series matched official code, item name, cycle, and unit.
- Unavailable source: `SPECIAL_AAA_03Y` is `SOURCE_NOT_AVAILABLE`; no substitute was used.
- Sample: 102 recent rows across base rate, KTB 3Y, and official USD/KRW.
- Pagination: KTB 3Y returned 6,931 rows over at least seven pages with zero duplicate keys.
- Full history: 125,625 rows, 18 series, 1964-05-04 through 2026-11-05.
- Incremental: all 18 series used five-business-day overlap; final unique row count remained 125,625.
- Publication: staging, independent readback, last-good preservation, and atomic failure tests passed.

Decision:

```text
ECOS_KEY_BINDING_PASS
ECOS_OFFICIAL_READBACK_PASS
ECOS_FULL_AND_INCREMENTAL_PASS
ECOS_DUPLICATE_KEY_ZERO
ECOS_ATOMIC_PUBLICATION_PASS
GATE_2_CLOSED_PASS
GATE_3_APPROVED_TO_START
```

Detailed evidence: `docs/gate2/GATE2_VALIDATION_REPORT.md`.

## Gate 3 Korea Rates & Funding

**Result: `GATE_3_CLOSED_PASS`**

- Inputs remained unchanged: ECOS 125,625 rows, FRED 456,067 rows, and Yahoo 437,232 rows retained their approved SHA-256 hashes.
- Derived publication: 153,329 rows, 156 metrics, 1998-11-13 through 2026-11-05, zero duplicate keys.
- Curve basis: common exact ECOS observation date 2026-11-04 with all required tenors.
- Changes and spreads: independently recalculated samples passed; no LOCF or synthetic dates were found.
- Korea-US: exact-date level/spread comparisons and US t to first later Korean observation alignment passed.
- Rolling correlations: 20/60/120-observation full-window checks passed.
- Source controls: `SPECIAL_AAA_03Y` remains disabled and ECOS USD/KRW remains separate from Yahoo `USDKRW=X`.
- Initial performance finding: the original all-output render was 4.874 seconds and failed the unchanged 2-second tab contract.
- Remediation: the initial view uses a 141-row latest index; historical outputs render only inside the six accessed subtabs; full market data loads only when Series Explorer is opened.
- Browser performance: cold max 1.306s, warm p95 0.423s, filter p95 0.365s, and startup max 2.873s.
- Runtime memory: maximum measured Korea Rates session RSS was 361.2 MB.
- App controls: all 18 Korea Rates outputs, lazy-history loading, hidden-output suspension, and existing Sector Rotation regression passed.
- Publication controls: staging rejection, independent readback, last-good preservation, and target integrity passed.
- ECOS source: Gate 2 and Gate 3 SHA-256 both equal `6245DA33D871B5A8ED264238EA9AE8FDBF4A5E8A0F5D814A9793EEDAA33447F5`; 125,625 rows, 18 series, and zero duplicate keys.

Decision:

```text
KOREA_YIELD_CURVE_PASS
RATE_CHANGE_BP_PASS
FUNDING_SPREAD_PASS
SPECIAL_AAA_DISABLED_PASS
KR_US_ALIGNMENT_PASS
FX_SOURCE_SEPARATION_PASS
DERIVED_ATOMIC_PUBLICATION_PASS
KOREA_RATES_UI_PASS
LEGACY_REGRESSION_PASS
COLD_RENDER_LE_2S
WARM_RENDER_P95_LE_2S
FILTER_RESPONSE_P95_LE_2S
ECOS_GATE2_SHA_UNCHANGED
SESSION_MEMORY_LE_500MB
DOCUMENTATION_UPDATED
GATE_3_CLOSED_PASS
GATE_4_APPROVED_TO_START
```

Detailed evidence: `docs/gate3/GATE3_VALIDATION_REPORT.md`.

# Gate 4 Status

```text
GATE_4_SECOND_INDEPENDENT_REAUDIT_PASS
GATE_4_CLOSED_PASS
GATE_5_APPROVED_TO_START
```

The first independent re-audit confirmed 11 of 12 original findings closed but identified same-day EOD weight lookahead, an incomplete 28/30 aggregate, and an Overview common-period defect. The second remediation adds strict prior-date weight snapshots, blocks incomplete dates, and enforces an exact common-period 100 baseline. The final build passes 28/28 data and control checks, 9 SOX UI outputs, 15 legacy outputs, five browser cold runs, ten warm transitions, and ten filter changes. Cold max is 0.070s, warm p95 0.289s, filter p95 0.079s, startup max 3.155s, and session RSS 365.5 MB. FRED, Yahoo, and ECOS approved hashes remain unchanged. Claude's second independent read-only re-audit found no HIGH or MEDIUM issues and approved Gate 4 closure and Gate 5 start. See `docs/gate4/CLAUDE_SECOND_INDEPENDENT_REAUDIT_REPORT.md`.

