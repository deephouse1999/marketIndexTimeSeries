# Gate 4 SOX Constituents — Claude 독립감사 보고서

- 감사일: 2026-11-06 (KST)
- 감사 대상 루트: `C:\app\econ_ts\marketIndexTimeSeries`
- 감사 성격: READ-ONLY 독립감사. 코드, CSV, FST, 문서와 Git 상태는 수정하지 않았고 데이터도 재수집·재생성하지 않았습니다. 이 보고서 파일 하나만 새로 작성했습니다.
- 수행 방식: 감사 대상 파일을 디바이스 브리지로 읽기 전용 스냅샷(staged copy)으로 가져왔습니다. 이후 격리된 감사 환경에서 독립 R 4.3.3, data.table, fst(GitHub 소스 빌드)로 readback·재계산을 했고 Python으로 SHA256과 Git index를 파싱했습니다. 프로젝트 스크립트(`validate_gate4.R` 등)는 **실행하지 않았습니다**. 모든 재계산은 감사자가 독립적으로 작성한 코드로 했습니다.
- 감사 한계: 사용자 PC에서 셸(`git status`, `Rscript`, 브라우저)을 실행할 수 없었습니다. 따라서 앱 실기동, 성능 재측정, 브라우저 렌더링은 재현하지 않고 제출된 증거와 정적 코드 검토로 판정했습니다. Git 상태는 `.git/index`를 직접 파싱해 판정했습니다.

---

## 1. Findings (심각도 순)

### F-01 [HIGH] 성능·UI·스크린샷 증거가 감사 대상 최종 빌드보다 먼저 생성됨: 증거와 산출물의 연결이 끊김
- 근거(파일 mtime, KST 2026-11-05):

| 시각 | 이벤트 |
|---|---|
| 18:23:03 | `original_ts_sox_components.fst` 생성 |
| 18:26:06 | `app.R` 수정 |
| 18:27:21–18:27:55 | `performance_cold_1..5.csv` |
| 18:27:52 | `performance_filter_runs.csv` |
| 18:28:00 | `performance_warm_runs.csv` |
| **18:34:27** | **`apps/timeseries/sox_constituents_server.R` 수정** (성능 측정 이후) |
| 18:34:37 | `ui_smoke_metrics.csv`, `ui_regression_retest.md` |
| **18:35:55** | **`sox_constituents.csv` / `official_membership_snapshot.csv` 재작성** |
| 18:37:03–18:37:19 | `sox_*.png` 스크린샷 |
| **18:38:27** | **`scripts/build_sox_gate4_summary.R` 수정** |
| **18:38:36** | **`derived_sox_daily_summary.fst` 재빌드** |
| 18:39:31 | `collect_sox_gate4.R`, `validate_gate4.R` 수정 |
| 18:39:41–45 | `performance_cold_runs.csv`(재집계), `gate4_validation.csv`, `file_integrity_inventory.csv` |

- cold 5회·warm 10회·filter 10회 측정은 모두 최종 서버 코드, 최종 구성종목 CSV, 최종 derived FST보다 **이전**에 수행되었습니다. UI smoke와 스크린샷도 최종 derived FST 재빌드 이전입니다. `validate_gate4.R`은 과거 측정 CSV를 다시 읽어 PASS로 재집계만 했습니다(`scripts/validate_gate4.R` 6–10행).
- 영향: 현재 감사 대상 빌드에 대한 성능·렌더링·lazy-loading 증거가 존재하지 않습니다.
- 판정: 필수검증 7, 8 → **NOT_PROVEN**

### F-02 [HIGH] 카탈로그 등록(collect_flag=TRUE)이 기존 수집기와 충돌: "Update Market Data" 1회로 Gate 4 수집 파이프라인이 확정적으로 실패
- 근거:
  - `scripts/register_sox_gate4.R` 26행은 신규 28개 구성종목을 `collect_flag="TRUE", active="TRUE"`, `source="YAHOO"`로 `series_catalog.csv`에 등록합니다(137행 이후 28행, `gate4=TRUE`). SOXQ와 005930.KS는 Gate 1부터 `collect_flag=TRUE`입니다(`docs/gate1/pending_collection_13.csv` 12–13행).
  - `apps/timeseries/dataExtract_fredyahoo.R` 350행 `update_series()`는 `active & collect_flag`인 YAHOO 행 전체를 `original_ts_yahoo.fst`에 수집·기록합니다(438행). 앱의 `input$update_data` 버튼(`app.R` 427–439행)이 이 수집기를 호출합니다.
  - 버튼이 실행되면 30개 Gate 4 시리즈가 legacy Yahoo 저장소에도 들어갑니다. 다음 `collect_sox_gate4.R` 실행에서는 `collect_ids <- setdiff(required_ids, existing_ids)`(113행)가 빈 집합이 됩니다. 148행 `!setequal(unique(readback$series_id), collect_ids)`가 참이 되어 `SOX_COMPONENT_READBACK_FAILED`로 중단됩니다.
  - 동일 시리즈가 두 저장소에 이중 저장되고, legacy Yahoo 파일 SHA 기준선도 깨집니다.
