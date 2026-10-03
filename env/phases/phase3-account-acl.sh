#!/bin/bash
# Phase 3 — 계정 / 그룹 / 디렉토리 / ACL (협업 + 최소 권한)
set -u
source /usr/local/lib/rec.sh
evidence_open phase3-account-acl

AGENT_HOME=/home/agent-admin/agent-app
LOG_DIR=/var/log/agent-app

echo "--- [3-1] 그룹 생성 ---"
rec_note "그룹을 둘로 나누는 이유:
  agent-common (admin, dev, test) — '공유' 영역. 세 사람이 파일을 주고받는 곳.
  agent-core   (admin, dev)       — '보안' 영역. 자격증명과 운영 로그가 있는 곳.
QA 담당(agent-test)은 업무상 업로드 파일은 다뤄야 하지만 API 키와 운영 로그를
볼 이유가 없다. 한 그룹으로 뭉뜽그리면 '공유하려면 비밀도 함께 열어야 하는'
구조가 되므로, 공유 축과 기밀 축을 별도 그룹으로 분리한다."

recsh 'for g in agent-common agent-core; do
         getent group "$g" >/dev/null || groupadd "$g"
       done; getent group agent-common agent-core'

echo "--- [3-2] 계정 생성 ---"
recsh 'for u in agent-admin agent-dev agent-test; do
         id "$u" >/dev/null 2>&1 || useradd -m -s /bin/bash "$u"
       done; echo created'

echo "--- [3-3] 그룹 배정 ---"
recsh 'usermod -aG agent-common agent-admin
       usermod -aG agent-common agent-dev
       usermod -aG agent-common agent-test
       usermod -aG agent-core   agent-admin
       usermod -aG agent-core   agent-dev
       echo assigned'

rec id agent-admin
rec id agent-dev
rec id agent-test

echo "--- [3-4] 디렉토리 생성 ---"
recsh "mkdir -p '$AGENT_HOME/bin' '$AGENT_HOME/upload_files' '$AGENT_HOME/api_keys' '$LOG_DIR'
       chown -R agent-admin:agent-admin /home/agent-admin
       echo created"

echo "--- [3-5] 소유권 / 모드 설정 ---"
rec_note "setgid 비트(2xxx)를 거는 이유:
디렉토리에 setgid 를 걸면 그 안에서 '누가' 파일을 만들든 파일의 그룹이
디렉토리의 그룹으로 자동 고정된다. 이게 없으면 agent-dev 가 만든 파일은
agent-dev 그룹이 되어 agent-admin 이 못 읽는 사고가 난다. 협업 디렉토리에서
권한이 시간이 지나며 무너지는 것을 구조적으로 막는 장치다."

recsh "
chmod 750 /home/agent-admin
chown agent-admin:agent-core   '$AGENT_HOME'             && chmod 2750 '$AGENT_HOME'
chown agent-admin:agent-core   '$AGENT_HOME/bin'         && chmod 2750 '$AGENT_HOME/bin'
chown agent-admin:agent-common '$AGENT_HOME/upload_files' && chmod 2770 '$AGENT_HOME/upload_files'
chown agent-admin:agent-core   '$AGENT_HOME/api_keys'    && chmod 2770 '$AGENT_HOME/api_keys'
chown agent-admin:agent-core   '$LOG_DIR'                && chmod 2770 '$LOG_DIR'
echo applied"

echo "--- [3-6] ACL 설정 ---"
rec_note "ACL 로 해결하는 것 두 가지:
(1) 통행권 분리 — agent-dev 는 monitor.sh 를 \$AGENT_HOME/bin 에 써야 하는데,
    그 경로가 agent-admin 의 홈 아래에 있다. /home/agent-admin 을 755 로 열면
    dev/test 가 admin 홈 전체를 들여다볼 수 있게 된다.
    그래서 'u:agent-dev:x' 만 준다. 목록은 못 보되(r 없음) 하위 경로로
    지나갈 수는 있는(x) 상태 — 최소 권한의 교과서적 형태다.
(2) 신규 파일 상속 — default ACL(-d)을 걸면 앞으로 만들어질 파일에도
    그룹 권한이 자동 적용된다. umask 설정에 의존하지 않게 된다."

recsh "
# (1) admin 홈: dev 에게 '통과만' 허용 (r 없음, x 만)
setfacl -m u:agent-dev:x /home/agent-admin

# (2) bin: dev 가 monitor.sh 를 작성해야 하므로 rwx + 신규 파일 상속
setfacl -m  u:agent-dev:rwx '$AGENT_HOME/bin'
setfacl -dm u:agent-dev:rwx '$AGENT_HOME/bin'
setfacl -dm g:agent-core:rx '$AGENT_HOME/bin'

# (3) upload_files: agent-common 공유 R/W, 신규 파일도 동일
setfacl -m  g:agent-common:rwx '$AGENT_HOME/upload_files'
setfacl -dm g:agent-common:rwx '$AGENT_HOME/upload_files'

# (4) api_keys: agent-core 전용 R/W, 그 외 완전 차단
setfacl -m  g:agent-core:rwx -m o::--- '$AGENT_HOME/api_keys'
setfacl -dm g:agent-core:rwx -dm o::--- '$AGENT_HOME/api_keys'

# (5) 로그 디렉토리: agent-core 전용 R/W, 그 외 완전 차단
setfacl -m  g:agent-core:rwx -m o::--- '$LOG_DIR'
setfacl -dm g:agent-core:rwx -dm o::--- '$LOG_DIR'
echo 'acl applied'"

