#!/bin/bash
# Phase 5 — monitor.sh 배치 및 검증 (정상 / 실패 / 경고 / 로테이션 전 경로)
set -u
source /usr/local/lib/rec.sh
evidence_open phase5-monitor

AGENT_HOME=/home/agent-admin/agent-app
LOG_DIR=/var/log/agent-app
MON="$AGENT_HOME/bin/monitor.sh"
APP_PAT='agent-app-linux-arm[6]4'

echo "--- [5-1] agent-dev 계정으로 monitor.sh 배치 ---"
rec_note "monitor.sh 는 agent-dev 가 '직접' 작성한다.
root 로 만들고 소유권만 바꾸면 Phase 3 에서 설계한 ACL 이 실제로 동작하는지
검증되지 않는다. agent-dev 가 스스로 \$AGENT_HOME/bin 에 쓸 수 있어야
'개발자가 스크립트를 작성하고 운영자가 실행한다'는 역할 분리가 성립한다."

recsh "sudo -u agent-dev cp /tmp/monitor.sh '$MON' && sudo -u agent-dev chmod 750 '$MON' && echo 'agent-dev 가 직접 배치 완료'"
recsh "ls -l '$MON'"
rec_note "소유자 agent-dev, 그룹 agent-core, 권한 750 인지 확인.
그룹이 agent-core 로 자동 지정된 것은 bin 디렉토리의 setgid 덕분이다.
agent-dev 가 chgrp 를 하지 않았는데도 그룹이 맞춰졌다."

echo
echo "=============================================================="
echo " [5-2] 실행 권한 검증 — 누가 실행할 수 있는가"
echo "=============================================================="
rec_note "cron 실행자는 agent-admin 이다. monitor.sh 는 750(rwxr-x---)이고
그룹이 agent-core 이므로, agent-core 소속인 agent-admin 은 그룹 권한 r-x 로
실행할 수 있어야 한다. 반대로 agent-core 가 아닌 agent-test 는 막혀야 한다.
Phase 3 의 권한 설계가 실제로 맞물려 돌아가는지 확인되는 지점이다."

recsh "sudo -u agent-admin test -x '$MON' && echo 'OK: agent-admin 실행 가능 (agent-core 소속)'"
recsh "sudo -u agent-dev   test -x '$MON' && echo 'OK: agent-dev 실행 가능 (소유자)'"
rec_expect_fail sudo -u agent-test cat "$MON"

echo
echo "=============================================================="
echo " [5-3] 정상 경로 — cron 실행자(agent-admin)로 수동 실행"
echo "=============================================================="
recsh "sudo -u agent-admin '$MON'; echo \"(exit=\$?)\""

echo "--- [5-4] 로그 기록 확인 ---"
recsh "ls -l '$LOG_DIR/monitor.log' && echo '--- 최근 라인 ---' && tail -3 '$LOG_DIR/monitor.log'"
rec_note "로그 포맷이 요구사항과 일치하는지 확인:
[YYYY-MM-DD HH:MM:SS] PID:... CPU:..% MEM:..% DISK_USED:..%"

echo "--- [5-5] 로그 파일 소유/그룹 (setgid 상속 확인) ---"
recsh "stat -c '%n  owner=%U  group=%G  mode=%a' '$LOG_DIR/monitor.log'"
rec_note "agent-admin 이 만든 파일인데 그룹이 agent-core 인 것은
로그 디렉토리의 setgid 비트가 동작했다는 뜻이다. 이것이 없으면 파일 그룹이
agent-admin 이 되어 agent-dev 가 로그를 읽지 못하게 된다."

echo
echo "=============================================================="
echo " [5-6] 경고 경로 — 방화벽을 끄면 경고만 내고 계속 진행하는가"
echo "=============================================================="
rec_note "요구사항: 방화벽 비활성 시 [WARNING] 을 출력하되 스크립트는 종료하지 않는다.
관제 도구가 방화벽 상태 때문에 멈춰 버리면 정작 필요한 자원 지표를 잃는다."

recsh "ufw --force disable >/dev/null 2>&1; grep '^ENABLED=' /etc/ufw/ufw.conf"
recsh "sudo -u agent-admin '$MON'; echo \"(exit=\$?)\""
rec_note "위 실행에서 [WARNING] 이 출력되었으나 exit=0 으로 정상 종료되었고
로그도 정상 기록되었는지 확인할 것. 경고는 흐름을 끊지 않아야 한다."

recsh "ufw --force enable >/dev/null 2>&1; grep '^ENABLED=' /etc/ufw/ufw.conf; echo '방화벽 복구 완료'"
recsh "sudo -u agent-admin '$MON' | grep -E 'firewall|WARNING' ; echo \"(exit=\$?)\""

