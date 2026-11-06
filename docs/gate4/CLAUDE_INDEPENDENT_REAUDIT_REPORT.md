# Gate 4 SOX Constituents — Claude 독립 재감사 보고서

- 재감사일: 2026-11-06 (KST)
- 대상: `C:\app\econ_ts\marketIndexTimeSeries` 최종 보완본
- 성격: READ-ONLY. 코드·CSV·FST·기존 증거는 수정하지 않았습니다. 데이터 재수집·재생성도, Gate 5 관련 작업도 하지 않았습니다. 이 파일 하나만 새로 작성했습니다.
- 방법: 대상 파일을 디바이스 브리지로 읽기 전용 스냅샷으로 가져와, 격리된 감사 환경에서 감사자가 작성한 독립 R(data.table/fst) 코드로 readback·재계산했습니다. SHA256은 `sha256sum`으로 계산했습니다. 프로젝트 스크립트는 실행하지 않았습니다.
- 한계: 사용자 PC 셸이 없어 앱 실기동과 브라우저 재측정은 재현하지 못했습니다. 따라서 성능·렌더링 항목은 최종 빌드 이후 생성된 증거와 정적 코드 검토로 판정했습니다.
- 1차 감사 보고서(`CLAUDE_INDEPENDENT_AUDIT_REPORT.md`)는 감사자 원본과 바이트 동일합니다(`cmp` 일치). 변조되지 않았습니다.

---

## 1. 신규 Findings (심각도 순)

### R-01 [HIGH] 비중 lookahead: 2026-11-04 집계에 같은 날 장마감 후(11-04 EOD) SOXQ 비중이 사용됨 — FAIL
- **경위:** 보완 과정에서 `collect_sox_gate4.R`이 다시 실행되었습니다. `sox_constituents.csv` mtime은 2026-11-06 08:53:22, raw FST는 08:53:35입니다. 이때 Invesco 응답의 `effectiveDate`가 바뀌어 `weight_as_of`가 **2026-11-03 → 2026-11-04**로 갱신되었고, 30개 비중이 모두 변경되었습니다(Σw 0.99984623 → 0.99979655).
- **독립 검증:** 신규 비중을 1차 감사 시 확보한 11-03 비중과 비교했습니다.
  - `log(new/old)`와 `log(1+r_2026-11-04)`의 상관계수는 **0.99998**입니다. 회귀 기울기는 0.99987입니다.
  - 신규 비중과 "11-03 비중을 11-04 수익률로 drift시킨 값"의 평균 절대오차는 **1.9e-6**입니다. 실제 평균 변경폭은 7.4e-4입니다.
  - 즉 신규 비중은 11-04 종가가 이미 반영된 기말 비중입니다.
- **영향:**
  - 11-04의 `proxy_weighted_return`, `constituent_contribution`, `value_chain_return`, `residual_return`이 같은 날 가격이 반영된 비중으로 계산되었습니다.
  - residual이 **-6.69e-6(-0.07bp) → -9.35e-4(-9.4bp)**로 약 140배 악화되었습니다. 기여도 순위도 왜곡됩니다. 예: QCOM 비중 +0.37%p, MU 비중 -0.31%p로, 당일 상승 종목은 과대·하락 종목은 과소 반영됩니다.
- **통제 공백:**
  - `build_sox_gate4_summary.R` 33–41행은 `weight_as_of`를 전혀 확인하지 않습니다.
  - `validate_gate4.R` 30행의 `no_membership_lookahead`는 멤버십 날짜만 검사합니다.
  - `LOOKAHEAD_POLICY.md`의 "used only on or after its `weight_as_of` date"는 같은 날 사용을 허용하는 문구입니다. 일간 수익률 가중에는 직전 영업일 종가 기준 비중(`weight_as_of < date`)이 필요합니다.
- **부수 문제:** 올바르던 11-03 비중 스냅샷(`weight_source_evidence.csv`)이 덮어써져 보존되지 않았습니다. 비중 스냅샷 이력 관리가 없습니다.
- **근거:** `apps/timeseries/sox_constituents.csv` 18열 `weight_as_of=2026-11-04`(30/30), `docs/gate4/daily_replication_evidence.csv` 2행 `residual_return=-9.351e-4`, `docs/gate4/contribution_samples.csv`.

