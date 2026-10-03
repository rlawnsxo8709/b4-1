#!/bin/bash
# 실습 환경 정리. 호스트에 남는 것이 없도록 이름 붙은 리소스를 전부 제거한다.
#   ./teardown.sh          컨테이너 + 네트워크 제거, 증거 소유권 복구
#   ./teardown.sh --all    이미지까지 제거
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSWERS="$(dirname "$HERE")"

docker rm -f agent-lab      >/dev/null 2>&1 && echo "removed container: agent-lab"
docker network rm agent-lab-net >/dev/null 2>&1 && echo "removed network:   agent-lab-net"

if [ "${1:-}" = "--all" ]; then
    docker rmi agent-lab:latest >/dev/null 2>&1 && echo "removed image:     agent-lab:latest"
fi

# 컨테이너가 root 로 생성한 증거 파일의 소유권을 호스트 사용자에게 되돌린다.
# (바인드 마운트를 쓰는 대가이며, PLAN.md 1-4 에 명시한 유일한 파일 접점이다)
if [ -d "$ANSWERS/evidence" ]; then
    if find "$ANSWERS/evidence" ! -user "$(id -un)" -print -quit | grep -q .; then
        echo "restoring evidence ownership (requires sudo)"
        sudo chown -R "$(id -u):$(id -g)" "$ANSWERS/evidence" && echo "evidence ownership restored"
    else
        echo "evidence ownership already correct"
    fi
fi

echo "done."
