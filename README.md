# marketIndexTimeSeries

시장 시계열과 미국 경제지표를 확인하기 위한 Shiny 앱 저장소입니다.

## 사용자 매뉴얼

### 1. 접속 방법

GitHub 저장소에 접속한 뒤 아래 링크를 클릭하면 됩니다.

- GitHub: <https://github.com/deephouse1999/marketIndexTimeSeries>
- Dashboard 앱: <https://deephouse1999.shinyapps.io/us_econ_dashboard/>
- Timeseries 앱: <https://deephouse1999.shinyapps.io/market_timeseries/>

### 2. 앱 구성

이 저장소에는 Shiny 앱이 2개 있습니다.

| 앱 | 위치 | 목적 |
| --- | --- | --- |
| Dashboard | `apps/dashboard/app.R` | Bloomberg 기반 미국 경제지표, 발표 일정, surprise, CPI/고용/물가 transmission 분석 확인 |
| Timeseries | `apps/timeseries/app.R` | Yahoo/FRED 기반 시장 시계열 조회, 비교 차트, 선택 데이터 다운로드 |

### 3. Dashboard 사용법

Dashboard 앱은 미국 경제지표를 한 화면에서 확인하기 위한 앱입니다.

주요 화면은 다음과 같습니다.

- `MoM Summary`: 주요 경제지표의 최근 변화와 surprise를 표 형태로 확인합니다.
- `Release Schedule`: 경제지표 발표 일정을 확인합니다. 기본적으로 당일 이후 일정이 중심이며, 필요 시 과거 발표도 볼 수 있습니다.
- `CPI Breakdown`: CPI 세부 구성요소와 기여도를 확인합니다.
- `Employment Breakdown`: 고용 관련 세부 지표를 확인합니다.
- `Shelter Lag Correlation`: 주거비 관련 지표와 후행 관계를 확인합니다.
- `Inflation Transmission`: PPI, CPI, 임금, 고용, 주거비 등이 Core PCE로 연결되는 lead-lag 관계를 확인합니다.

사용 흐름:

1. Dashboard 앱 링크를 엽니다.
2. 상단 탭에서 확인하려는 분석 화면을 선택합니다.
3. 표는 정렬, 페이지 이동, 검색을 이용해 필요한 지표를 찾습니다.
4. 차트는 hover로 날짜, 값, lag/correlation 정보를 확인합니다.
5. 발표 일정 화면에서는 future/past 구분을 이용해 앞으로 나올 지표와 지난 발표를 구분합니다.

### 4. Timeseries 사용법

Timeseries 앱은 시장지표와 경제 시계열을 선택해서 비교하는 앱입니다.

주요 기능은 다음과 같습니다.

- Yahoo/FRED 시계열 선택
- 선택한 시리즈의 가격 또는 지표 레벨 비교
- endpoint 기준 보정 차트로 값의 크기가 다른 시리즈를 한 그래프에서 비교
- 선택한 데이터를 CSV로 다운로드
- 앱 화면의 데이터 업데이트 버튼으로 최신 데이터를 즉시 반영
- `Semiconductor & Korea Link > Physical Indicators`에서 ECOS DRAM·Flash 국내 생산자물가지수와 월간 lead/lag 관계 확인
- `Series Explorer > Physical Indicators`에서 BWET 유조선 운임선물 ETF proxy 조회

DRAM·Flash 지표는 한국은행 생산자물가지수이며 글로벌 현물·계약가격이 아닙니다. BWET는 ETF 시장가격 proxy로서 VLCC 현물운임이나 Baltic 공식 운임지수가 아니며 선물 롤, 운용보수, 추적오차가 반영될 수 있습니다.

사용 흐름:

1. Timeseries 앱 링크를 엽니다.
2. 분석할 시리즈를 선택합니다.
3. 기간과 표시 방식을 조정합니다.
4. 일반 차트 또는 endpoint-scaled absolute level 차트로 비교합니다.
5. 필요한 경우 CSV 다운로드 버튼으로 선택 데이터를 저장합니다.
6. 최신 데이터가 필요하면 앱 안의 데이터 업데이트 버튼을 누릅니다.

### 5. 데이터 업데이트 주기

| 앱 | 업데이트 방식 | 주기 |
| --- | --- | --- |
| Dashboard | Bloomberg 원천 데이터 갱신 후 Shiny 앱 재배포 | 매주 월요일 저녁 |
| Timeseries | 정기 배치 및 앱 내부 데이터 업데이트 버튼 | KR 16:05 KST, US 18:05 New York 평일; 버튼 실행 시 즉시 |

Dashboard는 정해진 주기로 관리자가 데이터를 갱신하고 재배포합니다. Timeseries는 정기 배치로 Yahoo/FRED/ECOS 자료를 갱신하며, 사용자가 앱에서 업데이트 버튼을 누르면 Yahoo/FRED 자료를 즉시 갱신할 수도 있습니다.

## 개발자용 실행 방법

로컬에서 Dashboard 실행:

```r
shiny::runApp("apps/dashboard")
```

로컬에서 Timeseries 실행:

```r
shiny::runApp("apps/timeseries")
```

Timeseries 데이터 수동 갱신:

```r
source("apps/timeseries/dataExtract_fredyahoo.R")
```

Dashboard 재배포:

```r
source("scripts/deploy_bl_dashboard.R")
```


## Timeseries catalog and analysis

The Timeseries app includes these analysis tabs:

