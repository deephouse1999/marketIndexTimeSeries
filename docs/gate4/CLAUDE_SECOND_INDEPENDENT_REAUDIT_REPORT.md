# Gate 4 SOX Constituents — Claude 두 번째 독립 재감사 보고서

- 재감사일: 2026-11-06 (KST)
- 대상: `C:\app\econ_ts\marketIndexTimeSeries` 2차 보완 최종본
- 성격: READ-ONLY. 코드·CSV·FST·기존 증거와 앞선 두 감사보고서는 수정하지 않았습니다. 데이터 재수집·재생성과 Gate 5 작업도 하지 않았습니다. 이 파일 하나만 새로 작성했습니다.
- 방법: 대상 파일을 디바이스 브리지로 읽기 전용 스냅샷으로 가져와, 격리된 감사 환경에서 감사자가 작성한 독립 R(data.table/fst) 코드로 재계산했습니다. SHA256은 `sha256sum`으로 계산했습니다. 프로젝트 스크립트는 실행하지 않았습니다. 사용자 PC 셸이 없어 브라우저 재측정은 하지 않았고, 성능은 최종 빌드 이후 증거로 판정했습니다.
- 앞선 두 감사보고서는 감사자 원본과 바이트 동일합니다(`cmp` 일치). 변조되지 않았습니다.
- raw 저장소(`original_ts_sox_components.fst`, 08:53:35)와 `sox_constituents.csv`(08:53:22)는 1차 재감사 이후 변경되지 않았습니다. 2차 보완 중 재수집은 없었습니다.

---

## 1. Findings (심각도 순)

이번 재감사에서 **CRITICAL, HIGH, MEDIUM 발견사항은 없습니다**. 아래는 모두 비차단(LOW/INFO) 사항입니다.

### S-01 [LOW] 11-04 집계가 재구성 비중을 썼다는 사실이 UI와 파생 FST에 직접 표시되지 않음
- 게시된 11-04 `daily_summary`, `constituent_contribution`, `value_chain_return` 30+11+8행은 2026-11-03 `RECONSTRUCTED_PRE_EOD` 비중으로 계산되었습니다(재현 확인).
- 그런데 파생 FST의 `quality_flag`는 일반값 `SOXQ_PROXY_COMPLETE_PREVIOUS_SNAPSHOT`입니다. Overview 상태밴드는 "Weight SOXQ proxy as of 2026-11-04"(`sox_constituents_server.R` 67행)라서, 집계에 실제로 쓰인 비중 기준일·유형이 화면에 드러나지 않습니다.
- "공식 비중"으로 표시하는 곳은 없습니다. 배너는 "not official SOX index weights"이고, 재구성 사실은 `sox_weight_history.csv`, `contribution_samples.csv`(`snapshot_type` 열), `SOX_MEMBERSHIP_AND_WEIGHT_POLICY.md`, `LOOKAHEAD_POLICY.md`에 투명하게 공시되어 있습니다. 오인 표시가 아닌 공시 위치의 문제이므로 LOW로 분류합니다.
- 권고: Data Quality 표나 상태밴드에 "aggregate weights: 2026-11-03 RECONSTRUCTED_PRE_EOD"를 표시.

### S-02 [LOW] 문서 수치 표기 불일치
- `GATE4_VALIDATION_REPORT.md`는 "80.29% weight coverage"라고 적었는데, 이는 가용 비중 합계(0.8029398)입니다. `member_date_completeness.csv`의 `weight_coverage`는 0.803103(80.31%)입니다. 기준(분모)이 다른 표기 차이일 뿐 판정에는 영향이 없습니다.

### S-03 [LOW, 비차단] cold 측정 구간
- 승인된 계약대로 "초기 Shiny idle 및 필수 첫 화면 asset 준비 후 SOX 탭 클릭부터 visible+idle까지"로 측정했고, 문서에 공시되어 있습니다. 앱 startup은 별도로 측정했습니다(max 3.155s ≤ 5s).
- 브라우저 접속부터 첫 화면까지의 end-to-end 시간은 계약 항목이 아니므로 권고 사항으로만 남깁니다.

