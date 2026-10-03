#!/bin/bash
# Phase 1 — SSH 포트 20022 변경 + Root 원격 로그인 차단
set -u
source /usr/local/lib/rec.sh
evidence_open phase1-ssh

echo "--- [1-0] 변경 전 상태 ---"
recsh 'sshd -T 2>/dev/null | grep -E "^(port|permitrootlogin) "'
recsh 'ss -tulnp | grep sshd || echo "(no sshd listener)"'

echo "--- [1-1] sshd 드롭인 설정 작성 ---"
recsh 'head -5 /etc/ssh/sshd_config | grep -n Include'
rec_note "Ubuntu 는 sshd_config 최상단에서 sshd_config.d/*.conf 를 Include 한다.
sshd 설정은 '먼저 읽힌 값이 이긴다'는 규칙이므로, 드롭인 파일에 쓴 값이
아래쪽 기본값보다 우선 적용된다. 원본 sshd_config 를 건드리지 않아
패키지 업그레이드 시 충돌하지 않는 것이 드롭인 방식의 이점이다."

cat > /etc/ssh/sshd_config.d/99-agent.conf <<'EOF'
# B4-1 미션 기본 보안 설정
# 1) 포트 변경: 22 를 노리는 자동화 스캔의 접속 시도를 걷어낸다.
#    포트 변경 자체는 '방어'가 아니라 '잡음 제거'다. 진짜 방어는 아래 항목들이다.
Port 20022

# 2) root 원격 로그인 차단: 공격자가 이미 아는 계정명(root)으로 들어올 길을 막는다.
#    운영은 일반 계정 로그인 + sudo 로 하며, 이때 조작 주체가 로그에 남는다.
PermitRootLogin no
EOF

rec cat /etc/ssh/sshd_config.d/99-agent.conf

echo "--- [1-2] 설정 문법 검증 후 sshd 재기동 ---"
rec sshd -t          # 문법 오류 시 여기서 실패 → 재기동하지 않는다
recsh 'pkill -x sshd; sleep 1; /usr/sbin/sshd; sleep 1; echo "sshd restarted"'

echo "--- [1-3] 적용 결과: 유효 설정 ---"
recsh 'sshd -T | grep -E "^(port|permitrootlogin) "'

echo "--- [1-4] 적용 결과: 리슨 포트 ---"
rec ss -tulnp

echo "--- [1-5] 22번 포트가 더 이상 열려 있지 않은지 ---"
recsh 'ss -tuln | grep -E ":22\b" && echo "NG: 22 still open" || echo "OK: port 22 closed"'

rec_note "실무 함정 기록:
실제 Ubuntu 22.10+ / 24.04 호스트는 ssh.socket 소켓 액티베이션이 기본이라
sshd_config 의 Port 만 바꾸면 여전히 22 로 리슨한다. systemd 가 소켓을 먼저
잡고 sshd 를 넘겨주기 때문에 sshd_config 의 Port 가 무시되는 것이다.
해결은 둘 중 하나:
  (A) systemctl disable --now ssh.socket && systemctl enable --now ssh.service
  (B) /etc/systemd/system/ssh.socket.d/override.conf 에
      [Socket] / ListenStream= / ListenStream=20022  (빈 줄로 기존 값 초기화 필수)
본 실습 환경은 systemd 를 쓰지 않고 sshd 를 직접 기동하므로 해당 없음.
비교 자료로 (B) 파일을 config/ssh-socket-override.conf 에 함께 제출한다."

echo
echo "=== Phase 1 gate 결과 ==="
recsh '
fail=0
sshd -T | grep -q "^port 20022"          || { echo "NG: port"; fail=1; }
sshd -T | grep -q "^permitrootlogin no"  || { echo "NG: permitrootlogin"; fail=1; }
ss -tuln | grep -q ":20022 "             || { echo "NG: not listening on 20022"; fail=1; }
ss -tuln | grep -qE ":22 "               && { echo "NG: 22 still listening"; fail=1; }
[ $fail -eq 0 ] && echo "PHASE 1 GATE: PASS" || echo "PHASE 1 GATE: FAIL"
exit $fail'
