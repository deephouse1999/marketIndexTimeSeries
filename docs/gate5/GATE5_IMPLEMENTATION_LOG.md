# Gate 5 Implementation Log

## Status

```text
GATE_5_CLOSED_PASS
GATE_6_APPROVED_TO_START
```

Gate 5 started on 2026-11-06 after the independent Gate 4 second re-audit closed with PASS.

## Implemented foundation

- New York and Seoul schedule guards use named IANA time zones.
- New York DST is evaluated at runtime rather than encoded as fixed calendar dates.
- US and KR batch state contracts are written atomically under `batch_state/`.
- Collection and derived builds run in an isolated staging copy.
- Operating artifacts are published only after staged FST readback and duplicate-key validation.
- A transaction copy is retained and prior FST files become `.last_good` after publication.
- Missing all critical session markers becomes an explicit market-holiday NOOP.
- A partial critical set is a hard validation failure and cannot publish.

## Closure evidence

- Deterministic DST, standard-time, weekend, and schedule-window tests passed.
- Injected publication failure restored every previously published file.
- Network-enabled US and KR close batches passed with zero missing critical series.
- ECOS unposted observations were recorded as `PENDING_SOURCE` without false batch failure.
- Three Windows scheduled tasks were registered and independently read back.
- The first live SOX weight-history update preserved every prior key.

## Remediation finding

The first live publication exposed a legacy-key regression: FRED normalization used
`(series_id, date)` instead of the contracted `(source, series_id, date)` key. This
collapsed legacy `source=NA` rows against official `source=FRED` rows. Gate 5 was not
closed. The preserved US transaction backup with SHA-256
`67CBDA72DEB4ED07A559584711F8AB71F83D1C578CC9F719774438F96DE53884` is the rollback
source. The collector key was corrected to `(source, series_id, date)`, the baseline
was restored, and both live batches were rerun. Final FRED has 503,123 rows, including
all 246,950 legacy `source=NA` rows, with zero contracted duplicate keys.

## Operating condition

The registered Windows tasks use the current Windows user's interactive logon token.
The host must remain logged in. The DST and standard-time US tasks both exist; the
runtime New York time guard permits only the correct 18:05 ET invocation.
