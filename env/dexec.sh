#!/bin/bash
# Layer 1 기록: 컨테이너 안에서 스크립트를 실행하고
# 그 전체 출력(성공·실패·오타 전부)을 세션 원본 로그에 append 한다.
# 이 로그는 절대 편집하지 않는다. 다른 기록 레이어를 대조할 1차 사료다.
#
#   ./dexec.sh phases/phase1-ssh.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSWERS="$(dirname "$HERE")"
SCRIPT="${1:?usage: dexec.sh <script>}"

SESSION_LOG="$ANSWERS/evidence/session/$(date +%F)-session.log"
mkdir -p "$(dirname "$SESSION_LOG")"

{
    printf '\n'
    printf '=========================================================================\n'
    printf '  RUN   : %s\n' "$SCRIPT"
    printf '  AT    : %s\n' "$(date '+%F %T %Z')"
    printf '=========================================================================\n'
} >> "$SESSION_LOG"

docker exec -i agent-lab bash -l -s < "$SCRIPT" 2>&1 | tee -a "$SESSION_LOG"
rc="${PIPESTATUS[0]}"

printf -- '----- exit=%d -----\n' "$rc" >> "$SESSION_LOG"
exit "$rc"
