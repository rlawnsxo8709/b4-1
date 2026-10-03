#!/bin/bash
# Phase 2b — Phase 2 gate 검사식 수정 후 재검증
set -u
source /usr/local/lib/rec.sh
evidence_open phase2-ufw

rec_note "[게이트 실패 기록 — 원인 및 수정]
증상 : Phase 2 gate 가 '허용 규칙에 20022/15034 외 항목 존재 (allow=0)' 로 FAIL.
       그러나 ufw status verbose 출력상 규칙은 정확히 4행(20022/15034 의 v4/v6)뿐이었다.
원인 : 방화벽 설정이 아니라 게이트 검사식의 버그.
       'ufw status'(평문) 는 Action 컬럼을 'ALLOW' 로 출력하고,
       'ALLOW IN' 은 'ufw status verbose' 에서만 나온다.
       평문 출력에 'ALLOW IN' 을 grep 했으므로 매치 0 → allow=0.
확인 : ufw status | cat -A 로 실제 바이트를 확인해 'ALLOW' 뒤가 공백임을 검증.
수정 : 규칙 카운트를 'ufw status verbose' 기준으로 변경.
교훈 : 같은 명령이라도 옵션에 따라 출력 스키마가 달라진다. 스크립트에서 CLI 출력을
       파싱할 때는 '무엇을 파싱하는지'를 옵션까지 포함해 고정해야 한다.
       이 실패는 monitor.sh 에서 top/free 대신 /proc 을 직접 읽기로 한 판단과 같은 이유다."

echo "--- [2-7] 출력 스키마 차이 실증 ---"
recsh 'echo "[ufw status]        : $(ufw status         | grep -E "^20022/tcp " | head -1)"
       echo "[ufw status verbose]: $(ufw status verbose | grep -E "^20022/tcp " | head -1)"'

echo
echo "=== Phase 2 gate 재검증 (수정판) ==="
recsh '
fail=0
ufw status | grep -q "Status: active" || { echo "NG: ufw not active"; fail=1; }
ufw status | grep -q "20022/tcp"      || { echo "NG: 20022 rule missing"; fail=1; }
ufw status | grep -q "15034/tcp"      || { echo "NG: 15034 rule missing"; fail=1; }
t=$(ufw status verbose | grep -cE "ALLOW IN")
n=$(ufw status verbose | grep -E "ALLOW IN" | grep -cE "^(20022|15034)/tcp")
echo "허용 규칙 총 ${t}행 중 20022/15034 에 해당: ${n}행"
{ [ "$t" -eq "$n" ] && [ "$t" -eq 4 ]; } || { echo "NG: 의도하지 않은 허용 규칙 존재"; fail=1; }
ufw status verbose | grep -q "Default: deny (incoming)" || { echo "NG: default incoming policy"; fail=1; }
grep -q "^ENABLED=yes" /etc/ufw/ufw.conf || { echo "NG: ufw.conf ENABLED"; fail=1; }
[ $fail -eq 0 ] && echo "PHASE 2 GATE: PASS" || echo "PHASE 2 GATE: FAIL"
exit $fail'