### R-02 [HIGH] 구성종목 불완전 집계(28/30) 게시: 2026-11-05 SOX 지표가 정상 품질로 표시됨 — FAIL
- **원인:** 소유권 분리(F-02 보완)로 NVDA·MU는 legacy Yahoo 저장소가 소유합니다. 이 저장소는 2026-11-04에서 끝나고, Gate 4 raw는 2026-11-05까지 갱신되었습니다. 그런데 빌더(`build_sox_gate4_summary.R` 33–53행)에 완결성 검사가 없어 11-05 집계를 28개 종목으로 산출했습니다.
- **독립 재계산(값은 빌더와 일치, 차이 ≤1e-17):**
  - 2026-11-05: `member_count=28`, 누락 MU·NVDA(비중 합 **19.7%**, 커버리지 0.8029)
  - `breadth 0/28`, `proxy_weighted_return=-0.12216`(80% 비중으로 재정규화)
  - `top5_concentration=0.29552`, `top10=0.48675`. 30종목 기준 실제 값은 0.40002 / 0.61328로, 10%p 이상 과소입니다.
  - `sox_return`과 `residual`은 NA입니다.
- **표시:**
  - `quality_flag=SOXQ_PROXY_ESTIMATE`로, 정상 행과 구분되지 않습니다.
  - Overview 상태밴드 "Member aggregate 2026-11-05"(`sox_constituents_server.R` 69·75행)가 불완전 일자를 최신 집계로 안내합니다. Breadth 표(`docs/gate4/sox_breadth.png`)와 Contribution·Value Chain(Memory 그룹 누락, 7/8 그룹)에도 그대로 노출됩니다.
- **구조적 위험:** 두 수집기의 갱신 주기가 다르면 매일 재발합니다. Gate 5(스케줄 수집)의 전제 조건에 정면으로 충돌합니다.
- **통제 공백:** `validate_gate4.R`에 날짜별 `member_count == 30`이나 비중 커버리지 검사가 없습니다.

### R-03 [MEDIUM] Overview "common start = 100" 주장이 사실과 다름(F-11 미해결) — FAIL
- **독립 재계산:** `derived_sox_overview.fst` 월별 복리값은 빌더 산식과 일치합니다(max diff 0). 그러나 공통 시작점은 강제되지 않았습니다.
  - SOXQ: 2021-06-30 시작(최초 일자 2021-06-14). ^SOX, SOXX, XSD: 2020-11-30 시작.
  - 종료일: SOXQ 2026-11-05, 나머지 2026-11-04. SOXQ에만 11-05의 -12.1% 하루가 추가되어 마지막 구간이 왜곡됩니다.
  - 첫 점도 100이 아니라 첫 달 수익률을 반영한 값입니다(약 104–110).
- **근거:**
  - `scripts/build_sox_gate4_summary.R` 106–124행: 시리즈별 `cumprod`, 공통 시작·종료일 교집합 없음.
  - `derived_sox_overview.png`의 SOXQ 선이 2021년 중반에 시작하는데, 축 제목은 "common start = 100"입니다.
  - `GATE4_REMEDIATION_REPORT.md` F11 행의 "Common period is enforced"는 사실과 다릅니다.

### R-04 [LOW] cold 측정 구간이 SOX 첫 화면 작업을 제외함(공시됨)
- `sox_status`와 `sox_benchmark_plot`은 `suspendWhenHidden=FALSE`(`sox_constituents_server.R` 152–153행)입니다. 50–52행의 서버 초기화 preload 때문에 SOX 첫 화면은 세션 시작 시 이미 렌더링됩니다.
- cold 측정 클라이언트는 이미지가 존재할 때까지 기다린 뒤 타이머를 시작합니다(`measure_gate4_browser_client.R` 53행). 따라서 0.05s는 탭 전환 시간입니다.
- `app_startup_seconds`는 TCP 포트가 열린 시각(`measure_gate4_browser_performance.ps1` 14–20행)이며, 세션 준비 완료가 아닙니다.
- 결과적으로 "브라우저 접속 → SOX 첫 화면 표시"의 end-to-end 시간은 측정되지 않았습니다. `GATE4_VALIDATION_REPORT.md`에 측정 구간이 공시되어 있어 Low로 분류합니다.

