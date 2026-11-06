# Gate 3 UI Regression Retest

**Result: PASS**

Tested: 2026-11-05 17:46:27 KST

## Lazy Rendering

- The 141-row latest index loaded on first Korea Rates entry.
- The 153,329-row historical derived store remained unloaded on the initial Yield Curve and Rate Changes views.
- The historical store loaded only when a history-dependent subtab was opened.
- Hidden Plotly and DT outputs use `suspendWhenHidden = TRUE` and subtab guards.

## Functional Coverage

- Korea Rates retained outputs: kr_status_text, kr_build_text, kr_curve_meta, kr_curve_plot, kr_curve_table, kr_change_meta, kr_change_table, kr_spread_meta, kr_spread_plot, kr_quality_table, kr_special_status, kr_us_meta, kr_us_plot, kr_fx_meta, kr_fx_plot, kr_roll_meta, kr_rolling_plot, kr_alignment_table.
- Legacy regression outputs: sector_beating, sector_latest, sector_excess_plot, sector_table.
- Yield curve, bp changes, spreads, Korea-US alignment, FX separation, quality state, and disabled special-bond status rendered successfully.

## Runtime

- App source/startup evaluation: 1.751 seconds (gate <= 5 seconds).
- Session RSS after all Korea Rates and legacy outputs: 470.7 MB (gate <= 500 MB).
- The original pre-remediation all-output render result of 4.874 seconds remains preserved in the performance remediation report.
