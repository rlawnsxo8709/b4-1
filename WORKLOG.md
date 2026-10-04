# 작업 로그 (WORKLOG)

> 수행일: 2026-08-09 / 환경: Docker 비특권 컨테이너 (Ubuntu 24.04, aarch64)
>
> 이 문서는 **실패를 포함한** 시간순 기록이다.
> 성공한 결과만 적으면 "왜 그 설정이어야 했는지"의 근거가 사라진다.
> 과제 목표의 서술형 답변은 대부분 여기 적힌 실패에서 나왔다.
>
> - 원본 세션 녹화 : `evidence/session/2026-08-09-session.log` (편집하지 않음)
> - 구조화 증거     : `evidence/phase*.txt` (명령 + 출력 + 종료코드)
> - 최종 상태 검증  : `evidence/FINAL-VERIFICATION.txt`
>
> 구 번호 b1-1 로 2026-08-09~10 에 수행한 기록을 B4-1 로 재구성한 문서다.
> 출처와 재구성 범위는 [README.md](README.md) 상단의 출처 메모를 본다.

---

## 총평 — 이번 작업에서 실제로 걸린 문제 8건

| # | 문제 | 성격 | 어디서 |
|---|---|---|---|
| 1 | `ufw status` 와 `verbose` 의 출력 스키마가 다름 | 검증식 버그 | Phase 2 |
| 2 | agent-test 가 `upload_files` 에 도달 못 함 (경로 통행권) | **설계 결함** | Phase 3 |
| 3 | `AGENT_KEY_PATH` 가 파일이 아니라 디렉토리 | 문서-구현 불일치 | Phase 4·9 |
| 4 | 앱이 찾는 키 파일명이 `secret.key` (문서는 `t_secret.key`) | 문서-구현 불일치 | Phase 4·9 |
| 5 | `pkill -f` 가 자기 자신을 죽임 (**4회 반복**: Phase 4 1회, Phase 6 2회, Phase 9 1회) | 셸 함정 | Phase 4, 6, 9 |
| 6 | 명령 치환이 백그라운드 잡을 기다려 부하 테스트 무효화 | 측정 방법 오류 | Phase 6 |
| 7 | 환경 변수 오버라이드가 먹지 않음 (`set -a; . file` 이 호출자 값을 덮어씀) | **로직 버그** | Phase 6 이후 보강 (22:44) |
| 8 | 키 파일이 실제로 생성되지 않았는데 결과가 우연히 맞아 은폐됨 | **은폐된 버그** | Phase 9 |

이 중 **2, 8번은 게이트가 PASS 를 준 상태에서 발견됐다.** 검사 항목이 부족했기 때문이며,
두 경우 모두 게이트를 강화한 뒤 재검증했다. 아래 각 항목에 상세히 적는다.

