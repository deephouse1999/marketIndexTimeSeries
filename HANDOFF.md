# Market Timeseries Handoff

## Release

- Public app: <https://deephouse1999.shinyapps.io/market_timeseries/>
- shinyapps.io application: `market_timeseries`, account `deephouse1999`.
- Gate 6 deployment bundle: `12786763`.
- Final validation: `docs/gate6/GATE6_VALIDATION_REPORT.md`.

## Routine operation

Windows Task Scheduler runs:

- `MARKET_TS_US_CLOSE_DST` at 07:05 KST Tuesday-Saturday.
- `MARKET_TS_US_CLOSE_STANDARD` at 08:05 KST Tuesday-Saturday.
- `MARKET_TS_KR_CLOSE` at 16:05 KST Monday-Friday.

The US scripts enforce 18:05 America/New_York at runtime, including DST. The tasks use the current user's interactive logon token, so the Windows host must remain logged in. API keys are read from `FRED_API_KEY`/`FRED_API_KEY_1` and `ECOS_API_KEY`; keys must never be committed or added to deployment files.

Inspect runtime state:

```powershell
Get-Content batch_state/us_close_latest.json
Get-Content batch_state/kr_close_latest.json
schtasks /Query /TN MARKET_TS_US_CLOSE_DST /FO LIST /V
schtasks /Query /TN MARKET_TS_US_CLOSE_STANDARD /FO LIST /V
schtasks /Query /TN MARKET_TS_KR_CLOSE /FO LIST /V
```

Manual collection:

```powershell
powershell -File scripts/run_gate5_batch.ps1 -Batch us
powershell -File scripts/run_gate5_batch.ps1 -Batch kr
```

## Publication and recovery

Collectors run inside `batch_staging/<batch_id>`. Publication occurs only after FST readback and duplicate/critical-series validation. Previous files are retained in `batch_state/transactions/<batch_id>` and as `.last_good`. A failed or partial batch must not be labeled PASS or replace the operating set.

The public shinyapps.io app is an immutable deployment snapshot. Local scheduler runs update local FST files but do not automatically redeploy. Publish a new public snapshot with:

```powershell
Rscript scripts/deploy_timeseries_gate6.R
```

## Validation

```powershell
Rscript scripts/test_gate6_server.R
Rscript scripts/test_gate6_browser.R
powershell -File scripts/measure_gate6_browser_performance.ps1
Rscript scripts/validate_gate6.R
```

Current gates: browser function 28/28 PASS, integrated Gate 6 validation PASS, startup <=5s, tab/filter <=2s, and RSS <=500MB.

## Known source constraints

- Official historical SOX membership before 2026-11-04 is unavailable and is not inferred.
- SOX weights are disclosed SOXQ proxy weights, not official SOX index weights.
- `SPECIAL_AAA_03Y` remains inactive with `SOURCE_NOT_AVAILABLE`; no substitute series is used.
- ECOS unposted observations remain `PENDING_SOURCE`; no synthetic holiday values are generated.
