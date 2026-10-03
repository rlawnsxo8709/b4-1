#!/bin/bash
# agent-lab 컨테이너 기동.
#
# 격리 설계(PLAN.md 1-2):
#   - --privileged 없음         : 호스트 /dev 접근·탈출 경로 차단
#   - 호스트 cgroup 마운트 없음  : 운영 중인 다른 컨테이너에 영향 불가
#   - seccomp/apparmor 기본값 유지
#   - cap-add 는 ufw/iptables 에 필요한 NET_ADMIN, NET_RAW 두 개뿐
#   - 전용 네트워크로 운영 컨테이너와 분리
#   - 포트는 호스트 루프백에만 게시 (LAN 노출 없음)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSWERS="$(dirname "$HERE")"

IMAGE=agent-lab:latest
NAME=agent-lab
NET=agent-lab-net
APP_SRC="$ANSWERS/../questions/agent-app.zip"

mkdir -p "$ANSWERS/evidence/session"

echo "==> building image"
docker build -q -t "$IMAGE" "$HERE"

echo "==> ensuring dedicated network"
docker network inspect "$NET" >/dev/null 2>&1 || docker network create "$NET" >/dev/null

echo "==> (re)creating container"
docker rm -f "$NAME" >/dev/null 2>&1 || true

docker run -d --name "$NAME" \
    --hostname agent-lab \
    --network "$NET" \
    --cap-add NET_ADMIN --cap-add NET_RAW \
    --init \
    -e TZ=Asia/Seoul \
    -v "$ANSWERS/evidence:/evidence" \
    -p 127.0.0.1:20022:20022 \
    "$IMAGE" >/dev/null

echo "==> importing provided application"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
unzip -oq "$APP_SRC" -x '__MACOSX/*' -d "$TMP"
ARCH="$(docker exec "$NAME" uname -m)"
case "$ARCH" in
    aarch64|arm64) APP_BIN="agent-app-linux-arm64" ;;
    x86_64)        APP_BIN="agent-app-linux-x86"   ;;
    *) echo "unsupported arch: $ARCH" >&2; exit 1 ;;
esac
echo "    arch=$ARCH -> $APP_BIN"
docker cp "$TMP/$APP_BIN" "$NAME:/opt/$APP_BIN"
docker exec "$NAME" chmod 755 "/opt/$APP_BIN"

echo
docker ps --filter "name=$NAME" --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
echo
echo "접속: docker exec -it $NAME bash -l"
