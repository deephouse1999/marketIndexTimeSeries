# Gate 6 Validation Report

Validated: 2026-11-06 20:43:33 KST

**Result: PASS (21/21)**

## Final decision

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

## Evidence summary

- Browser functional: 28/28.
- Main-tab max: 1.999s.
- Cold max: 0.078s; warm p95: 0.291s; filter p95: 0.153s.
- Startup max: 3.145s; RSS: 434.6MB.
- Downloads: 3, 153352, 86716 rows.
- Public bundle: 12787377; URL: https://deephouse1999.shinyapps.io/market_timeseries/.

The initial FRED key-collapse finding remains documented in Gate 5 evidence. The baseline was restored before final collection, and this validation independently confirms no legacy-history loss.
