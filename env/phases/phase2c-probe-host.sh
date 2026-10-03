#!/bin/bash
# Phase 2c — 방화벽이 실제로 동작하는지 '컨테이너 바깥'에서 검증한다 (호스트에서 실행).
#
# ufw status 는 '규칙이 등록되어 있다'만 보여줄 뿐, 실제로 막히는지는 증명하지 못한다.
# 같은 네트워크에 일회용 프로브 컨테이너를 띄워 세 가지 경우를 구분한다.
#
#   20022  ALLOW + 리스너 있음   → 연결 성공
#   15034  ALLOW + 리스너 없음   → 즉시 connection refused  (패킷은 도달했다는 뜻)
#    9999  규칙 없음(기본 deny)  → 타임아웃                 (패킷이 DROP 되었다는 뜻)
#
# '거부(refused)'와 '무응답(timeout)'의 차이가 곧 방화벽이 살아 있다는 증거다.
set -uo pipefail

NET=agent-lab-net
TARGET=agent-lab
PROBE=agent-lab-probe

probe() {
    local port="$1" label="$2" start end elapsed rc out
    start=$(date +%s.%N)
    out=$(docker run --rm --name "$PROBE" --network "$NET" ubuntu:24.04 \
            timeout 6 bash -c "</dev/tcp/$TARGET/$port" 2>&1)
    rc=$?
    end=$(date +%s.%N)
    elapsed=$(awk -v s="$start" -v e="$end" 'BEGIN{printf "%.1f", e-s}')

    local verdict
    case "$rc" in
        0)   verdict="연결 성공 (ALLOW + 리스너 있음)" ;;
        124) verdict="타임아웃 → 패킷 DROP (방화벽이 막음)" ;;
        *)   verdict="연결 거부 → 패킷 도달함 (ALLOW 이나 리스너 없음)" ;;
    esac
    printf '  port %-6s %-28s rc=%-4s %5ss   %s\n' "$port" "$label" "$rc" "$elapsed" "$verdict"
    [ -n "$out" ] && printf '      (%s)\n' "$(echo "$out" | tail -1)"
}

{
    printf '### %s  [EXTERNAL PROBE — 호스트에서 실행]\n' "$(date '+%F %T')"
    printf '$ docker run --rm --network %s ubuntu:24.04 timeout 6 bash -c "</dev/tcp/%s/PORT"\n\n' "$NET" "$TARGET"
    probe 20022 "ALLOW + sshd 리슨"
    probe 15034 "ALLOW + 리스너 없음"
    probe  9999 "규칙 없음 (기본 deny)"
    printf '\n판정: 9999 만 타임아웃(DROP)이고 15034 는 즉시 거부되었다면,\n'
    printf '      방화벽이 규칙에 따라 실제로 패킷을 차단하고 있다는 뜻이다.\n'
    printf -- '--- end of external probe ---\n\n'
} 2>&1 | tee /dev/stderr | docker exec -i agent-lab bash -c 'cat >> /evidence/phase2-ufw.txt'
