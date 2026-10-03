# B4-1 실습 환경 이미지
#
# systemd 를 의도적으로 설치하지 않는다.
# systemd 를 컨테이너에서 돌리려면 --privileged 와 호스트 cgroup 쓰기 마운트가
# 필요해지는데, 그건 격리가 아니라 호스트 탈출 경로를 여는 것이다.
# 이 미션이 요구하는 sshd / cron / ufw / ACL 은 전부 systemd 없이 동작함을
# 사전 검증했으므로(PLAN.md 0-1), 진입점에서 데몬을 직접 기동한다.
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Seoul

RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends \
        openssh-server \
        ufw \
        cron \
        acl \
        iproute2 \
        iptables \
        sudo \
        procps \
        psmisc \
        util-linux \
        tzdata \
        gzip \
        findutils \
        less \
        ca-certificates && \
    rm -rf /var/lib/apt/lists/*

RUN ln -snf "/usr/share/zoneinfo/$TZ" /etc/localtime && echo "$TZ" > /etc/timezone

# sshd 런타임 디렉토리 + 호스트 키
RUN mkdir -p /run/sshd && ssh-keygen -A

COPY entrypoint.sh /usr/local/sbin/entrypoint.sh
COPY rec.sh        /usr/local/lib/rec.sh
RUN chmod 755 /usr/local/sbin/entrypoint.sh && chmod 644 /usr/local/lib/rec.sh

# 모든 대화형 셸에서 rec() 헬퍼를 바로 쓸 수 있게 한다
RUN printf '[ -f /usr/local/lib/rec.sh ] && . /usr/local/lib/rec.sh\n' \
      > /etc/profile.d/00-rec.sh

EXPOSE 20022 15034

ENTRYPOINT ["/usr/local/sbin/entrypoint.sh"]
