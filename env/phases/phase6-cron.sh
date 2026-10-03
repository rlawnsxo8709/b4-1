#!/bin/bash
# Phase 6 — cron 매분 자동 실행
set -u
source /usr/local/lib/rec.sh
evidence_open phase6-cron

AGENT_HOME=/home/agent-admin/agent-app
LOG_DIR=/var/log/agent-app
MON="$AGENT_HOME/bin/monitor.sh"

echo "--- [6-1] cron 데몬 상주 확인 ---"
rec_note "cron 등록에서 가장 흔한 실패는 문법 오류가 아니라
'cron 데몬이 아예 안 돌고 있는 것'이다. 등록은 성공하고 아무 일도 일어나지
않으므로 원인을 찾기 어렵다. 등록 전에 데몬부터 확인한다."
recsh "ps -eo pid,user,comm --no-headers | grep cron || echo 'NG: cron not running'"

echo "--- [6-2] agent-admin crontab 등록 ---"
rec_note "리디렉션을 /dev/null 이 아니라 cron.out 으로 보내는 이유:
cron 은 최소 환경에서 실행되므로 대화형 셸에서는 나지 않던 오류가 여기서만
발생한다. 출력을 버리면 그 오류를 영영 볼 수 없다. cron.out 은 'cron 환경에서만
생기는 문제'를 잡는 유일한 창구다."

sudo -u agent-admin crontab - <<EOF
# B4-1 시스템 관제 자동화
# monitor.sh 를 매분 실행하고, cron 환경에서만 발생하는 오류를 cron.out 에 남긴다.
* * * * * $MON >> $LOG_DIR/cron.out 2>&1
EOF

recsh "sudo -u agent-admin crontab -l"

echo "--- [6-3] 등록 시점의 로그 상태 (기준점) ---"
recsh "sudo -u agent-admin bash -c 'wc -l < $LOG_DIR/monitor.log'"
BEFORE=$(sudo -u agent-admin bash -c "wc -l < $LOG_DIR/monitor.log")
T0=$(date '+%F %T')
rec_note "기준 시각: $T0 / 기준 라인 수: $BEFORE
자동 실행의 증명은 '전후 두 시점의 측정값'이 있어야 성립한다.
한 시점의 로그만 보여 주면 수동 실행과 구별되지 않는다."

echo "--- [6-4] 2분 20초 대기 (매분 실행이므로 최소 2회 누적되어야 한다) ---"
for i in $(seq 1 14); do
    printf '  %s  경과 %2d0초  현재 라인 수: %s\n' \
        "$(date '+%H:%M:%S')" "$i" "$(sudo -u agent-admin bash -c "wc -l < $LOG_DIR/monitor.log")"
    sleep 10
done

AFTER=$(sudo -u agent-admin bash -c "wc -l < $LOG_DIR/monitor.log")
T1=$(date '+%F %T')

echo "--- [6-5] 자동 누적 결과 ---"
recsh "echo '기준 시각 : $T0   라인 수: $BEFORE'
       echo '측정 시각 : $T1   라인 수: $AFTER'
       echo \"증가분   : \$(( $AFTER - $BEFORE )) 줄\""

echo "--- [6-6] 누적된 로그 (타임스탬프가 1분 간격인지) ---"
recsh "sudo -u agent-admin tail -6 $LOG_DIR/monitor.log"
rec_note "타임스탬프가 정확히 1분 간격으로 찍혀 있다면 cron 이 스케줄대로
실행한 것이다. 수동 실행이었다면 간격이 불규칙했을 것이다."

echo "--- [6-7] cron 실행 기록 (시스템 로그) ---"
recsh "grep -i cron /var/log/syslog 2>/dev/null | tail -5 || echo '(syslog 미사용 환경 — cron.out 으로 대체 확인)'"

echo "--- [6-8] cron.out — cron 환경에서의 오류 여부 ---"
recsh "if [ -s $LOG_DIR/cron.out ]; then
         echo '--- cron.out 내용 (마지막 25줄) ---'
         sudo -u agent-admin tail -25 $LOG_DIR/cron.out
       else
         echo 'cron.out 비어 있음 = cron 환경에서 오류 없음'
       fi"

echo "--- [6-9] 임계값 경고가 실제로 기록되었는지 ---"
rec_note "제공 앱이 CPU/메모리를 주기적으로 끌어올리므로, 시간이 지나면
임계값 경고가 자연스럽게 발생한다. 인위적 부하 없이 경고 로직이 동작하는지
확인한다."
recsh "grep -c 'WARNING' $LOG_DIR/cron.out 2>/dev/null || echo 0"
recsh "grep 'WARNING' $LOG_DIR/cron.out 2>/dev/null | tail -5 || echo '(이번 구간에는 경고 미발생)'"

echo "--- [6-10] 자원 사용률 추이 ---"
recsh "sudo -u agent-admin tail -10 $LOG_DIR/monitor.log | awk '{print \$3, \$4, \$5, \$6}'"

echo
echo "=== Phase 6 gate 결과 ==="
recsh "
fail=0
pgrep -x cron >/dev/null || { echo 'NG: cron daemon not running'; fail=1; }
sudo -u agent-admin crontab -l | grep -q 'monitor.sh' || { echo 'NG: crontab entry missing'; fail=1; }
sudo -u agent-admin crontab -l | grep -qE '^\* \* \* \* \*' || { echo 'NG: not scheduled every minute'; fail=1; }
[ $AFTER -gt $BEFORE ] || { echo 'NG: monitor.log did not grow (자동 실행 안 됨)'; fail=1; }
[ \$(( $AFTER - $BEFORE )) -ge 2 ] || { echo 'NG: 2분 대기했으나 2회 미만 실행됨'; fail=1; }
tail -1 $LOG_DIR/monitor.log | grep -qE '^\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\] PID:[0-9]+ CPU:[0-9.]+% MEM:[0-9.]+% DISK_USED:[0-9]+%\$' || { echo 'NG: log format'; fail=1; }
[ \$fail -eq 0 ] && echo 'PHASE 6 GATE: PASS' || echo 'PHASE 6 GATE: FAIL'
exit \$fail"
