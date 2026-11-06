# Gate 5 Validation Report

Validated: 2026-11-06 KST

## Decision

```text
GATE_5_CLOSED_PASS
GATE_6_APPROVED_TO_START
```

All 30 final checks passed. Gate 6 was not started by this validation.

## Scheduled batches

| Batch | Schedule | Final live result |
|---|---|---|
| US close | 18:05 America/New_York; 07:05 KST during DST, 08:05 KST during standard time | 154 configured, 115 updated, 22 no-new-data, 17 pending-source, 0 missing critical |
| KR close | 16:05 Asia/Seoul, Monday-Friday | 22 configured, 1 updated, 4 no-new-data, 17 pending-source, 0 missing critical |

The two US Windows tasks are both registered Tuesday-Saturday. The runtime New York
time guard allows only the invocation corresponding to 18:05 ET. The KR task is
registered Monday-Friday. All three tasks were read back as enabled and ready.

## Publication controls

- Collectors and derived builders run in an isolated staging copy.
- FST readback and duplicate-key checks complete before publication.
- A partial critical set fails the batch; a fully absent critical set is a holiday NOOP.
- Publication keeps transaction backups and writes prior FST files as `.last_good`.
- An injected failure after the first file publication restored both test files.
- Batch state JSON is atomically written with all required contract fields.

## Remediation retained as evidence

The first US publication exposed an invalid legacy normalization key. The collector
collapsed FRED rows with `source=NA` against rows with `source=FRED` because it used
only `(series_id, date)`. Gate 5 was not closed at that point. The preserved transaction
backup was restored at the Gate 4 SHA-256 baseline:

```text
67CBDA72DEB4ED07A559584711F8AB71F83D1C578CC9F719774438F96DE53884
```

Normalization now uses `(source, series_id, date)`. Both live batches were rerun.
Final FRED contains 503,123 rows across 48 series, including all 246,950 legacy
`source=NA` rows, with zero contracted duplicate keys.

## Final source inventory

| Store | Rows | Series | Duplicate keys | SHA-256 |
|---|---:|---:|---:|---|
| FRED | 503,123 | 48 | 0 | `5518D3E5C9439FA420D74615943E1CDA37317AD7C00F4A04D46CC42DCE45E2D7` |
| Yahoo | 473,230 | 65 | 0 | `F8B3D16F13E32D1703CEC3ABAFCEE11B2B89F58BD2658F20B35690CB342A92AF` |
| ECOS | 125,645 | 18 | 0 | `EC006E153880F3A741DF9491ADED62D931E1CCAE8CD6DEA8A91EF3F7189CEE59` |
| SOX components | 207,906 | 30 | 0 | `AEEE8D9D1361433478683DB96FA2F0316176C13D8BE80A5913C1C6519853A7FA` |

SOX weight history is append-only: zero keys from the pre-batch transaction copy are
missing in the final operating file.

## Evidence

- `gate5_schedule_and_rollback_tests.csv`
- `gate5_validation_checks.csv`
- `scheduled_tasks_readback.txt`
- `holiday_test_state/us_close_latest.json`
- `holiday_test_state/kr_close_latest.json`
- `batch_state/us_close_latest.json`
- `batch_state/kr_close_latest.json`

## Operating condition

The scheduled tasks use the current Windows user's interactive token, so the host must
remain logged in. This constraint is visible in the scheduler readback evidence and is
not hidden by the PASS decision.
