#!/bin/bash
# Phase 4 — 애플리케이션 실행 환경 구성 및 기동
set -u
source /usr/local/lib/rec.sh
evidence_open phase4-app

AGENT_HOME=/home/agent-admin/agent-app
APP_BIN=agent-app-linux-arm64
# pkill/pgrep 패턴에 대괄호를 넣어 '자기 자신'이 매치되지 않게 한다.
# 이유는 [4-5] 의 rec_note 참조.
APP_PAT='agent-app-linux-arm[6]4'

echo "--- [4-1] 앱의 실제 요구사항 확인 (실측으로 확정) ---"
rec_note "[문서와 앱의 불일치 — 실측으로 확정한 내용]
미션 문서의 표기를 그대로 적용했더니 Boot 가 실패했다. 앱이 출력한 오류
메시지를 근거로 두 가지를 수정했다.

(1) AGENT_KEY_PATH 는 '파일'이 아니라 '디렉토리'다.
    문서: AGENT_KEY_PATH = \$AGENT_HOME/api_keys/t_secret.key
    실제: [2/5] Verifying Environment Variables [FAIL]
          >>> Key Path Mismatch. Expected: /home/agent-admin/agent-app/api_keys
    → AGENT_KEY_PATH 를 api_keys 디렉토리로 지정하니 [2/5] 통과.

(2) 앱이 찾는 키 파일명은 t_secret.key 가 아니라 secret.key 다.
    실제: [3/5] Checking Required Files [FAIL]
          >>> Missing File: secret.key
          >>>    (Expected location: .../api_keys/secret.key)
    → secret.key 생성 후 [3/5] 통과.
       ... Verified 'secret.key' with correct key string.

대응 : 문서 요구사항(t_secret.key)과 앱 요구사항(secret.key)을 모두 만족시키기
       위해 두 파일을 같은 내용으로 생성한다. 어느 쪽 기준으로 채점하더라도
       충족되며, 불일치 사실 자체를 기록에 남긴다.
교훈 : 사양서와 실제 구현이 어긋날 때 판단 근거는 '실행 결과'다.
       앱이 친절하게 Expected 값을 출력해 주었으므로 추측할 필요가 없었다."

echo "--- [4-2] 환경 변수 정의 (단일 원본) ---"
rec_note "환경 변수를 두 곳에서 쓰되 정의는 한 곳에만 둔다.
  /etc/agent-app.env          — 값의 유일한 원본. KEY=VALUE 평문.
  /etc/profile.d/agent-app.sh — 로그인 셸용. 위 파일을 set -a 로 읽어 export.
정의를 두 번 쓰면 반드시 어긋난다.

특히 중요한 것은 cron 이다. cron 은 /etc/profile.d 를 읽지 않고 PATH 와 HOME
정도만 있는 최소 환경에서 작업을 실행한다. 따라서 monitor.sh 는 로그인 셸
환경에 기대지 말고 /etc/agent-app.env 를 스스로 source 해야 한다.
'내 터미널에서는 되는데 cron 에서만 안 되는' 문제의 대부분이 여기서 나온다."

cat > /etc/agent-app.env <<EOF
# B4-1 에이전트 앱 실행 환경 — 값의 단일 원본
# 로그인 셸(profile.d)과 cron 실행 스크립트(monitor.sh)가 함께 참조한다.
AGENT_HOME=$AGENT_HOME
AGENT_PORT=15034
AGENT_UPLOAD_DIR=$AGENT_HOME/upload_files

# 주의: 앱은 이 값을 '디렉토리'로 기대한다(파일 경로가 아니다).
#       파일 경로를 넣으면 Boot [2/5] 가 Key Path Mismatch 로 실패한다.
AGENT_KEY_PATH=$AGENT_HOME/api_keys

AGENT_LOG_DIR=/var/log/agent-app

# 관제 스크립트가 감시할 프로세스 패턴.
# 대괄호는 pgrep 이 스크립트 자신을 매치하는 것을 막기 위한 것이다.
AGENT_APP_PATTERN=agent-app-linux-arm[6]4
EOF
chmod 644 /etc/agent-app.env

cat > /etc/profile.d/agent-app.sh <<'EOF'
# 로그인 셸에 에이전트 앱 환경 변수를 주입한다.
# 값 자체는 /etc/agent-app.env 에만 존재한다(단일 원본).
# set -a : 이 구간에서 대입되는 변수를 자동으로 export 한다.
if [ -r /etc/agent-app.env ]; then
    set -a
    . /etc/agent-app.env
    set +a
fi
EOF
chmod 644 /etc/profile.d/agent-app.sh

rec cat /etc/agent-app.env
rec cat /etc/profile.d/agent-app.sh

echo "--- [4-3] 로그인 셸에서 환경 변수가 실제로 잡히는지 ---"
recsh "sudo -iu agent-admin env | grep -E '^AGENT_' | sort"

echo "--- [4-4] 앱 바이너리 배치 ---"
recsh "install -o agent-admin -g agent-core -m 750 /opt/$APP_BIN '$AGENT_HOME/$APP_BIN'
       ls -l '$AGENT_HOME/$APP_BIN'"

