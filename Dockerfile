FROM steamcmd/steamcmd:ubuntu-22

RUN set -x \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y gosu wine-stable winbind xvfb mariadb-server xdg-user-dirs curl jq --no-install-recommends \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -ms /bin/bash steam \
    && gosu nobody true

RUN mkdir -p /data \
    && chown steam:steam /data

COPY init.sh /
COPY --chown=steam:steam run.sh /home/steam

WORKDIR /data
ARG VERSION="DEV"
ENV VERSION=$VERSION
LABEL version=$VERSION

ENV SETTING1="2" \
    SETTING2="testing" \
    SETTING3="/data/gamefiles/" \
    WORLDID="world1" \
    LISTENPORT="28000" \
    PGID="1000" \
    PUID="1000"

STOPSIGNAL SIGINT

EXPOSE 28000/tcp 28001/tcp 28002/tcp

ENTRYPOINT [ "/init.sh" ]
