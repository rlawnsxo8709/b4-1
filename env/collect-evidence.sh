#!/bin/bash
# 필수 증거 8종을 한 번에 재수집한다.
#
# 설정이 바뀌면 문서를 손으로 고치는 것이 아니라 이 스크립트를 다시 돌린다.
# 증거와 실제 상태가 어긋날 여지를 없애기 위한 재현 도구다.
set -u
source /usr/local/lib/rec.sh

AGENT_HOME=/home/agent-admin/agent-app
LOG_DIR=/var/log/agent-app
BIN="$AGENT_HOME/bin"

EVIDENCE_FILE=/evidence/FINAL-VERIFICATION.txt
: > "$EVIDENCE_FILE"
export EVIDENCE_FILE

{
    printf '============================================================\n'
    printf ' B4-1 최종 상태 검증 — 필수 증거 8종\n'
    printf ' 생성: %s\n' "$(date '+%F %T %Z')"
    printf ' 호스트: %s  커널: %s  아키텍처: %s\n' "$(hostname)" "$(uname -r)" "$(uname -m)"
    printf '============================================================\n\n'
} >> "$EVIDENCE_FILE"

hdr() {
    printf '\n############################################################\n# %s\n############################################################\n\n' "$1" >> "$EVIDENCE_FILE"
    printf '\n=== %s ===\n' "$1"
}

hdr "증거 1 — SSH 포트 20022 변경 및 Root 원격 접속 차단"
recsh "sshd -T | grep -E '^(port|permitrootlogin) '"
recsh "cat /etc/ssh/sshd_config.d/99-agent.conf"
recsh "ss -tuln | grep -E ':(22|20022) ' || echo '(no match)'"

hdr "증거 2 — 방화벽 활성화 및 20022/15034 만 허용"
rec ufw status verbose
recsh "grep '^ENABLED=' /etc/ufw/ufw.conf"

hdr "증거 3 — 계정/그룹 생성 (agent-admin/dev/test, agent-common/core)"
recsh "for u in agent-admin agent-dev agent-test; do id \"\$u\"; done"
rec getent group agent-common agent-core

hdr "증거 4 — 디렉토리 구조 및 권한 (ACL 포함)"
recsh "ls -ld /home/agent-admin '$AGENT_HOME' '$AGENT_HOME/bin' '$AGENT_HOME/upload_files' '$AGENT_HOME/api_keys' '$LOG_DIR'"
recsh "for d in /home/agent-admin '$AGENT_HOME' '$AGENT_HOME/upload_files' '$AGENT_HOME/api_keys' '$LOG_DIR'; do
         echo \"### \$d\"; getfacl -p \"\$d\" 2>/dev/null | grep -vE '^#'; echo; done"
echo "  [권한 격리 실증]"
recsh "sudo -u agent-test touch '$AGENT_HOME/upload_files/.chk' && echo 'OK: agent-test 는 공유 영역에 쓸 수 있다' && rm -f '$AGENT_HOME/upload_files/.chk'"
rec_expect_fail sudo -u agent-test ls "$AGENT_HOME/api_keys"
rec_expect_fail sudo -u agent-test ls "$LOG_DIR"
rec_expect_fail sudo -u agent-dev  ls /home/agent-admin

hdr "증거 5 — 앱 Boot Sequence 5단계 [OK] 및 Agent READY"
recsh "sed -n '/Starting Agent Boot Sequence/,/Agent READY/p' '$AGENT_HOME/app-boot.log' | tail -20"
recsh "ps -eo pid,user,args --no-headers | grep 'agent-app-linux-arm[6]4' | grep -v grep"
recsh "ss -tuln | grep ':15034 '"

hdr "증거 6 — monitor.sh 실행 결과 (프로세스/포트/리소스/경고)"
recsh "ls -l '$BIN/monitor.sh'"
recsh "sudo -u agent-admin '$BIN/monitor.sh'; echo \"(exit=\$?)\""

hdr "증거 7 — /var/log/agent-app/monitor.log 누적 기록 (최근 라인)"
recsh "sudo -u agent-admin bash -c 'wc -l < $LOG_DIR/monitor.log' | xargs echo '총 라인 수:'"
recsh "sudo -u agent-admin tail -10 '$LOG_DIR/monitor.log'"

hdr "증거 8 — crontab 매분 실행 등록 및 자동 실행 확인"
recsh "crontab -l -u agent-admin"
recsh "ps -eo pid,user,comm --no-headers | grep cron"
B=$(sudo -u agent-admin bash -c "wc -l < $LOG_DIR/monitor.log")
T0=$(date '+%F %T')
echo "  기준 시각 $T0 / 라인 수 $B — 70초 대기 후 재측정"
sleep 70
A=$(sudo -u agent-admin bash -c "wc -l < $LOG_DIR/monitor.log")
T1=$(date '+%F %T')
DELTA=$(( A - B ))
recsh "echo '자동 누적 검증'
       echo '  기준 : $T0  라인 수 $B'
       echo '  측정 : $T1  라인 수 $A'
       echo '  증가 : $DELTA 줄'
       [ $A -gt $B ] && echo '  판정 : PASS (cron 이 스스로 실행했다)' || echo '  판정 : FAIL'"
recsh "sudo -u agent-admin tail -3 '$LOG_DIR/monitor.log'"

echo
echo "완료: $EVIDENCE_FILE"
wc -l "$EVIDENCE_FILE"