- 영향: 일상적인 UI 조작 한 번으로 Gate 4 갱신 경로가 막힙니다. Gate 5(스케줄 수집)의 전제 조건과도 충돌합니다.
- 판정: 필수검증 9 → **FAIL**

### F-03 [MEDIUM] Korea Link가 legacy 000660.KS의 음수 Adjusted Close를 그대로 사용: -190.5% 수익률이 `ADJUSTED_CLOSE`로 게시됨
- 근거(독립 readback): `original_ts_yahoo.fst`의 000660.KS는 2000-01-04~2002-12-26 구간 778행의 `adjusted_value`가 음수입니다(예: 2000-01-04 close 540,750 / adj -228,824.2). 2002-12-27 수익률은 **-1.90476**입니다.
- `derived_sox_daily_summary.fst`의 `benchmark_return / 000660.KS`가 이 값을 `quality_flag=ADJUSTED_CLOSE`로 게시합니다. 2002-12-27 이후 최대 120영업일 동안 `us_next_korea` 상관계수(`*|000660.KS|*`)가 이상값에 오염됩니다.
- 원 데이터 결함은 Gate 4 이전부터 있었습니다. 다만 Gate 4 빌드(`build_sox_gate4_summary.R` 11–20행)는 가격 양수 여부나 극단 수익률을 점검하지 않았고, `validate_gate4.R` 30행의 adjusted 점검은 Gate 4 raw FST만 대상으로 합니다.
- 기본 화면(최근 5년)에는 보이지 않습니다. 사용자가 기간을 조정하거나 CSV를 다운로드하면 노출됩니다.

### F-04 [MEDIUM] "Close는 Gate 4 수익률에 사용하지 않는다" 정책과 코드가 불일치하며, 검증 범위에 공백이 있음
- 근거: `build_sox_gate4_summary.R` 14행은 `adjusted = ifelse(!is.na(adjusted_value), adjusted_value, close_value)`로 Close fallback을 사용합니다. `SOX_MEMBERSHIP_AND_WEIGHT_POLICY.md`의 "Close … is not used by Gate 4 return and contribution calculations"와 다릅니다.
- legacy NVDA(비중 1위 12.23%)는 6,989행 중 6,859행의 adjusted가 NA이고, adjusted는 2026-04-30부터만 존재합니다.
- 현재 게시된 2026-11-04 행은 NVDA 11-03·11-04 모두 adjusted가 있어 **영향이 없음을 확인**했습니다. 그러나 effective date 이전 이력을 쓰는 기능이 생기거나 adjusted가 누락되면 Close/Adj가 혼합된 수익률이 무검출로 생성됩니다.
- `validate_gate4.R` 30행 `adjusted_close_policy`는 legacy 경유 시리즈(NVDA, MU, ^SOX, SOXX, XSD, 000660.KS)를 검사하지 않습니다.

### F-05 [MEDIUM] US→KR 정렬이 같은 KR 거래일에 매핑되는 US 종가 중 가장 오래된 것을 남김(최신 US 수익률 폐기)
- 근거: `build_sox_gate4_summary.R` 63–68행은 `findInterval()+1`로 매핑한 뒤 `distinct(date, .keep_all=TRUE)`로 **첫 행(가장 이른 US 날짜)**을 유지합니다.
- 독립 재현(^SOX→005930.KS) 결과, 한 KR 거래일에 2개 이상 US 종가가 매핑되는 경우가 194건 있었고 각 경우 직전(최신) US 수익률이 버려졌습니다.
- lookahead는 아닙니다(`kr_date <= us_date` 위반 0건). 하지만 `LOOKAHEAD_POLICY.md`의 "US close to the first later Korean trading observation" 의도와 반대 방향의 stale pairing이며, 상관계수가 체계적으로 약화될 수 있습니다.

