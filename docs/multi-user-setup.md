# 멀티유저 설정 가이드

사내 Claude Code 공용 계정 사용 시 사용자별 비용/효율을 추적하기 위한 설정 가이드.

## 아키텍처

```
사용자 A PC → (OTLP, user.name=a) ─┐
사용자 B PC → (OTLP, user.name=b) ─┼→ 중앙 OTel Collector → Prometheus/Loki → Grafana
사용자 C PC → (OTLP, user.name=c) ─┘
```

## 1. 모니터링 서버 설정

모니터링 스택을 중앙 서버에 배포합니다.

```bash
# 모니터링 서버에서
git clone https://github.com/bemaru/claude-code-monitoring.git
cd claude-code-monitoring
docker compose up -d
```

외부 접근을 위해 OTel Collector 포트(4317, 4318)를 방화벽에서 열어줍니다.

## 2. 사용자별 Claude Code 설정

각 사용자의 `~/.claude/settings.json`에 아래 환경변수를 추가합니다.

```json
{
  "env": {
    "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
    "OTEL_METRICS_EXPORTER": "otlp",
    "OTEL_LOGS_EXPORTER": "otlp",
    "OTEL_EXPORTER_OTLP_PROTOCOL": "grpc",
    "OTEL_EXPORTER_OTLP_ENDPOINT": "http://<모니터링서버IP>:4317",
    "OTEL_METRIC_EXPORT_INTERVAL": "60000",
    "OTEL_RESOURCE_ATTRIBUTES": "user.name=<본인이름>,team=<소속팀>"
  }
}
```

### 필수 attribute

| Attribute | 설명 | 예시 |
|-----------|------|------|
| `user.name` | 사용자 식별자 (Prometheus label: `user_name`) | `kimjh` |
| `team` | 소속 팀 (비용 팀별 집계용) | `backend`, `frontend` |

### chezmoi로 배포하는 경우

템플릿을 활용해 사용자별 값을 자동 설정할 수 있습니다.

```jsonc
// dot_claude/settings.json.tmpl
{
  "env": {
    "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
    "OTEL_METRICS_EXPORTER": "otlp",
    "OTEL_LOGS_EXPORTER": "otlp",
    "OTEL_EXPORTER_OTLP_PROTOCOL": "grpc",
    "OTEL_EXPORTER_OTLP_ENDPOINT": "http://monitoring.internal:4317",
    "OTEL_METRIC_EXPORT_INTERVAL": "60000",
    "OTEL_RESOURCE_ATTRIBUTES": "user.name={{ .chezmoi.username }},team={{ .team }}"
  }
}
```

## 3. 대시보드 사용

Grafana(`http://<모니터링서버IP>:13000`)에서 **Claude Code Observability** 대시보드를 엽니다.

상단의 **User** / **Team** 드롭다운으로 필터링할 수 있습니다.

### User Analysis 섹션 패널

| 패널 | 용도 |
|------|------|
| Cost by User (Hourly) | 사용자별 시간당 비용 추이 |
| Tokens by User (Hourly) | 사용자별 토큰 소비량 |
| Cache Hit Rate by User | 사용자별 캐시 효율 (낮으면 CLAUDE.md 설정 필요) |
| Code Changes by User | 사용자별 코드 변경량 |
| Cost by User × Model | 사용자-모델 조합별 비용 (Opus 과다 사용 식별) |
| Cost by Team (Hourly) | 팀별 비용 집계 |

## 4. 비용 최적화 포인트

대시보드에서 확인할 수 있는 개선 신호:

- **Cache Hit Rate < 50%** → CLAUDE.md 미설정 또는 세션이 너무 짧음
- **Opus 비중 > 80%** → Sonnet으로 전환 가능한 작업 식별
- **토큰 대비 코드 변경량 낮음** → 프롬프트 구체화 필요
- **API Error 빈발** → rate limit 도달, 사용 시간대 분산 필요

## 주의사항

- `OTEL_RESOURCE_ATTRIBUTES`의 `user.name`은 Prometheus에서 `user_name`으로 변환됩니다 (`.` → `_`)
- Collector의 `resource_to_telemetry_conversion: enabled: true` 설정이 필수입니다
- 기존 단일 사용자 환경에서도 동일하게 작동합니다 (user_name 없으면 전체 집계)
