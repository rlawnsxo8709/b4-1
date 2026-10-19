#!/bin/bash
# =============================================================================
# monitor.sh — 에이전트 앱 상태 관제 및 로깅
#
#   위치   : $AGENT_HOME/bin/monitor.sh
#   소유   : agent-dev:agent-core   권한: 750
#   실행자 : agent-admin (cron 매분)
#
# 동작
#   1) Health Check  — 프로세스/포트가 죽어 있으면 즉시 exit 1 (실패로 종료)
#   2) 상태 점검     — 방화벽 비활성은 경고만 하고 계속 진행
#   3) 자원 수집     — CPU / MEM / DISK 사용률
#   4) 임계값 경고   — CPU>20%, MEM>10%, DISK>80%
#   5) 로그 기록     — monitor.log 에 1줄 추가, 10MB 초과 시 최대 10개로 로테이션
#
# 설계 판단 (왜 이렇게 짰는가)
#   - set -e 를 쓰지 않는다: 경고는 스크립트를 죽이면 안 된다. 종료는 오직
#     Health Check 실패에서만 명시적으로 한다.
#   - top / free 를 파싱하지 않고 /proc 을 직접 읽는다: 두 명령의 출력은
#     로케일(한국어 등)에 따라 헤더와 컬럼이 바뀌어 파싱이 깨진다.
#     /proc/stat 과 /proc/meminfo 는 로케일과 무관한 고정 포맷이다.
#   - ss 는 -p 옵션 없이 쓴다: -p 는 root 권한이 필요한데 실행자는 비특권
#     계정 agent-admin 이다. 포트 LISTEN 여부만 보면 되므로 -p 는 불필요하다.
#   - 방화벽은 'ufw status' 대신 /etc/ufw/ufw.conf 를 읽는다: ufw status 는
#     root 전용이다. sudo 권한을 추가로 주지 않고 점검하기 위한 선택이다.
#   - 프로세스 패턴에 대괄호를 쓴다: pgrep -f 가 자기 자신을 매치하는 사고를
#     막는다. 'agent-app-linux-arm[6]4' 는 실제 프로세스에는 매치되지만
#     이 패턴 문자열 자체에는 매치되지 않는다.
#   - 로그 로테이션을 logrotate 대신 스크립트 안에서 처리한다: logrotate 는
#     root 권한과 /etc/logrotate.d 접근이 필요한데 cron 실행자는 비특권
#     계정이다. 스크립트 자립성을 택했다.
# =============================================================================

set -uo pipefail

# 숫자·날짜 포맷이 로케일에 흔들리지 않도록 고정한다.
export LC_ALL=C

# -----------------------------------------------------------------------------
# 환경 변수 로드
#
# cron 은 /etc/profile.d 를 읽지 않는다. PATH 와 HOME 정도만 있는 최소 환경에서
# 실행되므로, 로그인 셸 환경에 기대지 말고 값의 원본을 직접 읽어야 한다.
# set -a 구간에서 대입된 변수는 자동으로 export 된다.
# -----------------------------------------------------------------------------
# 환경 파일은 '기본값'으로만 읽는다. 이미 환경에 있는 값은 덮어쓰지 않는다.
#
# 흔히 쓰는 (set -a; . file; set +a) 방식은 호출자가 명시적으로 준 값을
# 파일 값이 덮어써 버린다. AGENT_LOG_DIR=... ./monitor.sh 처럼 지정해도
# 무시되어 '분명히 넘겼는데 안 먹는' 문제가 된다.
# 명시적으로 준 값이 항상 이겨야 한다.
load_env_defaults() {
    local file="$1" line key val cur
    [ -r "$file" ] || return 0
    while IFS= read -r line; do
        case "$line" in ''|'#'*) continue ;; esac
        key="${line%%=*}"
        [ "$key" = "$line" ] && continue                    # '=' 가 없는 줄
        case "$key" in *[!A-Za-z0-9_]*) continue ;; esac     # 변수명이 아닌 줄
        val="${line#*=}"
        eval "cur=\${$key:-}"
        [ -n "$cur" ] && continue                            # 이미 설정됨 → 유지
        export "$key=$val"
    done < "$file"
}

load_env_defaults /etc/agent-app.env

