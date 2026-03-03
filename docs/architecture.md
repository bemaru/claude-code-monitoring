# Architecture

## 서비스 구성

| 서비스 | 이미지 | 포트 | 역할 |
|--------|--------|------|------|
| otel-collector | otel/opentelemetry-collector-contrib | 4317 (gRPC), 4318 (HTTP), 8889 | OTLP 수신 → 메트릭/로그 분배 |
| prometheus | prom/prometheus | 9090 | 메트릭 저장 (30일 보존) |
| loki | grafana/loki | 3100 | 로그 저장 |
| grafana | grafana/grafana-oss | 3030 | 대시보드 |

## 데이터 파이프라인

### 메트릭 (Prometheus)

- OTel Collector가 OTLP 메트릭을 수신해 Prometheus exporter(8889)로 노출
- Prometheus가 15초 간격으로 `otel-collector:8889` scrape
- Collector의 Prometheus exporter는 `send_timestamps: false`로 설정 (샘플 드롭 방지)

주요 메트릭:

- `claude_code_session_count_total` - 세션 수
- `claude_code_cost_usage_USD_total` (label: model) - 비용
- `claude_code_token_usage_tokens_total` (label: type) - 토큰 사용량
- `claude_code_lines_of_code_count_total` (label: type) - 코드 변경량
- `claude_code_active_time_seconds_total` (label: type) - 활성 시간
- `claude_code_code_edit_tool_decision_total` - 코드 수정 도구 허용/거절

### 로그 (Loki)

- OTel Collector가 OTLP 로그를 수신해 `otlphttp`로 Loki에 전송 (`http://loki:3100/otlp`)
- `service_name="claude-code"` 기준으로 조회
- OTLP attributes는 structured metadata로 저장되므로 LogQL에서 `| json` 파싱 없이 라벨/필드 사용 가능

주요 이벤트:

- `claude_code.tool_result` - 도구 실행 결과 (tool_name, success, duration_ms, error)
- `claude_code.api_request` - API 요청 (model, duration_ms, token/cost 관련 필드)
- `claude_code.api_error` - API 에러 (status_code, duration_ms, error, model)

## Grafana 대시보드

- UID: `claude-code-obs`
- 총 16개 패널
- datasource 참조 방식: UID 고정 객체 대신 이름 문자열 사용
  - Prometheus 패널: `"Prometheus"`
  - Loki 패널: `"Loki"`

| 섹션 | 패널 | 데이터소스 |
|------|------|-----------|
| Overview | Sessions, Cost, Tokens, LoC (1h) | Prometheus |
| Cost & Token Analysis | Cost by Model, Token Usage Rate by Type | Prometheus |
| Tool Usage | Tool Usage Rate, Tool Success Rate, Cumulative Tool Usage | Loki |
| Performance & Errors | API Request Duration by Model, API Errors by Status Code | Loki |
| Productivity | Code Changes Rate, Active Time | Prometheus |
| Event Logs | Tool Execution Events, API Error Events | Loki |

## 트러블슈팅

### 대시보드에 데이터가 안 보일 때

1. 컨테이너 상태 확인
   - `docker compose ps`
2. Prometheus scrape 상태 확인
   - `up{job="otel-collector"}`
3. Prometheus 메트릭 직접 조회
   - `sum(max_over_time(claude_code_cost_usage_USD_total{job="otel-collector"}[1h]))`
4. Loki 로그 직접 조회
   - `sum by (tool_name) (count_over_time({service_name="claude-code"} |= "claude_code.tool_result" [5m]))`
5. Prometheus 경고 로그 확인
   - `Error on ingesting samples that are too old or are too far into the future`
6. Collector 설정 확인
   - `collector-config.yaml`의 `prometheus.send_timestamps`가 `false`인지 확인
7. Grafana 대시보드 datasource 바인딩 확인
   - 대시보드 JSON이 `"Prometheus"`/`"Loki"` 이름 참조를 사용하는지 확인
