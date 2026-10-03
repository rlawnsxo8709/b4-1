# 로그인 셸에 에이전트 앱 환경 변수를 주입한다.
# 값 자체는 /etc/agent-app.env 에만 존재한다(단일 원본).
# set -a : 이 구간에서 대입되는 변수를 자동으로 export 한다.
if [ -r /etc/agent-app.env ]; then
    set -a
    . /etc/agent-app.env
    set +a
fi
