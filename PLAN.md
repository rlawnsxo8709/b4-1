# B4-1 수행 계획서

> 미션: 리눅스 서버 보안·권한 체계 구성 + 관제 자동화(monitor.sh) + cron 스케줄링
> 수행 환경: **Docker 격리 컨테이너 (비특권)** — 호스트 Ubuntu 24.04 / aarch64
> 최우선 원칙: **모든 작업은 기록을 남기며 진행한다.** 기록되지 않은 작업은 수행하지 않은 것으로 간주한다.

---

## 0. 사전 조사 결과 (계획의 전제)

| 항목 | 확인 내용 | 계획에 미치는 영향 |
|---|---|---|
| 호스트 아키텍처 | `aarch64` | 제공 앱은 **`agent-app-linux-arm64`** 사용. x86 바이너리 실행 불가 |
| 제공 앱 정체 | PyInstaller onefile (CPython 3.12 임베드), stripped ELF | 프로세스명이 `agent_app.py`가 **아님** → `pgrep` 패턴을 실제 바이너리명에 맞춰야 함 |
| 호스트 상태 | 운영 중 컨테이너 **27개**, 활성 SSH(22) | 호스트 직접 적용 금지 → 컨테이너 격리 확정 |
| Docker | 29.1.3, cgroup **v2**, cgroupns=private 기본, apparmor+seccomp 활성 | **systemd 없이도** 필요한 것 전부 동작 → `--privileged` 불필요 |
| 기본 bridge 네트워크 | 멤버 **0개** (운영 컨테이너는 전부 compose 전용 네트워크) | 전용 네트워크 생성 시 운영 컨테이너와 완전 분리 |
| 방화벽 | `ufw` 존재, `firewalld` 없음 | **UFW 선택** |
| 호스트 로케일 | 한국어(ko_KR) | `top`/`free` 출력이 한글 → 파싱 금지, `/proc` 직접 읽기 |

### 0-1. 사전 검증 (실제 실행하여 확인 완료)

계획을 쓰기 전에 일회용 컨테이너로 아래를 **실측**했다. (검증 후 컨테이너·네트워크 삭제 완료)

| 검증 항목 | 조건 | 결과 |
|---|---|---|
| `ufw --force enable` | `--privileged` 없음, systemd 없음, `NET_ADMIN`+`NET_RAW`만 | ✅ `Status: active`, 규칙 정상 적용 |
| `sshd` 20022 리슨 | systemd 없이 `/usr/sbin/sshd` 직접 기동 | ✅ `sshd -T` → `port 20022`, `permitrootlogin no`, `ss`에 LISTEN |
| `cron` 데몬 | systemd 없이 `cron` 직접 기동 | ✅ 프로세스 상주 |
| `setfacl` / default ACL | 일반 컨테이너 | ✅ `default:group:agent-core:rwx`, `other::---` 정상 |
| 운영 컨테이너와의 격리 | 전용 네트워크에서 운영 컨테이너 IP:포트 접속 | ✅ **차단됨** (timeout) |
| 호스트 커널 모듈 | `nf_tables` 로드 상태 | ✅ 이미 로드됨(refs=2179) — 신규 로드 유발 없음 |
| 호스트 포트 | 20022/15034 리슨 | ✅ 없음 |

**결론: systemd를 포기하면 `--privileged`가 전혀 필요 없다.** 이것이 아래 격리 설계의 근거다.

---

## 1. 호스트 영향 분석 (질문에 대한 정확한 답)

### 1-1. 최초 계획은 안전하지 않았다 — 수정함

처음 작성한 계획에는 아래가 있었고, 이건 "영향 없음"이라고 말할 수 없다:

| 최초 계획 | 실제 위험 |
|---|---|
| `--privileged` | 모든 capability + 호스트 `/dev` 전체 접근. 컨테이너 안에서 호스트 블록 디바이스를 마운트해 호스트 파일시스템에 쓸 수 있다. **설계상 탈출 경로** |
| `--cgroupns=host` + `-v /sys/fs/cgroup:rw` | 컨테이너의 systemd가 **호스트 cgroup 트리**를 조작 가능. 운영 컨테이너 27개의 리소스 제어에 영향 가능 |
| `-p 0.0.0.0:20022` | SSH 포트가 호스트의 **모든 인터페이스**(LAN 포함)에 노출 |

세 가지 모두 **"컨테이너 안에서 systemd를 돌리려는 것"** 때문에 필요했던 것이다.
0-1에서 systemd 없이도 sshd·cron·ufw·ACL이 전부 동작함을 확인했으므로, **systemd를 빼서 위험 요소를 근본 제거**한다.

