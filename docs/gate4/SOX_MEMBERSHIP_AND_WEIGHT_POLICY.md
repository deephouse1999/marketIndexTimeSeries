# SOX Membership and Weight Policy

## Membership

The current membership snapshot is read from Nasdaq's official SOX index endpoint. A row is active only when its observation date is within `[effective_from, effective_to]`. The first verified snapshot has `effective_from = 2026-11-04`; earlier membership is unknown.

Current members' full Yahoo price histories are retained for research, but those histories do not establish index membership. No current member is included in historical breadth, contribution, or value-chain aggregates before its effective date.

## Weights

The public Nasdaq response supplied membership but no official weights. The implementation therefore uses equity holdings from the official Invesco SOXQ endpoint and labels every weight:

```text
weight_source = SOXQ_PROXY
quality_flag = PROXY_WEIGHT_NOT_OFFICIAL_INDEX_WEIGHT
```

The proxy is suitable for an estimate, not official index replication. Residual return is reported as actual SOX return minus the SOXQ-proxy weighted component return.

Daily aggregation uses the latest snapshot strictly before the return date. The 2026-11-03 snapshot is transparently reconstructed from the preserved 2026-11-04 EOD snapshot by reversing each constituent's 2026-11-04 Adjusted Close return and renormalizing; it is labeled `RECONSTRUCTED_FROM_2026_11_04_EOD_PRICE_DRIFT`, not official. New official SOXQ EOD snapshots are appended and never overwrite prior dates.

Breadth, contribution, value-chain, and daily summary rows are published only when all 30 active members have valid daily returns and full weight coverage. Incomplete dates are retained in `member_date_completeness.csv` as quality evidence but are not published as normal aggregates.

## Return basis

Component, ETF, and Korea-link returns use Yahoo Adjusted Close. Close is stored for inspection but is not used by Gate 4 return and contribution calculations.