### R-05 [LOW] 불필요한 preload와 테스트 범위
- `overview_store`는 세션마다 읽히지만(51행) 어떤 출력도 사용하지 않습니다(dead load).
- legacy 회귀(`test_gate4_legacy_regression.R`)는 testServer 서버측 검증만 하며, 브라우저 렌더링은 아닙니다.

### R-06 [INFO]
- 보완 과정의 live 재수집으로 raw에 2026-11-05 29행이 추가되었습니다. 기존 207,876행은 키·값 변경 0건입니다(last_good 대비 독립 비교).
- 005930.KS는 Gate 1부터 `analysis_group=semiconductor_korea`로 Semiconductor & Korea Link 기본 선택에 포함되어 있습니다. 그러나 `collect_flag=FALSE`라 legacy 화면 데이터에는 없습니다. Gate 4 이전부터의 상태이며 회귀는 아닙니다.

---

## 2. 기존 F-01~F-12 재검증

| ID | 원 지적 | 재판정 | 독립 근거 |
|---|---|---|---|
| F-01 | 증거가 최종 빌드 이전 | **PASS** | 최종 빌드: 서버·app.R 09:19:44, derived 09:20:04, latest·overview 09:20:05. 이후 증거: Chromium cold 09:21:03–34, warm·filter 09:21:42–44, 스크린샷 09:23:18–34, UI smoke 09:26:03, legacy 09:26:12, validation 09:26:15, 해시 09:26:18. 최종 빌드 이후 코드·데이터 변경 없음 |
| F-02 | 수집기 충돌 | **PASS** (단 R-02 파생) | `series_catalog.csv` 163행, 키 중복 0. 필수 32개 중 legacy 수집 대상(active & collect_flag=TRUE)은 **NVDA, MU만**이고 나머지 30개는 `collect_flag=FALSE`. legacy Yahoo와 Gate 4 raw의 series 교집합 0, raw에 NVDA·MU 없음. `collect_sox_gate4.R` 113–114·149행: `collect_ids=required−{NVDA,MU}`, setequal 조건이 이제 일관됨. `dataExtract_fredyahoo.R` 350행 필터와 교차 확인 |
| F-03 | 000660.KS 음수가 | **PASS** | derived `benchmark_return` aux≤0 0건, \|ret\|>1 0건, 000660.KS 2002-12-26 이전 행 0, 2002-12-27 return NA(직전가 비양수). us_next_korea `aux_value` 재계산 일치 |
| F-04 | Close fallback | **PASS** | 빌더 14행 adjusted 전용, 24–29행 positive finite·\|r\|≤1 가드. NVDA는 adjusted NA 6,859행 제외(`price_quality_exclusions.csv`와 일치). 6개 벤치마크 수익률 독립 재계산 diff 0, 행수 일치(^SOX 8,182 / SOXX 6,365 / XSD 5,219 / SOXQ 1,358 / 000660.KS 5,928 / 005930.KS 6,708) |
| F-05 | 오래된 US 종가 유지 | **PASS** | 83행 `arrange(date, desc(us_date))`. 24개 쌍×창 독립 재계산(KR일별 최신 US 종가 선택): 행수 일치, 상관계수 max diff 0, `kr_date ≤ us_date` 위반 0, 복수 매핑 KR일 59–194건 모두 최신 US 채택 |
| F-06 | 기존 화면 회귀 없음 | **PASS** (R-05 한계) | `legacy_regression_results.csv` 15/15 출력(Sector 4, Series Explorer 2, Korea Rates 4, Semi Link 5), 최종 빌드 이후 09:26:12. 스크립트 내용 확인. legacy 서버 파일 mtime은 Gate 4 이전 |
| F-07 | 비브라우저 성능 | **PASS** (R-04 한계) | Chromium(chromote) DOM 기반, cold 5회 별도 R 프로세스(포트 5631–5635), warm 10회는 실제 subtab 클릭(7개 화면 전부 포함), filter 10회는 실제 `sox_link_range` 변경과 DOM 변화 대기. 재계산 결과 cold max 0.0674, warm p95 0.2622, filter p95 0.0848, startup max 2.688 — 모두 계약 이내 |
| F-08 | provenance | **PASS** (R-01 비중 이력 제외) | `collection_summary.csv`는 `validate_gate4.R` 56–68행 출력과 열 순서·`collection_mode`가 일치. raw last_good(46173B…) = 직전 게시본(11-05 18:23, 207,876행). derived last_good은 09:14:27 직전 빌드이며 target과 바이트 동일(결정적 재빌드, 내용 all.equal TRUE) |
| F-09 | index_weight 명칭 | **PASS** | CSV·증거 열 `proxy_weight_decimal`, UI 표 `proxy_weight_pct`(134–140행), 잔존 `index_weight` 0건 |
| F-10 | RSS 불일치 | **PASS** | 365.3 MB가 `ui_smoke_metrics.csv`, `gate4_validation.csv`, `performance_summary.csv`, 성능·검증 보고서에서 일치 |
| F-11 | Overview 시작점 불일치 | **FAIL** | R-03 |
| F-12 | latest 무조건 로드 | **PASS** (R-05) | 전체 derived(143,484행)는 `ensure_full()`로 Breadth·Contribution·Value Chain·Korea Link·Data Quality 진입 시에만 로드(60–63행). 첫 화면 소형 자산만 preload |

