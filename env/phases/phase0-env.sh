#!/bin/bash
# Phase 0 — 실습 환경 검증
set -u
source /usr/local/lib/rec.sh
evidence_open phase0-env

rec_note "실습 환경: Docker 비특권 컨테이너. --privileged 없음, 호스트 cgroup 마운트 없음.
cap-add 는 ufw/iptables 에 필요한 NET_ADMIN, NET_RAW 두 개뿐.
systemd 를 설치하지 않고 sshd/cron 을 entrypoint 에서 직접 기동하는 구성."

echo "--- [0-1] 커널/아키텍처 ---"
rec uname -a

echo "--- [0-2] 배포판 ---"
recsh 'cat /etc/os-release | head -3'

echo "--- [0-3] 시간대 (기록 시간축 일치 확인) ---"
rec date '+%F %T %Z'

echo "--- [0-4] PID 1 이 systemd 가 아님을 확인 ---"
rec ps -p 1 -o pid,comm,args --no-headers

echo "--- [0-5] 상주 데몬 (sshd / cron) ---"
recsh 'ps -eo pid,comm --no-headers | grep -E "sshd|cron"'

echo "--- [0-6] 필수 도구 존재 확인 ---"
recsh 'for t in ufw cron sshd setfacl getfacl ss pgrep df awk gzip find script crontab; do
         p=$(command -v "$t" 2>/dev/null || echo "MISSING")
         printf "%-10s %s\n" "$t" "$p"
       done'

echo "--- [0-7] 제공 앱 바이너리 ---"
recsh 'ls -l /opt/agent-app-linux-* && file /opt/agent-app-linux-* 2>/dev/null || true'

echo "--- [0-8] 증거 디렉토리 쓰기 가능 여부 ---"
recsh 'touch /evidence/.writetest && echo "writable: OK" && rm -f /evidence/.writetest'

echo
echo "=== Phase 0 gate 결과 ==="
recsh '
fail=0
[ "$(uname -m)" = "aarch64" ] || { echo "NG: arch"; fail=1; }
ps -p 1 -o comm= | grep -qv systemd || { echo "NG: pid1 is systemd"; fail=1; }
pgrep -x sshd >/dev/null || { echo "NG: sshd not running"; fail=1; }
pgrep -x cron >/dev/null || { echo "NG: cron not running"; fail=1; }
[ -x /opt/agent-app-linux-arm64 ] || { echo "NG: app binary"; fail=1; }
[ -w /evidence ] || { echo "NG: evidence not writable"; fail=1; }
[ $fail -eq 0 ] && echo "PHASE 0 GATE: PASS" || echo "PHASE 0 GATE: FAIL"
exit $fail'
