# Gate 4 Data Dictionary

## `sox_constituents.csv`

One row per verified current SOX member. Key fields are `ticker`, membership effective dates and source, SOXQ proxy weight and date, value-chain taxonomy, Korea linkage, company profile source, and quality flag.

## `original_ts_sox_components.fst`

Yahoo daily observations for the 28 current members absent from the legacy Yahoo store plus SOXQ and Samsung Electronics. Key: `(source, series_id, date)`. Fields: `date`, `series_id`, `close_value`, `adjusted_value`, `volume`, `source`, `collected_at`.

NVDA and MU remain in `original_ts_yahoo.fst`; they are not duplicated here.

## `derived_sox_daily_summary.fst`

Long-format derived store keyed by `(date, metric_group, metric_id)`.

| `metric_group` | Meaning |
|---|---|
| `daily_summary` | breadth, equal/proxy return, concentration, SOX return, residual |
| `constituent_contribution` | proxy-weight contribution and member return |
| `value_chain_return` | proxy-weighted value-chain return |
| `benchmark_return` | adjusted return and level for SOX/SOXX/XSD/SOXQ/Korean names |
| `us_next_korea` | US close to next Korean trading-day rolling correlation |

`quality_flag` distinguishes proxy estimates, adjusted-close quality guards, insufficient history, and latest-US-close to next-Korea alignment. Non-positive adjusted prices and daily returns above 100% in absolute value are not published.

## First-view assets

- `derived_sox_latest.fst`: latest status and metric index.
- `derived_sox_overview.fst`: common-trading-date Adjusted Close indexes for the four semiconductor benchmarks, sampled at month-end with an exact 100 baseline.
- `derived_sox_overview.png`: build-time common-start index chart used by the Overview screen.
- `sox_weight_history.csv`: append-only proxy-weight snapshots. `snapshot_type` and `quality_flag` distinguish official SOXQ EOD observations from transparent reconstructed pre-EOD weights.
- `member_date_completeness.csv`: expected/available member counts and weight coverage; incomplete dates are excluded from member aggregates.

The constituent weight field is `proxy_weight_decimal`; it is an SOXQ proxy and never an official SOX index weight.