echo
echo "=============================================================="
echo " [5-7] 실패 경로 — 앱이 죽으면 exit 1 로 종료하는가"
echo "=============================================================="
rec_note "Health Check 는 '경고'가 아니라 '실패'다. 감시 대상이 죽었는데
관제 스크립트가 정상 종료하면 cron 이 이상을 감지할 방법이 없다."

recsh "pkill -f '$APP_PAT'; sleep 2; pgrep -f '$APP_PAT' >/dev/null && echo 'still running' || echo '앱 종료됨'"
recsh "sudo -u agent-admin '$MON'; echo \"(exit=\$?)\""
rec_note "위 exit 코드가 1 이어야 한다. 프로세스 검사에서 [FAIL] 이 뜨고
그 시점에 즉시 종료되므로 포트 검사 이후 단계는 실행되지 않는다."

echo "--- [5-8] 앱 재기동 ---"
recsh "sudo -u agent-admin bash -c '
    set -a; . /etc/agent-app.env; set +a
    cd \"\$AGENT_HOME\"
    nohup ./agent-app-linux-arm64 >> \"\$AGENT_HOME/app-boot.log\" 2>&1 &
    echo \"relaunched pid=\$!\"'
sleep 5
ss -tuln | grep ':15034 ' && echo '앱 재기동 확인'"

echo "--- [5-9] 포트만 죽은 경우도 실패로 처리되는지 (참고) ---"
rec_note "프로세스는 살아 있으나 포트가 닫힌 상황은 별도 검사 항목이다.
본 앱은 프로세스와 포트가 함께 움직이므로 별도 실증은 생략하고,
스크립트 로직상 포트 검사 실패 시에도 die() 로 exit 1 함을 코드로 확인한다."
recsh "grep -A3 'Checking port' '$MON' | head -12"

echo
echo "=============================================================="
echo " [5-10] 로그 로테이션 — 10MB 초과 시 동작하는가"
echo "=============================================================="
rec_note "10MB 를 실제로 쌓으려면 오래 걸리므로, 더미 데이터로 임계 크기를
만든 뒤 스크립트를 실행해 로테이션 동작을 실증한다."

recsh "sudo -u agent-admin bash -c 'yes \"[2026-01-01 00:00:00] PID:0 CPU:0.0% MEM:0.0% DISK_USED:0%\" | head -c 11000000 > $LOG_DIR/monitor.log'
       ls -l $LOG_DIR/monitor.log | awk '{print \$5, \$9}'"
recsh "sudo -u agent-admin '$MON' | grep -E 'INFO|Rotat'; echo \"(exit=\$?)\""
recsh "ls -l $LOG_DIR/ | grep monitor"
rec_note "monitor.log 가 monitor.log.1 로 밀려나고, 새 monitor.log 가
작은 크기로 다시 시작되었는지 확인할 것."

echo "--- [5-11] 로테이션 후 정리 (이후 단계의 cron 검증을 위해 초기화) ---"
recsh "sudo -u agent-admin bash -c 'rm -f $LOG_DIR/monitor.log*; touch $LOG_DIR/monitor.log'
       ls -l $LOG_DIR/"

echo
echo "=== Phase 5 gate 결과 ==="
recsh "
fail=0
[ \"\$(stat -c '%U:%G:%a' '$MON')\" = 'agent-dev:agent-core:750' ] || { echo \"NG: monitor.sh perm = \$(stat -c '%U:%G:%a' '$MON')\"; fail=1; }
sudo -u agent-admin test -x '$MON' || { echo 'NG: agent-admin cannot execute'; fail=1; }
sudo -u agent-test  cat  '$MON' >/dev/null 2>&1 && { echo 'NG: agent-test can read monitor.sh'; fail=1; }

# 정상 실행 → exit 0 + 로그 1줄 증가
before=\$(wc -l < '$LOG_DIR/monitor.log' 2>/dev/null || echo 0)
sudo -u agent-admin '$MON' >/dev/null 2>&1 || { echo 'NG: normal run exit != 0'; fail=1; }
after=\$(wc -l < '$LOG_DIR/monitor.log' 2>/dev/null || echo 0)
[ \"\$after\" -gt \"\$before\" ] || { echo 'NG: log line not appended'; fail=1; }

# 로그 포맷 검증
tail -1 '$LOG_DIR/monitor.log' | grep -qE '^\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\] PID:[0-9]+ CPU:[0-9.]+% MEM:[0-9.]+% DISK_USED:[0-9]+%\$' \
  || { echo \"NG: log format mismatch: \$(tail -1 '$LOG_DIR/monitor.log')\"; fail=1; }

[ \$fail -eq 0 ] && echo 'PHASE 5 GATE: PASS' || echo 'PHASE 5 GATE: FAIL'
exit \$fail"
