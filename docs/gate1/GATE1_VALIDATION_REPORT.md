# Gate 1 Validation Report

**Result: PASS**

Initial review disposition: `PASS WITH MINOR RECONCILIATION`. The catalog/FST reconciliation and Bovespa Regional View correction are now complete.

Validated: 2026-11-05 14:23:36 KST

## Scope

- Catalog schema migration and metadata correction only.
- Existing FRED and Yahoo FST files were not recollected or rewritten.
- ECOS and SOX collection are deferred to later gates.

## Checks

| Check | Status | Detail |
|---|---|---|
| catalog_schema | PASS | 25 columns |
| catalog_unique_key | PASS | duplicate (source, series_id) = 0 |
| catalog_source_domain | PASS | ECOS, FRED, YAHOO |
| catalog_cycle_domain | PASS | , D, M, Q |
| catalog_price_policy_domain | PASS | adjusted, close |
| catalog_names | PASS | English and Korean names populated |
| non_destructive_deactivation | PASS | 7 legacy rows retained, collection/default display disabled |
| hidden_but_collectable | PASS | 4 global rows remain collectable but hidden by default |
| legacy_history_preserved | PASS | all deactivated Yahoo series remain in FST |
| bovespa_regional_classification | PASS | Bovespa retained in Regional View with no standalone module |
| required_metadata_corrections | PASS | 12 required identifiers, names, and classes match the Gate 1 contract |
| new_fred_registered | PASS | DFEDTARL, DFII10, T10YIE, DFF, SOFR |
| new_yahoo_registered | PASS | SHY, IEF, TLT, LQD, HYG, SOXQ, 005930.KS, HG=F |
| catalog_inventory_reconciled | PASS | 116 = 102 stored + 13 pending + 1 intentional |
| topix_catalog_only | PASS | ^TOPX retained only as a disabled catalog mapping |
| fred_row_count | PASS | 456067 rows |
| fred_date_range | PASS | 1901-06-30 to 2026-11-04 |
| fred_unique_key | PASS | duplicate keys = 0 |
| fred_sha256 | PASS | 67CBDA72DEB4ED07A559584711F8AB71F83D1C578CC9F719774438F96DE53884 |
| yahoo_row_count | PASS | 437232 rows |
| yahoo_date_range | PASS | 1919-12-31 to 2026-11-04 |
| yahoo_unique_key | PASS | duplicate keys = 0 |
| yahoo_sha256 | PASS | D9431E63A096991AEA2B03FDE34116155572F52F6FCA1A3F318EE7B8A3671972 |
| collector_catalog_load | PASS | collector parser accepts Gate 1 schema |
| shiny_source_load | PASS | app.R defines ui and server |

## Inventory

- Gate 1 legacy catalog: 116 rows, 25 columns (FRED 48, Yahoo 68).
- FRED FST: 456,067 rows, 43 stored series.
- Yahoo FST: 437,232 rows, 59 stored series.
- Newly registered, pending collection: 13 series.
- Reconciliation: legacy catalog 116 = stored 102 + pending 13 + intentional catalog-only 1.

## Catalog-FST Anti-Join

| Source | Series | Classification | Rationale |
|---|---|---|---|
| YAHOO | ^TOPX | INTENTIONALLY_CATALOG_ONLY | Unsupported Yahoo TOPIX symbol retained for mapping; collection and default display disabled |
| FRED | DFEDTARL | EXPECTED_PENDING_COLLECTION | Registered in Gate 1; collection begins in the applicable later gate |
| FRED | DFII10 | EXPECTED_PENDING_COLLECTION | Registered in Gate 1; collection begins in the applicable later gate |
| FRED | T10YIE | EXPECTED_PENDING_COLLECTION | Registered in Gate 1; collection begins in the applicable later gate |
| FRED | DFF | EXPECTED_PENDING_COLLECTION | Registered in Gate 1; collection begins in the applicable later gate |
| FRED | SOFR | EXPECTED_PENDING_COLLECTION | Registered in Gate 1; collection begins in the applicable later gate |
| YAHOO | SHY | EXPECTED_PENDING_COLLECTION | Registered in Gate 1; collection begins in the applicable later gate |
| YAHOO | IEF | EXPECTED_PENDING_COLLECTION | Registered in Gate 1; collection begins in the applicable later gate |
| YAHOO | TLT | EXPECTED_PENDING_COLLECTION | Registered in Gate 1; collection begins in the applicable later gate |
| YAHOO | LQD | EXPECTED_PENDING_COLLECTION | Registered in Gate 1; collection begins in the applicable later gate |
| YAHOO | HYG | EXPECTED_PENDING_COLLECTION | Registered in Gate 1; collection begins in the applicable later gate |
| YAHOO | SOXQ | EXPECTED_PENDING_COLLECTION | Registered in Gate 1; collection begins in the applicable later gate |
| YAHOO | 005930.KS | EXPECTED_PENDING_COLLECTION | Registered in Gate 1; collection begins in the applicable later gate |
| YAHOO | HG=F | EXPECTED_PENDING_COLLECTION | Registered in Gate 1; collection begins in the applicable later gate |

## Gate 1 Closure

- `CATALOG_INVENTORY_RECONCILED`
- `BOVESPA_REGIONAL_CLASSIFICATION_PASS`
- `LEGACY_FST_HASH_UNCHANGED`
- `DOCUMENTATION_UPDATED`
- `GATE_1_CLOSED_PASS`
- `GATE_2_APPROVED_TO_START`

## Gate Decision

Gate 1 is closed. Gate 2 ECOS Adapter development is approved to start.
