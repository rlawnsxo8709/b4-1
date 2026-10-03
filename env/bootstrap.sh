#!/bin/bash
# =============================================================================
# bootstrap.sh — 컨테이너 내부 1회 셋업 (Phase 1~4 통합, 최종 확정판)
#
# 단계별 phases/*.sh 는 '무엇을 왜 했는가'를 기록으로 남기기 위한 것이고,
# 이 파일은 그 과정에서 확정된 최종 설정만 모아 재현 가능하게 만든 것이다.
# 도중에 발견한 문제들의 해결책이 모두 반영되어 있다.
#
#   - SSH 포트 20022 / Root 로그인 차단
#   - UFW: 20022, 15034 만 허용
#   - 계정 3개, 그룹 2개, 디렉토리 권한 + ACL
#     (agent-common 에 통행권(x)만 부여해 공유 디렉토리에 도달 가능하게 함)
#   - 환경 변수 단일 원본 + cron 대응
#   - 앱 키 파일 (t_secret.key + secret.key 양쪽 생성)
#
# 사용법: docker exec -i agent-lab bash -s < bootstrap.sh
# =============================================================================
set -euo pipefail

AGENT_HOME=/home/agent-admin/agent-app
LOG_DIR=/var/log/agent-app
APP_BIN=agent-app-linux-arm64

step() { printf '\n=== %s ===\n' "$1"; }

# --- 1. SSH ------------------------------------------------------------------
step "SSH: 포트 20022, Root 로그인 차단"
cat > /etc/ssh/sshd_config.d/99-agent.conf <<'EOF'
Port 20022
PermitRootLogin no
EOF
sshd -t
pkill -x sshd 2>/dev/null || true
sleep 1
/usr/sbin/sshd
sshd -T | grep -E '^(port|permitrootlogin) '

# 참고: 실제 Ubuntu 22.10+ 호스트는 ssh.socket 소켓 액티베이션이 기본이라
# 위 설정만으로는 포트가 바뀌지 않는다. 그 환경에서는 아래가 추가로 필요하다.
#   systemctl disable --now ssh.socket
#   systemctl enable  --now ssh.service

# --- 2. 방화벽 ---------------------------------------------------------------
step "UFW: 필요한 포트만 허용"
ufw default deny incoming
ufw default allow outgoing
ufw allow 20022/tcp comment 'SSH'     # enable 이전에 먼저 등록 (락아웃 방지)
ufw allow 15034/tcp comment 'AGENT APP'
ufw --force enable
ufw status verbose

# --- 3. 계정 / 그룹 ----------------------------------------------------------
step "계정 및 그룹"
for g in agent-common agent-core; do
    getent group "$g" >/dev/null || groupadd "$g"
done
for u in agent-admin agent-dev agent-test; do
    id "$u" >/dev/null 2>&1 || useradd -m -s /bin/bash "$u"
done
usermod -aG agent-common agent-admin
usermod -aG agent-common agent-dev
usermod -aG agent-common agent-test
usermod -aG agent-core   agent-admin
usermod -aG agent-core   agent-dev
for u in agent-admin agent-dev agent-test; do id "$u"; done

# --- 4. 디렉토리 + 권한 + ACL -------------------------------------------------
step "디렉토리 구조와 권한"
mkdir -p "$AGENT_HOME"/{bin,upload_files,api_keys} "$LOG_DIR"
chown -R agent-admin:agent-admin /home/agent-admin

# setgid(2) : 누가 만들든 새 파일의 그룹이 디렉토리 그룹으로 고정된다.
chmod 750 /home/agent-admin
chown agent-admin:agent-core   "$AGENT_HOME"              && chmod 2750 "$AGENT_HOME"
chown agent-admin:agent-core   "$AGENT_HOME/bin"          && chmod 2750 "$AGENT_HOME/bin"
chown agent-admin:agent-common "$AGENT_HOME/upload_files" && chmod 2770 "$AGENT_HOME/upload_files"
chown agent-admin:agent-core   "$AGENT_HOME/api_keys"     && chmod 2770 "$AGENT_HOME/api_keys"
chown agent-admin:agent-core   "$LOG_DIR"                 && chmod 2770 "$LOG_DIR"

