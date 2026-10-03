#!/bin/bash
# Phase 9 — 미션 문서 표기와의 정합성 재검증
#
# 문서는 AGENT_KEY_PATH 를 파일 경로로, 키 파일명을 t_secret.key 로 지정한다.
# Phase 4 의 검증은 secret.key 가 없던 상태였으므로, 파일이 모두 갖춰진
# 지금 조건에서 '문서 표기 그대로' 되는지 다시 확인한다.
set -u
source /usr/local/lib/rec.sh
evidence_open phase9-doc-conformance

AGENT_HOME=/home/agent-admin/agent-app
API_KEYS="$AGENT_HOME/api_keys"

# 앱 종료는 이 바깥 셸에서만 수행한다.
# 이 스크립트는 'bash -l -s' 로 실행되므로 셸의 명령줄에 앱 이름이 없어 안전하다.
# recsh 안에서 pkill 을 부르면, 같은 명령줄에 들어 있는 실행 명령
# './agent-app-linux-arm64' 가 패턴에 매치되어 자기 셸을 죽인다. (실제로 겪음)
stop_app() { pkill -f 'agent-app-linux-arm[6]4' 2>/dev/null; sleep 2; }

launch() {   # launch <로그경로> <AGENT_KEY_PATH 값>
    recsh "sudo -u agent-admin bash -c '
        cd \"$AGENT_HOME\"
        AGENT_HOME=$AGENT_HOME AGENT_PORT=15034 \
        AGENT_UPLOAD_DIR=$AGENT_HOME/upload_files \
        AGENT_KEY_PATH=$2 \
        AGENT_LOG_DIR=/var/log/agent-app \
        nohup ./agent-app-linux-arm64 > $1 2>&1 &'
        sleep 5
        cat $1 2>/dev/null | head -14"
}

rec_note "[검증 목적]
가능하다면 미션 문서의 표기를 그대로 따르는 것이 맞다. 문서와 다르게 구현했다면
'왜 그럴 수밖에 없었는지'를 근거로 제시할 수 있어야 한다.
Phase 4 의 실패는 secret.key 가 없던 조건에서 관측된 것이므로,
지금 조건에서 문서 표기를 다시 시험해 결론을 확정한다."

echo "--- [9-1] 잔여 파일 정리 및 키 파일 재생성 ---"
rec_note "[결함 발견] api_keys 에 '\$f' 라는 이름의 파일이 있었다.
Phase 4 스크립트의 키 생성 루프에서 '경로/\$f' 처럼 작은따옴표를 써서
루프 변수가 확장되지 않은 결과다. Phase 7 의 배치 루프와 똑같은 실수이며,
그때는 증상이 바로 드러났지만 여기서는 실제 키 파일이 이전 수동 작업으로
이미 존재했던 탓에 드러나지 않았다.
'우연히 결과가 맞아서 버그가 숨는' 전형적인 경우다.
Phase 4 스크립트를 수정하고 키 파일을 규정대로 다시 만든다."

recsh "rm -f \"$API_KEYS/\\\$f\"
       for f in t_secret.key secret.key; do
         echo 'agent_api_key_test' > \"$API_KEYS/\$f\"
         chown agent-admin:agent-core \"$API_KEYS/\$f\"
         chmod 640 \"$API_KEYS/\$f\"
       done
       ls -l \"$API_KEYS/\"
       echo '--- 내용 (개행 가시화) ---'
       for f in t_secret.key secret.key; do
         printf '%-14s : ' \"\$f\"; cat -A \"$API_KEYS/\$f\"
       done"

echo
echo "=============================================================="
echo " [9-2] 시험 A — AGENT_KEY_PATH = 문서 표기 (파일 경로)"
echo "=============================================================="
stop_app
launch /tmp/probeA.log "$API_KEYS/t_secret.key"

echo
echo "=============================================================="
echo " [9-3] 시험 B — AGENT_KEY_PATH = 디렉토리 (현재 채택안)"
echo "=============================================================="
stop_app
launch /tmp/probeB.log "$API_KEYS"

echo
echo "=============================================================="
echo " [9-4] 시험 C — 문서가 지정한 t_secret.key 만 두는 경우"
echo "=============================================================="
rec_note "t_secret.key 만으로 앱이 동작한다면 secret.key 는 불필요하고
문서 표기만 남기면 된다. 이것도 확인해야 결론이 완결된다."
stop_app
recsh "mv \"$API_KEYS/secret.key\" /tmp/secret.key.bak && echo 'secret.key 임시 제거'"
launch /tmp/probeC.log "$API_KEYS"

echo "--- [9-5] secret.key 복구 ---"
stop_app
recsh "install -o agent-admin -g agent-core -m 640 /tmp/secret.key.bak \"$API_KEYS/secret.key\"
       rm -f /tmp/secret.key.bak
       ls -l \"$API_KEYS/\""

echo "--- [9-6] 최종 구성으로 앱 재기동 ---"
stop_app
recsh "sudo -u agent-admin bash -c '
         set -a; . /etc/agent-app.env; set +a
         cd \"\$AGENT_HOME\"
         nohup ./agent-app-linux-arm64 >> \"\$AGENT_HOME/app-boot.log\" 2>&1 &'
       sleep 6
       sed -n '/Starting Agent Boot Sequence/,/Agent READY/p' \"$AGENT_HOME/app-boot.log\" | tail -18
       ss -tuln | grep ':15034 ' && echo '재기동 확인'"

echo
echo "=============================================================="
echo " [9-7] 결론"
echo "=============================================================="
recsh "
a=\$(grep -q 'Agent READY' /tmp/probeA.log 2>/dev/null && echo '부팅 성공' || echo '부팅 실패')
b=\$(grep -q 'Agent READY' /tmp/probeB.log 2>/dev/null && echo '부팅 성공' || echo '부팅 실패')
c=\$(grep -q 'Agent READY' /tmp/probeC.log 2>/dev/null && echo '부팅 성공' || echo '부팅 실패')
printf '시험 A  AGENT_KEY_PATH = 파일 경로 (문서 표기) : %s\n' \"\$a\"
grep -m1 'Key Path Mismatch' /tmp/probeA.log 2>/dev/null | sed 's/^/          /'
printf '시험 B  AGENT_KEY_PATH = 디렉토리             : %s\n' \"\$b\"
printf '시험 C  t_secret.key 만 존재                  : %s\n' \"\$c\"
grep -m1 'Missing File' /tmp/probeC.log 2>/dev/null | sed 's/^/          /'
"

rec_note "[결론]
시험 A 가 실패하고 B 가 성공한다면, AGENT_KEY_PATH 를 디렉토리로 두는 것은
'선택'이 아니라 앱이 강제하는 '제약'이다. 문서 표기를 따를 수 없는 이유를
앱의 출력으로 증명한 셈이다.
시험 C 가 실패한다면 secret.key 도 앱이 강제하는 것이므로,
문서가 지정한 t_secret.key 와 함께 두 파일을 모두 유지하는 현재 방식이
문서와 앱을 동시에 만족시키는 유일한 방법이다."
