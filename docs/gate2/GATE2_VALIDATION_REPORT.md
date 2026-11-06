# Gate 2 ECOS Adapter Validation Report

**Result: PASS**

Validated: 2026-11-05 14:24:22 KST

## Scope

- Environment-only ECOS authentication.
- Official table, item, and metadata readback.
- Code, item name, cycle, and unit contract validation.
- Sample, pagination, full-history, and five-business-day overlap collection.
- Staging validation, independent readback, and atomic publication.

## Checks

| Check | Status | Detail |
|---|---|---|
| legacy_fred_unchanged | PASS | 456067 rows |
| legacy_yahoo_unchanged | PASS | 437232 rows |
| ecos_independent_readback | PASS | 125625 rows, 18 series |
| ecos_duplicate_keys | PASS | duplicate (source, series_id, date) = 0 |
| ecos_date_range | PASS | 1964-05-04 to 2026-11-05 |
| last_good_readable | PASS | 125625 rows, 18 series |
| ecos_catalog_contract | PASS | 19 catalog rows = 18 collectable + 1 unavailable |
| special_bond_unavailable | PASS | No unverified substitute was used |
| official_item_contract | PASS | 18/18 code, item name, cycle, and unit contracts verified |
| official_service_readback | PASS | 7 service checks |
| sample_collection | PASS | 102 rows across 3 series |
| pagination | PASS | 6931 rows across at least 7 pages |
| pending_source | PASS | Future unpublished data produced no fabricated row |
| full_history_collection | PASS | 18 full-history series logged |
| overlap_incremental | PASS | 18 series used five-business-day overlap |
| incremental_no_row_growth | PASS | Incremental rerun retained 125,625 unique rows |
| no_unpublished_staging | PASS | No staging file remains after publication |
| atomic_failure_preserves_last_good | PASS | Invalid duplicate-key staging was rejected and target hash stayed unchanged |
| api_key_not_persisted | PASS | ECOS_API_KEY value found in 0 repository text files |
| app_session_no_ecos_api | PASS | Shiny app has no ECOS adapter, key, or ECOS store reference during Gate 2 |

## Publication Inventory

- ECOS: 125,625 rows, 18 series, 1964-05-04 to 2026-11-05.
- Catalog: 18 official contracts verified; `SPECIAL_AAA_03Y` recorded as `SOURCE_NOT_AVAILABLE`.
- Latest daily observations may be `SUCCESS_PENDING_SOURCE`; no non-business-day or fabricated rows are generated.
- `USDKRW=X` and `ECOS_USDKRW` remain separate series.

## Decision

- `ECOS_KEY_BINDING_PASS`
- `ECOS_OFFICIAL_READBACK_PASS`
- `ECOS_FULL_AND_INCREMENTAL_PASS`
- `ECOS_DUPLICATE_KEY_ZERO`
- `ECOS_ATOMIC_PUBLICATION_PASS`
- `GATE_2_CLOSED_PASS`
- `GATE_3_APPROVED_TO_START`