echo "--- [3-7] 최종 권한 상태 ---"
recsh "ls -ld /home/agent-admin '$AGENT_HOME' '$AGENT_HOME/bin' '$AGENT_HOME/upload_files' '$AGENT_HOME/api_keys' '$LOG_DIR'"

for d in /home/agent-admin "$AGENT_HOME" "$AGENT_HOME/bin" "$AGENT_HOME/upload_files" "$AGENT_HOME/api_keys" "$LOG_DIR"; do
    echo "  [getfacl] $d"
    recsh "getfacl -p '$d' 2>/dev/null"
done

echo
echo "=============================================================="
echo " [3-8] 포지티브 테스트 — 되어야 하는 것은 되는가"
echo "=============================================================="
recsh "sudo -u agent-dev  touch '$AGENT_HOME/upload_files/from-dev.txt'  && echo 'OK: dev  가 upload_files 에 파일 생성'"
recsh "sudo -u agent-test touch '$AGENT_HOME/upload_files/from-test.txt' && echo 'OK: test 가 upload_files 에 파일 생성'"
recsh "ls -l '$AGENT_HOME/upload_files'"
rec_note "위 ls 결과에서 두 파일의 그룹이 모두 agent-common 인지 확인할 것.
생성자가 dev/test 로 다른데 그룹이 하나로 고정되었다면 setgid 가 동작한 것이다."

recsh "sudo -u agent-dev  touch '$AGENT_HOME/bin/from-dev.sh' && echo 'OK: dev 가 bin 에 파일 생성 (ACL u:agent-dev:rwx)'"
recsh "sudo -u agent-dev  ls '$AGENT_HOME/bin' && echo 'OK: dev 가 bin 목록 조회'"
recsh "sudo -u agent-admin touch '$LOG_DIR/from-admin.txt' && echo 'OK: admin 이 로그 디렉토리에 기록'"
recsh "sudo -u agent-dev   touch '$LOG_DIR/from-dev.txt'   && echo 'OK: dev 가 로그 디렉토리에 기록'"

echo
echo "=============================================================="
echo " [3-9] 네거티브 테스트 — 막혀야 하는 것은 막히는가"
echo "=============================================================="
rec_note "정상 케이스만 확인하는 것은 검증이 아니라 시연이다.
권한 설계의 진짜 증명은 '막혀야 할 것이 실제로 막히는가'에 있다."

rec_expect_fail sudo -u agent-test ls "$AGENT_HOME/api_keys"
rec_expect_fail sudo -u agent-test ls "$LOG_DIR"
rec_expect_fail sudo -u agent-test touch "$LOG_DIR/should-fail.txt"
rec_expect_fail sudo -u agent-test ls "$AGENT_HOME/bin"

echo "  --- ACL 통행권의 핵심 실증: dev 는 admin 홈을 '볼 수는 없지만 지날 수는 있다' ---"
rec_expect_fail sudo -u agent-dev ls /home/agent-admin
recsh "sudo -u agent-dev ls '$AGENT_HOME/bin' >/dev/null && echo 'OK: 목록은 못 봐도 하위 경로 통행은 가능 (u:agent-dev:x 의 효과)'"

echo
echo "=== Phase 3 gate 결과 ==="
recsh "
fail=0
id -nG agent-admin | tr ' ' '\n' | grep -qx agent-common || { echo 'NG: admin not in agent-common'; fail=1; }
id -nG agent-admin | tr ' ' '\n' | grep -qx agent-core   || { echo 'NG: admin not in agent-core'; fail=1; }
id -nG agent-dev   | tr ' ' '\n' | grep -qx agent-common || { echo 'NG: dev not in agent-common'; fail=1; }
id -nG agent-dev   | tr ' ' '\n' | grep -qx agent-core   || { echo 'NG: dev not in agent-core'; fail=1; }
id -nG agent-test  | tr ' ' '\n' | grep -qx agent-common || { echo 'NG: test not in agent-common'; fail=1; }
id -nG agent-test  | tr ' ' '\n' | grep -qx agent-core   && { echo 'NG: test MUST NOT be in agent-core'; fail=1; }

[ \"\$(stat -c '%U:%G:%a' '$AGENT_HOME/upload_files')\" = 'agent-admin:agent-common:2770' ] || { echo \"NG: upload_files perm = \$(stat -c '%U:%G:%a' '$AGENT_HOME/upload_files')\"; fail=1; }
[ \"\$(stat -c '%U:%G:%a' '$AGENT_HOME/api_keys')\"     = 'agent-admin:agent-core:2770' ]   || { echo \"NG: api_keys perm = \$(stat -c '%U:%G:%a' '$AGENT_HOME/api_keys')\"; fail=1; }
[ \"\$(stat -c '%U:%G:%a' '$LOG_DIR')\"                 = 'agent-admin:agent-core:2770' ]   || { echo \"NG: log dir perm = \$(stat -c '%U:%G:%a' '$LOG_DIR')\"; fail=1; }

sudo -u agent-test ls '$AGENT_HOME/api_keys' >/dev/null 2>&1 && { echo 'NG: test can read api_keys'; fail=1; }
sudo -u agent-test ls '$LOG_DIR'             >/dev/null 2>&1 && { echo 'NG: test can read log dir'; fail=1; }
sudo -u agent-dev  ls '$AGENT_HOME/bin'      >/dev/null 2>&1 || { echo 'NG: dev cannot traverse to bin'; fail=1; }

[ \$fail -eq 0 ] && echo 'PHASE 3 GATE: PASS' || echo 'PHASE 3 GATE: FAIL'
exit \$fail"
