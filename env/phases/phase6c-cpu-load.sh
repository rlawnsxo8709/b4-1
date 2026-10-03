#!/bin/bash
# Phase 6c — CPU 실부하 경고 재검증 (6b-2 실패 수정)
set -u
source /usr/local/lib/rec.sh
evidence_open phase6-cron

AGENT_HOME=/home/agent-admin/agent-app
MON="$AGENT_HOME/bin/monitor.sh"

rec_note "[6b-2 실패 기록 — 원인 및 수정]
증상 : CPU 부하 생성기 8개를 띄운 뒤 monitor.sh 를 실행했는데
       CPU Usage 가 1.7% 로 측정되어 경고가 발생하지 않았다.
원인 : 스크립트가 아니라 '측정 방법'의 결함이었다.
       부하 생성을 rec 헬퍼(recsh)로 실행했는데, recsh 내부는
         out=\"\$(bash -c \"\$1\" 2>&1)\"
       즉 명령 치환이다. 명령 치환은 stdout 파이프가 닫힐 때까지 기다리는데,
       백그라운드 잡이 그 stdout 을 상속받으므로 12초 부하가 전부 끝날 때까지
       블록된다. 결과적으로 '부하가 끝난 뒤에' monitor.sh 가 실행됐다.
수정 : 부하 생성기의 stdin/stdout/stderr 를 모두 분리하고 setsid 로 떼어내
       명령 치환이 기다리지 않게 한다. 그 상태에서 부하와 측정을 겹치게 한다.
교훈 : 백그라운드 프로세스를 명령 치환 안에서 띄우면 비동기가 아니게 된다.
       '실행은 됐는데 기대한 효과가 없다'면 측정 도구 자체를 의심해야 한다."

echo "--- [6c-1] 부하 생성 (stdout 분리로 진짜 비동기 실행) ---"
NCPU=$(nproc)
LOAD_N=$(( NCPU / 2 ))   # 20코어 중 10개 → 이론상 약 50%
echo "코어 ${NCPU}개 중 ${LOAD_N}개 점유 시도"

for i in $(seq 1 "$LOAD_N"); do
    setsid timeout 25 bash -c 'while :; do :; done' </dev/null >/dev/null 2>&1 &
done
sleep 3

echo "--- [6c-2] 부하가 실제로 걸렸는지 확인 ---"
recsh "echo \"load average: \$(cut -d' ' -f1-3 /proc/loadavg)\"
       echo \"busy bash 프로세스 수: \$(pgrep -fc 'while :' || echo 0)\""

echo "--- [6c-3] 부하 상태에서 monitor.sh 실행 (기본 임계값 CPU 20%) ---"
recsh "sudo -u agent-admin '$MON'; echo \"(exit=\$?)\""
rec_note "이번 실행의 CPU Usage 는 실제 부하에 의한 측정값이며,
임계값 20% 를 넘겨 [WARNING] CPU threshold exceeded 가 출력되어야 한다.
임계값 주입 없이 기본값 그대로 경고가 발생한 것이 핵심이다."

echo "--- [6c-4] 부하 해제 대기 후 정상 복귀 ---"
recsh 'pkill -f "while :" 2>/dev/null; sleep 4; echo "부하 종료"'
recsh "sudo -u agent-admin '$MON' | grep -E 'CPU Usage|WARNING|All resources'; echo \"(exit=\$?)\""

echo
echo "=== Phase 6c gate 결과 ==="
recsh "
fail=0
# 부하를 다시 걸고, 기본 임계값에서 CPU 경고가 나오는지 확인
for i in \$(seq 1 $LOAD_N); do setsid timeout 15 bash -c 'while :; do :; done' </dev/null >/dev/null 2>&1 & done
sleep 3
out=\$(sudo -u agent-admin '$MON' 2>&1)
rc=\$?
echo \"\$out\" | grep -E 'CPU Usage'
echo \"\$out\" | grep -q 'WARNING. CPU threshold exceeded' || { echo 'NG: 실부하에서 CPU 경고 미발생'; fail=1; }
[ \$rc -eq 0 ] || { echo 'NG: 경고 발생 시 exit != 0'; fail=1; }
pkill -f 'while :' 2>/dev/null
[ \$fail -eq 0 ] && echo 'PHASE 6c GATE: PASS' || echo 'PHASE 6c GATE: FAIL'
exit \$fail"
