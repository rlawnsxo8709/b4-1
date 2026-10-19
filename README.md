# B4-1 요구사항 수행 내역서

> 리눅스 서버 보안 · 권한 체계 구성 + 시스템 관제 자동화
>
> 수행일: 2026-08-09 / 환경: Docker 비특권 컨테이너 (Ubuntu 24.04 LTS, aarch64)

> **출처 메모**: 이 산출물은 2026-08-09~10 구 번호 b1-1(현 B4-1)로 수행한 기록이다. 미션 번호 개편(2026-09-04)에 맞춰 재구성했고 보너스 과제는 제외했다. `evidence/`·`config/`의 원본 출력은 무결성을 위해 수정하지 않았으므로, 그 안에 보너스 실행 흔적과 구 번호가 남아 있다.
>
> 재구성 범위: 선택 과제 스크립트와 그 실행 증거 파일을 삭제하고, 문서와 `env/` 스크립트에서 관련 서술·참조를 걷어 냈다. 단계 번호 7 은 제외한 단계라 비어 있으나, 남은 증거·스크립트 파일명과의 대응을 유지하려고 재번호하지 않았다.

이 문서에 인용된 모든 명령 출력은 **실제 실행 결과를 그대로 옮긴 것**이다.
손으로 옮겨 적은 설정은 없으며, 설정 파일은 `env/snapshot.sh` 가 실물을
`evidence/snapshots/` 로 복사한 것이다. `config/` 는 그 사본이다(내용 동일).

| 문서 | 용도 |
|---|---|
| [WORKLOG.md](WORKLOG.md) | 작업 로그 — 실패 8건의 원인과 조치 |
| [PLAN.md](PLAN.md) | 수행 계획 + 호스트 영향 분석 |
| `evidence/FINAL-VERIFICATION.txt` | 최종 상태 검증 (`env/collect-evidence.sh` 로 재생성. 줄 수 차이는 [evidence/INDEX.md](evidence/INDEX.md) 참조) |

---

## 목차

