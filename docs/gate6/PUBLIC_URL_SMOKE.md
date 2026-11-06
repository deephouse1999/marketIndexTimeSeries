# Public URL Smoke Test

Tested: 2026-11-06 KST

URL: <https://deephouse1999.shinyapps.io/market_timeseries/>

Deployment bundle: `12787377`

**Result: PASS**

- The application loaded with title `Market Time Series` and all five main tabs.
- Sector Rotation rendered 11 sectors with latest observation `2026-11-05`.
- Series Explorer rendered 101 default-visible entries; current dates include FRED through 2026-11-05 and Korean Yahoo observations through 2026-11-06.
- Korea Rates rendered the eight-tenor curve controls, bp change table, funding/credit spread table, and status `curve as of 2026-11-05`.
- SOX rendered the official 30-component disclosure, SOXQ proxy disclosure, derived date 2026-11-06, and latest complete member aggregate 30/30.
- The remediation release exposes a visible Breadth bar, eight Value Chain snapshot bars, KOSPI-only Korea Link relations, constituent descriptions, and finite line traces in all three Semiconductor & Korea Link charts.
- Series Explorer Raw Source Level now renders varying source observations directly, and Monthly Return Distribution renders without a DT server error.
- No startup error or external API prompt was visible.