### S-04 [LOW] 테스트 범위·향후 경로
- legacy 회귀 15개는 testServer 서버측 검증입니다.
- `collect_sox_gate4.R`(102–119행)의 비중 이력 append 로직은 코드 검토로만 확인했습니다. 런타임 실행 증거는 없고, 이번 보완에서 수집기는 실행되지 않았습니다. 다음 실집행 시 2026-11-03·11-04 행이 보존되는지 확인할 것을 권고합니다.
- `reconstruct_sox_weight_history.R`은 이력 전체를 다시 쓰는 1회성 스크립트입니다. 다만 9행 가드(`weight_as_of == 2026-11-04`일 때만 실행)로 재실행 위험은 제한됩니다.

### S-05 [LOW] 표시 품질
- 집계일이 하루뿐이라 Breadth 차트 x축이 밀리초 단위 눈금으로 표시됩니다(`docs/gate4/sox_breadth.png`). 외관상의 문제입니다.

### S-06 [INFO] 재구성 비중의 실측 정확도(감사자 실무기록 대조)
- 1차 감사 때 감사자가 원래의 2026-11-03 공식 SOXQ 스냅샷 30개 값을 직접 readback해 기록해 두었습니다. 이 값은 저장소에는 남아 있지 않습니다.
- 재구성값과의 오차는 **최대 5.29e-5(ASML), 평균 1.90e-6**입니다.
- 합계는 원본 0.99984623, 재구성 0.99979655입니다(11-04 EOD 합계로 정규화한 산식에 따른 차이).
- 게시 지표 대조:

| 지표 | 원본 비중 기준 | 재구성 비중 기준 |
|---|---:|---:|
| proxy return | -0.03128893 | -0.03128874 |
| residual | -6.69e-6 | -6.88e-6 |
| top5 | 0.400576 | 0.4005775 |

- 차이는 무시 가능한 수준입니다. 재구성 방법은 실질적으로 타당합니다.

---

## 2. R-01~R-05 재검증

| ID | 1차 재감사 지적 | 판정 | 독립 근거 |
|---|---|---|---|
| R-01 | 같은 날 EOD 비중 lookahead | **PASS** | 아래 3.1·3.2 |
| R-02 | 28/30 불완전 집계 게시 | **PASS** | 아래 3.3·3.4 |
| R-03 | Overview 공통 시작점 | **PASS** | 아래 3.5 |
| R-04 | cold 구간 공시 | **PASS (비차단 LOW, S-03)** | 계약 구간과 측정 구현 일치(`measure_gate4_browser_client.R` 53–60행), 공시 확인 |
| R-05 | 미사용 preload | **PASS** | `overview_store` 정의·preload·반환이 모두 제거됨. 서버 시그니처에서 `overview_path` 제거, `app.R` 478–485행 인자 4개. 세션 preload는 `latest_store`와 `constituent_store`만(45–46행). `test_sox_gate4_ui.R`에도 참조 없음 |

## 3. 요청 확인항목 1–8

### 3.1 비중 이력 — PASS
- `apps/timeseries/sox_weight_history.csv`(SHA256 D00F5B94…FA47)는 `docs/gate4/sox_weight_history_evidence.csv`와 바이트 동일합니다.
- (ticker, weight_as_of) 중복 0이고, 티커 집합은 구성종목 30개와 같습니다.

| weight_as_of | 행 | snapshot_type | quality_flag | Σw |
|---|---:|---|---|---:|
| 2026-11-03 | 30 | `RECONSTRUCTED_PRE_EOD` | `RECONSTRUCTED_FROM_2026_11_04_EOD_PRICE_DRIFT` | 0.99979655 |
| 2026-11-04 | 30 | `OFFICIAL_SOXQ_EOD` | `PROXY_WEIGHT_NOT_OFFICIAL_INDEX_WEIGHT` | 0.99979655 |

- 11-04 EOD 행은 `sox_constituents.csv` 비중과 일치합니다(max diff 8.7e-18).
- 산식 `w₍t−1₎ ∝ w₍t₎/(1+r₍t₎)`를 Σw(EOD)로 재정규화하는 계산을 감사자가 raw Adjusted Close로 독립 재현했고, **max diff 0**입니다. `weight_reconstruction_evidence.csv`의 가격·수익률·두 비중도 모두 일치합니다(diff 0).
- `reconstruction_basis` 열에 산식이 명시되어 있고, 공식 비중으로 표기하지 않습니다. 원본 11-03 스냅샷이 보존되지 않은 사실은 정책 문서에 공시되어 있습니다.

