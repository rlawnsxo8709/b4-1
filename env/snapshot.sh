#!/bin/bash
# 실제 적용된 설정 파일을 그대로 복사해 온다.
#
# 제출 문서에 설정을 '손으로 옮겨 적으면' 반드시 실제와 어긋난다.
# 오타가 나거나, 나중에 바뀐 설정이 문서에 반영되지 않는다.
# 그래서 문서에 넣을 설정은 항상 실물을 복사한다.
set -u

OUT=/evidence/snapshots
mkdir -p "$OUT"

copy() {
    local src="$1" dst="$2"
    if [ -r "$src" ]; then
        cp "$src" "$OUT/$dst" && echo "  saved: $dst  <- $src"
    else
        echo "  MISS : $src (읽을 수 없음)"
    fi
}

dump() {
    local dst="$1"; shift
    { printf '# 생성: %s\n# 명령: %s\n\n' "$(date '+%F %T %Z')" "$*"; "$@" 2>&1; } > "$OUT/$dst" \
        && echo "  saved: $dst  <- \$ $*"
}

echo "=== 설정 파일 스냅샷 ==="
copy /etc/ssh/sshd_config.d/99-agent.conf  sshd_config.d-99-agent.conf
copy /etc/agent-app.env                     agent-app.env
copy /etc/profile.d/agent-app.sh            profile.d-agent-app.sh
copy /etc/ufw/ufw.conf                      ufw.conf

echo
echo "=== 명령 출력 스냅샷 ==="
dump sshd-effective-config.txt  bash -c "sshd -T | grep -E '^(port|permitrootlogin|passwordauthentication) '"
dump ufw-status.txt             ufw status verbose
dump listening-ports.txt        ss -tulnp
dump accounts.txt               bash -c 'for u in agent-admin agent-dev agent-test; do id "$u"; done'
dump groups.txt                 getent group agent-common agent-core
dump crontab-agent-admin.txt    crontab -l -u agent-admin
dump directory-perms.txt        bash -c 'ls -ld /home/agent-admin /home/agent-admin/agent-app /home/agent-admin/agent-app/bin /home/agent-admin/agent-app/upload_files /home/agent-admin/agent-app/api_keys /var/log/agent-app'
dump getfacl-all.txt            bash -c 'for d in /home/agent-admin /home/agent-admin/agent-app /home/agent-admin/agent-app/bin /home/agent-admin/agent-app/upload_files /home/agent-admin/agent-app/api_keys /var/log/agent-app; do echo "### $d"; getfacl -p "$d" 2>/dev/null; echo; done'
dump script-perms.txt           ls -l /home/agent-admin/agent-app/bin

echo
echo "스냅샷 위치: $OUT"
ls -l "$OUT"