### F-06 [MEDIUM] 기존 4개 화면 회귀시험 증거가 없음
- `scripts/test_sox_gate4_ui.R`은 SOX 출력 8개만 검사합니다. Sector Rotation, Series Explorer, Korea Rates & Funding, Semiconductor & Korea Link는 Gate 4에서 재시험되지 않았습니다. Gate 3 회귀시험(`docs/gate3/ui_smoke_test.md`)은 legacy 출력까지 포함했습니다.
- Gate 4는 `app.R`(18:26 수정)와 `series_catalog.csv`(+28행)를 변경했습니다. `series_catalog.csv` 변경은 Series Explorer 필터·benchmark 선택지(`show_inactive`)에 영향을 줍니다.
- 정적 검토 결과 Gate 4 코드가 기존 서버 함수를 직접 바꾼 흔적은 없습니다(`sector_server.R`, `link_server.R`, `korea_rates_server.R` mtime은 Gate 4 이전). 회귀 위험 자체는 낮지만 증거가 없습니다.
- 판정: 필수검증 9 → **NOT_PROVEN**(F-02와 합쳐 최종 FAIL)

### F-07 [MEDIUM] 성능 측정 방법이 "visible render"를 측정하지 못하고, warm 측정은 사실상 무의미
- `scripts/gate4_perf_worker.R`은 `shiny::testServer`로 서버측 값만 생성합니다. 브라우저 렌더링, plotly JS, `suspendWhenHidden` 동작은 측정되지 않습니다. Gate 3은 "browser evidence"를 기준으로 삼았습니다(`docs/MARKET_TIMESERIES_WBS.md` 9행).
- warm 10회(3.3–5.6 ms)는 `sox_subtab`만 바꾸고 이미 계산된 output 값을 다시 읽는 구조입니다(40행). 재렌더링 시간이 아닙니다. 또 4개 출력만 반복하며 Korea Link, Constituents, Data Quality는 제외됩니다.
- `filter_1..10`(18:27:52, startup 1.338s)은 `cold_5`(18:27:53 시작) 프로세스와 시간이 겹칩니다. 독립 실행 조건이 문서화되지 않았습니다.
- 수치 자체는 계약을 충족합니다(cold max 1.839s ≤ 2s, warm p95 0.005s, filter p95 0.061s, 감사자 재계산 일치). 하지만 F-01과 이 항목 때문에 기준 충족은 **NOT_PROVEN**입니다.

### F-08 [MEDIUM] 산출물 재현성(provenance): 제출 스크립트로는 일부 증거 파일을 만들 수 없음
- `docs/gate4/collection_summary.csv`(18:39:53)의 열 순서는 `…duplicate_keys,first_date,last_date,membership_effective_from,historical_membership_before_effective_from,collection_mode`입니다. 현행 `collect_sox_gate4.R` 161–171행은 `…duplicate_keys,collection_mode,first_date,…` 순서로 기록하므로, 이 파일은 현행 스크립트 출력이 아닙니다. raw FST는 18:23 이후 갱신되지 않았으므로 수집기가 재실행되지도 않았습니다.
- `sox_constituents.csv`는 18:35:55에 재작성되었습니다. 그런데 수집기가 같은 실행에서 함께 쓰는 `weight_source_evidence.csv`는 18:22:38 그대로입니다. 즉 구성종목 CSV는 제출된 수집기가 아닌 다른 경로로 갱신되었습니다(`profile_source` 열 추가로 보임).
- 내용 대조 결과 비중 값은 일치합니다(max diff 8.7e-18). 다만 수집기는 `profile_updated_at`을 `profile_source` 앞에 쓰는데, 현 CSV는 `…profile_updated_at, profile_source` 순서로 저장되어 있습니다.
- `.last_good` 파일은 현재 파일과 바이트가 동일하고 mtime도 ms 단위까지 동일합니다(raw 18:23:03.197, derived 18:38:36.747). derived 빌드 스크립트(85–87행)는 이전 target을 rename해 last_good으로 만드는데, 이 경우 이전 mtime이 남아야 합니다. 현재 상태는 스크립트 동작과 맞지 않으며, 별도 rollback 시점도 제공하지 않습니다.

