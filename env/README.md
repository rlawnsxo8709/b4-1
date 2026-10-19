# env — 실습 환경

이 미션은 SSH·방화벽·계정·cron 같은 **서버 설정을 바꾸는 작업**이라 Mac 에서 직접 할 수 없다.
그래서 Docker 컨테이너 안에 Ubuntu 서버를 띄우고 그 안에서 수행한다.

이 디렉토리는 그 **무대와 기록 도구**다. 제출물은 저장소 루트의 `README.md`(수행 내역서)와
`scripts/monitor.sh` 이고, 여기 있는 파일은 제출물을 실제로 돌려 보고 증거를 남기기 위한 것이다.

---

## 빠른 시작

Docker 엔진(Docker Desktop, OrbStack 등)이 떠 있어야 한다. 이 디렉토리(`env/`)에서:

```bash
./run.sh                                          # 이미지 빌드 + 컨테이너 기동 + 앱 반입
docker cp ../scripts/monitor.sh agent-lab:/tmp/   # 제출물을 컨테이너로 복사
docker exec -i agent-lab bash -s < bootstrap.sh   # 미션 요구사항 일괄 적용

# 앱을 백그라운드로 상주 (x86_64 기준. arm64 는 바이너리명을 agent-app-linux-arm64 로)
docker exec agent-lab sudo -u agent-admin bash -c \
  'set -a; . /etc/agent-app.env; set +a; cd "$AGENT_HOME" || exit 1; nohup ./agent-app-linux-x86 > "$AGENT_HOME/app-boot.log" 2>&1 < /dev/null &'

docker exec agent-lab sudo -u agent-admin /home/agent-admin/agent-app/bin/monitor.sh   # 관제 1회
docker exec agent-lab tail -5 /var/log/agent-app/monitor.log                            # cron 누적 확인

./teardown.sh                                     # 정리
```

앱을 포그라운드로 띄워 Boot Sequence 를 보는 방법 등 상세는 저장소 루트 `README.md` 6절.

---

## 파일 구성

### ① 환경 만들기·지우기

| 파일 | 실행 위치 | 역할 |
|---|---|---|
| `Dockerfile` | — | Ubuntu 24.04 + sshd·ufw·cron·acl 등을 설치한 이미지 설계도 (아래 설명) |
| `entrypoint.sh` | 컨테이너 | 컨테이너 시작 시 sshd·cron 을 직접 띄우고, UFW 가 켜져 있던 상태면 규칙을 다시 적용한다. systemd 가 없으므로 이것이 대신한다 |
| `run.sh` | 호스트 | 이미지 빌드 → 전용 네트워크 생성 → 컨테이너 (재)생성 → `../agent-app.zip` 에서 아키텍처에 맞는 바이너리를 골라 `/opt` 로 반입 |
| `bootstrap.sh` | 컨테이너 | 미션 요구사항 일괄 적용: SSH(20022, Root 차단) → UFW → 계정·그룹 → 디렉토리·권한·ACL → 환경 변수 → 앱·키 파일 → monitor.sh 배치 → cron 등록 |
| `teardown.sh` | 호스트 | 컨테이너·네트워크 삭제, `--all` 이면 이미지까지. 컨테이너가 만든 `evidence/` 파일의 소유권도 되돌린다 |

`bootstrap.sh` 는 아래 `phases/` 에서 시행착오를 거쳐 **확정된 설정만 모은 통합본**이다.

### ② 증거 기록 도구

수행 내역서에 붙일 출력을 손으로 옮겨 적지 않기 위해 만든 것이다.

