#!/bin/bash
# ---------------------------------------------------------------------------
# Layer 2 기록 헬퍼 — 증거 자동 적재
#
# 증거를 손으로 복사·붙여넣기 하지 않기 위한 도구다.
# 검증 명령을 이 함수들에 통과시키면 [시각 + 명령어 + 출력 + 종료코드]가
# 증거 파일에 append-only 로 쌓인다. 보고서는 이 파일에서 그대로 인용한다.
#
#   source /usr/local/lib/rec.sh
#   evidence_open phase1-ssh        # 증거 파일 지정 + 헤더 기록
#   rec sshd -T                     # 일반 명령
#   recsh 'ss -tulnp | grep sshd'   # 파이프/리다이렉션이 필요한 경우
#   rec_expect_fail sudo -u agent-test cat /path/secret   # 실패가 정상인 검증
#   rec_note "왜 이렇게 했는지"
# ---------------------------------------------------------------------------

EVIDENCE_DIR="${EVIDENCE_DIR:-/evidence}"

evidence_open() {
    local name="$1"
    mkdir -p "$EVIDENCE_DIR"
    export EVIDENCE_FILE="$EVIDENCE_DIR/${name}.txt"
    {
        printf '============================================================\n'
        printf ' EVIDENCE : %s\n' "$name"
        printf ' OPENED   : %s\n' "$(date '+%F %T %Z')"
        printf ' HOST     : %s    USER: %s\n' "$(hostname)" "$(id -un)"
        printf '============================================================\n\n'
    } >> "$EVIDENCE_FILE"
    printf '>>> evidence file: %s\n' "$EVIDENCE_FILE"
}

# 출력과 종료코드를 함께 기록한다.
# 종료코드를 남기는 이유: "명령은 돌았지만 실패했다"를 놓치지 않기 위해서다.
rec() {
    local f="${EVIDENCE_FILE:-$EVIDENCE_DIR/misc.txt}" out rc
    out="$("$@" 2>&1)"; rc=$?
    printf '### %s\n$ %s\n%s\n--- exit=%d ---\n\n' \
        "$(date '+%F %T')" "$*" "$out" "$rc" >> "$f"
    printf '%s\n' "$out"
    return $rc
}

# 셸 문법(파이프·리다이렉션·글로브)이 필요한 명령용
recsh() {
    local f="${EVIDENCE_FILE:-$EVIDENCE_DIR/misc.txt}" out rc
    out="$(bash -c "$1" 2>&1)"; rc=$?
    printf '### %s\n$ %s\n%s\n--- exit=%d ---\n\n' \
        "$(date '+%F %T')" "$1" "$out" "$rc" >> "$f"
    printf '%s\n' "$out"
    return $rc
}

# 네거티브 테스트: 차단되어야 정상인 검증.
# 성공해 버리면 그것이 권한 설계의 결함이므로 FAIL 로 기록한다.
rec_expect_fail() {
    local f="${EVIDENCE_FILE:-$EVIDENCE_DIR/misc.txt}" out rc verdict
    out="$("$@" 2>&1)"; rc=$?
    if [ "$rc" -ne 0 ]; then
        verdict='PASS (차단 확인됨)'
    else
        verdict='FAIL (차단되어야 하는데 성공함 — 권한 설계 결함)'
    fi
    printf '### %s  [NEGATIVE TEST]\n$ %s\n%s\n--- exit=%d  %s ---\n\n' \
        "$(date '+%F %T')" "$*" "$out" "$rc" "$verdict" >> "$f"
    printf '%s\n[%s]\n' "$out" "$verdict"
    [ "$rc" -ne 0 ]
}

# 명령이 아닌 판단·맥락을 증거 파일에 남긴다.
rec_note() {
    local f="${EVIDENCE_FILE:-$EVIDENCE_DIR/misc.txt}"
    printf '### %s  [NOTE]\n%s\n\n' "$(date '+%F %T')" "$*" >> "$f"
    printf '[NOTE] %s\n' "$*"
}
