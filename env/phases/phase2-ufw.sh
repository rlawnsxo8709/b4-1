#!/bin/bash
# Phase 2 — UFW 방화벽: 필요한 포트만 허용
set -u
source /usr/local/lib/rec.sh
evidence_open phase2-ufw

echo "--- [2-0] 변경 전 상태 ---"
rec ufw status

rec_note "방화벽은 UFW 를 선택했다. 본 환경에 firewalld 는 없고,
Ubuntu 계열 표준 도구가 UFW 이기 때문이다.
규칙 적용 순서가 중요하다: allow 20022 를 '먼저' 넣고 enable 한다.
반대로 하면 원격 세션이 끊겨 스스로 잠기는데(lockout), 실습 환경이라도
이 순서를 습관으로 들여야 실제 서버에서 사고가 나지 않는다."

echo "--- [2-1] 기본 정책: 들어오는 것은 막고 나가는 것은 허용 ---"
rec ufw default deny incoming
rec ufw default allow outgoing

echo "--- [2-2] 필요한 포트만 허용 (enable 이전에 먼저 등록) ---"
rec ufw allow 20022/tcp comment 'SSH'
rec ufw allow 15034/tcp comment 'AGENT APP'

echo "--- [2-3] 방화벽 활성화 ---"
rec ufw --force enable

echo "--- [2-4] 적용 결과 ---"
rec ufw status verbose
rec ufw status numbered

echo "--- [2-5] 설정 파일상의 활성 상태 (monitor.sh 가 참조할 값) ---"
recsh 'grep -E "^ENABLED=" /etc/ufw/ufw.conf'
rec_note "monitor.sh 는 비특권 계정(agent-admin)으로 cron 실행된다.
그런데 'ufw status' 는 root 전용이라 일반 계정에서는 실패한다.
따라서 방화벽 점검은 644 로 누구나 읽을 수 있는 /etc/ufw/ufw.conf 의
ENABLED 값을 확인하는 방식으로 구현한다. sudo 권한을 추가로 주지 않고도
점검이 가능하다는 점이 최소 권한 원칙에 부합한다."

echo "--- [2-6] 비특권 계정에서 ufw status 가 실패함을 실증 ---"
recsh 'id -u nobody >/dev/null 2>&1 && su -s /bin/bash nobody -c "ufw status" 2>&1 | head -3; echo "(exit=$?)"'

echo
echo "=== Phase 2 gate 결과 ==="
recsh '
fail=0
ufw status | grep -q "Status: active" || { echo "NG: ufw not active"; fail=1; }
ufw status | grep -q "20022/tcp"      || { echo "NG: 20022 rule missing"; fail=1; }
ufw status | grep -q "15034/tcp"      || { echo "NG: 15034 rule missing"; fail=1; }
# 허용 규칙이 정확히 이 둘 뿐인지 (v4/v6 각 1건씩 = 4행)
n=$(ufw status | grep -cE "^(20022|15034)/tcp")
t=$(ufw status | grep -cE "ALLOW IN")
[ "$n" -eq "$t" ] || { echo "NG: 허용 규칙에 20022/15034 외 항목 존재 (allow=$t, expected=$n)"; fail=1; }
grep -q "^ENABLED=yes" /etc/ufw/ufw.conf || { echo "NG: ufw.conf ENABLED"; fail=1; }
[ $fail -eq 0 ] && echo "PHASE 2 GATE: PASS" || echo "PHASE 2 GATE: FAIL"
exit $fail'