| 파일 | 실행 위치 | 역할 |
|---|---|---|
| `rec.sh` | 컨테이너 | `rec`, `recsh`, `rec_expect_fail`, `rec_note` 함수 모음. 명령을 실행하면서 [시각·명령·출력·종료코드]를 `evidence/*.txt` 에 append 한다. 이미지에 포함되어 로그인 셸에서 자동 로드된다 |
| `dexec.sh` | 호스트 | `./dexec.sh <스크립트>` — 컨테이너에서 스크립트를 실행하고 전체 출력을 `evidence/session/<날짜>-session.log` 에 남긴다 |
| `collect-evidence.sh` | 컨테이너 | 필수 증거 8종을 재수집해 `evidence/FINAL-VERIFICATION.txt` 를 **새로 쓴다** (cron 확인을 위해 70초 대기 포함) |
| `snapshot.sh` | 컨테이너 | 실제 설정 파일·명령 출력을 `evidence/snapshots/` 로 복사한다 |

> **주의**: 컨테이너의 `/evidence` 는 저장소 `evidence/` 에 바인드 마운트되어 있다.
> 이 도구들을 실행하면 수행 내역서가 인용하는 2026-08 원본 증거가 덮어써지거나 뒤에 덧붙는다.
> 설정을 실제로 바꿔 증거를 다시 만들 때만 쓴다.

### ③ `phases/` — 단계별 수행 기록

2026-08 수행 당시 단계마다 실행한 스크립트다. 이름에 `b`·`c`·`d` 가 붙은 것은
그 단계에서 실패한 뒤 고쳐서 다시 검증한 기록이다(원인은 루트의 `WORKLOG.md`).

| 파일 | 내용 |
|---|---|
| `phase0-env.sh` | 실습 환경 검증 |
| `phase1-ssh.sh` | SSH 포트 20022 변경 + Root 원격 로그인 차단 |
| `phase2-ufw.sh` | UFW: 필요한 포트만 허용 |
| `phase2b-ufw-gate.sh` | Phase 2 검사식 수정 후 재검증 |
| `phase2c-probe-host.sh` | 방화벽이 실제로 막는지 컨테이너 **바깥**(호스트)에서 접속 시험 |
| `phase3-account-acl.sh` | 계정 / 그룹 / 디렉토리 / ACL |
| `phase3b-acl-fix.sh` | agent-test 가 upload_files 에 도달하지 못하던 결함 수정 |
| `phase4-app.sh` | 앱 실행 환경 구성 및 기동 |
| `phase5-monitor.sh` | monitor.sh 배치 및 검증 (정상 / 실패 / 경고 / 로테이션) |
| `phase6-cron.sh` | cron 매분 자동 실행 |
| `phase6b-threshold.sh` | 임계값 경고 경로 실증 |
| `phase6c-cpu-load.sh` | CPU 실부하 경고 재검증 |
| `phase6d-gate.sh` | 6c 검사 재실행 (pkill 자기매치 수정판) |
| `phase9-doc-conformance.sh` | 미션 문서 표기(키 경로·파일명)와 앱 요구의 정합성 재검증 |

> **기록용이며 다시 실행하지 않는다.** 14개 모두 `evidence/` 에 기록을 남기고,
> `phase0`·`phase4`·`phase5`·`phase9` 는 arm64 바이너리명이 박혀 있어 x86_64 호스트에서는
> 그대로 동작하지 않는다. 환경 재현은 `bootstrap.sh` 로 한다.

---

## Dockerfile

```dockerfile
FROM ubuntu:24.04
```
베이스 이미지. 미션 권장은 22.04 이며, 24.04 와의 차이는 아래 "실제 서버와 다른 점" 참조.

| 구간 | 하는 일 |
|---|---|
| `ENV DEBIAN_FRONTEND=noninteractive` | apt 설치 중 대화형 질문(시간대 선택 등)으로 빌드가 멈추지 않게 한다 |
| `ENV TZ=Asia/Seoul` + `ln -snf .../zoneinfo` | 로그 시각을 한국 시간으로 맞춘다 (`monitor.log` 타임스탬프) |
| `apt-get install ...` | 미션에 필요한 도구만 설치하고 apt 캐시는 지워 이미지를 줄인다 |
| `mkdir -p /run/sshd && ssh-keygen -A` | sshd 가 요구하는 런타임 디렉토리와 호스트 키 생성 |
| `COPY entrypoint.sh`, `COPY rec.sh` | 진입점과 증거 기록 헬퍼를 이미지에 넣는다 |
| `/etc/profile.d/00-rec.sh` | 로그인 셸마다 `rec.sh` 를 자동 로드 |
| `EXPOSE 20022 15034` | 사용하는 포트의 **문서 표기**일 뿐, 실제 게시는 `run.sh` 가 정한다 |
| `ENTRYPOINT [entrypoint.sh]` | 컨테이너 시작 시 sshd·cron 기동 후 대기 |

