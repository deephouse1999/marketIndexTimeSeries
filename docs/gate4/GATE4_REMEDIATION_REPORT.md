# Gate 4 Independent Audit Remediation

## Scope

This report answers the findings in `CLAUDE_INDEPENDENT_AUDIT_REPORT.md`. No Gate 5 work was started.

| Finding | Remediation | Final evidence |
|---|---|---|
| F01 final-build evidence mismatch | Rebuilt all derived assets, then reran UI, legacy regression, Chromium performance, screenshots, hashes, and 22 validations | final timestamps; `gate4_validation.csv` |
| F02 collector ownership conflict | Legacy collector owns NVDA/MU only; Gate 4 owns 30 other required series; Gate 4-owned catalog rows are not legacy-collectable | `collector_ownership_validation.csv`; `series_disposition.csv` |
| F03 negative SK Hynix adjusted prices | Excluded 778 non-positive adjusted observations and blocked extreme daily returns from publication | `price_quality_exclusions.csv`; validation checks |
| F04 Close fallback | Removed Close fallback; returns and levels require positive finite Adjusted Close | `build_sox_gate4_summary.R`; `adjusted_close_policy` |
| F05 oldest US close retained | Sort by Korean date and descending US date, then retain the latest US close | `NEXT_KR_TRADING_DAY_LATEST_US_CLOSE` readback |
| F06 legacy regression absent | Exercised Sector Rotation, Series Explorer, Korea Rates, and Semiconductor Link | `legacy_regression_results.csv` (15/15) |
| F07 non-browser performance | Added real Chromium click-to-visible/idle and filter DOM measurements | 5 cold, 10 warm, 10 filter CSV rows |
| F08 weak reproducibility/provenance | Added canonical metadata script, independent collection readback, atomic target/last-good hashing, and PowerShell process-isolated browser harness | scripts and `file_integrity_inventory.csv` |
| F09 ambiguous index weight | Renamed field to `proxy_weight_decimal` and retained `SOXQ_PROXY` disclosure | constituent and weight evidence CSVs |
| F10 inconsistent RSS | Re-ran final UI smoke once and uses its 365.5 MB value throughout final reports | `ui_smoke_metrics.csv` |
| F11 unequal Overview inception | Common period is enforced; build-time monthly returns are compounded and indexed to 100 | `derived_sox_overview.fst/.png` |
| F12 unconditional latest loading | Only the small latest index, constituent metadata, and PNG are preloaded; full 143,438-row history remains event-driven | server code and browser timings |

## Second remediation after independent re-audit

The first re-audit report is preserved unchanged in `CLAUDE_INDEPENDENT_REAUDIT_REPORT.md`.

| Finding | Remediation | Evidence |
|---|---|---|
| R-01 same-day EOD weight lookahead | Added append-only weight history and strict `weight_as_of < return date`. Preserved 2026-11-04 official EOD snapshot and transparently reconstructed the unavailable 2026-11-03 pre-EOD snapshot by reversing 2026-11-04 Adjusted Close drift; never labels it official | `sox_weight_history.csv`; `weight_reconstruction_evidence.csv`; `strict_prior_weight_usage` |
| R-02 28/30 aggregate published | Added 30-member and full-weight completeness gate. The 2026-11-05 28/30 date is quality evidence only and all member aggregate groups stop at the latest complete 2026-11-04 date | `member_date_completeness.csv`; `complete_member_aggregate_only`; `incomplete_dates_not_published` |
| R-03 Overview common period | Uses the four-series shared trading-date intersection. All series run 2021-06-11 to 2026-11-04 and start exactly at 100 | `derived_sox_overview.fst/.png`; overview validation checks |
| R-04 timing disclosure | Retained the disclosed contract timing: click after initial Shiny idle and required first-view asset readiness. App startup remains separately measured | performance CSVs and report |
| R-05 dead preload | Removed unused `overview_store`; only the displayed PNG and latest status index preload | server code |

## Final controls

```text
COLLECTOR_OWNERSHIP_CONFLICT_RESOLVED
ADJUSTED_CLOSE_QUALITY_GUARD_PASS
LATEST_US_CLOSE_ALIGNMENT_PASS
STRICT_PRIOR_WEIGHT_SNAPSHOT_PASS
INCOMPLETE_MEMBER_DATE_BLOCKED
OVERVIEW_COMMON_PERIOD_EXACT_100_PASS
FINAL_BUILD_BROWSER_PERFORMANCE_PASS
LEGACY_REGRESSION_PASS
LEGACY_FST_HASH_UNCHANGED
DOCUMENTATION_UPDATED
```

Independent decision received:

```text
GATE_4_SECOND_INDEPENDENT_REAUDIT_PASS
GATE_4_CLOSED_PASS
GATE_5_APPROVED_TO_START
```