### 1-2. 수정된 컨테이너 사양

```bash
docker network create agent-lab-net

docker run -d --name agent-lab \
  --hostname agent-lab \
  --network agent-lab-net \          # 운영 컨테이너와 분리된 전용 네트워크
  --cap-add NET_ADMIN --cap-add NET_RAW \   # ufw/iptables에 필요한 최소 권한만
  --init \                            # PID1 좀비 수거
  -e TZ=Asia/Seoul \                  # 기록 타임스탬프를 호스트 시간축과 일치시킴
  -v "$PWD/answers/evidence:/evidence" \    # 기록 영속화 (유일한 호스트 경로 접점)
  -p 127.0.0.1:20022:20022 \          # 루프백 전용 — LAN 노출 없음
  agent-lab:latest
```

`--privileged` 없음 / 호스트 cgroup 마운트 없음 / seccomp·apparmor 기본값 유지.

### 1-3. 영향 없음 (검증 완료)

- 호스트 **SSH(22)**, `/etc/passwd`, `/etc/shadow`, 홈 디렉토리 — 컨테이너는 자체 파일시스템
- 호스트 **UFW/iptables** — 컨테이너는 자체 network namespace. 안에서 `ufw enable`을 해도 호스트 규칙과 무관
- **운영 컨테이너 27개** — 전용 네트워크로 분리, 크로스 접속 차단 실측 확인
- **커널 모듈** — `nf_tables`는 docker가 이미 사용 중이라 신규 로드 유발 없음

### 1-4. 의도적인 호스트 접점 3가지 (숨기지 않고 명시)

| 접점 | 범위 | 되돌리기 |
|---|---|---|
| `answers/evidence` 바인드 마운트 | 이 프로젝트 폴더 **한 곳**. 기록을 컨테이너 삭제 후에도 남기기 위함 | 컨테이너가 root로 파일을 만드므로 **종료 시 `sudo chown -R $USER:$USER answers/evidence` 수행** (계획에 포함) |
| `-p 127.0.0.1:20022` | 호스트 **루프백 전용** 바인딩 + docker의 DNAT 규칙 1건 | 컨테이너 삭제 시 자동 제거 |
| docker 리소스 | 이미지 1개(~150MB), 네트워크 1개, 컨테이너 1개 — 전부 `agent-lab` 이름 | `env/teardown.sh` 한 방에 삭제 |

**한 줄 요약: 수정된 설계에서는 호스트에 실질적 영향이 없다. 남는 접점은 위 3개뿐이고 전부 이름이 붙어 있어 일괄 삭제된다.**

---

## 2. 기록 체계 (이 미션의 최우선 사항)

기록은 3개 레이어로 쌓는다. **레이어가 서로를 검증**하도록 설계했다.

```
Layer 1  세션 원본(raw)   ── script(1) 터미널 전체 녹화. 오타·실패 포함, 절대 편집 안 함
Layer 2  구조화 증거      ── rec() 헬퍼가 [시각 + 명령어 + 출력 + exit code]를 자동 적재
Layer 3  서사 로그        ── WORKLOG.md. 의도 / 실패 / 원인 / 조치를 사람 말로
```

### 2-1. Layer 1 — 세션 원본 녹화

각 Phase 시작 시:
```bash
script -q -a -c "bash" /evidence/session/$(date +%F)-phaseN.log
```
- 편집 금지. 실패한 명령과 오타까지 그대로 남는 **1차 사료**
- Layer 2/3에서 뭔가 빠지거나 왜곡되면 여기로 대조

### 2-2. Layer 2 — `rec()` 헬퍼 (기록 자동화의 핵심)

증거를 손으로 복사·붙여넣기 하지 않는다. 모든 검증 명령은 `rec`를 통과시킨다.

```bash
# env/rec.sh
rec() {
  local f="${EVIDENCE_FILE:-/evidence/misc.txt}" out rc
  out="$("$@" 2>&1)"; rc=$?
  printf '### %s\n$ %s\n%s\n--- exit=%d ---\n\n' \
         "$(date '+%F %T')" "$*" "$out" "$rc" >> "$f"
  printf '%s\n' "$out"
  return $rc
}
```