### 3.2 strict prior weight — PASS
- `build_sox_gate4_summary.R` 39–41행은 `weight_as_of < date`인 최신 스냅샷만 사용합니다.
- 게시된 contribution 30행은 모두 date 2026-11-04 / weight_as_of 2026-11-03입니다(`contribution_samples.csv` 위반 0).
- 감사자가 11-03 재구성 비중으로 11-04 지표 11개, 기여도 30개, value chain 8개를 독립 재계산했고 모두 일치합니다(diff ≤ 7.6e-19).
- 대조 검증: 같은 날 EOD 비중을 쓰면 proxy가 -0.03036049가 되는데, 게시값은 -0.03128874입니다. 따라서 EOD 비중은 사용되지 않았습니다.
- residual은 -6.88e-6으로 정상 수준을 회복했습니다(1차 재감사 시 -9.35e-4).

### 3.3 완결성 게이트 — PASS
- 독립 재계산 결과:
  - 2026-11-04: 기대 30 / 가용 30, coverage 1.0, 사용 비중 2026-11-03
  - 2026-11-05: 기대 30 / 가용 28(MU·NVDA 누락), 가용 비중 0.8029398 / 기대 0.9997966 = **80.31%**, 사용 비중 2026-11-04
- `member_date_completeness.csv`와 일치합니다(`complete` TRUE/FALSE).
- 파생 FST의 `daily_summary`, `constituent_contribution`, `value_chain_return`에 **2026-11-05 행 0건**, 2026-11-04 이전 행 0건입니다.

### 3.4 member_count와 UI 상태 — PASS
- 게시된 `member_count`는 {30} 하나뿐이고, value chain `aux_value` 합도 30입니다.
- `derived_sox_latest.fst`의 `daily_summary` 최신일은 2026-11-04이고, latest 79행이 파생 FST의 metric별 최신값과 일치합니다.
- 상태밴드 코드(63·69행)는 daily_summary 최신일과 "(latest complete 30/30)"을 표시합니다. 최종 스크린샷 `sox_overview.png`에서 "Member aggregate 2026-11-04 (latest complete 30/30)"을 확인했습니다.

### 3.5 Overview — PASS
- `derived_sox_overview.fst`는 4개 시리즈 각 67점이며, 날짜 집합이 동일하고 기간은 **2021-06-11~2026-11-04**입니다. 첫 값은 4개 모두 **정확히 100**입니다(`== 100` TRUE).
- 독립 재계산: 4개 시리즈 공통 거래일 교집합 1,356일(2021-06-11~2026-11-04), `100×adj/adj₀` 지수, 월말 샘플 값 max diff 0.
- 최종 PNG와 스크린샷에서 4개 선이 모두 2021년 중반 100에서 시작함을 확인했습니다.

### 3.6 preload 제거 — PASS (R-05)

### 3.7 최종 빌드 증거 정합성 — PASS
- **시각 순서(2026-11-06 KST):**

| 구분 | 시각 |
|---|---|
| app.R | 15:34:17 |
| 비중 이력 | 15:34:52 |
| 빌더 | 15:35:34 |
| server.R | 15:35:51 |
| **derived FST** | **15:36:03** |
| overview FST/PNG | 15:36:04 |
| Chromium cold 5회 | 15:36:50–15:37:23 |
| warm 10회 / filter 10회 | 15:37:31–32 |
| 스크린샷 7장 | 15:37:58–15:38:14 |
| UI smoke | 15:38:26 |
| legacy | 15:38:35 |
| 검증 28/28 | 15:38:39 |
| 해시 | 15:38:41 |

  최종 빌드 이후 코드·데이터 변경은 없습니다. derived last_good(15:34:57)은 직전 빌드이며 target과 바이트·내용이 동일합니다(identical TRUE).
- **성능(재계산 일치):** cold max 0.0696s(5/5 PASS, 포트별 별도 프로세스), warm p95 0.2886s(7개 subview 전부 포함, 10/10), filter p95 0.0791s(10/10), startup max 3.155s, RSS 365.5MB. 모두 계약 이내입니다.
- **UI·회귀:** UI smoke 9개 출력(`ui_smoke_metrics.csv`), legacy 15/15(Sector 4, Series Explorer 2, Korea Rates 4, Semi Link 5).
- **중복키·행수:**
  - raw: 207,905행 / 30 시리즈 / 키 중복 0 / 1972-06-01~2026-11-05
  - derived: **143,438행** / 79 metric / 키 중복 0 / 1994-05-04~2026-11-05
  - benchmark_return 33,760행, us_next_korea 109,629행(1차 재감사와 동일), 멤버 그룹 30+11+8행