---

## 3. 요청 확인항목 1–10

| # | 항목 | 판정 | 근거 |
|---|---|---|---|
| 1 | 소유권 NVDA·MU legacy / 30개 Gate 4, Update Market Data 무충돌 | **PASS** | F-02 행 참조. 단 갱신주기 불일치로 R-02 발생 |
| 2 | positive finite Adjusted 전용, 000660.KS 778행·극단수익률 차단 | **PASS** | F-03, F-04 |
| 3 | KR 거래일별 latest eligible US close | **PASS** | F-05 |
| 4 | 기존 4개 화면 회귀 증거 | **PASS** | 15/15, 서버측 |
| 5 | 최종 빌드 이후 Chromium 5+10+10과 측정 구간 | **PASS** (R-04) | 시각 순서 확인, 수치 재계산 일치 |
| 6 | 중복키 0, 행수·기간, lookahead 방지 | **FAIL** | raw 207,905행 / 30 시리즈 / 중복 0 / 1972-06-01~2026-11-05 / adjusted NA·비양수 0. derived 143,484행 / 79 metric / 중복 0 / 1994-05-04~2026-11-05. 멤버 집계 2026-11-04 미만 0행(멤버십 lookahead 없음). 그러나 **비중 lookahead(R-01)**와 불완전 집계(R-02) |
| 7 | SHA256 7개와 provenance | **PASS** | 아래 표. 7개 모두 일치 |
| 8 | Overview 산식, 7개 화면, 전체 FST 지연 로드, 시작 API 0 | **FAIL** | 7개 tabPanel·9개 출력 렌더 증거 PASS, 지연 로드 PASS, 앱·서버 소스에 http/getSymbols/GET/POST 없고 수집기는 `input$update_data`에서만 호출(정적 PASS). 그러나 **Overview 공통 시작점 FAIL(R-03)** |
| 9 | 문서·RSS·필드명·품질플래그 정합성 | **FAIL** | RSS·필드명·수치 PASS. 그러나 11-05 불완전 행이 정상 플래그(R-02), 보완보고서 F11 "common period enforced" 오기재(R-03), 비중 기준일 변경과 그 영향이 문서에 없음(R-01) |
| 10 | Gate 5 미착수 | **PASS** | 스케줄러·Gate 5 스크립트 없음, `MARKET_TIMESERIES_WBS.md` Gate 5 "NOT STARTED"(mtime 11-05 17:48, 변경 없음), Git index 변경 없음(2026-07-02) |