- **exit code까지 기록** → "명령은 돌았지만 실패였다"를 놓치지 않음
- 화면에도 그대로 출력되므로 작업 흐름이 끊기지 않음
- 파일이 append-only → 시간순 재구성 가능
- 보고서 작성 시 이 파일에서 **그대로 인용**. 손으로 옮겨 적는 순간 신뢰도가 깨진다

### 2-3. Layer 3 — `WORKLOG.md` (서사)

실패를 감추지 않는다. 이 미션의 채점은 "무엇을 했나"보다 **"왜 그렇게 했나"**에 있고, 그 근거는 실패 경험에서 나온다.

항목 형식:
```markdown
## [Phase 1] SSH 포트 변경
- 시각: 2026-08-09 22:14
- 의도: sshd_config.d/99-agent.conf에 Port 20022 지정
- 결과: ❌ ss에 여전히 22가 보임
- 원인: Ubuntu 24.04는 ssh.socket 소켓 액티베이션이 기본. sshd_config의 Port가 무시됨
- 조치: (컨테이너는 systemd 미사용이라 미해당) 실제 호스트였다면 ssh.socket disable 필요 → 보고서에 비교 서술
- 증거: evidence/phase1-ssh.txt L23-41
```

### 2-4. 설정 파일은 손으로 옮겨 적지 않는다

`env/snapshot.sh`가 실제 파일을 `answers/config/`로 **복사**한다.
```
/etc/ssh/sshd_config.d/99-agent.conf  →  config/sshd_config.d-99-agent.conf
/etc/agent-app.env                    →  config/agent-app.env
agent-admin crontab -l                →  config/agent-admin.crontab
```
제출 문서의 설정 = 실제 적용된 설정임이 보장된다.

### 2-5. `evidence/INDEX.md` — 체크리스트 → 증거 매핑

미션이 요구하는 필수 증거 8종을 **파일:라인**으로 연결한다. 채점자가 찾아 헤매지 않도록.

| # | 필수 증거 | 파일 | 위치 |
|---|---|---|---|
| 1 | SSH 20022 + Root 차단 | `phase1-ssh.txt` | L-- |
| 2 | UFW 활성 + 2개 포트만 허용 | `phase2-ufw.txt` | L-- |
| 3 | 계정/그룹 생성 | `phase3-account.txt` | L-- |
| 4 | 디렉토리 구조 + ACL | `phase3-acl.txt` | L-- |
| 5 | Boot 5단계 [OK] + Agent READY | `phase4-boot.txt` | L-- |
| 6 | monitor.sh 실행 결과 | `phase5-monitor.txt` | L-- |
| 7 | monitor.log 누적 | `phase6-cron.txt` | L-- |
| 8 | crontab 등록 + 로그 증가 | `phase6-cron.txt` | L-- |

### 2-6. 재현성 — `collect-evidence.sh`

모든 검증 명령을 한 번에 재실행해 증거 번들을 통째로 재생성하는 스크립트.
설정이 바뀌면 손으로 고치는 게 아니라 **다시 돌린다**. 증거와 실제 상태의 불일치를 원천 차단.

### 2-7. 시각 일관성

컨테이너 TZ를 `Asia/Seoul`로 고정한다. `monitor.log` 타임스탬프, `rec()` 기록, WORKLOG 시각, 호스트 시각이 **하나의 시간축**에 놓여야 cron 자동 실행 증명(1분 간격 누적)이 성립한다.

---

## 3. 최종 산출물 구조

```
answers/
├── PLAN.md                       # 이 문서
├── README.md                     # 제출 문서 1: 요구사항 수행 내역서
├── WORKLOG.md                    # Layer 3: 서사 로그 (의도/실패/원인/조치)
├── env/
│   ├── Dockerfile
│   ├── run.sh                    # 컨테이너 기동 (비특권 사양)
│   ├── teardown.sh               # 컨테이너·네트워크·이미지 일괄 삭제 + evidence chown
│   ├── rec.sh                    # Layer 2: 증거 자동 적재 헬퍼
│   ├── snapshot.sh               # 실제 설정 파일 → config/ 복사
│   ├── collect-evidence.sh       # 전체 검증 재실행
│   └── bootstrap.sh              # 컨테이너 내부 1회 셋업
├── scripts/
│   └── monitor.sh                # 제출 산출물 2 (필수)
├── config/                       # 실제 적용된 설정 파일 사본 (자동 생성)
└── evidence/                     # Layer 1+2 (호스트 바인드 마운트)
    ├── INDEX.md
    ├── session/                  # script(1) 원본 녹화
    └── phaseN-*.txt              # rec() 구조화 증거
```

---

## 4. 단계별 계획

