# Gate 4 Performance Report

Final build measured 2026-11-06 KST with `scripts/measure_gate4_browser_performance.ps1`.

| Test | p50 | p95 | max | Contract |
|---|---:|---:|---:|---:|
| Cold first visible render, 5 fresh R/browser processes | 0.059 s | 0.070 s | 0.070 s | max <= 2.0 s |
| Warm transition, 10 actual subview clicks | 0.132 s | 0.289 s | 0.299 s | p95 <= 2.0 s |
| Korea Link date filter, 10 actual changes | 0.073 s | 0.079 s | 0.082 s | p95 <= 2.0 s |

- App startup max: 3.155 seconds; contract <= 5 seconds.
- Session RSS after all outputs: 365.5 MB; contract <= 500 MB.
- Cold starts after the app is connected, initial Shiny work is idle, and the required first-view assets are ready; timing ends when the clicked tab is visible and idle.
- Overview uses a build-time PNG generated from the four benchmarks' shared trading dates, sampled at month-end after an exact common 100 baseline. This removes session-time chart construction.
- The full historical derived FST loads only for data-dependent subviews. Hidden Plotly and DT outputs retain `suspendWhenHidden=TRUE`.
- The original pre-remediation failures are retained in `performance_cold_runs_pre_remediation.csv`.
