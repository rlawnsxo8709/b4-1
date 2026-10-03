#!/bin/bash
# Phase 6b — 임계값 경고 경로 실증
set -u
source /usr/local/lib/rec.sh
evidence_open phase6-cron

AGENT_HOME=/home/agent-admin/agent-app
LOG_DIR=/var/log/agent-app
MON="$AGENT_HOME/bin/monitor.sh"

rec_note "[임계값 경고 실증 — 왜 별도 검증이 필요한가]
Phase 6 의 cron 누적 구간에서는 임계값 경고가 한 번도 뜨지 않았다.
원인은 스크립트 결함이 아니라 장비 규모다.
  - CPU 20 코어 → 앱이 코어 하나를 100% 써도 시스템 전체로는 5%
  - MEM 119.6GB → 앱이 256MB 를 잡아도 전체 비율은 0.2% 남짓
요구사항의 임계값(CPU 20%, MEM 10%)은 소형 VM 기준으로 잡힌 값이라
이 장비에서는 평상시 부하로 도달하지 않는다.

따라서 경고 경로를 두 가지 방법으로 각각 실증한다.
  (1) CPU  — 실제 부하를 걸어 진짜로 20% 를 넘긴다. 측정값도 경고도 모두 진짜다.
  (2) MEM/DISK — 119GB 메모리와 디스크를 한계까지 채우는 것은 위험하고 무의미하므로,
      임계값을 낮춰 주입하는 방식으로 비교·분기 로직이 동작함을 확인한다.
      스크립트의 기본값은 요구사항 그대로(20/10/80) 유지되며 변경하지 않았다."

echo "--- [6b-1] 장비 규모 (경고가 왜 안 떴는지의 근거) ---"
recsh "echo \"CPU cores : \$(nproc)\"
       awk '/MemTotal/{printf \"MemTotal  : %.1f GB\n\", \$2/1024/1024}' /proc/meminfo
       echo \"코어 1개를 100% 점유해도 시스템 전체로는 \$(awk -v n=\$(nproc) 'BEGIN{printf \"%.1f\", 100/n}')%\""

echo
echo "=============================================================="
echo " [6b-2] CPU 경고 — 실제 부하를 걸어 검증"
echo "=============================================================="
rec_note "20코어 중 8개를 점유해 시스템 CPU 사용률을 40% 안팎으로 올린다.
monitor.sh 는 /proc/stat 을 1초 간격으로 샘플링하므로 이 구간의 실제
사용률이 그대로 측정된다. 부하는 12초 후 자동 종료된다."

recsh 'for i in $(seq 1 8); do timeout 12 bash -c "while :; do :; done" & done
       echo "부하 생성기 8개 기동 (12초 후 자동 종료)"
       sleep 2'

recsh "sudo -u agent-admin '$MON'; echo \"(exit=\$?)\""
rec_note "위 출력에서 CPU Usage 가 20% 를 넘고 [WARNING] CPU threshold exceeded 가
출력되었는지 확인할 것. 부하는 실제이며 측정값도 실제다."

recsh 'wait 2>/dev/null; sleep 3; echo "부하 종료 대기 완료"'

echo "--- [6b-3] 부하 해제 후 정상 복귀 확인 ---"
recsh "sudo -u agent-admin '$MON' | grep -E 'CPU Usage|WARNING|All resources'; echo \"(exit=\$?)\""

echo
echo "=============================================================="
echo " [6b-4] MEM / DISK 경고 — 임계값 주입으로 분기 로직 검증"
echo "=============================================================="
rec_note "실제 사용률은 그대로 두고 임계값만 낮춰 실행한다.
'현재 MEM 9% > 임계값 1%' 이므로 경고가 발생해야 한다.
이는 수치를 조작하는 것이 아니라, 비교 대상을 바꿔 분기를 태우는 방식이다."

recsh "sudo -u agent-admin env MEM_THRESHOLD=1 '$MON' | grep -E 'MEM Usage|WARNING'; echo \"(exit=\$?)\""
recsh "sudo -u agent-admin env DISK_THRESHOLD=1 '$MON' | grep -E 'DISK Used|WARNING'; echo \"(exit=\$?)\""

echo "--- [6b-5] 세 경고 동시 발생 ---"
recsh "sudo -u agent-admin env CPU_THRESHOLD=0 MEM_THRESHOLD=1 DISK_THRESHOLD=1 '$MON'; echo \"(exit=\$?)\""
rec_note "세 경고가 모두 출력되면서도 exit=0 으로 정상 종료되고 로그가 기록되는지
확인할 것. 경고는 흐름을 끊지 않는다는 요구사항이 지켜지는 지점이다."

echo "--- [6b-6] 기본값이 요구사항 그대로인지 재확인 ---"
recsh "grep -E 'CPU_THRESHOLD=|MEM_THRESHOLD=|DISK_THRESHOLD=' '$MON' | grep -v '^#'"
rec_note "환경 변수를 주지 않으면 CPU 20 / MEM 10 / DISK 80 으로 동작한다.
요구사항의 기본 동작은 변경되지 않았다."

echo
echo "=== Phase 6b gate 결과 ==="
recsh "
fail=0
# 임계값 주입 시 경고가 실제로 출력되는지
sudo -u agent-admin env CPU_THRESHOLD=0  '$MON' | grep -q 'WARNING. CPU threshold exceeded'  || { echo 'NG: CPU warning not emitted'; fail=1; }
sudo -u agent-admin env MEM_THRESHOLD=1  '$MON' | grep -q 'WARNING. MEM threshold exceeded'  || { echo 'NG: MEM warning not emitted'; fail=1; }
sudo -u agent-admin env DISK_THRESHOLD=1 '$MON' | grep -q 'WARNING. DISK threshold exceeded' || { echo 'NG: DISK warning not emitted'; fail=1; }
# 경고가 나도 종료코드는 0 이어야 한다
sudo -u agent-admin env CPU_THRESHOLD=0 MEM_THRESHOLD=1 DISK_THRESHOLD=1 '$MON' >/dev/null 2>&1 || { echo 'NG: 경고 시 exit != 0'; fail=1; }
# 기본값 확인
grep -q 'CPU_THRESHOLD:-20'  '$MON' || { echo 'NG: CPU default != 20'; fail=1; }
grep -q 'MEM_THRESHOLD:-10'  '$MON' || { echo 'NG: MEM default != 10'; fail=1; }
grep -q 'DISK_THRESHOLD:-80' '$MON' || { echo 'NG: DISK default != 80'; fail=1; }
[ \$fail -eq 0 ] && echo 'PHASE 6b GATE: PASS' || echo 'PHASE 6b GATE: FAIL'
exit \$fail"
