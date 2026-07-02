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
| Timeseries | 앱 내부 데이터 업데이트 버튼 실행 | 버튼을 누르는 즉시 |

Dashboard는 정해진 주기로 관리자가 데이터를 갱신하고 재배포합니다. Timeseries는 사용자가 앱에서 업데이트 버튼을 누르면 Yahoo/FRED 데이터를 기준으로 즉시 갱신됩니다.

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