### SHA256 독립 재계산

| 파일 | 감사자 재계산 | inventory 일치 |
|---|---|---|
| original_ts_fred.fst | 67CBDA72…53884 | ✔ (Gate 1 기준선 일치) |
| original_ts_yahoo.fst | D9431E63…71972 | ✔ (Gate 1 기준선 일치) |
| original_ts_ecos.fst | 6245DA33…447F5 | ✔ (Gate 3 기준선 일치) |
| original_ts_sox_components.fst | 2288AAD2…00B1A | ✔ |
| original_ts_sox_components.fst.last_good | 46173B96…BAFF4 | ✔ (1차 감사 시점 target과 동일 → 직전 게시본) |
| derived_sox_daily_summary.fst | D823CC50…0DFA8 | ✔ |
| derived_sox_daily_summary.fst.last_good | D823CC50…0DFA8 | ✔ (09:14:27 직전 빌드, 바이트 동일) |

참고(inventory 외): `derived_sox_latest.fst` BF16BE69…727D(derived와 metric별 최신값 79건 일치), `derived_sox_overview.fst` A797A778…0044, `derived_sox_overview.png` 75A4B935…BD7D.

### 표본 재계산(30종목 전수)
- 2026-11-04: 30개 모두 전일 2026-11-03 기준이며, 수익률·정규화 기여도·breadth(4/26/0, 13.33%)·EW·proxy·top5(0.4000187)·top10(0.6132775)·^SOX·residual·value chain 8개가 모두 빌더와 일치합니다(diff ≤ 7e-18). 산식은 맞지만 입력 비중이 R-01 lookahead입니다.
- 2026-11-05: 28종목으로 일치합니다(R-02).
- 정규화 기여도 합계가 `proxy_weighted_return`과 일치합니다(1차 F-11 기여도 합계 불일치 해소).

---

## 4. 종결 전 보완 요구 (수정은 하지 않음)
1. **R-01:** 일간 수익률에는 `weight_as_of < date`인 직전 스냅샷만 사용하도록 빌더에서 강제하고 검증 항목을 추가해야 합니다. 비중 스냅샷은 날짜별로 이력 보존해야 합니다(11-03 스냅샷 복원 또는 재취득 근거 기록). 11-04 집계는 재산출해야 합니다.
2. **R-02:** 날짜별 완결성 게이트를 둬야 합니다(member_count = 유효 멤버 수, 비중 커버리지 100%). 불완전 일자는 게시 차단 또는 별도 `INCOMPLETE_MEMBERSHIP` 플래그와 UI 표시가 필요합니다. legacy·Gate 4 수집 주기 동기화 규칙도 정의해야 합니다.
3. **R-03:** Overview를 4개 시리즈의 공통 시작·종료일 교집합으로 산출하고, 시작점이 정확히 100이 되도록(기준 월말 = 100) 수정한 뒤 보완보고서 문구를 정정해야 합니다.
4. R-04, R-05는 권고 사항입니다(end-to-end 첫 화면 시간 측정, dead preload 제거).

---

## 5. 최종 판정

```text
GATE_4_INDEPENDENT_REAUDIT_FAIL
GATE_4_REMEDIATION_REQUIRED
NO_GATE_5_START
```

**사유:** 1차 지적 12건 중 11건(F-01~F-10, F-12)은 독립 재검증으로 해소가 확인되었습니다. 그러나 다음 세 가지 때문에 종결할 수 없습니다.
- 보완 중 재수집으로 **같은 날 기말 비중이 11-04 집계에 적용되는 lookahead**가 새로 생겼습니다(R-01, HIGH).
- **28/30 종목만으로 산출한 11-05 SOX 지표가 정상 품질로 게시**되고 있습니다(R-02, HIGH).
- **Overview 공통 시작점(F-11)**이 여전히 충족되지 않습니다(R-03).
