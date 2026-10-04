# B4-1 요구사항 수행 내역서

> 리눅스 서버 보안 · 권한 체계 구성 + 시스템 관제 자동화
>
> 수행일: 2026-08-09 / 환경: Docker 비특권 컨테이너 (Ubuntu 24.04 LTS, aarch64)

> **출처 메모**: 이 산출물은 2026-08-09~10 구 번호 b1-1(현 B4-1)로 수행한 기록이다. 미션 번호 개편(2026-09-04)에 맞춰 재구성했고 보너스 과제는 제외했다. `evidence/`·`config/`의 원본 출력은 무결성을 위해 수정하지 않았으므로, 그 안에 보너스 실행 흔적과 구 번호가 남아 있다.
>
> 재구성 범위: 선택 과제 스크립트와 그 실행 증거 파일을 삭제하고, 문서와 `env/` 스크립트에서 관련 서술·참조를 걷어 냈다. 단계 번호 7 은 제외한 단계라 비어 있으나, 남은 증거·스크립트 파일명과의 대응을 유지하려고 재번호하지 않았다.

이 문서에 인용된 모든 명령 출력은 **실제 실행 결과를 그대로 옮긴 것**이다.
손으로 옮겨 적은 설정은 없으며, 설정 파일은 `env/snapshot.sh` 가 실물을
`config/` 로 복사한 것이다.

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
5. [실행 방법](#5-실행-방법)

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
│   ├── Dockerfile, run.sh, teardown.sh
│   ├── bootstrap.sh        Phase 1~4 통합 셋업 (최종 확정판)
│   ├── rec.sh              증거 자동 적재 헬퍼
│   ├── snapshot.sh         실제 설정 파일 → config/ 복사
│   ├── collect-evidence.sh 필수 증거 8종 일괄 재수집
│   └── phases/             단계별 수행·검증 스크립트
├── config/                 실제 적용된 설정 파일 사본 (자동 생성)
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

---

## 5. 실행 방법

### 환경 기동
```bash
cd answers/env
./run.sh                                   # 이미지 빌드 + 컨테이너 기동 + 앱 반입
docker cp ../scripts/monitor.sh       agent-lab:/tmp/
docker exec -i agent-lab bash -s < bootstrap.sh    # 전체 셋업
```

### 앱 실행
```bash
docker exec -it agent-lab sudo -u agent-admin bash -c \
  'set -a; . /etc/agent-app.env; set +a; cd $AGENT_HOME && ./agent-app-linux-arm64'
```
종료는 `Ctrl+C`. cron 검증 중에는 `nohup ... &` 로 상주시킨다.

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