# 환경 파일이 없거나 항목이 빠져도 동작하도록 기본값을 둔다.
AGENT_HOME="${AGENT_HOME:-/home/agent-admin/agent-app}"
AGENT_PORT="${AGENT_PORT:-15034}"
AGENT_LOG_DIR="${AGENT_LOG_DIR:-/var/log/agent-app}"
case "$(uname -m)" in
    aarch64|arm64) DEFAULT_APP_PATTERN='agent-app-linux-arm[6]4' ;;
    *)             DEFAULT_APP_PATTERN='agent-app-linux-x8[6]' ;;
esac
APP_PATTERN="${AGENT_APP_PATTERN:-$DEFAULT_APP_PATTERN}"

LOG_FILE="$AGENT_LOG_DIR/monitor.log"
UFW_CONF=/etc/ufw/ufw.conf

# 임계값 — 요구사항의 기본값은 CPU 20 / MEM 10 / DISK 80 이다.
# 환경 변수로 덮어쓸 수 있게 한 이유는 두 가지다.
#   (1) 검증: 실제 자원을 한계까지 몰지 않고도 경고 경로를 실증할 수 있다.
#   (2) 운영: 장비마다 정상 부하 수준이 다르다. 코어 20개 장비에서 CPU 20% 는
#       평상시에도 넘길 수 있는 값이라, 하드코딩하면 경고가 무의미해진다.
# 값을 주지 않으면 요구사항 그대로 동작한다.
CPU_THRESHOLD="${CPU_THRESHOLD:-20}"
MEM_THRESHOLD="${MEM_THRESHOLD:-10}"
DISK_THRESHOLD="${DISK_THRESHOLD:-80}"

# 로그 보존 정책
MAX_LOG_SIZE=$((10 * 1024 * 1024))   # 10MB
MAX_LOG_FILES=10                     # monitor.log.1 ~ .10

# -----------------------------------------------------------------------------
# 공통 함수
# -----------------------------------------------------------------------------

# bash 는 실수 비교를 못 한다. awk 로 대신한다. (a > b 이면 성공)
gt() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a > b) }'; }

die() {
    echo
    echo "[FATAL] $*"
    echo "====== MONITOR ABORTED ======"
    exit 1
}

# -----------------------------------------------------------------------------
# 자원 수집
# -----------------------------------------------------------------------------

# CPU — /proc/stat 의 첫 줄('cpu ' 로 시작, 모든 코어 합계)을 읽는다.
#
#   cpu  1925 50536 3070 1990454 1829  0   40      0     0     0
#        $2   $3    $4   $5      $6    $7  $8      $9    $10   $11
#        user nice  sys  idle    iowait irq softirq steal guest guest_nice
#
# 각 값은 부팅 이후 CPU 가 그 상태로 보낸 시간의 '누적치'다
# (단위 1/100초, 코어 합산 — 코어 6개면 1초에 약 600 씩 늘어난다).
#   $2  user        일반 프로세스가 일한 시간
#   $3  nice        우선순위를 낮춘 프로세스가 일한 시간
#                   (제공 앱은 스스로 nice=10 으로 낮추므로 앱 부하가 여기에 쌓인다)
#   $4  system      커널이 일한 시간 (시스템 콜 처리 등)
#   $5  idle        할 일이 없어 쉰 시간
#   $6  iowait      디스크 입출력을 기다리며 쉰 시간
#   $7  irq         하드웨어 인터럽트 처리
#   $8  softirq     소프트웨어 인터럽트 처리 (네트워크 패킷 처리 등)
#   $9  steal       가상 머신에서 하이퍼바이저가 다른 VM 에 내준 시간
#   $10 guest       이 머신이 게스트 VM 을 돌린 시간 ($2 에 이미 포함)
#   $11 guest_nice  nice 게스트 VM 시간 ($3 에 이미 포함)
#
# 가져오는 값은 두 개다.
#   쉰 시간  = idle($5) + iowait($6)
#              iowait 은 CPU 가 일하지 않고 기다리기만 하는 시간이라 쉰 것으로 본다.
#   전체 시간 = $2 ~ 마지막 칸의 합
#              guest·guest_nice 는 이중 합산되지만 VM 을 돌리지 않는 서버에서는 0 이다.
read_cpu_sample() {
    awk '/^cpu /{
        idle = $5 + $6
        total = 0
        for (i = 2; i <= NF; i++) total += $i
        print idle, total
    }' /proc/stat
}

