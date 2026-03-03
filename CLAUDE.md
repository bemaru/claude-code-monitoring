# Claude Code Monitoring

Claude Code 세션의 메트릭/로그를 수집하는 OTel 기반 모니터링 스택.

## 아키텍처

```
Claude Code → OTLP (4317/4318) → OTel Collector → Prometheus (메트릭) + Loki (로그) → Grafana (3030)
```

## 로컬 실행

```bash
docker compose up -d
```

## 트러블슈팅

`bash scripts/healthcheck.sh` 또는 [docs/architecture.md#트러블슈팅](docs/architecture.md#트러블슈팅) 참고.

## 주의사항

- Collector의 `send_timestamps`는 반드시 `false`여야 함 (true이면 Prometheus가 stale 처리)
- Grafana 12에서 provisioned datasource 참조는 문자열 이름 사용 (`"Prometheus"`, `"Loki"`)
- Loki OTLP 수신 시 attributes는 structured metadata로 저장됨 (`| json` 파싱 불필요)