### F-09 [LOW] 공식 비중 오인 가능성이 남은 열 이름
- Constituents 표(`sox_constituents_server.R` 127–129행)와 `contribution_samples.csv`, `sox_constituents.csv`는 SOXQ 프록시 비중을 `index_weight` 열 이름으로 노출합니다. 표시값은 %(5.049 등)인데 단위 표기가 없습니다(`docs/gate4/sox_constituents.png`).
- 상단 배너("Weights are SOXQ proxy weights, not official SOX index weights"), `weight_source=SOXQ_PROXY`, `quality_flag=PROXY_WEIGHT_NOT_OFFICIAL_INDEX_WEIGHT`가 같은 화면에 있어 오인 위험은 낮습니다.
- 권고: `proxy_weight_pct` 등으로 명칭 정정.

### F-10 [LOW] 수치 보고 불일치
- 세션 RSS가 `GATE4_VALIDATION_REPORT.md`에서는 **399.2 MB**, `GATE4_PERFORMANCE_REPORT.md`, `ui_smoke_metrics.csv`, `gate4_validation.csv`에서는 **387.1 MB**입니다.
- App startup은 `ui_regression_retest.md` 1.649s, 보고서 max 1.387s입니다. 보고서 max는 perf 실행 기준이고 UI smoke 실행을 제외해 산출되었습니다.

### F-11 [LOW] UI 표시 정확성
- Overview 차트는 각 시리즈를 **자기 첫 관측일** 기준 100으로 지수화해 한 축에 그립니다(^SOX 1994, SOXQ 2021; `sox_constituents_server.R` 67–73행). 누적성과를 오도하는 비교가 됩니다.
- 상태 밴드의 "Data 2026-11-05"는 005930.KS·Korea link의 최신일입니다. 구성종목 집계는 2026-11-04까지이고, 000660.KS는 2026-11-03에서 끝나지만 별도 stale 표시가 없습니다.
- 구성종목 기여도 합계(-0.03128412, 비정규화)와 `proxy_weighted_return`(-0.03128893, Σw=0.99984623로 정규화)이 4.8e-6 차이 납니다. 기여도 막대의 합이 표시된 프록시 수익률과 정확히 일치하지 않으므로 문서화가 필요합니다.

### F-12 [LOW] lazy-loading 서술과 코드의 미세 불일치
- `sox_constituents_server.R` 111–115행의 `observe()`는 탭 진입과 무관하게 세션 시작 시 `ensure_latest()`를 호출해 6 KB latest FST를 읽습니다. `test_sox_gate4_ui.R` 14행의 "탭 진입 전 latest_store NULL" 단언은 testServer가 초기 flush를 하지 않아 통과한 것으로 보입니다.
- 4.1 MB historical store의 lazy-load는 코드상 정상입니다(`ensure_full()`은 SOX 출력과 subtab observer에서만 호출).
- 첫 렌더 때 reactiveVal set이 자기 의존성을 무효화해 렌더가 1회 반복될 수 있습니다(31–38행).

### F-13 [INFO] 범위·문서
- WBS의 Gate 4 범위는 "SOX constituent **history**, collection, value chain, and contribution analysis"입니다. 반면 결과물의 breadth, contribution, value-chain 집계는 **단 1일(2026-11-04)**입니다. lookahead 금지 정책상 정당하지만, "이력" 산출물로 수용할지는 오너가 결정해야 합니다.
- `docs/MARKET_TIMESERIES_WBS.md`(10행 "APPROVED TO START")와 `MARKET_TIMESERIES_INTEGRITY.md`에는 Gate 4가 반영되지 않았습니다.
- `series_catalog.csv`의 SOXQ, 005930.KS 외 21개 행에 `display_name_ko` 문자 깨짐이 있습니다(예: 005930.KS `l<l1l l`). Gate 1 이전부터의 기존 결함이며 Gate 4 범위 밖입니다.

---

## 2. 필수 독립검증 결과