# 누적치라 한 번만 읽으면 '부팅 이후 평균'이 나와 현재 상태를 알 수 없다.
# 그래서 1초 간격으로 두 번 읽고, 그 사이 늘어난 양만 비교한다.
#   사용률 = (1 - 쉰 시간 증가분 / 전체 시간 증가분) * 100
#   예) 1초 동안 전체 599 증가, 쉰 시간 568 증가 → (1 - 568/599) * 100 = 5.2%
# 측정 창을 1초로 둔 것은 매분 도는 cron 작업을 짧게 끝내기 위해서다.
# 대신 그 1초 밖에서 잠깐 튄 부하는 잡히지 않는다.
collect_cpu() {
    local i1 t1 i2 t2
    read -r i1 t1 < <(read_cpu_sample)
    sleep 1
    read -r i2 t2 < <(read_cpu_sample)
    awk -v i1="$i1" -v t1="$t1" -v i2="$i2" -v t2="$t2" 'BEGIN {
        di = i2 - i1; dt = t2 - t1
        if (dt <= 0) { print "0.0" } else { printf "%.1f", (1 - di / dt) * 100 }
    }'
}

# MEM — /proc/meminfo 에서 두 줄을 읽는다.
#
#   MemTotal:       16434648 kB     $1 = 항목명, $2 = 값, $3 = 단위(kB)
#   MemFree:        15586764 kB
#   MemAvailable:   15528376 kB
#
#   MemTotal      물리 메모리 전체 → 분모로 가져온다
#   MemAvailable  스왑 없이 새 프로그램이 바로 쓸 수 있는 양의 커널 추정치
#                 (비어 있는 메모리 + 비울 수 있는 캐시) → '여유분'으로 가져온다
#   MemFree       아무 데도 쓰이지 않는 메모리 → 쓰지 않는다
#
# 사용률 = (1 - MemAvailable / MemTotal) * 100
# MemFree 를 쓰지 않는 이유: 리눅스는 남는 메모리를 파일 캐시로 쓰고, 캐시는 필요하면
# 바로 비울 수 있다. MemFree 로 계산하면 이 캐시까지 '사용 중'으로 잡혀 사용률이 부풀려진다.
# CPU 와 달리 누적치가 아니라 '지금 상태'이므로 한 번만 읽으면 된다.
collect_mem() {
    awk '/^MemTotal:/     { total = $2 }
         /^MemAvailable:/ { avail = $2 }
         END {
             if (total > 0) printf "%.1f", (1 - avail / total) * 100
             else print "0.0"
         }' /proc/meminfo
}

# DISK — 루트(/) 파티션을 df -P 로 읽는다.
#
#   Filesystem     1024-blocks   Used Available Capacity Mounted on
#   overlay          414220248 193784 414026464       1% /
#   $1             $2          $3     $4        $5       $6
#
#   $2 1024-blocks  전체 크기 (KB)
#   $3 Used         사용 중인 양
#   $4 Available    일반 사용자가 더 쓸 수 있는 양 (root 예약분 제외)
#   $5 Capacity     사용률 = Used / (Used + Available), 올림 → DISK_USED 로 가져온다
#
# 1번째 줄은 헤더이므로 2번째 줄(NR == 2)의 5번째 칸에서 '%' 를 떼어 숫자만 남긴다.
# -P(POSIX 형식)를 쓰는 이유: 기본 df 는 장치명이 길면 줄을 바꿔 칸 위치가 밀린다.
# -P 는 파티션 하나를 항상 한 줄로 출력해 '2번째 줄 5번째 칸'이 고정된다.
collect_disk() {
    df -P / | awk 'NR == 2 { gsub("%", "", $5); print $5 }'
}

# -----------------------------------------------------------------------------
# 로그 로테이션 — 기록 '전에' 확인한다
#
# monitor.log 가 10MB 를 넘으면 .1 로 밀어내고 번호를 하나씩 올린다.
# 가장 오래된 .10 은 삭제된다. 결과적으로 최대 11개 파일(본체 + 10개)이
# 유지되며 총량은 약 110MB 를 넘지 않는다.
# 번호를 큰 쪽부터 옮겨야 덮어쓰기 사고가 나지 않는다.
# -----------------------------------------------------------------------------
rotate_log_if_needed() {
    [ -f "$LOG_FILE" ] || return 0

    local size
    size=$(stat -c %s "$LOG_FILE" 2>/dev/null || echo 0)
    [ "$size" -lt "$MAX_LOG_SIZE" ] && return 0

    echo "[INFO] Log size ${size} bytes exceeds ${MAX_LOG_SIZE} — rotating"

    rm -f "${LOG_FILE}.${MAX_LOG_FILES}"
    local i
    for (( i = MAX_LOG_FILES - 1; i >= 1; i-- )); do
        [ -f "${LOG_FILE}.${i}" ] && mv -f "${LOG_FILE}.${i}" "${LOG_FILE}.$(( i + 1 ))"
    done
    mv -f "$LOG_FILE" "${LOG_FILE}.1"

    echo "[INFO] Rotated: monitor.log -> monitor.log.1 (최대 ${MAX_LOG_FILES}개 보관)"
}