각 Phase는 **작업 → 검증 gate → 기록**. gate 실패 시 다음으로 넘어가지 않는다.
모든 검증은 `rec`를 통해 실행하며, Phase 종료 시 `snapshot.sh` + WORKLOG 항목을 남긴다.

### Phase 0 — 실습 환경 구축

- `Dockerfile`: `ubuntu:24.04` + `openssh-server ufw cron acl iproute2 sudo procps tzdata`
- **systemd 미설치** (1-1 참조). `entrypoint.sh`가 `sshd` + `cron`을 기동 후 상주
- 앱 바이너리 `docker cp`로 반입
- `evidence/session/`, `evidence/INDEX.md` 초기화

**gate**: 컨테이너 Running / `uname -m` = `aarch64` / `/evidence` 쓰기 가능

---

### Phase 1 — SSH 보안 설정

- `/etc/ssh/sshd_config.d/99-agent.conf` → `Port 20022`, `PermitRootLogin no`
- **문서화 포인트**: 실제 Ubuntu 24.04 호스트는 `ssh.socket` 소켓 액티베이션이 기본이라 `sshd_config`의 `Port`만 바꾸면 **여전히 22로 리슨**한다. 본 환경은 systemd 미사용이라 해당되지 않지만, `config/ssh-socket-override.conf`를 함께 제출하고 보고서에서 두 방식을 비교 서술한다. (실무에서 가장 많이 걸리는 함정)

**gate**: `sshd -T | grep -E '^(port|permitrootlogin) '` / `ss -tulnp | grep sshd` → 0.0.0.0:20022 / 호스트에서 `ssh -p 20022` 성공, `ssh -p 22` 실패, `root` 거부

---

### Phase 2 — 방화벽 (UFW)

```
ufw default deny incoming ; ufw default allow outgoing
ufw allow 20022/tcp ; ufw allow 15034/tcp ; ufw --force enable
```
- `allow 20022`를 **먼저** 넣고 enable — 실습이라도 락아웃 예방 습관을 들인다
- 0-1에서 비특권 컨테이너 동작 확인 완료

**gate**: `ufw status verbose` → active + 2개 포트만 ALLOW / 미허용 포트 차단 확인

---

### Phase 3 — 계정 / 그룹 / 디렉토리 / ACL

```
groupadd agent-common ; groupadd agent-core
useradd -m -s /bin/bash agent-{admin,dev,test}
usermod -aG agent-common agent-admin,agent-dev,agent-test
usermod -aG agent-core   agent-admin,agent-dev
```

`AGENT_HOME=/home/agent-admin/agent-app`

| 경로 | owner:group | 모드 | ACL |
|---|---|---|---|
| `/home/agent-admin` | agent-admin:agent-admin | 750 | `u:agent-dev:x` (통행권만) |
| `$AGENT_HOME` | agent-admin:agent-core | 2750 | — |
| `$AGENT_HOME/bin` | agent-admin:agent-core | 2750 | `u:agent-dev:rwx` + default |
| `$AGENT_HOME/upload_files` | agent-admin:**agent-common** | **2770** | `g:agent-common:rwx` + default |
| `$AGENT_HOME/api_keys` | agent-admin:**agent-core** | **2770** | `g:agent-core:rwx`, `o::---` + default |
| `/var/log/agent-app` | agent-admin:**agent-core** | **2770** | `g:agent-core:rwx`, `o::---` + default |

**설계 의도 (보고서 핵심 서술)**
- **setgid(2)**: 누가 만들든 새 파일 그룹이 자동 고정 → 협업 중 권한이 무너지지 않음
- **default ACL**: 신규 파일에 그룹 rw 자동 상속 → umask 의존 제거
- **`u:agent-dev:x` on `/home/agent-admin`**: agent-dev는 admin 홈 **내용을 볼 수 없지만** 하위 `bin`까지 통행은 가능. 최소 권한의 교과서적 사례
- **`o::---`**: agent-test는 `agent-common`이지 `agent-core`가 아니므로 api_keys·로그 접근 불가

**gate (네거티브 테스트가 핵심)**
- `id agent-{admin,dev,test}` / `getfacl` 3개 디렉토리
- ❌ `sudo -u agent-test cat $AGENT_KEY_PATH` → `Permission denied`
- ❌ `sudo -u agent-test ls /var/log/agent-app` → `Permission denied`
- ✅ `sudo -u agent-dev touch $AGENT_HOME/upload_files/x` → 성공, 그룹이 `agent-common`