| # | 항목 | 판정 | 재현 근거 |
|---|---|---|---|
| 1 | SOX 공식 구성종목 30개, 중복 없음 | **PASS** | `sox_constituents.csv` readback: 30행, unique ticker 30, `membership_source=NASDAQ_OFFICIAL` 30/30, `membership_as_of=effective_from=2026-11-04`, `effective_to` 전부 NA. `official_membership_snapshot.csv`와 완전 동일. 단, Nasdaq 원응답 자체는 증거로 보존되지 않아 "공식성"은 수집 코드(`collect_sox_gate4.R` 20–32행)와 URL로만 확인 가능 |
| 2 | 모든 비중 SOXQ_PROXY, 공식 비중 오인 문구 없음 | **PASS (Low F-09)** | `weight_source=SOXQ_PROXY` 30/30, `quality_flag=PROXY_WEIGHT_NOT_OFFICIAL_INDEX_WEIGHT` 30/30, Σw=0.99984623, `weight_as_of=2026-11-03 ≤ effective_from`. UI 문구(배너·상태밴드·차트 제목 "SOXQ proxy contribution"·축 "Proxy-weighted return")에 "official weight" 표현 없음. 열 이름 `index_weight`만 개선 필요 |
| 3 | 2026-11-04 이전 소급 집계 없음 | **PASS** | derived에서 `daily_summary`·`constituent_contribution`·`value_chain_return`의 2026-11-04 미만 행 **0**. 세 그룹 모두 날짜는 2026-11-04 하루뿐(11 / 30 / 8행). `benchmark_return`(1994~)과 `us_next_korea`(2000~)는 지수·종목 단위로 membership과 무관 |
| 4 | 수익률·기여도·breadth·top5/10·residual 표본 재계산 | **PASS** | 30종목 전체를 raw 저장소에서 adjusted만으로 독립 재계산(전일 전부 2026-11-03 확인). 수익률·기여도 max abs diff **0**. advancing 4 / declining 26 / unchanged 0 / breadth 13.333%, EW -0.0364189, proxy -0.0312889, top5 0.400576, top10 0.6085004(동률 비중 0건이라 `unique()` 사용 무해), ^SOX -0.0312956, residual -6.69e-6, value-chain 8개 전부 diff 0. Korea link 표본(^SOX→005930.KS 20D @2026-11-05 = 0.3167775, 120D @2012-02-28 = 0.4476923) 일치. 방법론 이슈는 F-03, F-05 |
| 5 | raw·derived 중복키 0, 행·시리즈·기간 | **PASS** | raw: 207,876행, 30 시리즈, (source, series_id, date) 중복 0, adjusted NA 0, 1972-06-01~2026-11-05. derived: 147,548행, 79 metric, (date, metric_group, metric_id) 중복 0, 1994-05-04~2026-11-05. `derived_sox_latest.fst` 79행이 derived의 metric별 최신값과 일치 |
| 6 | SHA256 재계산 | **PASS** | 감사자 sha256sum이 기존 값과 일치: FRED `67CBDA72…3884`, Yahoo `D9431E63…1972`, ECOS `6245DA33…47F5`(Gate 1/3 기준선과도 일치), raw 및 raw.last_good `46173B96…AFF4`, derived 및 derived.last_good `F50688B1…EBDE4`. 단, last_good provenance는 F-08 참조 |
| 7 | 7개 하위화면, lazy loading, 시작 시 외부 API 0 | **NOT_PROVEN** | 정적 검토: 7개 tabPanel 확인, 앱·서버 소스에 http/getSymbols/GET/POST 없음, 수집기는 버튼 이벤트에서만 `sys.source` → 시작 시 API 0은 **정적으로 PASS**. 그러나 렌더·lazy 증거는 최종 빌드 이전(F-01)이고 testServer 기반(F-07). latest store는 세션 시작 시 로드(F-12). 스크린샷 7장은 렌더 사실을 보이지만 derived 재빌드 이전 |
| 8 | cold 5 / warm 10 / filter 10 기준 충족 | **NOT_PROVEN** | 기록 수치는 계약 충족(cold max 1.839s, warm p95 0.00503s, filter p95 0.06109s, startup max 1.387s; 감사자 재계산 일치). 그러나 최종 빌드 이전 측정(F-01), warm 측정 무의미, 브라우저 미측정(F-07) |
| 9 | 기존 4개 화면 회귀 위험 | **FAIL** | F-02(수집기 충돌, 확정적 실패 경로) + F-06(회귀시험 부재) |
| 10 | Git dirty 상태에서 사용자 변경과 Gate 4 범위 구분 | **PASS (방법 한정)** | 아래 3절 |

---

## 3. Git 작업트리 판정

`.git/index`를 직접 파싱해 blob SHA-1을 재계산했습니다(셸 `git status` 실행 불가).

