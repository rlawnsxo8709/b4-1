#!/bin/bash
# Phase 6c gate 재실행 — pkill 자기매치 수정판
set -u
source /usr/local/lib/rec.sh
evidence_open phase6-cron

AGENT_HOME=/home/agent-admin/agent-app
MON="$AGENT_HOME/bin/monitor.sh"
LOAD_N=$(( $(nproc) / 2 ))

rec_note "[pkill 자기매치 — 같은 함정 3회째]
Phase 6c 의 gate 가 exit=143(SIGTERM) 으로 중단됐다.
gate 안에서 pkill -f 'while :' 를 실행했는데, 그 gate 자체가
bash -c \"... pkill -f 'while :' ...\" 로 돌고 있어 자기 명령줄이 패턴에 매치됐다.
Phase 4 의 앱 종료, 이번 부하 종료 — 같은 원인으로 세 번 걸렸다.

일반화하면: pkill/pgrep -f 는 '자기 자신을 포함한' 전체 프로세스 목록을 훑는다.
패턴 문자열이 실행 중인 셸의 명령줄에 남아 있으면 반드시 자기를 잡는다.
대응은 두 가지다.
  (1) 패턴에 대괄호를 넣어 문자열과 정규식을 어긋나게 한다: 'whil[e] :'
  (2) 패턴을 파일(스크립트) 안에 두고 명령줄에는 노출하지 않는다.
monitor.sh 는 (2)에 해당해 안전하지만, 감시 패턴에 (1)도 함께 적용해 두었다."

echo "--- 잔여 부하 프로세스 정리 (안전 패턴) ---"
recsh "pkill -f 'whil[e] :' 2>/dev/null; sleep 2; echo \"잔여: \$(pgrep -fc 'whil[e] :' 2>/dev/null || echo 0)\""

echo
echo "=== Phase 6c gate 재실행 (실부하 기본 임계값 CPU 경고) ==="
for i in $(seq 1 "$LOAD_N"); do
    setsid timeout 20 bash -c 'while :; do :; done' </dev/null >/dev/null 2>&1 &
done
sleep 3

recsh "
fail=0
out=\$(sudo -u agent-admin '$MON' 2>&1); rc=\$?
echo \"\$out\" | grep -E 'CPU Usage'
echo \"\$out\" | grep -E 'WARNING. CPU threshold'
echo \"\$out\" | grep -q 'WARNING. CPU threshold exceeded' || { echo 'NG: 실부하에서 CPU 경고 미발생'; fail=1; }
[ \$rc -eq 0 ] || { echo 'NG: 경고 발생 시 exit != 0'; fail=1; }
[ \$fail -eq 0 ] && echo 'PHASE 6c GATE: PASS' || echo 'PHASE 6c GATE: FAIL'
exit \$fail"

recsh "pkill -f 'whil[e] :' 2>/dev/null; sleep 2; echo \"정리 완료. 잔여: \$(pgrep -fc 'whil[e] :' 2>/dev/null || echo 0)\""
recsh "sudo -u agent-admin '$MON' | grep -E 'CPU Usage|All resources'"
