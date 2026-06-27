# marketIndexTimeSeries

Shiny apps for market time-series monitoring and U.S. economic dashboard views.

## Apps

- Dashboard: `apps/dashboard/app.R`
- Timeseries: `apps/timeseries/app.R`

The dashboard is currently deployed at:

<https://deephouse1999.shinyapps.io/us_econ_dashboard/>

The timeseries app is currently deployed at:

<https://deephouse1999.shinyapps.io/market_timeseries/>

## Run locally

Dashboard:

```r
shiny::runApp("apps/dashboard")
```

Timeseries:

```r
shiny::runApp("apps/timeseries")
```

## Data

Dashboard data files are bundled in `apps/dashboard` as `.rda` files.
Timeseries data files are bundled in `apps/timeseries` as `.fst` files.

To refresh the FRED/Yahoo timeseries data:

```r
source("apps/timeseries/dataExtract_fredyahoo.R")
```

To redeploy the dashboard to shinyapps.io from this repo:

```r
source("scripts/deploy_bl_dashboard.R")
```