- **SHA256(감사자 재계산, inventory 7개 모두 일치):**

| 파일 | SHA256 |
|---|---|
| original_ts_fred.fst | 67CBDA72…53884 (Gate 1 기준선) |
| original_ts_yahoo.fst | D9431E63…71972 (Gate 1 기준선) |
| original_ts_ecos.fst | 6245DA33…447F5 (Gate 3 기준선) |
| original_ts_sox_components.fst | 2288AAD2…00B1A |
| original_ts_sox_components.fst.last_good | 46173B96…BAFF4 (직전 게시본) |
| derived_sox_daily_summary.fst | 7040B53C…65E94 |
| derived_sox_daily_summary.fst.last_good | 7040B53C…65E94 |

  참고(inventory 외): latest 19F635FC…575F, overview FST BD8BB880…2CE2, overview PNG 36B6D58D…6A9B.
- 28개 검증 항목은 감사자 재계산과 모순되는 것이 없습니다.

### 3.8 F-01~F-12 지속 해소 및 Gate 5 — PASS
| ID | 상태 | 근거 |
|---|---|---|
| F-01 | 해소 유지 | 3.7 시각 순서 |
| F-02 | 해소 유지 | `series_catalog.csv` 미변경(08:52:07). legacy 수집 대상은 NVDA·MU뿐, 나머지 30개는 `collect_flag=FALSE`, 저장소 간 교집합 0 |
| F-03 | 해소 유지 | benchmark aux≤0 0건, \|ret\|>1 0건, 000660.KS 비양수 778행 제외 |
| F-04 | 해소 유지 | 빌더 13–33행 Adjusted 전용 + 가드 |
| F-05 | 해소 유지 | next_kr 함수 미변경, us_next_korea 행수 동일(109,629) |
| F-06 | 해소 유지 | legacy 15/15, 최종 빌드 이후 |
| F-07 | 해소 유지 | Chromium 5+10+10, 최종 빌드 이후 |
| F-08 | 해소 유지 | last_good = 직전 산출물, 비중 이력 append 구조 도입 |
| F-09 | 해소 유지 | `proxy_weight_decimal` / UI `proxy_weight_pct` |
| F-10 | 해소 유지 | RSS 365.5MB가 모든 문서에서 일치 |
| F-11 | **해소** | 3.5 |
| F-12 | 해소 유지 | 전체 FST는 `ensure_full()` 경로로만 로드(54–57행), 서버 초기화 시 미로드 |

- 앱 시작 시 외부 API: 앱·서버 소스에 http/getSymbols/GET/POST가 없습니다. 수집기는 `input$update_data` 이벤트에서만 호출됩니다(정적 PASS).
- Gate 5: 스케줄러·Gate 5 스크립트가 없습니다. `MARKET_TIMESERIES_WBS.md` Gate 5는 "NOT STARTED"(mtime 11-05 17:48, 미변경)이고, Git index도 미변경입니다(2026-07-02).

---

## 4. 결론

R-01(비중 lookahead), R-02(불완전 집계), R-03(Overview 공통 시작점), R-05(dead preload)가 최종 빌드에서 독립 재계산으로 해소되었음을 확인했습니다. R-04는 승인 계약 범위 내의 비차단 사항입니다. 1차 감사 F-01~F-12도 모두 해소 상태를 유지합니다.

재구성된 2026-11-03 비중은 공식 비중으로 오인 표시되지 않습니다. 산식은 독립적으로 재현되었고, 감사자 실무기록의 원본 값과 대조해도 실질 오차가 없습니다(최대 5.3e-5).

잔여 사항 S-01~S-05는 모두 LOW로 Gate 종결을 막지 않습니다. 다만 S-01(재구성 비중의 UI 공시)과 S-04(비중 이력 append 런타임 확인)는 Gate 5 첫 실집행 때 확인할 것을 권고합니다.

## 5. 최종 판정

```text
GATE_4_SECOND_INDEPENDENT_REAUDIT_PASS
GATE_4_CLOSED_PASS
GATE_5_APPROVED_TO_START
```