> 설명용으로 정리한 버전은 [EXPLAIN.md 4장](EXPLAIN.md#4-실패에서-배운-것) 참조.

---

## Phase 0 — 실습 환경 구축

**의도**: 호스트에 영향 없이 미션을 수행할 격리 환경 마련.

**판단 과정**:
초안은 `--privileged` + `--cgroupns=host` + 호스트 cgroup 쓰기 마운트였다. systemd 를
컨테이너에서 돌리기 위한 조합인데, 이건 격리가 아니라 탈출 경로를 여는 것이다.
호스트에는 운영 중인 컨테이너가 27개 있었으므로 그대로 진행할 수 없었다.

그래서 **"systemd 가 정말 필요한가"** 를 먼저 실측했다. 일회용 컨테이너에
`NET_ADMIN` + `NET_RAW` 만 주고 확인한 결과:

| 검증 | 결과 |
|---|---|
| `ufw --force enable` | ✅ active, 규칙 정상 |
| `sshd` 20022 리슨 | ✅ systemd 없이 직접 기동 가능 |
| `cron` 데몬 | ✅ 상주 |
| `setfacl` default ACL | ✅ 정상 |
| 운영 컨테이너 접속 | ✅ 전용 네트워크로 차단됨 |

**결론**: systemd 를 포기하니 `--privileged` 가 통째로 불필요해졌다.
필요한 것은 capability 2개뿐이었다.

**결과**: PASS. PID 1 이 systemd 가 아님을 확인, TZ=Asia/Seoul 로 호스트와 시간축 일치.

---

## Phase 1 — SSH 포트 변경 및 Root 차단

**의도**: `sshd_config.d/99-agent.conf` 드롭인으로 Port 20022, PermitRootLogin no.

**결과**: PASS (22 → 20022, `without-password` → `no`)

**기록해 둘 것 — ssh.socket 함정**:
본 환경은 systemd 를 쓰지 않아 문제없이 적용됐지만, **실제 Ubuntu 22.10+ / 24.04
호스트라면 이 설정만으로는 포트가 바뀌지 않는다.** systemd 의 `ssh.socket` 이 소켓
액티베이션으로 22번을 먼저 잡고 sshd 에 넘겨주기 때문에 `sshd_config` 의 `Port` 가
무시된다. 해결은 둘 중 하나:

- (A) `systemctl disable --now ssh.socket` + `systemctl enable --now ssh.service`
- (B) `/etc/systemd/system/ssh.socket.d/override.conf` 에
  `ListenStream=` (빈 줄로 초기화) 후 `ListenStream=20022`

"설정 파일은 고쳤는데 왜 안 바뀌지"의 대표 사례라 별도로 남긴다.

---

## Phase 2 — UFW 방화벽

**의도**: 기본 정책 deny incoming, 20022/15034 만 허용.

**실패 1 — 게이트 검사식 버그**

```
NG: 허용 규칙에 20022/15034 외 항목 존재 (allow=0, expected=4)
PHASE 2 GATE: FAIL
```

방화벽 설정은 정상인데 게이트가 FAIL 을 냈다. 원인은 `grep -cE "ALLOW IN"` 이
0을 반환한 것.

`ufw status | cat -A` 로 실제 바이트를 확인한 결과:

```
20022/tcp                  ALLOW       Anywhere    # 평문: "ALLOW"
20022/tcp                  ALLOW IN    Anywhere    # verbose: "ALLOW IN"
```

**같은 명령이라도 옵션에 따라 출력 스키마가 다르다.** 평문 출력에 verbose 용
패턴을 grep 한 것이 원인이었다. 게이트를 verbose 기준으로 고쳐 PASS.

이 실패가 나중에 monitor.sh 에서 `top`/`free` 를 쓰지 않고 `/proc` 을 직접 읽기로
결정한 근거가 됐다. CLI 출력은 옵션·로케일·버전에 따라 변한다.

**추가 검증 — 규칙 등록이 아니라 실제 차단인지**

`ufw status` 는 "규칙이 등록되어 있다"만 보여 줄 뿐 실제로 막히는지는 증명하지 못한다.
같은 네트워크에 프로브 컨테이너를 띄워 세 경우를 구분했다:

| 포트 | 조건 | 결과 | 해석 |
|---|---|---|---|
| 20022 | ALLOW + 리스너 있음 | 0.2초 연결 성공 | 정상 |
| 15034 | ALLOW + 리스너 없음 | 0.2초 **연결 거부** | 패킷이 도달함 |
| 9999 | 규칙 없음 (기본 deny) | 6.2초 **타임아웃** | 패킷이 DROP 됨 |

**거부(refused)와 무응답(timeout)의 차이**가 방화벽이 살아 있다는 증거다.

---

## Phase 3 — 계정 / 그룹 / 디렉토리 / ACL

**의도**: agent-common(공유) / agent-core(보안) 로 축을 분리하고 setgid + ACL 적용.

**실패 2 — 설계 결함 (게이트가 놓침)**

첫 실행에서 게이트는 **PASS** 였다. 그런데 로그를 보니:

```
touch: cannot touch '.../upload_files/from-test.txt': Permission denied
```

요구사항은 "upload_files: group=agent-common, R/W 가능" 이고 agent-test 는
agent-common 소속이므로 **되어야 정상**이다.

원인은 `upload_files` 자체가 아니라 **가는 길**이었다:

```
/home/agent-admin        750 + ACL u:agent-dev:x   → test 통행 불가
  └ agent-app            2750 agent-admin:agent-core → test 는 core 아님, 통행 불가
      └ upload_files     2770 agent-admin:agent-common → 여기는 맞지만 도달 못 함
```

리눅스는 최종 디렉토리 권한만 보는 게 아니라 **경로상의 모든 디렉토리에 실행(x)
권한을 요구한다.** 중간 한 곳만 막혀도 도달할 수 없다.

**수정**: `/home/agent-admin` 과 `$AGENT_HOME` 에 `g:agent-common:x` 부여.
읽기(r)는 주지 않았다.

```
group:agent-common:--x
other::---
```

결과적으로 **"길을 알면 지나갈 수 있지만 둘러볼 수는 없는"** 상태가 됐다.
agent-test 는 `$AGENT_HOME` 의 목록조차 볼 수 없지만, 경로를 정확히 지정한
`upload_files` 에는 도달해 쓸 수 있다. 공유 디렉토리를 보안 디렉토리 하위에
두면서 최소 권한을 유지하는 방법이다.

**게이트도 함께 고쳤다**: 네거티브 테스트만 있고 "agent-test 의 정당한 쓰기"라는
포지티브 케이스가 없었다. 세 계정 모두에 대해 공유 영역 쓰기와 그룹 상속을
검사하도록 보강했다.

권한을 푸는 작업이라 **통행권 부여 후 기밀 영역이 여전히 막혀 있는지 재확인**했다.
api_keys / 로그 / bin 모두 차단 유지 확인.

---

## Phase 4 — 앱 실행 환경

**실패 3, 4 — 문서와 앱의 불일치 2건**

미션 문서대로 설정했더니 Boot 가 `[2/5]` 에서 실패했다. 앱이 친절하게 기대값을
출력해 준 덕분에 추측 없이 확정할 수 있었다.

```
[2/5] Verifying Environment Variables     [FAIL]
   >>> Key Path Mismatch. Expected: /home/agent-admin/agent-app/api_keys
```
→ `AGENT_KEY_PATH` 는 **파일이 아니라 디렉토리**다. (문서: `.../api_keys/t_secret.key`)

수정 후 `[3/5]` 에서 다시 실패:
```
[3/5] Checking Required Files             [FAIL]
   >>> Missing File: secret.key
```
→ 앱이 찾는 파일명은 **`secret.key`** 다. (문서: `t_secret.key`)

**대응**: 두 파일을 같은 내용으로 생성해 문서 요구와 앱 요구를 모두 충족시켰다.
어느 쪽 기준으로 채점하더라도 통과하며, 불일치 사실 자체를 기록에 남긴다.

**실패 5 — `pkill -f` 자기매치 (이번 작업에서 모두 4번 걸림)**

앱을 정리하려고 `bash -c "... pkill -f agent-app-linux-arm64 ..."` 를 실행했더니
셸이 종료코드 143(SIGTERM)으로 죽었다. `pkill -f` 는 **자기 자신을 포함한** 전체
프로세스의 명령줄을 훑는데, 패턴 문자열이 실행 중인 셸의 명령줄에 그대로 들어
있어서 자기를 죽인 것이다.

**해결**: 패턴에 대괄호를 넣어 문자열과 정규식을 어긋나게 한다.
```
agent-app-linux-arm[6]4
```
이 정규식은 실제 프로세스(`...arm64`)에 매치되지만, 명령줄에 남는 문자열
(`...arm[6]4`)에는 매치되지 않는다. monitor.sh 의 감시 패턴도 이 형태로 고정했다.

같은 함정에 Phase 6 에서 두 번 더 걸렸고(`pkill -f 'while :'`, `phase6-cron.txt` 의 노트는
이 시점까지를 '3회째'로 적었다), Phase 9 에서 한 번 더 걸려 **모두 4회**가 됐다.
구조화 증거에서 `exit=143` 으로 확인되는 위치는 Phase 4 1건, Phase 6 2건, Phase 9 4건이다.
Phase 9 의 4건은 한 번의 시험 실행 안에서 연달아 같은 원인으로 중단된 것이라 사고 횟수로는 1회로 센다.
이 작업에서 가장 비용이 컸던 함정이다.

**앱의 정체**: PyInstaller 단일 바이너리이고, 단순 대기 서버가 아니라
**CPU/메모리를 주기적으로 끌어올리는 부하 생성기**(Cycle: 0 → 256MB/Lv10 → 0)였다.
monitor.sh 의 임계값 경고가 실제로 발동하도록 설계된 것으로 보인다.

**결과**: Boot 5/5 [OK] + `Agent READY`, `0.0.0.0:15034` LISTEN, 실행자 agent-admin.

---

## Phase 5 — monitor.sh

**설계 판단**은 스크립트 상단 주석에 모두 적었다. 요지:

| 결정 | 이유 |
|---|---|
| `set -e` 미사용 | 경고가 스크립트를 죽이면 안 된다. 종료는 Health Check 실패에서만 |
| `/proc` 직접 파싱 | `top`/`free` 는 로케일에 따라 헤더가 바뀐다 (Phase 2 의 교훈) |
| `ss` 를 `-p` 없이 | `-p` 는 root 필요. 실행자는 비특권 agent-admin |
| `/etc/ufw/ufw.conf` 읽기 | `ufw status` 는 root 전용. sudo 추가 없이 점검하기 위해 |
| 로테이션 자체 구현 | logrotate 는 root + `/etc/logrotate.d` 필요 |

**검증한 4가지 경로** (정상만 확인하면 검증이 아니라 시연이다):

| 경로 | 조건 | 결과 |
|---|---|---|
| 정상 | 앱 정상 + 방화벽 활성 | exit 0, 로그 1줄 추가 |
| 경고 | `ufw disable` | `[WARNING]` 출력, **exit 0**, 로그 정상 기록 |
| 실패 | 앱 종료 | `[FAIL]` → **exit 1**, 이후 단계 미실행 |
| 로테이션 | 11MB 더미 로그 | `monitor.log` → `.1`, 새 로그 시작 |

**권한 체계가 맞물리는지도 확인**: agent-dev 가 직접 `bin/` 에 작성(ACL 동작),
setgid 로 그룹이 자동으로 agent-core 지정, agent-admin 은 그룹 권한으로 실행 가능,
agent-test 는 차단.

---

## Phase 6 — cron

**결과**: 22:32:02, 22:33:02 — 정확히 1분 간격 자동 누적 확인. PASS.

**cron.out 으로 리디렉션한 이유**: cron 은 최소 환경에서 실행되므로 대화형 셸에서는
나지 않던 오류가 여기서만 발생한다. `/dev/null` 로 버리면 그 오류를 영영 볼 수 없다.
실제로 이번엔 오류가 없었지만, 없다는 것을 확인할 수 있다는 게 요점이다.

**실패 6 — 부하 테스트가 무효였다**

CPU 임계값 경고를 실증하려고 부하 생성기 8개를 띄우고 monitor.sh 를 실행했는데
CPU 가 1.7% 로 측정됐다. 스크립트 문제가 아니라 **측정 방법**의 문제였다.

부하 생성을 기록 헬퍼 `recsh` 로 실행했는데, 내부가
```bash
out="$(bash -c "$1" 2>&1)"
```
즉 **명령 치환**이다. 명령 치환은 stdout 파이프가 닫힐 때까지 기다리고,
백그라운드 잡이 그 stdout 을 상속받으므로 **12초 부하가 끝날 때까지 블록**된다.
결과적으로 부하가 끝난 뒤에 측정이 일어났다.

**해결**: `setsid ... </dev/null >/dev/null 2>&1 &` 로 완전히 떼어내 진짜 비동기로 만들었다.

**재측정 결과**: 20코어 중 10개 점유 → **CPU 51.3%**, 기본 임계값 20% 에서
`[WARNING] CPU threshold exceeded (51.3% > 20%)` 발생. 조작 없는 실측 경고다.

**임계값을 환경 변수로 덮어쓸 수 있게 한 이유**: 이 장비는 20코어 / 119.6GB 라
요구사항의 임계값(소형 VM 기준)에 평상시 부하로는 도달하지 않는다. MEM/DISK 는
119GB 를 채우는 대신 임계값을 낮춰 분기 로직을 확인했다.
**기본값은 요구사항 그대로 20/10/80 이며 변경하지 않았다.**

덧붙여, cron 이 돌던 중 **MEM 12.8% 가 자연 발생해 기본 임계값 10% 에서 경고가
실제로 기록됐다**(`cron.out`). 조작 없이 잡힌 경고다.

---

## Phase 6 이후 — 환경 변수 오버라이드 보강 (monitor.sh 후속 수정)

**실패 7 — 환경 변수 오버라이드가 먹지 않음**

Phase 6 의 cron 검증까지 끝난 뒤, 같은 환경 파일 로딩 방식을 쓰는 다른 스크립트를 시험하다
증상이 드러났다. 그 스크립트는 이 산출물에서 제외했고, 그 단계의 증거 파일도 삭제했다.
따라서 당시 증상의 흔적은 **`evidence/session/2026-08-09-session.log` L1531–1538 에만** 남아 있다.
아래는 그 원문을 **요약한 것**이다(원인 두 줄을 한 줄로 합쳤고, 수정 줄은 아래 서술에 풀어 썼으며,
영향 줄의 제외한 스크립트 이름은 "제외한 다른 스크립트"로 바꿨다). 원문 그대로는 세션 로그에서 확인한다.

```
증상 : AGENT_LOG_DIR=/var/log/does-not-exist 로 실행했는데
       출력에는 source: /var/log/agent-app 가 찍혔다.
원인 : (set -a; . /etc/agent-app.env; set +a) 가 호출자가 준 값을 파일 값으로 덮어썼다.
영향 : monitor.sh 와 제외한 다른 스크립트가 같은 패턴이었으므로 함께 수정했다.
```

`monitor.sh` 의 수정 시각은 22:44 이다(`config/script-perms.txt`). Phase 6 의 마지막 부하 시험(22:36)보다
뒤이므로 번호와 서술 위치를 Phase 6 다음에 두었다. 처음 `monitor.sh` 는 환경 파일을
`set -a; . /etc/agent-app.env; set +a` 로 읽었다. 이 방식은 **호출자가 명시적으로 준 값을 파일 값으로
덮어쓰므로**, 파일이 항상 이기는 구조였다.

→ `load_env_defaults()` 로 교체. 이미 설정된 변수는 건너뛰고 비어 있는 것만 채운다.
**명시적으로 준 값이 항상 이긴다.**

현재 산출물에서 이 차이를 다시 확인한 **로컬 리허설**(호스트 bash, 임시 환경 파일 사용. 컨테이너 증거가 아니다):

```
$ cat x.env
AGENT_LOG_DIR=/var/log/agent-app

# 구 방식 (set -a; . file)
$ AGENT_LOG_DIR=/var/log/does-not-exist bash -c 'set -a; . x.env; set +a; echo "AGENT_LOG_DIR=$AGENT_LOG_DIR"'
AGENT_LOG_DIR=/var/log/agent-app

# 현재 scripts/monitor.sh 의 load_env_defaults()
$ AGENT_LOG_DIR=/var/log/does-not-exist bash -c '. loader.sh; load_env_defaults x.env; echo "AGENT_LOG_DIR=$AGENT_LOG_DIR"'
AGENT_LOG_DIR=/var/log/does-not-exist

# 값을 주지 않았을 때는 파일 값으로 채운다
$ env -u AGENT_LOG_DIR bash -c '. loader.sh; load_env_defaults x.env; echo "AGENT_LOG_DIR=$AGENT_LOG_DIR"'
AGENT_LOG_DIR=/var/log/agent-app
```

(`loader.sh` 는 `scripts/monitor.sh` 에서 `load_env_defaults()` 함수 본문만 `sed -n` 으로 떼어 낸 파일이다.)
이 리허설은 함수 동작만 보여 준다. monitor.sh 를 실제로 `AGENT_LOG_DIR=/var/log/does-not-exist` 로
돌린 컨테이너 실행 기록은 없다. 코드상 이 경우 Health Check 통과 후 `[FATAL] Log directory not found`
로 exit 1 이 되는 것이 기대 동작이다.

---

## Phase 9 — 문서 정합성 재검증 (추가 수행)

**의도**: 가능하다면 미션 문서의 표기를 그대로 따르는 것이 맞다. Phase 4 의 실패는
`secret.key` 가 없던 조건에서 관측된 것이라, 파일이 모두 갖춰진 상태에서 문서 표기를
다시 시험해 결론을 확정하기로 했다.

**세 방향 시험 결과**

| 시험 | 설정 | 결과 |
|---|---|---|
| A | `AGENT_KEY_PATH` = `.../api_keys/t_secret.key` (문서 표기) | ❌ `[2/5]` `Key Path Mismatch. Expected: .../api_keys` |
| B | `AGENT_KEY_PATH` = `.../api_keys` (디렉토리) | ✅ Boot 5/5 + `Agent READY` |
| C | `t_secret.key` 만 두고 `secret.key` 제거 | ❌ `[3/5]` `Missing File: secret.key` |

**결론**: 디렉토리 지정과 `secret.key` 는 **선택이 아니라 앱이 강제하는 제약**이다.
문서를 안 따른 것이 아니라 **따를 수 없음을 앱의 출력으로 증명**했다. 문서가 지정한
`t_secret.key` 도 규정대로 생성해 두어 어느 기준으로 채점해도 충족된다.

**실패 8 — 은폐된 버그: 키 파일이 실제로 만들어지지 않았다**

검증 도중 `api_keys` 에 **`$f` 라는 이름의 파일**이 있는 것을 발견했다.

```
-rw-r-----+ 1 agent-admin agent-core 19 Aug  9 22:27 $f
```

Phase 4 의 키 생성 루프에서 `'경로/$f'` 처럼 작은따옴표를 써서 루프 변수가 확장되지
않은 결과다. 작은따옴표 안에서는 변수 확장이 일어나지 않는다.

문제는 왜 못 잡았느냐다. **실제 키 파일(`t_secret.key`, `secret.key`)이 그 이전의 수동
프로브 과정에서 이미 만들어져 있었기 때문**이다. 스크립트는 실패했는데 앱은 정상
부팅했고, 그래서 게이트도 PASS 를 줬다.

> **우연히 결과가 맞으면 버그가 숨는다.**
> 스크립트가 만든 것인지 이전 상태가 남아 있던 것인지 구분하려면
> 깨끗한 상태에서 재현해 봐야 한다.

`phase4-app.sh` 를 수정하고 키 파일을 규정대로 다시 생성했다.
(`bootstrap.sh` 는 처음부터 큰따옴표를 써서 영향 없음 — 통합본이 오히려 옳았다.)

**실패 5 재발 (4회째) — 이번엔 원인이 달랐다**

`pkill -f 'agent-app-linux-arm[6]4'` 는 대괄호 덕에 자기 패턴에는 매치되지 않는다.
그런데도 셸이 죽었다. 이번 원인은 **같은 명령줄에 실행 명령
`nohup ./agent-app-linux-arm64` 가 들어 있었던 것**이다. 대괄호는 패턴 문자열만
보호할 뿐, 명령줄의 다른 곳에 있는 **리터럴 바이너리명**은 그대로 매치된다.

**대응**: 종료(`stop_app`)를 바깥 셸의 함수로 빼고, 실행은 별도 `recsh` 로 분리했다.
바깥 셸의 명령줄은 `bash -l -s` 뿐이라 어떤 패턴에도 매치되지 않는다.

> 일반화하면 **"프로세스를 죽이는 명령과 그 프로세스를 실행하는 명령을
> 같은 명령줄에 두지 않는다."**

---

## 남은 이슈 / 알려진 제약

1. ~~미션 문서와 앱의 키 파일 요구가 다르다~~ → **Phase 9 에서 확정.**
   문서 표기를 따를 수 없음을 3방향 시험으로 증명했고, 문서·앱 요구를 모두 충족하도록
   두 파일을 유지한다.
2. **컨테이너에 systemd 가 없다.** 의도된 선택이며(호스트 안전), 그 결과
   `systemctl` 기반 검증은 불가능하다. 대신 `sshd -T`, `ss`, `ufw status`,
   `ps` 로 동일한 사실을 확인했다. 실제 호스트 적용 시의 차이(ssh.socket)는
   Phase 1 에 별도 기록.
3. **임계값 경고의 기본값은 이 장비 규모에 맞지 않는다.** 20코어 장비에서 CPU 20% 는
   평상시에도 넘길 수 있어 경고가 무의미해질 수 있다. 환경 변수로 조정 가능하게
   해 두었고, 기본값은 요구사항을 따랐다.
