################################################################################
# Life is Feudal: Your Own — Linux Docker Image
#
# Runs the Windows-only dedicated server via Wine + Xvfb on Ubuntu.
# MariaDB is expected as an external service (see docker-compose.yml).
#
# SteamCMD AppID: 320850 (anonymous login, no game purchase needed for server)
################################################################################

FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive

# ── 1. Base packages + Wine (distro package) ─────────────────────────────────
# Using Ubuntu's own wine package (Wine 6.0.3) rather than WineHQ's latest.
# Wine 11.x hangs during wineboot --init in containers (COM/RPC subsystems).
# Wine 6.0 is simple, stable, and well-suited for a 2015-era game server.
RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        software-properties-common \
        gnupg2 \
        wget \
        ca-certificates \
        curl \
        lib32gcc-s1 \
        xvfb \
        cabextract \
        winbind \
        tini \
        telnet \
        locales \
        gettext-base \
        mariadb-client \
        wine wine32 wine64 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ── 2. Locale ─────────────────────────────────────────────────────────────────
RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

# ── 3. Create unprivileged user ───────────────────────────────────────────────
RUN useradd -m -s /bin/bash lif && \
    echo 'export WINEPREFIX=/home/lif/.wine'  >> /home/lif/.bashrc && \
    echo 'export DISPLAY=:99'                  >> /home/lif/.bashrc
USER lif
WORKDIR /home/lif

# ── 4. Download winetricks (prefix init happens at runtime in entrypoint) ─────
# Wine prefix creation during `docker build` often produces broken prefixes
# because the build environment lacks full kernel capabilities (e.g. /proc,
# personality syscall for 32-bit). We defer wineboot + vcrun2015 to first run.
ENV WINEPREFIX=/home/lif/.wine
ENV WINEDEBUG=-all
RUN wget -q -O /home/lif/winetricks \
        https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks && \
    chmod +x /home/lif/winetricks

# ── 5. Install SteamCMD ──────────────────────────────────────────────────────
RUN mkdir -p /home/lif/steamcmd && \
    curl -sqL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz \
        | tar xzf - -C /home/lif/steamcmd

# ── 6. Create server directory ────────────────────────────────────────────────
# Game files are downloaded on first run via SteamCMD, not at build time.
# This keeps the image small (~450MB vs ~1.6GB) at the cost of a longer first start.
RUN mkdir -p /home/lif/yoserver/config /home/lif/yoserver/Logs

# ── 7. Back to root so entrypoint can do setup, then drop privileges ──────────
USER root

# ── 8. Copy entrypoint & config templates ─────────────────────────────────────
# Templates go to /opt/lif-templates/ (not /home/lif/yoserver/) because the
# yoserver directory is volume-mounted at runtime and would hide these files.
COPY entrypoint.sh /entrypoint.sh
COPY config_local.cs.template /opt/lif-templates/config_local.cs.template
COPY world_1.xml.template /opt/lif-templates/world_1.xml.template
RUN chmod +x /entrypoint.sh && chown -R lif:lif /home/lif /opt/lif-templates

# ── 9. Ports ──────────────────────────────────────────────────────────────────
#   28000     — Game traffic (default)
#   28001/2   — Steam query + additional game traffic
EXPOSE 28000/udp 28000/tcp 28001/udp 28001/tcp 28002/udp 28002/tcp

# ── 10. Go ────────────────────────────────────────────────────────────────────
# tini as PID 1 ensures proper signal handling and zombie reaping.
ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]