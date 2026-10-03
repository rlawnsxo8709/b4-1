#!/bin/bash
# Phase 3b — Phase 3 결함 수정: agent-test 의 upload_files 접근 불가 해결
set -u
source /usr/local/lib/rec.sh
evidence_open phase3-account-acl

AGENT_HOME=/home/agent-admin/agent-app
LOG_DIR=/var/log/agent-app

rec_note "[결함 발견 및 수정 — 경로 통행권]
증상 : agent-test 가 upload_files 에 파일 생성 실패 (Permission denied).
       요구사항은 'upload_files: group=agent-common, R/W 가능' 이고
       agent-test 는 agent-common 소속이므로 되어야 정상이다.
원인 : upload_files 자체의 권한(2770 agent-admin:agent-common)은 옳았다.
       문제는 '목적지'가 아니라 '가는 길'이었다.
       upload_files 의 경로는 /home/agent-admin/agent-app/upload_files 인데
         - /home/agent-admin  : 750 + ACL u:agent-dev:x  → test 통행 불가
         - \$AGENT_HOME       : 2750 agent-admin:agent-core → test 는 core 아님, 통행 불가
       리눅스는 최종 디렉토리 권한만 보는 게 아니라 경로상의 '모든' 디렉토리에
       실행(x) 권한을 요구한다. 중간 한 곳만 막혀도 도달할 수 없다.
수정 : /home/agent-admin 과 \$AGENT_HOME 에 g:agent-common:x 를 부여한다.
       읽기(r)는 주지 않는다 → 목록은 볼 수 없고 통과만 가능하다.
       'x without r' = 길을 알면 지나갈 수 있지만 둘러볼 수는 없다.
       이것이 공유 디렉토리를 보안 디렉토리 하위에 두면서도 최소 권한을
       유지하는 방법이다.
게이트 : 이 결함을 Phase 3 gate 가 잡지 못했다. 네거티브 테스트만 넣고
       'agent-test 의 정당한 쓰기'라는 포지티브 케이스를 빠뜨렸기 때문이다.
       gate 에 해당 검사를 추가한다."

echo "--- [3b-1] 통행권 부여 (r 없이 x 만) ---"
recsh "
setfacl -m g:agent-common:x /home/agent-admin
setfacl -m g:agent-common:x '$AGENT_HOME'
echo 'traverse ACL applied'"

recsh "getfacl -p /home/agent-admin 2>/dev/null | grep -vE '^#'"
recsh "getfacl -p '$AGENT_HOME' 2>/dev/null | grep -vE '^#'"

echo "--- [3b-2] 재검증: agent-test 가 upload_files 에 쓸 수 있는가 ---"
recsh "sudo -u agent-test touch '$AGENT_HOME/upload_files/from-test.txt' && echo 'OK: test 가 upload_files 에 파일 생성'"
recsh "ls -l '$AGENT_HOME/upload_files'"
rec_note "두 파일의 생성자는 agent-dev / agent-test 로 다르지만 그룹은 모두
agent-common 으로 고정되어 있어야 한다. setgid 가 동작한 증거다."

echo "--- [3b-3] 통행권을 준 뒤에도 기밀 영역은 여전히 막혀 있는가 ---"
rec_note "권한을 풀 때 가장 위험한 순간이다. 통행권을 주면서 실수로
기밀 영역까지 열리지 않았는지 반드시 재확인해야 한다."
rec_expect_fail sudo -u agent-test ls "$AGENT_HOME/api_keys"
rec_expect_fail sudo -u agent-test ls "$LOG_DIR"
rec_expect_fail sudo -u agent-test ls "$AGENT_HOME/bin"
rec_expect_fail sudo -u agent-test ls "$AGENT_HOME"
rec_expect_fail sudo -u agent-test ls /home/agent-admin
rec_note "위 결과: agent-test 는 \$AGENT_HOME 의 목록조차 볼 수 없다(x만 있고 r 없음).
그럼에도 경로를 정확히 지정한 upload_files 에는 도달해 쓸 수 있다.
'통과는 되지만 둘러볼 수는 없는' 상태가 의도대로 구현되었다."

