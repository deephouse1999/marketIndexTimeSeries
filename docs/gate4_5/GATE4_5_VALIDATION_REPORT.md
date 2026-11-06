# Gate 4.5 Physical Indicators Validation

Validated: 2026-11-06 21:32:48 KST

**Result: PASS (21/21)**

## Decision

```text
ECOS_DRAM_METADATA_READBACK_PASS
ECOS_FLASH_METADATA_READBACK_PASS
PHYSICAL_COLLECTION_PASS
AVAILABLE_AT_CONTRACT_PASS
NO_DAILY_LOCF_PASS
REFERENCE_MONTH_SEMANTICS_PASS
BWET_PROXY_SEMANTICS_PASS
UI_VISIBILITY_PASS
SCHEDULE_INCLUSION_PASS
GATE_4_5_SELF_VALIDATION_PASS
GATE_4_5_SECOND_INDEPENDENT_REAUDIT_PASS
GIT_REPRODUCIBILITY_PASS
GATE_4_5_CLOSED_PASS
RELEASE_APPROVED
```

## Inventory

- KR_DRAM_PPI: 381 rows; 1995-01-01 to 2026-09-01; duplicates 0.
- KR_FLASH_MEMORY_PPI: 261 rows; 2005-01-01 to 2026-09-01; duplicates 0.
- BWET_VLCC_PROXY: 882 rows; 2023-05-03 to 2026-11-05; duplicates 0.

## Evidence

- Official ECOS item metadata was read back before collection; both code contracts are VERIFIED.
- ECOS monthly observations remain monthly and were not expanded with daily LOCF.
- ECOS does not expose historical publication/revision timestamps through the item/search response used here. `source_updated_at` is therefore NA; `available_at` is explicitly conservative collection availability.
- PPI lead/lag output is explicitly reference-month exploratory analysis, not a point-in-time release-lag trading signal.
- BWET keeps Close and Adjusted Close and is explicitly labeled as an ETF proxy, not a VLCC spot or Baltic official index.
- WTI regime relative performance is BWET daily return minus XLE daily return within WTI up/down regimes.
- Browser checks: 11/11; Physical Indicators visible render 0.846s.
- Integrated performance: cold max 0.077s; warm p95 0.241s; filter p95 0.083s; startup max 3.163s; RSS 413.4MB.
- The Shiny session reads local FST files only; collection remains in scheduled batch scripts.
- Public shinyapps.io bundle `12787559` passed 9/9 direct smoke checks.
- Release commit `e001a21a15b51e81f84ffd809d84c90512e51503` matched `origin/main` during the independent re-audit.

## Files

- `ecos_physical_metadata_snapshot.csv`
- `physical_series_collection_report.csv`
- `available_at_validation.csv`
- `ui_browser_checks.csv`
- `gate4_5_validation_checks.csv`
- `PUBLIC_URL_SMOKE.md`
- `INDEPENDENT_REAUDIT.md`
