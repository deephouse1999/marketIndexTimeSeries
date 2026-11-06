# Gate 4 SOX Constituents Validation Report

Validated: 2026-11-06 KST, after independent-audit remediation.

## Decision

```text
GATE_4_SECOND_INDEPENDENT_REAUDIT_PASS
GATE_4_CLOSED_PASS
GATE_5_APPROVED_TO_START
```

Internal validation passed 28/28 checks after the second remediation. Claude's second independent read-only re-audit accepted the final build with no HIGH or MEDIUM findings.

## Final build

| Check | Result |
|---|---:|
| Official Nasdaq members | 30 |
| Required series | 32 |
| Legacy Yahoo series reused | 2 (`NVDA`, `MU`) |
| Gate 4 series collected | 30 |
| Gate 4 raw rows / duplicate keys | 207,905 / 0 |
| Derived rows / metrics / duplicate keys | 143,438 / 79 / 0 |
| Membership effective date | 2026-11-04 |
| Proxy weight sum | 0.99979655 |
| Weight snapshots | 2026-11-03 reconstructed pre-EOD; 2026-11-04 official EOD |
| Published member aggregates | complete 30/30 dates only |
| UI smoke | PASS, 9 outputs |
| Legacy regression | PASS, 15 outputs across 4 screens |
| App-time external API calls | 0 |

Returns use positive finite Yahoo Adjusted Close only. The 778 non-positive legacy `000660.KS` observations are excluded; returns over 100% in absolute value are not published. US closes mapping to the same Korean session retain the latest US close. Daily weights must satisfy `weight_as_of < return date`. The incomplete 2026-11-05 member set (28/30, available weight 80.29%, coverage 80.31%) is recorded in quality evidence and not published as an aggregate.

## Collector ownership

The legacy Yahoo collector owns `NVDA` and `MU`. The Gate 4 collector owns the other 30 required series. Gate 4-owned catalog rows have `collect_flag=FALSE`, preventing the legacy Update Market Data workflow from collecting or duplicating them. Evidence: `collector_ownership_validation.csv`.

## Performance

Measurements use final-build Chromium DOM visibility and Shiny idle state. Cold timing starts after initial app startup/idle, at the first SOX tab click.

| Test | Result | Contract |
|---|---:|---:|
| App startup max | 3.155 s | <= 5 s |
| Cold visible render max, 5 fresh processes | 0.070 s | <= 2 s |
| Warm tab render p95, 10 actual transitions | 0.289 s | <= 2 s |
| Filter response p95, 10 actual changes | 0.079 s | <= 2 s |
| Session RSS | 365.5 MB | <= 500 MB |

The first-view status and prebuilt Overview PNG are lightweight startup assets. The 143,438-row history remains lazy and hidden Plotly/DT outputs remain suspended. Overview uses the four-series shared trading-date intersection, 2021-06-11 through 2026-11-04, with every first value exactly 100.

## Integrity

Legacy approved hashes are unchanged:

- FRED: `67CBDA72DEB4ED07A559584711F8AB71F83D1C578CC9F719774438F96DE53884`
- Yahoo: `D9431E63A096991AEA2B03FDE34116155572F52F6FCA1A3F318EE7B8A3671972`
- ECOS: `6245DA33D871B5A8ED264238EA9AE8FDBF4A5E8A0F5D814A9793EEDAA33447F5`

Gate 4 source and derived target/last-good artifacts are independently hashed in `file_integrity_inventory.csv`. Atomic replacement is exercised by the collectors/builders; last-good is a prior published artifact, not a manually copied proof file.

## Evidence

- `GATE4_REMEDIATION_REPORT.md`
- `gate4_validation.csv`
- `collection_summary.csv`
- `collector_ownership_validation.csv`
- `price_quality_exclusions.csv`
- `sox_weight_history_evidence.csv`
- `weight_reconstruction_evidence.csv`
- `member_date_completeness.csv`
- `daily_replication_evidence.csv`
- `contribution_samples.csv`
- `performance_cold_runs.csv`
- `performance_warm_runs.csv`
- `performance_filter_runs.csv`
- `performance_summary.csv`
- `legacy_regression_results.csv`
- `file_integrity_inventory.csv`
- final browser screenshots `sox_*.png`
- `CLAUDE_SECOND_INDEPENDENT_REAUDIT_REPORT.md`