- Sector Rotation: 1W/1M/3M/6M/YTD returns, 1M excess versus SPY, monthly rank change, and 20/60/120-day volatility for all 11 US sectors.
- Series Explorer: filtered level/return charts, CSV download, return-based correlation, explicit benchmark beta, current drawdown, and maximum drawdown.
- Korea Rates & Funding: official ECOS curve, rate changes, funding/credit spreads, Korea-US comparisons, FX linkage, and rolling correlations.
- Semiconductor & Korea Link: SOXX/XSD/NVDA/MU/SKHY/EWY/KOSPI/SK hynix performance, signal spreads, next-Korean-session relationship, and rolling correlations.

Series are configured once in `apps/timeseries/series_catalog.csv`. Adding a Yahoo row with `active=TRUE` and `collect_flag=TRUE` triggers full-history collection on its first update and incremental collection afterward. `default_visible` controls the normal explorer list independently. Disabling collection or default display never deletes stored history.

The ECOS/SOX integrated work order completed Gates 1-6 on 2026-11-06. It now includes official ECOS history, Korea Rates, SOX constituent analysis, guarded US/KR scheduled collection, atomic publication, final regression/performance validation, and the public release. Final evidence is in `docs/gate6/GATE6_VALIDATION_REPORT.md`.

Return, correlation, beta, momentum, and volatility calculations use Adjusted Close with Close fallback. Absolute-level charts use Close. The app does not download at startup; use Update Yahoo Data explicitly.

Run an incremental Yahoo update:

```r
options(market_ts.skip_autorun = TRUE)
source("apps/timeseries/dataExtract_fredyahoo.R")
run_market_data_update(update_fred = FALSE, update_yahoo = TRUE)
```

Run a full Yahoo adjusted-history resync:

```r
run_market_data_update(update_fred = FALSE, update_yahoo = TRUE, yahoo_full_resync = TRUE)
```

## ECOS collector

ECOS collection is a standalone batch process. The Shiny app does not call ECOS during startup or a user session. Set `ECOS_API_KEY` in the operating environment; never place the key in code, CSV, logs, or deployment archives.

Refresh the official table/item/meta readback:

```powershell
Rscript scripts/ecos_gate2_readback.R
```

Validate and register the verified ECOS catalog rows:

```powershell
Rscript scripts/run_register_ecos_gate2.R
```

Run full-history collection on an empty ECOS store, or five-business-day overlap collection when history already exists:

```powershell
Rscript scripts/collect_ecos_gate2.R
```

Run the independent Gate 2 checks:

```powershell
Rscript scripts/validate_gate2.R
```

Gate 2 evidence is in `docs/gate2/GATE2_VALIDATION_REPORT.md`.

## Korea Rates & Funding

Gate 3 derives its analysis store from the existing ECOS and FRED FST files. The build is offline and non-destructive: source FST files are read-only, staging is validated before publication, and the Shiny tab lazy-loads only the derived FST. The app never calls ECOS or FRED APIs during startup or a user session.

Build the derived store:

```powershell
Rscript scripts/build_korea_rates_summary.R
Rscript scripts/build_market_ui_core.R
```

Run UI and integrity validation:

```powershell
Rscript scripts/test_korea_rates_ui.R
Rscript scripts/measure_gate3_performance.R
Rscript scripts/validate_gate3.R
```

The initial Korea Rates view reads `derived_korea_rates_latest.fst` and loads the full historical rate store only after a history-dependent subtab is opened. The prejoined and pretransformed `derived_series_explorer.fst` is read once per app session so Series Explorer tab transitions remain below the two-second contract without any external API call.

Gate 3 evidence is in `docs/gate3/GATE3_VALIDATION_REPORT.md`; performance evidence is in `docs/gate3/GATE3_PERFORMANCE_REMEDIATION.md`.
# SOX Constituents (Gate 4)

The Time Series app now includes a lazy-loaded `SOX Constituents` tab covering overview, breadth, contribution, value chain, Korea linkage, constituents, and data quality. Membership is an official Nasdaq snapshot; weights are clearly identified as an Invesco SOXQ proxy. Historical membership before 2026-11-04 is not inferred.

Gate 4 implementation and independent audit evidence is in [`docs/gate4/GATE4_VALIDATION_REPORT.md`](docs/gate4/GATE4_VALIDATION_REPORT.md).

## Scheduled collection and release

Gate 5 registered three guarded Windows tasks:

- `MARKET_TS_US_CLOSE_DST`: Tuesday-Saturday 07:05 KST.
- `MARKET_TS_US_CLOSE_STANDARD`: Tuesday-Saturday 08:05 KST.
- `MARKET_TS_KR_CLOSE`: Monday-Friday 16:05 KST.

The US runtime guard permits only 18:05 America/New_York, so exactly one US task runs across DST changes. Collection runs in staging, validates schema, duplicates, freshness, and critical series, builds derived stores, and then publishes with transaction rollback and `.last_good` preservation. Runtime state is written to `batch_state/us_close_latest.json` and `batch_state/kr_close_latest.json`.

Run a batch manually:

```powershell
powershell -File scripts/run_gate5_batch.ps1 -Batch us
powershell -File scripts/run_gate5_batch.ps1 -Batch kr
```

Deploy the validated public app:

```powershell
Rscript scripts/deploy_timeseries_gate6.R
```

The public release is <https://deephouse1999.shinyapps.io/market_timeseries/>. Local scheduled updates do not mutate the immutable shinyapps.io bundle; rerun the deployment command when a new public snapshot is required.