---

### Phase 4 — 앱 실행 환경 구성

- 환경 변수 **2벌** (역할이 다름):
  - `/etc/profile.d/agent-app.sh` — 대화형 로그인 셸용
  - `/etc/agent-app.env` — **cron·스크립트용**. cron은 `/etc/profile.d`를 읽지 않으므로 monitor.sh가 이걸 `source`한다 ← **핵심 함정**
- 키 파일 `$AGENT_KEY_PATH` = `agent_api_key_test`, `agent-admin:agent-core`, `640`
  - **함정**: 개행 포함 여부를 앱이 엄격히 볼 수 있음. `echo`(개행 O) 먼저 → `[3/5]` 실패 시 `printf %s`(개행 X) 재시도. **두 시도 모두 WORKLOG에 기록**
- 앱은 `agent-admin`으로 실행 (루트 금지 — `[1/5]`가 서비스 계정 확인)
- `[4/5] Port is available`은 **바인딩 전 포트가 비어 있는지** 검사 → 이전 인스턴스 남아 있으면 실패. 재실행 전 항상 정리

**gate**
- Boot `[1/5]`~`[5/5]` 전부 `[OK]` + `Agent READY` (전체 출력을 evidence에 적재)
- `ss -tulnp | grep 15034` → LISTEN
- **`ps -ef`로 실제 프로세스명 확인·기록** → Phase 5 pgrep 패턴 확정

---

### Phase 5 — monitor.sh 구현

**배치**: `$AGENT_HOME/bin/monitor.sh`, 소유 `agent-dev:agent-core`, 모드 `750`
- 실행자는 cron의 `agent-admin`. admin은 `agent-core`라 그룹 `r-x`로 실행 가능 — **권한 체계가 실제로 맞물리는지 검증되는 지점**
- 작성자 agent-dev가 `bin`에 쓰려면 Phase 3의 `u:agent-dev:rwx` ACL이 선행

| 항목 | 방법 | 이유 |
|---|---|---|
| 셸 옵션 | `set -uo pipefail` (`-e` 미사용) | 경고가 스크립트를 죽이면 안 됨 |
| 환경 로드 | `/etc/agent-app.env` source + 기본값 폴백 | cron 최소 환경 대응 |
| 프로세스 | `pgrep -f "$APP_PATTERN"` → 없으면 `exit 1` | 패턴은 Phase 4 실측값 |
| 포트 | `ss -ltn \| grep -q ':15034 '` → 없으면 `exit 1` | `-p`는 root 필요 → **의도적 제외** |
| 방화벽 | `/etc/ufw/ufw.conf`의 `ENABLED=yes` grep | **함정**: `ufw status`는 root 전용. 비특권 agent-admin이 sudo 없이 점검하는 방법. 비활성 시 `[WARNING]`만, 종료 안 함 |
| CPU | `/proc/stat` 1초 간격 2회 → `(1-idle_d/total_d)*100` | `top` 파싱은 **한국어 로케일에서 깨짐** |
| MEM | `/proc/meminfo` `MemTotal`/`MemAvailable` | `free` 헤더도 로케일 의존 |
| DISK | `df -P /` 5번째 컬럼 `%` 제거 | `-P`로 POSIX 고정폭 강제 |
| 임계값 비교 | `awk 'BEGIN{exit !(v>t)}'` | bash는 실수 비교 불가 |
| 로그 | `[%F %T] PID:.. CPU:..% MEM:..% DISK_USED:..%` append | 요구 포맷 그대로 |
| 용량 관리 | 10MB 초과 시 `.9→.10` 역순 shift, `.10` 삭제, 본체→`.1` | **logrotate 대신 스크립트 로직**: logrotate는 root와 `/etc/logrotate.d`가 필요한데 실행자는 비특권 agent-admin |

**gate**
- `ls -l` → `-rwxr-x--- agent-dev agent-core`
- ✅ `sudo -u agent-admin monitor.sh` → 정상 출력 + `$?` = 0
- ❌ `sudo -u agent-test monitor.sh` → `Permission denied`
- **실패 경로**: 앱 종료 후 실행 → `exit 1` 확인 → 앱 재기동
- **경고 경로**: `ufw disable` 후 실행 → `[WARNING]` 출력되나 **종료 안 됨** 확인 → `ufw enable` 복구
- **로테이션**: 10MB 더미 로그 주입 → shift 동작 확인
- 위 5가지는 각각 별도 evidence 블록으로 남긴다 (정상 케이스만 기록하면 검증이 아니다)

