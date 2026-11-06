# Lookahead Policy

- Membership applies from the verified `effective_from` date and never earlier.
- A daily return may use only the latest weight snapshot with `weight_as_of < return date`; same-day EOD weights are prohibited.
- Weight snapshots are append-only by `(ticker, weight_as_of)` in `sox_weight_history.csv`.
- A member aggregate is published only when all 30 active members have valid returns and full proxy-weight coverage.
- Current membership is not backfilled into historical breadth or contribution.
- US-to-Korea analysis maps a US close to the first later Korean trading observation.
- Missing historical membership is reported as `NOT_AVAILABLE`, not estimated.
- Similar securities, successor tickers, and delisted names are not substituted without a documented source record.