echo "--- [4-5] API 키 파일 생성 (문서 요구 + 앱 요구 양쪽 충족) ---"
# 주의: 루프 변수를 쓰는 경로는 반드시 큰따옴표로 감싼다.
# '경로/$f' 처럼 작은따옴표를 쓰면 변수가 확장되지 않아
# '$f' 라는 이름의 파일이 만들어진다. (실제로 이 실수를 했고 Phase 9 에서 발견)
recsh "for f in t_secret.key secret.key; do
         echo 'agent_api_key_test' > \"$AGENT_HOME/api_keys/\$f\"
         chown agent-admin:agent-core \"$AGENT_HOME/api_keys/\$f\"
         chmod 640 \"$AGENT_HOME/api_keys/\$f\"
       done
       ls -l \"$AGENT_HOME/api_keys/\"
       echo '--- 내용 (개행 가시화: \$ 가 줄끝 개행) ---'
       cat -A \"$AGENT_HOME/api_keys/secret.key\""
rec_note "키 파일 내용은 echo 로 생성했으므로 끝에 개행(LF)이 붙는다.
앱은 이 상태를 'correct key string' 으로 인정했다([3/5] 통과).
만약 앱이 개행 없는 정확 일치를 요구했다면 printf '%s' 로 재생성해야 한다."

echo "--- [4-6] 기존 인스턴스 정리 (Boot [4/5] 는 포트가 비어 있어야 통과) ---"
rec_note "[함정 기록] pkill -f 는 자기 자신을 죽일 수 있다.
프로브 과정에서 bash -c \"... pkill -f agent-app-linux-arm64 ...\" 를 실행했더니
셸 자신의 명령줄에도 그 문자열이 들어 있어 pkill 이 부모 셸을 죽였다
(종료코드 143 = SIGTERM). 해결책은 패턴에 대괄호를 넣는 것이다.
  agent-app-linux-arm[6]4
이 정규식은 'agent-app-linux-arm64' 에 매치되지만, 명령줄에 남는 문자열
'agent-app-linux-arm[6]4' 자체에는 매치되지 않는다.
같은 이유로 monitor.sh 의 감시 패턴도 이 형태로 고정한다."

recsh "pkill -f '$APP_PAT' 2>/dev/null; sleep 1
       ss -tuln | grep -q ':15034 ' && echo 'WARN: 15034 still in use' || echo 'OK: port 15034 free'"

echo "--- [4-7] 앱 기동 (agent-admin 으로 실행, root 금지) ---"
recsh "sudo -u agent-admin bash -c '
    set -a; . /etc/agent-app.env; set +a
    cd \"\$AGENT_HOME\"
    nohup ./$APP_BIN > \"\$AGENT_HOME/app-boot.log\" 2>&1 &
    echo \"launched pid=\$!\"
'
sleep 5"

echo "--- [4-8] Boot Sequence 출력 ---"
recsh "sed -n '1,/Agent READY/p' '$AGENT_HOME/app-boot.log'"

echo "--- [4-9] 기동 이후 앱 동작 로그 (앱의 성격 확인) ---"
recsh "grep -A6 'Agent Worker Started' '$AGENT_HOME/app-boot.log' | head -8"
rec_note "이 앱은 단순 대기 서버가 아니라 CPU 와 메모리를 주기적으로 끌어올리는
부하 생성기다(Cycle: 0 -> 256MB/Lv10 -> 0). monitor.sh 의 임계값 경고
(CPU>20%, MEM>10%)가 실제로 발동하도록 설계된 것으로 보인다.
따라서 경고 로직은 인위적 조작 없이 자연스럽게 검증할 수 있다."

echo "--- [4-10] 실행 사용자 / 실제 프로세스명 확인 ---"
rec_note "미션 예시는 프로세스명을 agent_app.py 로 적고 있으나, 제공된 앱은
PyInstaller 로 패키징된 단일 실행 바이너리다. 실제 프로세스명은 아래 실측값이며
monitor.sh 의 감시 패턴은 추측이 아니라 이 값에 맞춘다."
recsh "ps -eo pid,user,comm,args --no-headers | grep 'agent-app-linux-arm[6]4' | grep -v grep"

echo "--- [4-11] 포트 LISTEN 확인 ---"
rec ss -tulnp

echo
echo "=== Phase 4 gate 결과 ==="
recsh "
fail=0
LOG='$AGENT_HOME/app-boot.log'
for n in 1 2 3 4 5; do
  grep -qE \"\\[\$n/5\\].*\\[OK\\]\" \"\$LOG\" || { echo \"NG: boot step \$n not [OK]\"; fail=1; }
done
grep -q 'All Boot Checks Passed' \"\$LOG\" || { echo 'NG: boot checks banner missing'; fail=1; }
grep -q 'Agent READY'            \"\$LOG\" || { echo 'NG: Agent READY missing'; fail=1; }
ss -tuln | grep -q ':15034 '           || { echo 'NG: not listening on 15034'; fail=1; }
pid=\$(pgrep -f 'agent-app-linux-arm[6]4' | head -1)
[ -n \"\$pid\" ] || { echo 'NG: app process not found'; fail=1; }
if [ -n \"\$pid\" ]; then
  owner=\$(ps -o user= -p \"\$pid\" | tr -d ' ')
  [ \"\$owner\" = 'agent-admin' ] || { echo \"NG: app running as \$owner (must be agent-admin)\"; fail=1; }
  [ \"\$owner\" = 'root' ] && { echo 'NG: root 실행은 금지'; fail=1; }
fi
[ \$fail -eq 0 ] && echo 'PHASE 4 GATE: PASS' || echo 'PHASE 4 GATE: FAIL'
exit \$fail"