설치 패키지와 쓰임새:

| 패키지 | 쓰임새 |
|---|---|
| `openssh-server` | sshd (포트 20022, Root 차단) |
| `ufw`, `iptables` | 방화벽 (UFW 는 iptables 의 프런트엔드) |
| `cron` | monitor.sh 매분 실행 |
| `acl` | `setfacl` / `getfacl` |
| `iproute2` | `ss` (포트 LISTEN 확인) |
| `sudo` | 다른 계정으로 명령 실행 (`sudo -u agent-admin ...`) |
| `procps`, `psmisc` | `ps`, `pgrep`, `pkill` 등 프로세스 도구 |
| `util-linux`, `findutils`, `gzip`, `less` | 기본 유틸리티 |
| `tzdata` | 시간대 데이터 |
| `ca-certificates` | TLS 인증서 |

**systemd 를 일부러 넣지 않았다.** 컨테이너에서 systemd 를 돌리려면 `--privileged` 와
호스트 cgroup 쓰기 마운트가 필요한데, 이는 호스트 탈출 경로를 여는 것이다.
sshd·cron·ufw·ACL 은 systemd 없이 동작하므로 `entrypoint.sh` 가 직접 띄운다.

---

## 실제 서버와 다른 점

| 항목 | 이 환경 | 실제 Ubuntu 서버(VM) |
|---|---|---|
| OS 버전 | Ubuntu 24.04 | 미션 권장 22.04 |
| 서비스 관리 | systemd 없음. `systemctl` 사용 불가, sshd·cron 은 `entrypoint.sh` 가 기동 | `systemctl restart ssh` 등. 22.10+ 는 `ssh.socket` 이 포트를 먼저 잡으므로 `systemctl disable --now ssh.socket` 이 추가로 필요 |
| 방화벽 범위 | 컨테이너 네트워크 네임스페이스에만 적용 (`NET_ADMIN`, `NET_RAW` capability 로 허용) | 호스트 전체 |
| 호스트에서의 접근 | `127.0.0.1:20022` 만 게시. 15034 는 게시하지 않아 컨테이너 안에서만 보인다 | 방화벽이 허용한 포트로 외부 접근 가능 |
| 재시작 후 | sshd·cron·UFW 는 `entrypoint.sh` 가 복구. **앱은 자동으로 뜨지 않는다** | systemd 유닛을 만들면 자동 기동 가능 |

---

## 자주 하는 작업

**monitor.sh 를 고친 뒤 컨테이너에 반영** — 컨테이너 안의 파일은 저장소 파일의 사본이다.
```bash
docker cp ../scripts/monitor.sh agent-lab:/tmp/
docker exec agent-lab sudo -u agent-dev cp /tmp/monitor.sh /home/agent-admin/agent-app/bin/monitor.sh
```
기존 파일에 덮어쓰므로 소유자(agent-dev:agent-core)와 권한(750)이 유지된다.

**경고 경로 확인** — 이 앱의 부하는 코어 1개·최대 256MB 라 코어와 메모리가 넉넉한 호스트에서는
기본 임계값(CPU 20%, MEM 10%)을 넘지 않는다. 임계값을 낮춰 한 번 실행한다(로그에 1줄 기록됨).
```bash
docker exec agent-lab sudo -u agent-admin env CPU_THRESHOLD=1 MEM_THRESHOLD=1 \
  /home/agent-admin/agent-app/bin/monitor.sh
```

**컨테이너 셸 접속**
```bash
docker exec -it agent-lab bash -l
```