# =============================================================================
# 실행
# =============================================================================

echo "====== SYSTEM MONITOR RESULT ======"
echo

# --- 1) Health Check : 실패하면 즉시 종료한다 --------------------------------
echo "[HEALTH CHECK]"

APP_PID=$(pgrep -f "$APP_PATTERN" 2>/dev/null | head -1)
if [ -z "$APP_PID" ]; then
    echo "Checking process '${APP_PATTERN}'... [FAIL]"
    die "Agent application process not running."
fi
echo "Checking process '${APP_PATTERN}'... [OK] (PID: ${APP_PID})"

# ss 는 -p 없이 사용한다(비특권 계정에서 동작해야 하므로).
# 주소 끝이 :PORT 인 LISTEN 소켓을 찾는다. IPv4/IPv6 모두 매치되도록 [:.] 로 시작.
if ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${AGENT_PORT}\$"; then
    echo "Checking port ${AGENT_PORT}... [OK]"
else
    echo "Checking port ${AGENT_PORT}... [FAIL]"
    die "Port ${AGENT_PORT} is not in LISTEN state."
fi
echo

# --- 2) 상태 점검 : 경고만 하고 계속 진행한다 --------------------------------
echo "[SECURITY CHECK]"
if [ -r "$UFW_CONF" ] && grep -q '^ENABLED=yes' "$UFW_CONF"; then
    echo "Checking firewall (ufw)... [OK] (enabled)"
else
    # 방화벽이 꺼져 있다고 관제를 멈추면 안 된다. 관제는 계속하되 경고를 남긴다.
    echo "Checking firewall (ufw)... [WARNING]"
    echo "[WARNING] Firewall is not active — 인바운드가 무방비 상태입니다"
fi
echo

# --- 3) 자원 수집 -------------------------------------------------------------
CPU_USAGE=$(collect_cpu)
MEM_USAGE=$(collect_mem)
DISK_USED=$(collect_disk)

echo "[RESOURCE MONITORING]"
printf 'CPU Usage  : %s%%\n' "$CPU_USAGE"
printf 'MEM Usage  : %s%%\n' "$MEM_USAGE"
printf 'DISK Used  : %s%%\n' "$DISK_USED"
echo

# --- 4) 임계값 경고 -----------------------------------------------------------
WARN_COUNT=0
if gt "$CPU_USAGE" "$CPU_THRESHOLD"; then
    echo "[WARNING] CPU threshold exceeded (${CPU_USAGE}% > ${CPU_THRESHOLD}%)"
    WARN_COUNT=$(( WARN_COUNT + 1 ))
fi
if gt "$MEM_USAGE" "$MEM_THRESHOLD"; then
    echo "[WARNING] MEM threshold exceeded (${MEM_USAGE}% > ${MEM_THRESHOLD}%)"
    WARN_COUNT=$(( WARN_COUNT + 1 ))
fi
if gt "$DISK_USED" "$DISK_THRESHOLD"; then
    echo "[WARNING] DISK threshold exceeded (${DISK_USED}% > ${DISK_THRESHOLD}%)"
    WARN_COUNT=$(( WARN_COUNT + 1 ))
fi
[ "$WARN_COUNT" -eq 0 ] && echo "[INFO] All resources within thresholds"
echo

# --- 5) 로그 기록 -------------------------------------------------------------
if [ ! -d "$AGENT_LOG_DIR" ]; then
    die "Log directory not found: ${AGENT_LOG_DIR}"
fi
if [ ! -w "$AGENT_LOG_DIR" ]; then
    die "Log directory not writable by $(id -un): ${AGENT_LOG_DIR}"
fi

rotate_log_if_needed

LOG_LINE="[$(date '+%Y-%m-%d %H:%M:%S')] PID:${APP_PID} CPU:${CPU_USAGE}% MEM:${MEM_USAGE}% DISK_USED:${DISK_USED}%"
if echo "$LOG_LINE" >> "$LOG_FILE"; then
    echo "[INFO] Log appended: ${LOG_FILE}"
else
    die "Failed to append log: ${LOG_FILE}"
fi

exit 0