- HEAD `bad97f3` "Add user manual"(reflog 2026-07-02). 추적 파일은 16개뿐입니다.
- HEAD 대비 MODIFIED: `README.md`, `apps/timeseries/app.R`, `apps/timeseries/dataExtract_fredyahoo.R`, `apps/timeseries/original_ts_fred.fst`, `apps/timeseries/original_ts_yahoo.fst`.
- Gate 1~4 산출물 전체(`docs/gate*`, `scripts/*gate*`, `series_catalog.csv`, `sox_*`, `*_sox_*`, ECOS·Korea rates 파일 등)는 **untracked**입니다. 따라서 Git만으로는 Gate 간 경계를 구분할 수 없습니다.
- mtime 기준 Gate 4 창(2026-11-05 18:22:16~18:40:18 KST)에서 변경된 파일은 다음과 같습니다.
  - `register_sox_gate4.R`
  - `collect_sox_gate4.R`
  - `build_sox_gate4_summary.R`
  - `validate_gate4.R`
  - `gate4_perf_worker.R`
  - `test_sox_gate4_ui.R`
  - `capture_sox_gate4_ui.R`
  - `run_gate4_app.R`
  - `app.R`
  - `sox_constituents_server.R`
  - `series_catalog.csv`
  - `sox_constituents.csv`
  - `sox_company_sources.csv`
  - SOX FST 4종과 last_good
  - `docs/gate4/*`
  - `README.md`, `CHANGELOG.md`, `VALIDATION_REPORT.md`
- legacy FRED, Yahoo, ECOS FST는 Gate 4 창 이전 mtime(06:37 / 07:07 / 14:19)이고 SHA가 기준선과 일치합니다. 따라서 이들의 HEAD 대비 변경은 **Gate 4 이전(사용자 또는 이전 Gate)** 변경입니다. 같은 논리로 `dataExtract_fredyahoo.R`(13:02) 수정도 Gate 4 범위가 아닙니다.
- Gate 4가 기존 추적 파일 중 변경한 것은 `app.R`(SOX 탭 추가, 42·340–343·478–484행)과 `README.md`입니다.
- 권고: Gate 단위 커밋이나 태그가 없어 감사 추적성이 약합니다. Gate 4 종결 전에 Gate 1~4 산출물을 커밋 단위로 분리하기를 권고합니다(오너 결정 사항).

---

## 4. 종결 전 보완 요구 (수정은 하지 않음)

1. F-02: Gate 4 시리즈의 legacy 수집기 편입을 차단하거나(collect_flag 분리, 전용 플래그 사용 등) 수집기 간 소유권 규칙을 정의하고, `collect_sox_gate4.R` 148행의 setequal 조건을 재설계해야 합니다.
2. F-01·F-07: **최종 빌드 고정 후** cold 5회, warm 10회, filter 10회를 브라우저(또는 Gate 3과 동등한 방법)로 재측정해야 합니다. warm은 실제 재렌더링을 측정해야 하며, 7개 하위화면 전부를 포함해야 합니다.
3. F-06: Sector Rotation, Series Explorer, Korea Rates, Semiconductor & Korea Link 회귀 smoke를 재실행하고 증거를 남겨야 합니다.
4. F-03·F-04: 가격 ≤ 0 및 극단 수익률 가드를 넣고, legacy 경유 시리즈에도 adjusted 정책 검증을 적용하거나 Close fallback 사용을 정책에 명시해야 합니다.
5. F-05: 매핑 시 최신 US 종가를 유지하거나 누적하도록 정의하고 정책에 명문화해야 합니다.
6. F-08: 제출 스크립트만으로 `sox_constituents.csv`, `collection_summary.csv`, last_good가 재생성되는지 확인하고 Nasdaq·Invesco 원응답 스냅샷을 보존해야 합니다.
7. F-09~F-13은 문서·라벨 정정 수준입니다.

---

## 5. 최종 판정

```text
GATE_4_INDEPENDENT_AUDIT_FAIL
GATE_4_REMEDIATION_REQUIRED
NO_GATE_5_START
```

사유: 데이터 무결성 항목(1–6)은 독립 재계산으로 모두 PASS했고 계산 정확성도 확인되었습니다. 그러나 다음 세 가지로 Gate 종결 요건을 충족하지 못합니다.

- 기존 수집기와의 충돌로 Gate 4 갱신 경로가 확정적으로 실패합니다(F-02, HIGH).
- 성능·UI 증거가 감사 대상 최종 빌드를 증명하지 못합니다(F-01, HIGH).
- 기존 화면 회귀 증거가 없습니다(F-06).
