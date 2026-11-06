# Gate 4 Independent Audit Handoff

## Required audit posture

Run a separate read-only audit. Do not recollect data, modify FST files, or repair findings during the audit.

## Minimum checks

1. Re-read `sox_constituents.csv` and independently confirm 30 unique official members.
2. Confirm every weight is labeled `SOXQ_PROXY` and no UI copy calls it an official SOX weight.
3. Confirm no constituent aggregate exists before 2026-11-04.
4. Confirm collector ownership: legacy Yahoo owns NVDA/MU only and Gate 4 owns the other 30 required series.
5. Recompute sampled positive Adjusted Close returns, normalized weighted contributions, breadth, top-5/top-10 concentration, and residual.
6. Confirm non-positive SK Hynix prices and extreme returns are absent from published metrics, and latest-US-close alignment is used.
7. Confirm raw and derived duplicate keys are zero.
8. Confirm all seven subviews and the four legacy screens render and no app-start API call occurs.
9. Recompute all seven SHA256 values in `file_integrity_inventory.csv` and inspect target/last-good provenance.
10. Review the final-build five cold, ten warm, and ten filter browser records and the retained pre-remediation failure evidence.
11. Confirm every published contribution uses `weight_as_of < date` and inspect the reconstructed 2026-11-03 snapshot evidence.
12. Confirm the 2026-11-05 28/30 date is excluded from all member aggregates and the Overview has identical bounds with first value 100 for all four series.

## Current implementation status

```text
GATE_4_SECOND_INDEPENDENT_REAUDIT_PASS
GATE_4_CLOSED_PASS
GATE_5_APPROVED_TO_START
```

Completed report: `CLAUDE_SECOND_INDEPENDENT_REAUDIT_REPORT.md`.