# 통행권(x)만 부여한다. r 이 없으므로 목록은 볼 수 없고 통과만 가능하다.
# 이것이 없으면 agent-common 구성원이 upload_files 에 도달조차 못 한다
# (리눅스는 경로상의 모든 디렉토리에 x 를 요구한다).
setfacl -m g:agent-common:x /home/agent-admin
setfacl -m g:agent-common:x "$AGENT_HOME"

# agent-dev 는 monitor.sh 를 작성해야 하므로 bin 에 쓰기 권한이 필요하다.
setfacl -m  u:agent-dev:rwx "$AGENT_HOME/bin"
setfacl -dm u:agent-dev:rwx "$AGENT_HOME/bin"
setfacl -dm g:agent-core:rx "$AGENT_HOME/bin"

# 공유 영역: agent-common R/W, 신규 파일도 상속
setfacl -m  g:agent-common:rwx "$AGENT_HOME/upload_files"
setfacl -dm g:agent-common:rwx "$AGENT_HOME/upload_files"

# 보안 영역: agent-core 만 R/W, 그 외 완전 차단
for d in "$AGENT_HOME/api_keys" "$LOG_DIR"; do
    setfacl -m  g:agent-core:rwx -m o::--- "$d"
    setfacl -dm g:agent-core:rwx -dm o::--- "$d"
done

ls -ld /home/agent-admin "$AGENT_HOME" "$AGENT_HOME"/{bin,upload_files,api_keys} "$LOG_DIR"

# --- 5. 환경 변수 ------------------------------------------------------------
step "환경 변수 (단일 원본)"
cat > /etc/agent-app.env <<EOF
# B4-1 에이전트 앱 실행 환경 — 값의 단일 원본
AGENT_HOME=$AGENT_HOME
AGENT_PORT=15034
AGENT_UPLOAD_DIR=$AGENT_HOME/upload_files

# 주의: 앱은 이 값을 '디렉토리'로 기대한다(파일 경로가 아니다).
AGENT_KEY_PATH=$AGENT_HOME/api_keys

AGENT_LOG_DIR=$LOG_DIR

# 관제 대상 프로세스 패턴. 대괄호는 pgrep 자기매치 방지용이다.
AGENT_APP_PATTERN=agent-app-linux-arm[6]4
EOF
chmod 644 /etc/agent-app.env

cat > /etc/profile.d/agent-app.sh <<'EOF'
# 로그인 셸 환경 주입. 값 자체는 /etc/agent-app.env 에만 존재한다.
if [ -r /etc/agent-app.env ]; then
    set -a
    . /etc/agent-app.env
    set +a
fi
EOF
chmod 644 /etc/profile.d/agent-app.sh
cat /etc/agent-app.env

# --- 6. 앱 배치 + 키 파일 -----------------------------------------------------
step "앱 바이너리와 키 파일"
if [ -f "/opt/$APP_BIN" ]; then
    install -o agent-admin -g agent-core -m 750 "/opt/$APP_BIN" "$AGENT_HOME/$APP_BIN"
fi
# 미션 문서는 t_secret.key 를, 앱은 secret.key 를 요구한다. 양쪽 모두 생성한다.
for f in t_secret.key secret.key; do
    echo 'agent_api_key_test' > "$AGENT_HOME/api_keys/$f"
    chown agent-admin:agent-core "$AGENT_HOME/api_keys/$f"
    chmod 640 "$AGENT_HOME/api_keys/$f"
done
ls -l "$AGENT_HOME/api_keys/"

# --- 7. 관제 스크립트 ---------------------------------------------------------
step "관제 스크립트 배치 (agent-dev 소유)"
if [ -f /tmp/monitor.sh ]; then
    sudo -u agent-dev cp /tmp/monitor.sh "$AGENT_HOME/bin/monitor.sh"
    sudo -u agent-dev chmod 750 "$AGENT_HOME/bin/monitor.sh"
fi
ls -l "$AGENT_HOME/bin"

# --- 8. cron -----------------------------------------------------------------
step "cron 매분 실행 등록"
pgrep -x cron >/dev/null || cron
sudo -u agent-admin crontab - <<EOF
# B4-1 시스템 관제 자동화
* * * * * $AGENT_HOME/bin/monitor.sh >> $LOG_DIR/cron.out 2>&1
EOF
crontab -l -u agent-admin

printf '\n=== bootstrap 완료 ===\n'
printf '앱 실행:\n'
printf "  sudo -u agent-admin bash -c 'set -a; . /etc/agent-app.env; set +a; cd \$AGENT_HOME && ./%s'\n" "$APP_BIN"
