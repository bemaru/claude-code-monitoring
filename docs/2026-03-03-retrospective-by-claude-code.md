# 2026-03-03 Claude Code 회고

## 작업 내용

Grafana 대시보드에 데이터가 표시되지 않는 문제 디버깅.

## 진단 과정

1. Docker 컨테이너 상태 확인 → 4개 모두 정상 가동
2. OTel Collector (8889) 메트릭 확인 → 데이터 수신 중
3. Prometheus (9090) 쿼리 → 일부 메트릭만 조회됨
4. `job` 레이블 불일치 발견 (`claude-code` vs `otel-collector`)
5. `session_count_total`의 `increase()` 문제 발견 → `count_over_time()`으로 수정
6. Loki 로그 구조 확인 → `| json` 파싱 실패 원인 발견 (log body가 JSON 아닌 단순 문자열)
7. 대시보드 쿼리 전체 수정 후 적용

## 찾은 것

- Prometheus 쿼리 문제 (session_count의 `increase` → `count_over_time`)
- Loki `| json` 파싱 실패 (structured metadata라 파싱 불필요)
- 존재하지 않는 메트릭 참조 (`commit_count`, `pull_request_count` → 아직 미발생)

## 못 찾은 것 (codex가 해결)

- `collector-config.yaml`의 `send_timestamps: true` → `false` 변경 필요. 원본 타임스탬프를 보내면 Prometheus가 stale 처리함
- Grafana 12에서 datasource 참조 형식: `{ "type": "prometheus", "uid": "prometheus" }` → `"Prometheus"` 문자열

## 왜 못 찾았나

- CLI에서 range query로 데이터가 보이니까 "쿼리는 맞다"고 성급하게 결론냄
- Grafana API 인증 실패(비번 변경) 후 실제 대시보드 검증을 포기함
- Collector 설정은 "수신이 되고 있으니 정상"이라고 가정하고 의심 대상에서 제외함
- end-to-end 검증 없이 중간 단계 통과만으로 완료 판단

## 교훈

- CLI 테스트 통과 ≠ 최종 환경에서 동작. 반드시 end-to-end 검증 필요
- 데이터가 "있다"와 "Grafana에서 보인다"는 다른 문제 — 수신 측 설정(timestamp, datasource 참조)도 점검해야 함
- 인증 실패 같은 장애물에서 포기하지 말고 우회 방법을 찾을 것
