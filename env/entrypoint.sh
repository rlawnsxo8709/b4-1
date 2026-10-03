#!/bin/bash
# agent-lab 컨테이너 진입점.
# systemd 를 쓰지 않으므로 sshd / cron 을 여기서 직접 기동한다.
# 컨테이너를 재시작해도 서비스가 살아나도록 여기에 모아 둔다.
set -u

log() { printf '[entrypoint %s] %s\n' "$(date '+%F %T')" "$*"; }

mkdir -p /run/sshd
[ -f /etc/ssh/ssh_host_ed25519_key ] || ssh-keygen -A >/dev/null 2>&1

if ! pgrep -x sshd >/dev/null 2>&1; then
    if /usr/sbin/sshd; then
        log "sshd started (port: $(sshd -T 2>/dev/null | awk '/^port /{print $2}' | paste -sd, -))"
    else
        log "WARNING: sshd failed to start"
    fi
fi

if ! pgrep -x cron >/dev/null 2>&1; then
    if cron; then log "cron started"; else log "WARNING: cron failed to start"; fi
fi

# UFW 는 systemd 유닛으로 복원되지 않으므로, 이전에 활성화한 적이 있으면
# 컨테이너 재기동 시 규칙을 다시 적용해 준다.
if [ -f /etc/ufw/ufw.conf ] && grep -q '^ENABLED=yes' /etc/ufw/ufw.conf; then
    if ufw --force enable >/dev/null 2>&1; then log "ufw rules reapplied"; fi
fi

log "ready"
exec sleep infinity