echo "--- [3b-4] 테스트 잔여 파일 정리 ---"
recsh "rm -f '$LOG_DIR/from-admin.txt' '$LOG_DIR/from-dev.txt' '$AGENT_HOME/bin/from-dev.sh'
       ls -la '$LOG_DIR' '$AGENT_HOME/bin'"

echo
echo "=== Phase 3 gate 재검증 (포지티브 케이스 보강판) ==="
recsh "
fail=0
# 그룹 소속
id -nG agent-admin | tr ' ' '\n' | grep -qx agent-common || { echo 'NG: admin not in agent-common'; fail=1; }
id -nG agent-admin | tr ' ' '\n' | grep -qx agent-core   || { echo 'NG: admin not in agent-core'; fail=1; }
id -nG agent-dev   | tr ' ' '\n' | grep -qx agent-common || { echo 'NG: dev not in agent-common'; fail=1; }
id -nG agent-dev   | tr ' ' '\n' | grep -qx agent-core   || { echo 'NG: dev not in agent-core'; fail=1; }
id -nG agent-test  | tr ' ' '\n' | grep -qx agent-common || { echo 'NG: test not in agent-common'; fail=1; }
id -nG agent-test  | tr ' ' '\n' | grep -qx agent-core   && { echo 'NG: test MUST NOT be in agent-core'; fail=1; }

# 디렉토리 소유/모드
[ \"\$(stat -c '%U:%G:%a' '$AGENT_HOME/upload_files')\" = 'agent-admin:agent-common:2770' ] || { echo 'NG: upload_files perm'; fail=1; }
[ \"\$(stat -c '%U:%G:%a' '$AGENT_HOME/api_keys')\"     = 'agent-admin:agent-core:2770' ]   || { echo 'NG: api_keys perm'; fail=1; }
[ \"\$(stat -c '%U:%G:%a' '$LOG_DIR')\"                 = 'agent-admin:agent-core:2770' ]   || { echo 'NG: log dir perm'; fail=1; }

# 포지티브: agent-common 세 명 모두 upload_files 에 쓸 수 있어야 한다 (이번에 보강한 검사)
for u in agent-admin agent-dev agent-test; do
  f=\"$AGENT_HOME/upload_files/.gate-\$u\"
  sudo -u \$u touch \"\$f\" 2>/dev/null || { echo \"NG: \$u cannot write upload_files\"; fail=1; }
  [ -f \"\$f\" ] && [ \"\$(stat -c '%G' \"\$f\")\" = 'agent-common' ] || { echo \"NG: \$u file group not agent-common\"; fail=1; }
  rm -f \"\$f\"
done

# 포지티브: agent-core 두 명은 로그 디렉토리에 쓸 수 있어야 한다
for u in agent-admin agent-dev; do
  f=\"$LOG_DIR/.gate-\$u\"
  sudo -u \$u touch \"\$f\" 2>/dev/null || { echo \"NG: \$u cannot write log dir\"; fail=1; }
  rm -f \"\$f\"
done

# 네거티브: agent-test 는 기밀 영역 접근 불가
sudo -u agent-test ls '$AGENT_HOME/api_keys' >/dev/null 2>&1 && { echo 'NG: test can read api_keys'; fail=1; }
sudo -u agent-test ls '$LOG_DIR'             >/dev/null 2>&1 && { echo 'NG: test can read log dir'; fail=1; }
sudo -u agent-test ls '$AGENT_HOME'          >/dev/null 2>&1 && { echo 'NG: test can list AGENT_HOME'; fail=1; }
sudo -u agent-dev  ls /home/agent-admin      >/dev/null 2>&1 && { echo 'NG: dev can list admin home'; fail=1; }

# 통행권: dev/test 는 목록은 못 봐도 통과는 되어야 한다
sudo -u agent-dev  ls '$AGENT_HOME/bin'          >/dev/null 2>&1 || { echo 'NG: dev cannot traverse to bin'; fail=1; }
sudo -u agent-test ls '$AGENT_HOME/upload_files' >/dev/null 2>&1 || { echo 'NG: test cannot traverse to upload_files'; fail=1; }

[ \$fail -eq 0 ] && echo 'PHASE 3 GATE: PASS' || echo 'PHASE 3 GATE: FAIL'
exit \$fail"