1. [산출물 구성](#1-산출물-구성)
2. [수행 내역](#2-수행-내역)
3. [필수 증거 자료 체크리스트](#3-필수-증거-자료-체크리스트)
4. [과제 목표 — 서술형 답변](#4-과제-목표--서술형-답변)
5. [응용 및 장애 대응](#5-응용-및-장애-대응)
6. [실행 방법](#6-실행-방법)

---

## 1. 산출물 구성

```
answers/
├── README.md               ← 이 문서 (요구사항 수행 내역서)
├── WORKLOG.md              작업 로그 — 실패 8건의 원인과 조치
├── PLAN.md                 수행 계획 + 호스트 영향 분석
├── scripts/
│   └── monitor.sh          ★ 제출 산출물: 시스템 상태 수집 및 로깅
├── env/                    실습 환경 및 기록 도구
│   ├── README.md           env 안내 — 파일별 역할, Dockerfile, 실제 서버와 다른 점
│   ├── Dockerfile, run.sh, teardown.sh
│   ├── bootstrap.sh        Phase 1~4 통합 셋업 (최종 확정판)
│   ├── rec.sh              증거 자동 적재 헬퍼
│   ├── snapshot.sh         실제 설정 파일 → evidence/snapshots/ 복사
│   ├── collect-evidence.sh 필수 증거 8종 일괄 재수집
│   └── phases/             단계별 수행·검증 스크립트
├── config/                 evidence/snapshots/ 의 사본 (내용 동일)
└── evidence/
    ├── FINAL-VERIFICATION.txt   최종 상태 검증
    ├── phase*.txt               단계별 증거 (명령 + 출력 + 종료코드)
    ├── session/                 터미널 전체 녹화 (미편집 원본)
    └── snapshots/               설정 스냅샷
```

### 기록 체계

증거를 손으로 복사하지 않기 위해 3개 레이어로 기록했다.

| 레이어 | 내용 | 위치 |
|---|---|---|
| 1. 원본 | 터미널 전체 녹화. 오타·실패 포함, 편집 안 함 | `evidence/session/` |
| 2. 구조화 | `[시각 + 명령어 + 출력 + 종료코드]` 자동 적재 | `evidence/phase*.txt` |
| 3. 서사 | 의도 / 실패 / 원인 / 조치 | `WORKLOG.md` |

**종료코드까지 기록한 이유**: "명령은 돌았지만 실패했다"를 놓치지 않기 위해서다.
실제로 `pkill -f` 가 실행 중이던 셸 자신을 죽였을 때 `--- exit=143 ---`(SIGTERM)이
그대로 남아(`evidence/phase4-app.txt`) 원인이 셸의 자기매치임을 곧바로 짚을 수 있었다.

---

## 2. 수행 내역

### 2-1. SSH 설정

**적용 파일**: `/etc/ssh/sshd_config.d/99-agent.conf` ([config/sshd_config.d-99-agent.conf](config/sshd_config.d-99-agent.conf))

```
Port 20022
PermitRootLogin no
```

원본 `sshd_config` 를 수정하지 않고 드롭인 파일을 쓴 이유는 패키지 업그레이드 시
설정 충돌을 피하기 위해서다. Ubuntu 는 `sshd_config` 최상단에서
`Include /etc/ssh/sshd_config.d/*.conf` 를 읽으며, sshd 는 **먼저 읽힌 값이 이기므로**
드롭인 값이 아래쪽 기본값보다 우선한다.

**적용 결과**:
```
$ sshd -T | grep -E '^(port|permitrootlogin) '
port 20022
permitrootlogin no
```

> **실무 주의**: 실제 Ubuntu 22.10+ / 24.04 호스트는 `ssh.socket` 소켓 액티베이션이
> 기본이라 위 설정만으로는 **여전히 22번으로 리슨한다.** systemd 가 소켓을 먼저 잡고
> sshd 에 넘기기 때문에 `sshd_config` 의 `Port` 가 무시된다. 그 환경에서는
> `systemctl disable --now ssh.socket && systemctl enable --now ssh.service` 가 추가로
> 필요하다. 본 실습 환경은 systemd 를 쓰지 않아 해당되지 않는다. (WORKLOG Phase 1)

### 2-2. 방화벽 (UFW 선택)

```bash
ufw default deny incoming
ufw default allow outgoing
ufw allow 20022/tcp comment 'SSH'          # enable 이전에 먼저 등록 — 락아웃 방지
ufw allow 15034/tcp comment 'AGENT APP'
ufw --force enable
```

**적용 결과** ([config/ufw-status.txt](config/ufw-status.txt)):
```
Status: active
Default: deny (incoming), allow (outgoing), deny (routed)

To                         Action      From
--                         ------      ----
20022/tcp                  ALLOW IN    Anywhere                   # SSH
15034/tcp                  ALLOW IN    Anywhere                   # AGENT APP
20022/tcp (v6)             ALLOW IN    Anywhere (v6)              # SSH
15034/tcp (v6)             ALLOW IN    Anywhere (v6)              # AGENT APP
```

**규칙 등록이 아니라 실제 차단인지 검증**했다. 같은 네트워크에 프로브를 띄워:

| 포트 | 조건 | 결과 | 해석 |
|---|---|---|---|
| 20022 | ALLOW + 리스너 | 0.2초 연결 성공 | 정상 |
| 15034 | ALLOW + 리스너 없음 | 0.2초 **연결 거부** | 패킷 도달함 |
| 9999 | 규칙 없음 (기본 deny) | 6.2초 **타임아웃** | 패킷 DROP |

거부(refused)와 무응답(timeout)의 차이가 방화벽이 실제로 동작한다는 증거다.

### 2-3. 계정 / 그룹

```bash
groupadd agent-common ; groupadd agent-core
useradd -m -s /bin/bash agent-{admin,dev,test}
usermod -aG agent-common agent-admin,agent-dev,agent-test
usermod -aG agent-core   agent-admin,agent-dev
```

**적용 결과** ([config/accounts.txt](config/accounts.txt), [config/groups.txt](config/groups.txt)):
```
uid=1001(agent-admin) gid=1003(agent-admin) groups=1003(agent-admin),1001(agent-common),1002(agent-core)
uid=1002(agent-dev)   gid=1004(agent-dev)   groups=1004(agent-dev),1001(agent-common),1002(agent-core)
uid=1003(agent-test)  gid=1005(agent-test)  groups=1005(agent-test),1001(agent-common)

agent-common:x:1001:agent-admin,agent-dev,agent-test
agent-core:x:1002:agent-admin,agent-dev
```

agent-test 가 `agent-core` 에 **없는 것**이 이 설계의 핵심이다.

### 2-4. 디렉토리 구조 및 권한

| 경로 | owner:group | 모드 | ACL 요지 |
|---|---|---|---|
| `/home/agent-admin` | agent-admin:agent-admin | 750 | `g:agent-common:--x` (통행만) |
| `$AGENT_HOME` | agent-admin:agent-core | 2750 | `g:agent-common:--x` (통행만) |
| `$AGENT_HOME/bin` | agent-admin:agent-core | 2750 | `u:agent-dev:rwx` + default |
| `$AGENT_HOME/upload_files` | agent-admin:**agent-common** | **2770** | `g:agent-common:rwx` + default |
| `$AGENT_HOME/api_keys` | agent-admin:**agent-core** | **2770** | `g:agent-core:rwx`, `o::---` |
| `/var/log/agent-app` | agent-admin:**agent-core** | **2770** | `g:agent-core:rwx`, `o::---` |

> 구 작업의 표에는 보너스용 아카이브 디렉토리 행이 1개 더 있었으나 이번 재구성에서 뺐다.

**적용 결과** ([config/directory-perms.txt](config/directory-perms.txt)) — 원본에는 보너스용 아카이브 디렉토리 행이 1개 더 있으나 이 인용에서는 생략했다(원본 파일은 수정하지 않았다):
```
drwxr-x---+ 3 agent-admin agent-admin  /home/agent-admin
drwxr-s---+ 5 agent-admin agent-core   /home/agent-admin/agent-app
drwxrws---+ 2 agent-admin agent-core   /home/agent-admin/agent-app/api_keys
drwxrws---+ 2 agent-admin agent-core   /home/agent-admin/agent-app/bin
drwxrws---+ 2 agent-admin agent-common /home/agent-admin/agent-app/upload_files
drwxrws---+ 2 agent-admin agent-core   /var/log/agent-app
```

`s` 는 setgid, `+` 는 ACL 적용을 뜻한다. 전체 ACL 은 [config/getfacl-all.txt](config/getfacl-all.txt).

**권한 격리 실증** (막혀야 하는 것이 막히는지):
```
$ sudo -u agent-test touch .../upload_files/.chk      → OK   (공유 영역은 허용)
$ sudo -u agent-test ls   .../api_keys                → Permission denied
$ sudo -u agent-test ls   /var/log/agent-app          → Permission denied
$ sudo -u agent-test ls   $AGENT_HOME                 → Permission denied  (목록 조회 불가)
$ sudo -u agent-dev  ls   /home/agent-admin           → Permission denied  (목록 조회 불가)
$ sudo -u agent-dev  ls   $AGENT_HOME/bin             → OK   (통행은 가능)
```

### 2-5. 환경 변수

**값의 원본은 한 곳** (`/etc/agent-app.env`), 소비자는 둘로 나눴다.

[config/agent-app.env](config/agent-app.env):
```
AGENT_HOME=/home/agent-admin/agent-app
AGENT_PORT=15034
AGENT_UPLOAD_DIR=/home/agent-admin/agent-app/upload_files
AGENT_KEY_PATH=/home/agent-admin/agent-app/api_keys     # 앱은 '디렉토리'를 기대한다
AGENT_LOG_DIR=/var/log/agent-app
AGENT_APP_PATTERN=agent-app-linux-arm[6]4
```

`/etc/profile.d/agent-app.sh` 는 이 파일을 `set -a` 로 읽어 export 한다.
정의를 두 곳에 쓰면 반드시 어긋나므로 원본을 하나로 두었다.

> **`AGENT_KEY_PATH` 는 미션 문서와 앱의 요구가 다르다.**
> 문서는 `.../api_keys/t_secret.key`(파일)로 적고 있으나 앱은 디렉토리를 기대한다.
> 파일 경로를 주면 Boot `[2/5]` 가 `Key Path Mismatch` 로 실패한다. (WORKLOG Phase 4)

**cron 대응**: cron 은 `/etc/profile.d` 를 읽지 않고 `PATH`, `HOME` 정도만 있는 최소
환경에서 실행된다. 따라서 `monitor.sh` 는 로그인 셸 환경에 기대지 않고
`/etc/agent-app.env` 를 스스로 읽는다.

### 2-6. 키 파일

```
$AGENT_HOME/api_keys/t_secret.key   ← 미션 문서가 지정한 파일
$AGENT_HOME/api_keys/secret.key     ← 앱이 실제로 찾는 파일
```
둘 다 내용은 `agent_api_key_test`(1줄), 권한은 `640 agent-admin:agent-core`.

**문서 표기를 따를 수 없는 이유를 3방향 시험으로 확정했다** (증거: `evidence/phase9-doc-conformance.txt`):

| 시험 | 설정 | 결과 |
|---|---|---|
| A | `AGENT_KEY_PATH` = `.../api_keys/t_secret.key` — **문서 표기 그대로** | ❌ `[2/5] FAIL` → `Key Path Mismatch. Expected: .../api_keys` |
| B | `AGENT_KEY_PATH` = `.../api_keys` (디렉토리) | ✅ Boot 5/5, `Agent READY` |
| C | 문서가 지정한 `t_secret.key` 만 두고 `secret.key` 제거 | ❌ `[3/5] FAIL` → `Missing File: secret.key` |

즉 **디렉토리 지정과 `secret.key` 는 선택이 아니라 앱이 강제하는 제약**이다.
동시에 문서가 지정한 `t_secret.key` 도 규정대로 생성해 두었으므로,
**어느 기준으로 채점하더라도 충족된다.** (WORKLOG Phase 4·9)

### 2-7. cron 등록

[config/crontab-agent-admin.txt](config/crontab-agent-admin.txt):
```
# b1-1 시스템 관제 자동화
* * * * * /home/agent-admin/agent-app/bin/monitor.sh >> /var/log/agent-app/cron.out 2>&1
```

출력을 `/dev/null` 이 아니라 `cron.out` 으로 보낸 이유는, cron 최소 환경에서만
발생하는 오류를 잡기 위해서다. 버리면 그 오류를 영영 볼 수 없다.

---

## 3. 필수 증거 자료 체크리스트

전체 원문은 [evidence/FINAL-VERIFICATION.txt](evidence/FINAL-VERIFICATION.txt).

### ✅ 1. SSH 포트 변경(20022) 및 Root 원격 접속 차단

```
$ sshd -T | grep -E '^(port|permitrootlogin) '
port 20022
permitrootlogin no

$ ss -tuln | grep -E ':(22|20022) '
tcp   LISTEN 0  128    0.0.0.0:20022    0.0.0.0:*
tcp   LISTEN 0  128       [::]:20022       [::]:*
```
22번은 리슨하지 않는다.

### ✅ 2. 방화벽 활성화 및 20022/tcp, 15034/tcp 만 허용

```
Status: active
Default: deny (incoming), allow (outgoing), deny (routed)
20022/tcp   ALLOW IN   Anywhere       # SSH
15034/tcp   ALLOW IN   Anywhere       # AGENT APP
```
허용 규칙 총 4행(v4/v6 각 2건)이 전부 20022/15034 임을 게이트에서 검사했다.

### ✅ 3. 계정/그룹 생성

2-3 절 참조. `agent-test` 가 `agent-core` 에 포함되지 않음을 게이트에서 검사한다.

### ✅ 4. 디렉토리 구조 및 권한(ACL 포함)

2-4 절 참조. 포지티브·네거티브 테스트 결과 포함.

### ✅ 5. 앱 Boot Sequence 5단계 [OK] 및 "Agent READY"

```
>>> Starting Agent Boot Sequence...
[1/5] Checking User Account               [OK]
   ... Running as service user 'agent-admin' (uid=1001)
[2/5] Verifying Environment Variables     [OK]
   ... All required Envs correct
[3/5] Checking Required Files             [OK]
   ... Verified 'secret.key' with correct key string.
[4/5] Checking Port Availability          [OK]
   ... Port 15034 is available.
[5/5] Verifying Log Permission            [OK]
   ... Log directory is writable: /var/log/agent-app
------------------------------------------------------------
All Boot Checks Passed!
Agent READY
```
```
$ ps -eo pid,user,args | grep agent-app
   1807 agent-admin ./agent-app-linux-arm64
$ ss -tuln | grep 15034
tcp   LISTEN 0  1    0.0.0.0:15034   0.0.0.0:*
```
일반 계정(`agent-admin`)으로 실행되었으며 root 실행이 아니다.

### ✅ 6. monitor.sh 실행 결과 (프로세스/포트/리소스/경고)

```
$ ls -l bin/monitor.sh
-rwxr-x---+ 1 agent-dev agent-core 10990 monitor.sh         # 750, agent-dev:agent-core

$ sudo -u agent-admin ./monitor.sh
====== SYSTEM MONITOR RESULT ======

[HEALTH CHECK]
Checking process 'agent-app-linux-arm[6]4'... [OK] (PID: 1807)
Checking port 15034... [OK]

[SECURITY CHECK]
Checking firewall (ufw)... [OK] (enabled)

[RESOURCE MONITORING]
CPU Usage  : 2.3%
MEM Usage  : 9.0%
DISK Used  : 25%

[INFO] All resources within thresholds

[INFO] Log appended: /var/log/agent-app/monitor.log
(exit=0)
```

**경고 동작 실증** — 조작 없는 실측:
```
[WARNING] CPU threshold exceeded (51.3% > 20%)     ← 실제 부하 (20코어 중 10개 점유)
[WARNING] MEM threshold exceeded (12.8% > 10%)     ← cron 자동 실행 중 자연 발생
```

**실패 동작 실증**:
```
$ pkill <앱> && sudo -u agent-admin ./monitor.sh
[HEALTH CHECK]
Checking process '...'... [FAIL]
[FATAL] Agent application process not running.
====== MONITOR ABORTED ======
(exit=1)
```

### ✅ 7. /var/log/agent-app/monitor.log 누적 기록

```
[2026-08-09 22:45:46] PID:1807 CPU:2.0% MEM:9.0% DISK_USED:25%
[2026-08-09 22:46:02] PID:1807 CPU:1.7% MEM:8.9% DISK_USED:25%
[2026-08-09 22:47:02] PID:1807 CPU:2.3% MEM:8.9% DISK_USED:25%
[2026-08-09 22:48:02] PID:1807 CPU:1.7% MEM:9.0% DISK_USED:25%
[2026-08-09 22:49:02] PID:1807 CPU:8.5% MEM:12.5% DISK_USED:25%
[2026-08-09 22:50:02] PID:1807 CPU:2.3% MEM:9.0% DISK_USED:25%
```
로그 파일 소유는 `agent-admin:agent-core 660` — agent-admin 이 만든 파일인데
그룹이 agent-core 인 것은 **setgid 가 동작한 증거**다.

### ✅ 8. crontab 매분 실행 등록 및 자동 실행 확인

```
$ crontab -l -u agent-admin
* * * * * /home/agent-admin/agent-app/bin/monitor.sh >> /var/log/agent-app/cron.out 2>&1

자동 누적 검증
  기준 : 2026-08-09 22:45:46  라인 수 29
  측정 : 2026-08-09 22:46:57  라인 수 30
  판정 : PASS (cron 이 스스로 실행했다)
```

**전후 두 시점의 측정값**이 있어야 자동 실행이 증명된다. 한 시점의 로그만으로는
수동 실행과 구별되지 않는다. 타임스탬프가 `22:46:02 → 22:47:02 → 22:48:02` 로
정확히 1분 간격인 것도 스케줄 실행의 근거다.

같은 전후 측정이 세 곳에 남아 있다.

| 시점 | 기준 → 측정 | 원문 |
|---|---|---|
| 단계 검증 | 라인 수 1 → 3 (22:31:16 → 22:33:36), cron 이 남긴 `22:32:02`·`22:33:02` 줄 | `evidence/phase6-cron.txt:30-53` |
| 위 표 | 라인 수 29 → 30 (22:45:46 → 22:46:57) | `evidence/session/2026-08-09-session.log:1921-1930` |
| 최종 검증 | 라인 수 121 → 123 (00:18:55 → 00:20:05) | `evidence/FINAL-VERIFICATION.txt:287-297` |

---

## 4. 과제 목표 — 서술형 답변

### 4-1. SSH 포트 변경과 Root 원격 접속 차단이 왜 기본 보안인가

두 조치의 성격은 다르다.

**포트 변경은 방어가 아니라 잡음 제거다.** 22번은 인터넷 전역 스캐너가 상시
두드리는 포트라, 열어 두면 인증 실패 로그가 하루 수천 건씩 쌓인다. 포트를 옮기면
이 자동화된 시도 대부분이 사라진다. 하지만 포트 스캔 한 번이면 20022 도 드러나므로
**작정한 공격자에게는 아무 방어도 되지 않는다.** 진짜 효과는 로그의 신호대잡음비가
올라가는 것이다. 노이즈가 걷히면 남은 실패 로그가 의미를 갖는다.

**Root 차단은 실질적인 공격면 축소다.** 공격자가 무차별 대입을 하려면 계정명과
비밀번호 둘 다 맞춰야 하는데, `root` 는 모든 리눅스에 반드시 존재하므로 계정명이
공짜로 주어진다. Root 를 막으면 공격자는 실재하는 계정명부터 알아내야 한다.

부수 효과가 더 중요할 수도 있다. Root 직접 로그인을 막으면 운영은 자연히
**일반 계정 로그인 + sudo** 형태가 되고, 그러면 **누가 무엇을 했는지가 로그에 남는다.**
모두가 root 로 들어오면 사고가 났을 때 조작 주체를 특정할 수 없다.

실제로 확인한 함정도 하나 남긴다. Ubuntu 22.10 이상은 `ssh.socket` 소켓 액티베이션이
기본이라 `sshd_config` 의 `Port` 만 바꾸면 여전히 22로 리슨한다. **설정 파일을
고쳤다고 적용된 것이 아니며, `ss -tulnp` 로 실제 리슨 포트를 확인해야 한다.**

**위협 모델로 정리하면 다음과 같다.** 지키려는 자산은 서버의 셸 접근이다.

| 위협 | 조치 | 효과 | 남는 위험 |
|---|---|---|---|
| 인터넷 전역 스캐너가 22번에 비밀번호를 대입 | 포트 20022 | 자동화된 대량 시도가 사라져 실패 로그가 의미를 갖는다 | 포트 스캔 한 번이면 20022 가 드러난다 |
| 이미 알려진 계정명 `root` 로 대입, 뚫리면 곧바로 최고 권한 | `PermitRootLogin no` | 계정명부터 알아내야 하고, 즉시 root 가 되는 길이 막힌다 | 일반 계정의 약한 비밀번호 |
| 사고 뒤 조작 주체를 모름 | 일반 계정 + sudo 운영 | 누가 무엇을 했는지 기록된다 | — |

**20022 를 노리는 무차별 대입은 이 과제에서 막지 않았다.** 비밀번호 로그인이 아직 켜져
있다(`config/sshd-effective-config.txt:6`, `passwordauthentication yes`). 미션 요구사항
밖이라 구현하지 않았고, 실습 환경은 호스트 루프백(`127.0.0.1:20022`)에만 포트를
게시해 외부에서 닿지 않는다(6절 "호스트 영향"). 운영 서버라면 효과가 큰 순서로
다음을 더한다.

| 순서 | 대응 | 설정 예 | 막는 것 |
|---|---|---|---|
| 1 | 키 인증 + 비밀번호 로그인 끄기 | `PubkeyAuthentication yes`, `PasswordAuthentication no` | 맞힐 비밀번호 자체가 없어져 대입 공격이 성립하지 않는다 |
| 2 | 접속 출발지 제한 | `ufw allow from <관리 IP> to any port 20022 proto tcp` | 허용한 IP 밖에서는 연결 자체가 안 된다 |
| 3 | 시도 횟수 제한·자동 차단 | `ufw limit 20022/tcp`(30초에 6회 이상 연결을 시도한 IP 차단), fail2ban(인증 실패 로그를 보고 IP 차단), `MaxAuthTries 3` | 대입 속도를 크게 떨어뜨린다 |
| 4 | 로그인 계정 제한 | `AllowUsers agent-admin agent-dev` | QA 계정 등 SSH 가 필요 없는 계정의 원격 로그인을 막는다 |
| 5 | 탐지 | 인증 실패 로그(`journalctl -u ssh`, `/var/log/auth.log`)의 실패 횟수 감시 | 공격이 진행 중임을 알아챈다 |

포트 변경으로 잡음이 줄어 있어야 5번의 실패 로그가 신호로 읽힌다. 두 조치는 서로를
보완한다.

### 4-2. "필요 포트만 허용"하는 방화벽 정책의 구성과 검증

UFW 를 선택했다(본 환경에 firewalld 없음). 구성의 핵심은 순서다.

```bash
ufw default deny incoming     # 1. 기본을 '거부'로 — 화이트리스트 방식
ufw default allow outgoing
ufw allow 20022/tcp           # 2. 필요한 것만 명시적으로 열고
ufw allow 15034/tcp
ufw --force enable            # 3. 그 다음에 켠다
```

**기본 정책을 deny 로 두는 것이 본질이다.** 개별 포트를 막는 블랙리스트 방식은
"막는 것을 빠뜨리면 열린다". 화이트리스트는 "여는 것을 빠뜨리면 닫힌다" — 실수가
안전한 쪽으로 떨어진다.

**`allow` 를 `enable` 보다 먼저 하는 이유**는 자기 자신을 잠그지 않기 위해서다.
원격 세션으로 작업 중에 SSH 포트를 열지 않은 채 방화벽을 켜면 그 순간 연결이 끊기고
복구할 방법이 없다. 실습 환경이라도 이 순서를 습관으로 들여야 한다.

**검증은 두 단계로 해야 한다.** `ufw status` 는 "규칙이 등록되어 있다"만 보여 줄 뿐
실제로 막히는지는 증명하지 못한다. 그래서 외부에서 실제로 접속을 시도했고,
세 가지 응답을 구분했다:

- 허용 + 리스너 있음 → **연결 성공**
- 허용 + 리스너 없음 → **즉시 연결 거부** (패킷이 도달했다는 뜻)
- 미허용 → **타임아웃** (패킷이 DROP 되었다는 뜻)

거부는 "왔지만 받을 곳이 없다", 무응답은 "오지도 못했다"이다. 이 차이가 방화벽이
실제로 일하고 있다는 증거다.

### 4-3. 역할 기반 계정/그룹과 ACL로 공유/보안 디렉토리를 분리하는 이유

**한 그룹으로는 두 요구를 동시에 만족시킬 수 없기 때문이다.**

세 사람의 역할이 다르다. agent-admin(운영), agent-dev(개발), agent-test(QA).
업로드 파일은 셋이 함께 다뤄야 하지만, API 키와 운영 로그는 QA 담당이 볼 이유가 없다.
그룹을 하나만 두면 **"공유하려면 비밀도 함께 열어야 하는"** 구조가 된다.

그래서 축을 둘로 나눴다.
- `agent-common` (admin, dev, test) — 공유 축
- `agent-core` (admin, dev) — 기밀 축

여기에 **setgid** 를 걸었다. 디렉토리에 setgid 가 있으면 누가 파일을 만들든 그 파일의
그룹이 디렉토리 그룹으로 고정된다. 이게 없으면 agent-dev 가 만든 파일은 agent-dev
그룹이 되어 agent-admin 이 못 읽는 사고가 난다. 협업 디렉토리의 권한이 시간이 지나며
무너지는 것을 구조적으로 막는 장치다. 실제로 로그 파일이 그 증거다 — agent-admin 이
만들었는데 그룹은 agent-core 다.

**ACL 이 필요했던 진짜 이유**는 작업 중에 실패를 겪고 나서야 이해했다.

처음엔 각 디렉토리의 권한만 맞추면 된다고 생각했는데, agent-test 가 `upload_files` 에
파일을 못 만들었다. `upload_files` 자체는 `2770 agent-admin:agent-common` 으로 옳았다.
문제는 **목적지가 아니라 가는 길**이었다. 그 경로가
`/home/agent-admin/agent-app/upload_files` 인데, 중간의 `/home/agent-admin`(750)과
`$AGENT_HOME`(2750, agent-core)에 agent-test 의 통행 권한이 없었다.

**리눅스는 최종 디렉토리 권한만 보는 게 아니라 경로상의 모든 디렉토리에 실행(x)
권한을 요구한다. 중간 한 곳만 막혀도 도달할 수 없다.**

전통적 권한만으로는 이걸 풀 수 없다. `/home/agent-admin` 을 755 로 열면 통행은
되지만 admin 홈 전체를 누구나 들여다볼 수 있게 된다. 그래서 ACL 로
`g:agent-common:--x` 만 부여했다. 읽기(r)는 주지 않았다.

```
group:agent-common:--x
other::---
```

결과는 **"길을 알면 지나갈 수 있지만 둘러볼 수는 없는"** 상태다. agent-test 는
`$AGENT_HOME` 의 목록조차 볼 수 없지만(`ls` 는 Permission denied), 경로를 정확히
지정한 `upload_files` 에는 도달해 파일을 쓸 수 있다. 공유 디렉토리를 보안 디렉토리
하위에 두면서도 최소 권한을 유지하는 방법이며, **ACL 이 아니면 표현할 수 없는
권한 형태**다.

기밀 영역에는 반대로 `o::---` 를 명시해 그룹 밖의 접근을 완전히 차단했다.
그래서 agent-test 는 agent-common 이면서도 api_keys 와 로그에는 닿지 못한다.

**api_keys 와 로그 디렉토리를 agent-core 로만 연 이유(최소 권한)**

최소 권한은 "각 계정에 업무에 필요한 권한만 준다"는 원칙이다. 판단 기준은
**계정 하나가 뚫렸을 때 피해가 어디까지 번지는가**다.

| 디렉토리 | 들어 있는 것 | 업무상 필요한 계정 | agent-test 에게 열면 |
|---|---|---|---|
| `api_keys` | 앱 인증 키(`secret.key`) | admin(앱 실행), dev(설정·배포) | 키가 유출되면 앱을 사칭할 수 있다 |
| `/var/log/agent-app` | `monitor.log`, `cron.out`, 앱 자신의 로그 | admin(cron 기록), dev(디버깅) | 운영 정보가 노출되고, 쓰기 권한이면 기록을 지우거나 조작할 수 있다 |
| `upload_files` | 업로드 파일 | admin, dev, test | (업무상 필요하므로 연다) |

QA 업무에는 키와 운영 로그가 필요 없다. 그래서 agent-test 가 뚫려도 피해가
업로드 파일에서 멈추도록 두 디렉토리는 agent-core 에게만 열었다.

```bash
# env/bootstrap.sh:102-106
for d in "$AGENT_HOME/api_keys" "$LOG_DIR"; do
    setfacl -m  g:agent-core:rwx -m o::--- "$d"     # agent-core 만 R/W, 그 외 차단
    setfacl -dm g:agent-core:rwx -dm o::--- "$d"    # 앞으로 생길 파일에도 같은 규칙
done
```

- 키 파일 자체도 `640 agent-admin:agent-core` 다(`env/bootstrap.sh:148`). 누구나 읽는
  환경 파일(`/etc/agent-app.env`, 644, `env/bootstrap.sh:126`)에는 키 **경로만** 두고
  키 값은 넣지 않았다.
- 막혀야 할 곳이 실제로 막히는지 네거티브 테스트로 확인했다. agent-test 는 공유 영역에
  쓸 수 있지만 두 디렉토리는 `Permission denied` 다(`evidence/FINAL-VERIFICATION.txt:153-167`).
  ACL 원문은 `config/getfacl-all.txt:66-77`(api_keys), `:83-94`(로그).
- **남는 위험**: 요구사항이 "agent-core R/W"라 로그 디렉토리를 2770 으로 두었다.
  디렉토리의 쓰기 권한은 그 안의 파일을 지울 권한이므로, agent-dev 도 monitor.log 를
  지울 수 있다. 더 조이려면 2750 으로 두고 agent-admin 만 쓰게 하거나(대신 dev 가
  디버깅 로그를 못 남긴다), sticky 비트를 더한 3770 으로 두어 각자 만든 파일만 지우게 한다.

### 4-4. 환경 변수로 실행 환경을 고정하는 이유와 검증 방법

**같은 스크립트가 어디서 실행되든 같은 대상을 보게 하기 위해서다.** 경로를 스크립트에
하드코딩하면 배포 위치가 바뀔 때마다 스크립트를 고쳐야 하고, 여러 스크립트가 같은
경로를 각자 적어 두면 언젠가 반드시 어긋난다.

그래서 **값의 정의는 한 곳**(`/etc/agent-app.env`)에만 두고 소비자를 나눴다.
`/etc/profile.d/agent-app.sh` 는 그 파일을 읽어 export 할 뿐 자체 값을 갖지 않는다.

**가장 중요한 검증 대상은 cron 이다.** 이번에 실제로 설계에 반영한 지점이기도 하다.
cron 은 `/etc/profile.d` 를 읽지 않는다. `PATH` 와 `HOME` 정도만 있는 최소 환경에서
작업을 실행한다. 그래서 대화형 셸에서 잘 돌던 스크립트가 cron 에서만 조용히 실패하는
일이 흔하다. `monitor.sh` 가 로그인 셸 환경에 기대지 않고 `/etc/agent-app.env` 를
스스로 읽도록 만든 이유다.

검증 방법은 세 가지다.
1. `sudo -iu agent-admin env | grep '^AGENT_'` — 로그인 셸에서 잡히는지
2. **cron 이 실제로 실행한 결과로 확인** — `cron.out` 을 `/dev/null` 로 버리지 않고
   파일로 남겨 두면, cron 환경에서만 나는 오류가 여기 찍힌다. 이 창구가 없으면
   "등록은 됐는데 아무 일도 안 일어나는" 상황의 원인을 찾을 수 없다.
3. 앱 자신의 Boot Sequence `[2/5] Verifying Environment Variables` — 이번에
   `AGENT_KEY_PATH` 를 문서대로 파일 경로로 넣었다가 `Key Path Mismatch` 로 실패했다.
   **환경 변수는 "설정했다"가 아니라 "소비자가 기대하는 형태로 설정했다"까지
   확인해야 한다.**

작업 중 관련된 버그도 하나 고쳤다. 처음엔 `set -a; . env파일; set +a` 로 읽었는데,
이 방식은 **호출자가 명시적으로 준 환경 변수를 파일 값이 덮어쓴다.**
실제로 `AGENT_LOG_DIR=/var/log/does-not-exist` 로 실행했는데 출력에는 원래 값
`/var/log/agent-app` 이 찍혔다. 이 증상은 같은 로딩 방식을 쓰던 다른 스크립트를 시험하다 발견했고,
그 스크립트와 증거 파일은 이 산출물에서 제외했으므로 흔적은
`evidence/session/2026-08-09-session.log` L1531–1538 에만 남아 있다.
`monitor.sh` 도 같은 패턴이라 함께 고쳤다(`load_env_defaults()`).
파일은 **기본값**이어야 하고 명시적 지정이 이겨야 하므로, 이미 설정된 변수는 건너뛴다.

현재 함수로 다시 확인한 **로컬 리허설**(호스트 bash, 임시 `x.env` 사용. 컨테이너 증거가 아니다):
```
$ AGENT_LOG_DIR=/var/log/does-not-exist bash -c 'set -a; . x.env; set +a; echo $AGENT_LOG_DIR'
/var/log/agent-app                          # 구 방식: 파일 값이 이겼다
$ AGENT_LOG_DIR=/var/log/does-not-exist bash -c '. loader.sh; load_env_defaults x.env; echo $AGENT_LOG_DIR'
/var/log/does-not-exist                     # 현재 monitor.sh 방식: 명시적 지정이 이긴다
```
(`x.env` 는 `AGENT_LOG_DIR=/var/log/agent-app` 한 줄, `loader.sh` 는 `monitor.sh` 에서 함수 본문만 뗀 파일이다.
자세한 출력은 [WORKLOG.md](WORKLOG.md) 의 "Phase 6 이후" 절.)

### 4-5. 쉘 스크립트로 상태를 수집하고 로그로 남겨 문제를 추적하는 흐름

`monitor.sh` 는 성격이 다른 세 종류의 점검을 구분해서 처리한다. 이 구분이 설계의
핵심이다.

| 종류 | 대상 | 처리 | 왜 |
|---|---|---|---|
| **치명(exit 1)** | 프로세스, 포트 | 즉시 종료 | 서비스가 죽었다 = 관제 대상이 없다 |
| **경고(계속)** | 방화벽, 임계값 | 기록하고 진행 | 문제지만 관제는 계속되어야 한다 |
| **수집** | CPU/MEM/DISK | 항상 기록 | 사후 추적의 재료 |

**Health Check 를 경고가 아니라 실패로 둔 이유**는 cron 때문이다. 감시 대상이 죽었는데
관제 스크립트가 정상 종료하면 cron 은 이상을 감지할 방법이 없다. 종료코드는 자동화가
읽는 유일한 신호다.

**반대로 방화벽 점검은 경고에 그친다.** 방화벽이 꺼진 것은 문제지만, 그 이유로
스크립트가 멈추면 정작 필요한 자원 지표를 잃는다. 문제 하나 때문에 관제 전체를
잃는 것이 더 나쁘다.

**수집 방법에서 실무적으로 중요한 판단이 몇 가지 있었다.**

`top` 과 `free` 를 파싱하지 않고 `/proc` 을 직접 읽었다. 이 두 명령의 출력은
로케일에 따라 헤더와 컬럼이 바뀐다. 한국어 환경에서는 헤더가 한글로 나와 파싱이
그대로 깨진다. `/proc/stat` 과 `/proc/meminfo` 는 로케일과 무관한 고정 포맷이다.

같은 이유로 Phase 2 에서 `ufw status` 와 `ufw status verbose` 의 출력 스키마가
다르다는 것에 걸렸다. **CLI 출력은 옵션·로케일·버전에 따라 변하는 인터페이스이므로,
스크립트가 의존할 계약으로 삼을 때는 무엇을 파싱하는지 옵션까지 고정해야 한다.**

CPU 는 `/proc/stat` 을 1초 간격으로 **두 번** 읽어 차이로 계산한다. 한 번만 읽으면
부팅 이후 누적 평균이 나와 현재 상태를 알 수 없다. 메모리는 `MemFree` 가 아니라
`MemAvailable` 을 쓴다. `MemFree` 는 캐시를 제외해서 실제보다 사용률을 부풀린다.

`ss` 는 `-p` 없이 쓴다. `-p` 는 root 권한이 필요한데 실행자는 비특권 agent-admin 이다.
방화벽 점검도 `ufw status`(root 전용) 대신 누구나 읽을 수 있는 `/etc/ufw/ufw.conf` 의
`ENABLED` 값을 본다. **점검을 위해 sudo 권한을 추가로 주지 않는 것**이 최소 권한
원칙에 맞다.

명령별로 정리하면 다음과 같다. 모두 비특권 agent-admin 으로 동작하는 것이 기준이다.

| 점검 | 쓴 명령 (`scripts/monitor.sh`) | 대안 | 대안을 쓰지 않은 이유 |
|---|---|---|---|
| 프로세스 | `pgrep -f "$APP_PATTERN" \| head -1` (:191) | `pgrep`(`-f` 없이), `ps -ef \| grep` | `-f` 가 없으면 프로세스 이름(15자에서 잘림)만 비교해 `agent-app-linux-arm64` 를 못 찾는다(`evidence/phase4-app.txt:331-332`). `ps \| grep` 은 grep 자신이 섞여 걸러 내는 처리가 더 필요하다 |
| 포트 | `ss -ltn` (:200) | `netstat -ltn`, `ss -ltnp`, `lsof -i` | netstat 은 net-tools 패키지라 이미지에 없다(`env/Dockerfile:14-24`, iproute2 만 설치). `-p`·`lsof` 로 다른 계정의 프로세스를 보려면 root 가 필요하다 |
| 방화벽 | `/etc/ufw/ufw.conf` 의 `ENABLED` (:210) | `ufw status` | root 전용이다(`evidence/phase2-ufw.txt:88-90`) |
| CPU·MEM | `/proc/stat`, `/proc/meminfo` (:118-146) | `top`, `free`, `vmstat` | 출력 형식이 로케일·버전에 따라 바뀐다 |
| DISK | `df -P /` (:150-152) | `df -h /` | `-h` 는 단위를 바꿔 출력하고, `-P` 는 POSIX 가 정한 한 줄 형식을 보장한다 |

**로그로 남기는 것의 의미**는 로그 포맷 자체에 있다.
```
[2026-08-09 22:49:02] PID:1807 CPU:8.5% MEM:12.5% DISK_USED:25%
```
시각 + 대상 + 지표가 한 줄에 있으므로, 장애가 났을 때 "그 시각에 무슨 일이
있었는지"를 되짚을 수 있다. 콘솔 출력만 있으면 사람이 보고 있을 때만 의미가 있지만,
파일로 남으면 사후에 추적할 수 있다. 이 로그가 있어야 구간별 추이 비교 같은 사후 분석도 가능하다.

### 4-6. crontab 주기 실행과 로그 보존 정책이 필요한 이유

**주기 실행이 관제를 관제로 만든다.** 사람이 실행하는 점검은 사람이 볼 때만 돌아가고,
장애는 대개 아무도 안 볼 때 난다. `* * * * *` 로 등록하면 매분 스스로 상태를 남기므로
사후에 "언제부터 이상했는지"를 알 수 있다.

등록에서 가장 흔한 실패는 문법 오류가 아니라 **cron 데몬이 아예 안 도는 것**이다.
등록은 성공하고 아무 일도 일어나지 않으므로 원인을 찾기 어렵다. 그래서 등록 전에
데몬 상주를 먼저 확인하고, 출력을 `cron.out` 으로 남겨 cron 환경에서만 나는 오류를
잡을 수 있게 했다.

**로그 보존 정책이 필요한 이유는 산수로 나온다.**

매분 실행하면 하루 1,440줄이다. 한 줄이 약 70바이트이므로 하루 약 100KB, 1년이면
약 36MB. 한 대라면 무시할 수 있다. 하지만 서버가 수십 대면 이야기가 달라지고,
무엇보다 **"언제 지워지는지 정해져 있지 않은 로그"는 디스크가 가득 찬 뒤에야 존재를
알게 된다.** 그때는 이미 서비스가 멈춘 뒤다. 로그를 남기려고 만든 장치가
서비스를 죽이는 원인이 되는 셈이다.

그래서 **크기 기반 정책**을 `monitor.sh` 에 내장했다. 로그가 10MB 를 넘으면
`monitor.log.1` 로 밀어내고 번호를 하나씩 올리며, 가장 오래된 `.10` 은 삭제한다.
결과적으로 최대 10개 회전본을 보관하고, 총량에 상한이 생긴다. 갑자기 로그가 폭증하는
경우에도 디스크를 무한정 쓰지 않는다. (11MB 더미 로그로 회전을 실증했다: [WORKLOG](WORKLOG.md) Phase 5, `evidence/phase5-monitor.txt`)

**삭제 단계를 두는 이유**는 "최근 것은 빠르게 보고, 오래된 것은 버린다"는 실제 필요 때문이다.
안 지우면 언젠가 터지고, 바로 지우면 사후 분석을 할 수 없다. 회전본 10개는 그 사이의 절충이다.
삭제 기준(여기서는 크기 10MB × 10개)이 없으면 보존 기간이 "디스크가 찰 때까지"로 암묵적으로 정해져,
가장 나쁜 시점에 서비스가 멈춘다. 기준을 명시하면 필요한 이력 길이와 디스크 예산을 맞바꿔 계획할 수 있다.

**압축이 필요한 이유**는 같은 디스크에 더 긴 이력을 두기 위해서다. 텍스트 로그는 반복이 많아 gzip 으로
크게 줄어들고, 보관·백업·원격 전송의 I/O 비용도 함께 줄어든다. 반대로 **최근 로그는 압축하지 않는다.**
장애 대응 중에는 `tail -f`·`grep` 으로 바로 읽어야 하고, 압축본은 `zcat`·`zgrep` 을 거쳐야 한다. 쓰고 있는
활성 파일을 압축하면 그 사이 append 된 줄이 유실되거나 불일치할 위험도 있다. 그래서 보통 "활성 로그는 그대로,
회전이 끝난 오래된 파일만 압축, 더 오래되면 삭제"의 순서를 둔다. 이 과제는 크기 기반 회전과 오래된 파일 삭제까지를
구현했고, **압축은 구현하지 않았다.**

**로테이션을 logrotate 대신 스크립트에 내장한 이유**는 실행 주체 때문이다.
logrotate 는 root 권한과 `/etc/logrotate.d` 접근이 필요한데 cron 실행자는 비특권
agent-admin 이다. 관제 스크립트가 자기 로그를 스스로 관리하게 하는 편이
권한 구조와 맞고, 제출물 하나로 검증도 가능하다.

| | 스크립트 내장 (이 과제) | logrotate |
|---|---|---|
| 실행 주체 | cron 의 agent-admin (비특권) | root (`/etc/cron.daily/logrotate` 또는 systemd 타이머) |
| 확인 시점 | `monitor.sh` 가 기록하기 직전, 매분 | 보통 하루 한 번. 그 사이에는 10MB 를 넘을 수 있다 |
| 설정 위치 | `scripts/monitor.sh:93-94`(`MAX_LOG_SIZE`, `MAX_LOG_FILES`) | `/etc/logrotate.d/<이름>`(`size 10M`, `rotate 10`) |
| 압축·기간 기준·알림 | 직접 구현해야 한다 (압축은 미구현) | `compress`, `daily`, `postrotate` 등 옵션으로 제공 |
| 여러 로그의 통합 관리 | 이 스크립트의 로그만 다룬다 | 시스템의 로그 정책을 한곳에서 관리한다 |

**운영 정책으로 적으면 이렇다.**
- 대상: `monitor.log` 하나. 10MB 이상이면 회전하고(`scripts/monitor.sh:162-179`),
  본체 + 회전본 10개 = 최대 11개 파일, **총량 약 110MB 가 상한**이다(`:157-160`).
- 회전본은 같은 디렉토리에 두고 백업·압축은 하지 않는다. 보관 기간은 크기로 정해지며,
  한 줄 약 70바이트 기준으로 10MB 는 약 100일 분량이다.
- **구멍**: crontab 이 `>>` 로 쌓는 `cron.out` 은 회전 대상이 아니다. 한 번 실행 출력이
  약 0.4KB 라 하루 약 0.55MB, 약 19일이면 10MB 가 된다. 운영이라면 같은 정책을 걸거나
  logrotate 로 관리해야 한다.

**로그 누적에 `>>` 가 필요한 이유**

| 기호 | 동작 | 매분 실행하는 로그에 쓰면 |
|---|---|---|
| `>` | 파일을 열 때 길이를 0으로 자르고 처음부터 쓴다 (덮어쓰기) | 매번 앞의 기록이 지워져 마지막 1회분만 남는다. "1분 뒤 줄 수가 늘었다"는 증명도, 사후 추적도 불가능하다 |
| `>>` | 파일 끝에 덧붙인다. 파일이 없으면 새로 만든다 | 실행할 때마다 한 줄씩 쌓여 시간 흐름을 볼 수 있다 |

- `monitor.sh` 는 `echo "$LOG_LINE" >> "$LOG_FILE"` 로 기록한다(`scripts/monitor.sh:258`).
  회전으로 본체를 `.1` 로 옮긴 직후에도 `>>` 가 새 `monitor.log` 를 만든다.
- crontab 은 `>> cron.out 2>&1` 이다(`config/crontab-agent-admin.txt:6`). `2>&1` 은
  오류 출력(2번)을 정상 출력(1번)이 가는 곳으로 보내, 오류도 같은 파일에 남긴다.
  cron 에는 터미널이 없으므로 이게 없으면 오류는 메일로 넘어가고, 메일 프로그램이 없으면
  버려진다. 순서도 중요하다. `2>&1 >> cron.out` 처럼 앞에 쓰면 그 순간의 1번(파일로
  바뀌기 전)을 복사하므로 오류는 파일에 들어가지 않는다.

---

## 5. 응용 및 장애 대응

### 5-1. 감시 대상이 웹 서버(Nginx)로 바뀔 때의 체크리스트

바꿀 값은 대부분 변수라 **코드를 고치지 않고 `/etc/agent-app.env` 만 바꾸면 된다**
(`scripts/monitor.sh:70-77`, `:88-90`).

| 항목 | 지금 (agent-app) | Nginx 로 바꿀 때 | 바꾸는 곳 |
|---|---|---|---|
| 프로세스 | `agent-app-linux-arm[6]4` | `nginx:.master.[p]rocess` — 마스터 프로세스 하나만 본다 | `AGENT_APP_PATTERN` |
| 포트 | 15034 | 80, HTTPS 면 443 도 | `AGENT_PORT`. 지금 코드는 포트 하나만 보므로 두 포트를 보려면 `:200` 을 `for` 반복으로 확장한다 |
| 방화벽 | 20022, 15034 허용 | 15034 대신 80(·443) 허용 | `env/bootstrap.sh:54-55` 의 `ufw allow` |
| 관제 로그 | `monitor.log` (10MB × 10개) | 그대로 | `AGENT_LOG_DIR` |
| 대상 서비스 로그 | 앱 로그 | `access.log`·`error.log` 는 요청마다 쌓여 빨리 커진다. 별도 logrotate 정책을 두고, 읽을 계정의 그룹·권한을 다시 정한다(Ubuntu 패키지는 보통 `adm` 그룹 소유 — 환경에 따라 확인) | `/etc/logrotate.d/nginx` |
| 임계값 | CPU 20 / MEM 10 / DISK 80 | 트래픽에 따라 CPU 변동이 크다. 평상시 수치를 실측해 정한다 | `CPU_THRESHOLD` 등 환경 변수 |

- **마스터만 보는 이유**: Nginx 는 마스터 1개(root, 설정을 읽고 80/443 을 열고 워커를 관리)와
  워커 여러 개(일반 계정, 요청 처리)로 돈다. 워커가 죽으면 마스터가 다시 띄우지만, 마스터가
  죽으면 서비스가 끝난다. 1024 미만 포트는 root 만 열 수 있어서 이렇게 역할이 나뉜다.
- **패턴을 `nginx` 로만 두면 안 된다.** `pgrep -f` 는 명령줄에 그 글자만 있으면 잡으므로,
  Nginx 가 죽어 있어도 `vim /etc/nginx/nginx.conf` 나 `tail -f /var/log/nginx/access.log` 가
  떠 있으면 `[OK]` 가 난다. 로컬 호스트 리허설 발췌(컨테이너 증거가 아니다. 편집기는 `exec -a` 로
  이름만 흉내 낸 프로세스이고, 워커 19줄과 명령을 실행한 셸 자신이 잡힌 줄은 생략했다):
  ```
  $ pgrep -fa nginx
  4508 nginx: master process nginx -g daemon off;
  4896 nginx: worker process          (워커 20개 중 1개)
  14549 vim /etc/nginx/nginx.conf 20   ← 편집기도 잡힌다
  $ pgrep -fa 'nginx:.master.[p]rocess'
  4508 nginx: master process nginx -g daemon off;
  ```
- **패턴에 공백을 쓰지 않는다.** 환경 파일에 `nginx: master [p]rocess` 처럼 공백을 넣으면,
  `/etc/profile.d/agent-app.sh` 가 이 파일을 셸로 읽을 때 `master` 를 명령으로 실행하려다
  깨진다. 그래서 공백 대신 아무 글자 하나인 `.` 을 쓴다.
- **포트 LISTEN 만으로는 부족하다.** 워커가 멈춰도 포트는 열려 있을 수 있으므로 실제 응답을
  확인하는 단계를 더하는 것이 좋다. 예: `curl -fsS -m 3 -o /dev/null http://127.0.0.1/` 가
  실패하면 `exit 1`. (제안이며 구현하지 않았다.)
- 그대로 두는 것: Health Check 실패 시 `exit 1`, 방화벽·임계값은 경고만, 로그 포맷과 회전.

### 5-2. 프로세스는 살아 있는데 포트가 열리지 않을 때

`monitor.sh` 에서는 프로세스 `[OK]`, 포트 `[FAIL]` 로 나타나고 `exit 1` 로 끝난다
(`scripts/monitor.sh:200-205`).

**가능한 원인**

| 원인 | 증상 | 확인 |
|---|---|---|
| 아직 기동 중 | 몇 초 뒤 열린다 | 잠시 뒤 `ss -ltn` 재확인 |
| 기동 단계에서 실패 + 자동 재시작 반복 | PID 가 계속 바뀌고 실행 시간이 짧다 | `ps -o pid,etime,args -p PID`, 앱 기동 로그 |
| 다른 포트나 다른 주소로 바인드 | `AGENT_PORT` 오타, `127.0.0.1` 로만 열림 | `sudo ss -ltnp`, `/proc/PID/environ` |
| 포트 충돌 | 다른 프로세스가 같은 포트를 쥐고 있어 바인드 실패 | `sudo ss -ltnp \| grep 15034` |
| 권한 | 일반 계정이 1024 미만 포트를 열려고 함 | 앱 로그의 `Permission denied` (15034 라 이 앱은 해당 없음) |
| 방화벽 | 로컬에서는 LISTEN 인데 외부에서만 안 된다 | 외부에서 접속해 "거부"와 "타임아웃"을 구분 |

**확인 순서**

1. `ss -ltn | grep 15034` — 정말 안 열렸는지 로컬에서 다시 본다. 정상이면
   `evidence/FINAL-VERIFICATION.txt:211` 처럼 보인다.
2. `ps -o pid,stat,etime,args -p PID` — 프로세스 상태와 실행 시간. 이 앱은 프로세스가
   2개(부모·자식)로 보인다(`evidence/FINAL-VERIFICATION.txt:205-206`).
3. **앱 기동 로그(`$AGENT_HOME/app-boot.log`)의 Boot Sequence** — 5단계 중 어디서 멈췄는지 본다.
   포트를 여는 것은 `[4/5]` 이후라, 앞 단계에서 죽으면 포트까지 가지 못한다. 실제로
   `AGENT_KEY_PATH` 를 잘못 넣었을 때 `[2/5] Key Path Mismatch` 로 멈췄다(`evidence/phase4-app.txt:93-105`).
4. 다른 포트·주소로 열렸는지, 같은 포트를 쥔 프로세스가 있는지 root 로 `ss -ltnp` 를 본다.
   이 앱은 `[4/5] Checking Port Availability` 에서 충돌을 스스로 점검한다(`evidence/FINAL-VERIFICATION.txt:194-195`).
5. 로컬은 LISTEN 인데 외부에서만 안 되면 방화벽이다. **즉시 "연결 거부"는 패킷이 도착했지만
   받을 프로그램이 없다는 뜻이고, "타임아웃"은 방화벽이 패킷을 버렸다는 뜻이다**
   (`evidence/phase2-ufw.txt:158-161`: 허용 + 리스너 없음 → 0.2초 거부, 규칙 없음 → 6.2초 타임아웃).
6. 최근에 바뀐 것 — `/etc/agent-app.env`, 키 파일 권한, 배포 이력.

이 앱은 프로세스와 포트가 함께 움직여서 "프로세스만 살아 있는" 상황을 실제로 만들어
시험하지는 못했다(`evidence/phase5-monitor.txt:178-181`). 위 절차는 코드 경로와 다른
단계의 증거를 근거로 한 것이다.

### 5-3. 로그가 급증해 디스크가 찰 위험이 있을 때

| 단계 | 할 일 |
|---|---|
| **단기 1** 확인 | `df -h /`, `du -xh /var/log --max-depth=2 \| sort -h \| tail` 로 범인 파일과 증가 속도를 찾는다. `monitor.log` 의 `DISK_USED` 추이로 언제부터 늘었는지 잡는다 |
| **단기 2** 발생원 차단 | 에러 폭주, DEBUG 로그 레벨, 재시작 반복을 먼저 끊는다. 원인을 두고 공간만 비우면 곧 다시 찬다 |
| **단기 3** 증거 보존 | 지우기 전에 `tail -n 10000` 등으로 원인 분석용 샘플을 다른 디스크에 떠 둔다 |
| **단기 4** 공간 확보 | 오래된 회전본을 압축·삭제·이동한다. **쓰는 중인 로그는 `rm` 하지 않고 `: > 파일` 로 비운다** |
| **중기 1** 회전 정책 | 모든 로그에 크기·기간 기준의 회전과 압축을 건다(logrotate 또는 이 과제의 10MB × 10개 방식) |
| **중기 2** 격리 | `/var/log` 를 별도 파티션이나 쿼터로 분리해 로그가 루트 파티션을 채우지 못하게 한다 |
| **중기 3** 발생량 축소 | 로그 레벨 조정, 중복 메시지 억제, 중앙 수집으로 보내고 로컬 보존은 짧게 |
| **중기 4** 경보 | 70/80/90% 단계 경보와 증가 속도 경보를 둔다. 하루 증가량을 실측해 용량을 계획한다 |
| **중기 5** 근본 원인 | 폭주를 일으킨 버그·재시도 로직을 고치고 재발 방지 테스트를 둔다 |

**원인 분석 절차**: (1) 급증이 시작된 시각을 `DISK_USED` 추이와 파일 수정 시각으로 잡는다 →
(2) 샘플에서 가장 많이 반복되는 메시지를 센다(`sort | uniq -c | sort -rn | head`) →
(3) 그 시각의 배포·설정 변경·외부 요인(트래픽, 의존 서비스 장애)과 맞춰 본다 →
(4) 원인을 고친 뒤 증가 속도가 평상시로 돌아왔는지 확인한다.

**`rm` 대신 `: >` 인 이유**: `rm` 은 파일 이름만 지운다. 프로세스가 그 파일을 열고 있으면
내용은 남아 공간이 돌아오지 않는다. 로컬 호스트 리허설(300MB 가짜 로그를 프로세스가 연 채로
`rm`. 컨테이너 증거가 아니다. 출력은 측정값만 남기고 줄였다):
```
300MB 로그 생성 후  : 사용량 1218811M
rm 한 뒤           : 사용량 1218811M   ← 그대로, 이름만 사라짐
프로세스가 쥔 파일  : access.log (deleted)
: > /proc/PID/fd/3 : 사용량 1218511M   ← 300MB 가 돌아옴
```
이미 `rm` 했다면 `lsof +L1` 로 "지워졌지만 열려 있는 파일"을 찾아 위처럼 비우거나,
프로세스가 로그 파일을 다시 열게 한다(Nginx 는 `nginx -s reopen`).

이 과제에서 감지는 `DISK_USED` 임계값 경고가 맡는다(`scripts/monitor.sh:240-242`).
임계값을 낮춰 경고 분기를 실증했다(`evidence/phase6-cron.txt:230-233`, `DISK_THRESHOLD=1`).
`monitor.log` 자체는 10MB × 10개로 총량에 상한이 있지만, `cron.out` 은 회전하지 않는다(4-6절).

---

## 6. 실행 방법

### 환경 기동
Docker 엔진(Docker Desktop, OrbStack 등)이 떠 있어야 한다. 저장소 루트에서:
```bash
cd env
./run.sh                                   # 이미지 빌드 + 컨테이너 기동 + 앱 반입
docker cp ../scripts/monitor.sh       agent-lab:/tmp/
docker exec -i agent-lab bash -s < bootstrap.sh    # 전체 셋업
```

`run.sh` 와 `bootstrap.sh` 는 컨테이너 아키텍처(`uname -m`)를 보고 제공 바이너리를
고르고, 관제 패턴(`AGENT_APP_PATTERN`)도 그에 맞춰 기록한다. 아래 명령은 x86_64
호스트(Intel/AMD) 기준이다. arm64 호스트(Apple Silicon)에서는 바이너리명을
`agent-app-linux-arm64`, 패턴을 `agent-app-linux-arm[6]4` 로 바꾼다
(`bootstrap.sh` 마지막 줄이 그 환경의 실행 명령을 출력한다).

### 앱 실행
```bash
docker exec -it agent-lab sudo -u agent-admin bash -c \
  'set -a; . /etc/agent-app.env; set +a; cd $AGENT_HOME && ./agent-app-linux-x86'
```
종료는 `Ctrl+C`. cron 검증 중에는 백그라운드로 상주시킨다:
```bash
docker exec agent-lab sudo -u agent-admin bash -c \
  'set -a; . /etc/agent-app.env; set +a; cd "$AGENT_HOME" || exit 1; nohup ./agent-app-linux-x86 > "$AGENT_HOME/app-boot.log" 2>&1 < /dev/null &'

docker exec agent-lab pkill -f 'agent-app-linux-x8[6]'    # 백그라운드 앱 정지
```
`nohup` 명령만 `&` 로 보낸다. `cd ... && nohup ... &` 처럼 목록 전체를 백그라운드로
보내면 바이너리명이 명령줄에 남은 bash 서브셸이 앱의 부모로 살아 남고,
`monitor.sh` 의 `pgrep -f ... | head -1` 이 앱 대신 그 셸의 PID 를 잡는다.

### 관제 확인
```bash
docker exec agent-lab sudo -u agent-admin /home/agent-admin/agent-app/bin/monitor.sh
docker exec agent-lab tail -5 /var/log/agent-app/monitor.log   # cron 이 매분 1줄씩 추가
```

### 검증 / 기록 재생성
```bash
./dexec.sh collect-evidence.sh     # 필수 증거 8종 재수집
./dexec.sh snapshot.sh             # 설정 파일 스냅샷 갱신
```

### 정리
```bash
./teardown.sh          # 컨테이너 + 네트워크 제거, 증거 소유권 복구
./teardown.sh --all    # 이미지까지 제거
```

### 호스트 영향

`--privileged` 없이, 호스트 cgroup 마운트 없이, capability 2개(`NET_ADMIN`,
`NET_RAW`)만으로 구성했다. 호스트의 SSH·방화벽·계정·파일시스템과 다른 컨테이너에
영향이 없음을 실측 확인했다. 남는 접점은 `evidence/` 바인드 마운트,
루프백 전용 포트 게시(`127.0.0.1:20022`), docker 리소스 3개(이미지·네트워크·컨테이너)
뿐이며 `teardown.sh` 로 일괄 제거된다. 상세는 [PLAN.md](PLAN.md) 1절.
