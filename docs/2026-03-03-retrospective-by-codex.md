# 2026-03-03 Codex 회고

## 작업 내용

Claude Code가 1차 진단한 Grafana 대시보드 공백 이슈를 이어받아, 원인 확정과 복구까지 진행했다.

- 대시보드/수집 파이프라인 end-to-end 검증
- `collector-config.yaml`의 `send_timestamps: true`를 `false`로 변경
- `grafana/claude-code-dashboard.json`의 datasource 참조를 UID 고정 방식에서 이름 참조(`"Prometheus"`, `"Loki"`)로 변경
- Grafana/Collector 재기동 및 쿼리/로그 재검증

## 진단 과정

1. 컨테이너 상태 및 Collector/Prometheus/Grafana 로그 확인
2. Collector debug 로그에서 메트릭/로그 수신 자체는 정상임을 확인
3. Prometheus 로그에서 `too old or too far into the future` 경고 반복 확인
4. Prometheus/Loki API로 대시보드 패널 쿼리를 직접 실행해 데이터 유무 분리
5. Grafana 내부 DB를 조회해 실제 datasource UID와 대시보드 참조 UID 불일치 확인
6. datasource UID를 프로비저닝으로 강제하려다 Grafana provisioning 실패(재시작 루프) 발생
7. 해당 시도 롤백 후, 대시보드 쪽을 datasource 이름 참조로 변경
8. Collector timestamp 설정 수정 후 재기동, 경고 재발/패널 쿼리 결과 재검증

## 찾은 것

- 화면 공백의 핵심 원인 1: Grafana datasource UID 불일치
  - 대시보드는 `prometheus`/`loki` UID를 가정
  - 실제 Grafana 12 환경의 UID는 랜덤 값
- 원인 2: `send_timestamps: true`로 인한 Prometheus 샘플 드롭 경고
- 대시보드가 비는 문제는 "데이터 미수집"만이 아니라 "조회 바인딩 실패"일 수 있다는 점

## 못 찾은 것

- 원본 타임스탬프가 왜 어긋났는지(클라이언트/수집 경로 어느 지점의 시계 불일치인지)까지는 추적하지 못했다.
- Grafana admin 비밀번호가 기본값(`admin/admin`)과 달랐던 정확한 변경 이력은 확인하지 못했다.

## 왜 못 찾았나

- 이번 목표를 "대시보드 복구"에 두고, 서비스 정상화와 재발 방지 조치에 우선순위를 뒀다.
- 계정/운영 이력(누가 언제 비밀번호를 바꿨는지), 클라이언트 시계 상태 같은 운영 컨텍스트는 저장소만으로 확인이 어려웠다.
- timestamp 문제는 `send_timestamps: false` 적용 후 즉시 증상이 멈춰, 근본 원인 추적을 추가로 진행하지 않았다.

## 교훈

- Grafana 공백 이슈는 반드시 `수집(Collector) -> 저장(Prometheus/Loki) -> 조회(Grafana)`로 분리해서 본다.
- Grafana 12에서는 대시보드에 datasource UID를 하드코딩할 때 운영 리스크가 크다. 이름 참조가 더 안전한 선택일 수 있다.
- OTel Prometheus exporter는 특별한 이유가 없으면 `send_timestamps: false`를 기본으로 두는 편이 안정적이다.
- 설정 실험은 롤백 경로를 먼저 확보해야 한다. 작은 datasource 변경도 Grafana 부팅 실패로 이어질 수 있다.
