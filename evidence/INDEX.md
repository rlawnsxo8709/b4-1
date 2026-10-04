# 증거 자료 색인

미션이 요구하는 **필수 증거 8종**을 파일·라인으로 연결한다.
채점자가 찾아 헤매지 않도록 하는 것이 목적이다.

- 최종 상태 검증: `FINAL-VERIFICATION.txt` (388줄) — `env/collect-evidence.sh` 로 재생성 가능. 단, 이번 재구성에서 이 스크립트의 추가 항목 블록을 제거했으므로 지금 재생성하면 필수 8종 구간(L1–305, 뒤따르는 빈 줄까지 약 306줄)만 나오며, 추가 항목 구간 L308–388 은 재생성본에 포함되지 않는다. 원본 388줄 파일과 줄 수·줄 번호가 달라질 수 있다.
- 단계별 상세: `phase*.txt` — 명령 + 출력 + **종료코드**가 시간순으로 append
- 원본 녹화: `session/2026-08-09-session.log` (2,237줄) — 실패·오타 포함, 편집하지 않음
- 설정 실물: `snapshots/` — `env/snapshot.sh` 가 실제 파일을 복사한 것

---

## 필수 증거 8종

| # | 필수 증거 | 위치 | 보조 자료 |
|---|---|---|---|
| 1 | SSH 포트 변경(20022) 및 Root 원격 접속 차단 | `FINAL-VERIFICATION.txt` **L9–37** | `phase1-ssh.txt`, `snapshots/sshd_config.d-99-agent.conf` |
| 2 | 방화벽 활성화 및 20022/tcp, 15034/tcp 만 허용 | `FINAL-VERIFICATION.txt` **L38–62** | `phase2-ufw.txt`, `snapshots/ufw-status.txt` |
| 3 | 계정/그룹 생성 (agent-admin/dev/test, agent-common/core) | `FINAL-VERIFICATION.txt` **L63–80** | `phase3-account-acl.txt`, `snapshots/accounts.txt` |
| 4 | 디렉토리 구조 및 권한(ACL 포함) | `FINAL-VERIFICATION.txt` **L81–175** | `phase3-account-acl.txt`, `snapshots/getfacl-all.txt` |
| 5 | 앱 Boot Sequence 5단계 [OK] 및 "Agent READY" | `FINAL-VERIFICATION.txt` **L176–215** | `phase4-app.txt` |
| 6 | monitor.sh 실행 결과 (프로세스/포트/리소스/경고) | `FINAL-VERIFICATION.txt` **L216–247** | `phase5-monitor.txt` |
| 7 | monitor.log 누적 기록 (최근 라인) | `FINAL-VERIFICATION.txt` **L248–271** | `phase6-cron.txt` |
| 8 | crontab 매분 실행 등록 및 자동 실행 확인 | `FINAL-VERIFICATION.txt` **L272–308** | `phase6-cron.txt`, `snapshots/crontab-agent-admin.txt` |

> **원본 무결성 안내**: `FINAL-VERIFICATION.txt` 의 **L308–388**(L308 이 구분선, L309 가 첫 제목)은 구 작업에서 필수 8종 외에 함께 수행한
> 추가 항목(통계 리포트·경고 기록·로그 보존)의 실행 기록이다. 이 B4-1 산출물의 범위가 아니며,
> 원본을 수정하지 않는다는 원칙에 따라 삭제하지 않고 남겨 두었다. `session/` 녹화와 `snapshots/script-perms.txt`
> (`config/script-perms.txt` 와 동일)에도 같은 흔적이 있다. 위 표의 증거 1–8(마지막 내용 줄 L305)만 필수 증거다. 표의 범위는 제목 줄부터 다음 블록의 구분선 줄까지라, 8행의 끝 L308 은 추가 항목 블록의 구분선이다.

---

## 단계별 증거 파일

| 파일 | 줄 수 | 내용 |
|---|---|---|
| `phase0-env.txt` | 83 | 실습 환경 검증 (비특권 컨테이너, systemd 부재 확인) |
| `phase1-ssh.txt` | 95 | SSH 포트/Root 차단, ssh.socket 함정 기록 |
| `phase2-ufw.txt` | 166 | 방화벽 규칙, **게이트 검사식 버그 기록**, 외부 프로브 3종 |
| `phase3-account-acl.txt` | 483 | 계정/그룹/ACL, **경로 통행권 결함 발견·수정**, 포지티브·네거티브 테스트 |
| `phase4-app.txt` | 366 | **문서-앱 불일치 2건**, pkill 자기매치 함정, Boot 5/5 |
| `phase5-monitor.txt` | 250 | monitor.sh 4경로 검증 (정상/경고/실패/로테이션) |
| `phase6-cron.txt` | 429 | cron 자동 누적, **부하 테스트 무효화 원인**, 실부하 CPU 경고 |

## 특히 볼 만한 기록

정상 동작만이 아니라 **실패와 그 원인**이 기록되어 있다.
상세한 서사는 [`../WORKLOG.md`](../WORKLOG.md)에 정리했다.

| 내용 | 파일 |
|---|---|
| `ufw status` 와 `verbose` 의 출력 스키마 차이 | `phase2-ufw.txt` |
| 외부 프로브로 방화벽 실동작 증명 (거부 vs 타임아웃) | `phase2-ufw.txt` |
| 경로 통행권 결함 — 게이트가 PASS 를 준 설계 오류 | `phase3-account-acl.txt` |
| `AGENT_KEY_PATH` 가 디렉토리, 키 파일명이 `secret.key` | `phase4-app.txt` |
| `pkill -f` 자기매치 (4회 반복: Phase 4 1회, Phase 6 2회, Phase 9 1회) | `phase4-app.txt`, `phase6-cron.txt`, `phase9-doc-conformance.txt` |
| 명령 치환이 백그라운드 잡을 기다려 부하 테스트 무효화 | `phase6-cron.txt` |
| 실부하 CPU 51.3% → 기본 임계값 20% 경고 발생 | `phase6-cron.txt` |

---

## 기록 방식

증거는 손으로 복사하지 않았다. `env/rec.sh` 의 헬퍼를 통해 자동 적재된다.

```
### 2026-08-09 22:27:24
$ sshd -T | grep -E '^(port|permitrootlogin) '
port 20022
permitrootlogin no
--- exit=0 ---
```

- `rec` / `recsh` — 명령 + 출력 + 종료코드
- `rec_expect_fail` — 차단되어야 정상인 검증. 성공하면 `FAIL` 로 기록된다
- `rec_note` — 명령이 아닌 판단·맥락

**종료코드를 남기는 이유**는 "명령은 돌았지만 실패했다"를 놓치지 않기 위해서다.
실제로 `pkill -f` 가 실행 중이던 셸 자신을 죽였을 때 `--- exit=143 ---`(SIGTERM)이
그대로 남아(`phase4-app.txt`) 원인이 셸의 자기매치임을 곧바로 짚을 수 있었다.