---

### Phase 6 — cron 자동 실행

```
* * * * * /home/agent-admin/agent-app/bin/monitor.sh >> /var/log/agent-app/cron.out 2>&1
```
- `agent-admin` crontab에 등록. `cron` 데몬 상주 확인 필수 (안 돌면 조용히 아무 일도 안 일어남 — 최다 실패 원인)
- stdout을 `cron.out`으로 리디렉션 → cron 환경에서만 나는 오류를 잡는 창구

**gate**
- `crontab -l -u agent-admin`
- `wc -l monitor.log` **측정 → 2분 대기 → 재측정**하여 라인 수 증가 확인 (양쪽 시각을 evidence에 기록해야 "자동 실행"의 증명이 성립)
- `cron.out`이 비어 있는지(= 에러 없음)
- `tail -5 monitor.log` → 1분 간격 타임스탬프 확인

---

### Phase 8 — 제출 문서 작성

`README.md`(수행 내역서)를 **evidence에서 인용해서** 채운다. 손으로 옮겨 적지 않는다.

1. **수행 내역** — Phase별 설정/명령어 (SSH, UFW, 계정·그룹·ACL, 디렉토리 권한, 환경 변수, cron)
2. **필수 증거 8종** — `evidence/INDEX.md` 매핑대로 인용
3. **과제 목표 6개 서술형 답변** — 채점 핵심. WORKLOG의 실패 기록을 근거로 씀:
   - SSH 포트 변경·Root 차단이 왜 "기본" 보안인가 — 자동화 스캔 노이즈 감소 + 계정명 추측 공격면 제거. 단 **포트 변경은 방어가 아니라 잡음 제거**임을 명시
   - `agent-common`(공유) vs `agent-core`(보안) 분리 이유 — Phase 3 네거티브 테스트 결과로 뒷받침
   - 환경 변수로 실행 환경을 고정하는 이유 — cron 최소 환경에서 스크립트가 깨진 실제 경험(WORKLOG)을 근거로
   - 로그 보존 정책이 왜 필요한가 — 매분 실행 시 **실측 증가량**으로 디스크 고갈 시점 추정

---

## 5. 리스크 및 대응

| 리스크 | 신호 | 대응 |
|---|---|---|
| 앱 프로세스명이 `agent_app.py`가 아님 | `pgrep` 미탐지 | Phase 4에서 `ps -ef` 실측 후 패턴 확정 |
| 키 파일 개행 불일치 | Boot `[3/5]` 실패 | `echo` ↔ `printf %s` 교차 시도, 양쪽 기록 |
| cron 데몬 미기동 | 로그가 안 늘어남 | `ps -eo comm \| grep cron` 확인, `cron.out` 점검 |
| `top`/`free` 한글 헤더 파싱 실패 | CPU/MEM 공란 | `/proc` 직접 파싱 (반영됨) |
| 비특권 `ufw status` 실패 | 항상 WARNING | `/etc/ufw/ufw.conf` 읽기 (반영됨) |
| 앱 재실행 시 포트 점유 | Boot `[4/5]` 실패 | 기존 프로세스 종료 후 재기동 |
| evidence가 root 소유로 생성 | 호스트에서 편집 불가 | `teardown.sh`에서 `chown -R $USER:$USER` (반영됨) |
| 컨테이너 재시작 시 sshd/cron 정지 | 서비스 없음 | `entrypoint.sh`가 기동하도록 구성 (반영됨) |
| UFW가 iptables-nft를 못 씀 | `ufw enable` 오류 | 0-1에서 정상 확인. 문제 시 `iptables-legacy`로 alternatives 전환 |

---

## 6. 진행 순서

```
Phase 0 환경  →  1 SSH  →  2 UFW  →  3 계정/ACL  →  4 앱 실행
                                                        ↓
             8 문서  ←  6 cron  ←  5 monitor.sh
```

Phase 3의 ACL 설계가 Phase 5(monitor.sh 소유·실행 권한)와 Phase 6(cron 실행자)의 전제다.
**Phase 3의 네거티브 테스트를 통과하기 전에는 뒤로 넘어가지 않는다.**

각 Phase 종료 시 반드시: `rec` 증거 적재 → `snapshot.sh` → `WORKLOG.md` 항목 추가.

> 단계 번호 7 은 제외한 단계라 비어 있다. 이미 수집된 증거·스크립트 파일명(`phase9-…` 등)과의 대응을 유지하려고 재번호하지 않았다.
