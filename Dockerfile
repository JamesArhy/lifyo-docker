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

# ── 6. Download LiF:YO dedicated server (Windows build via SteamCMD) ─────────
# This is done at build time so the image ships ready to run.
# To update later, just rebuild or run the steamcmd command in the entrypoint.
RUN /home/lif/steamcmd/steamcmd.sh \
        +@sSteamCmdForcePlatformType windows \
        +force_install_dir /home/lif/yoserver \
        +login anonymous \
        +app_update 320850 validate \
        +quit

# ── 7. Copy default configs into place ────────────────────────────────────────
RUN cp /home/lif/yoserver/docs/config_local.cs /home/lif/yoserver/config_local.cs.template && \
    cp /home/lif/yoserver/docs/default_world_config.xml /home/lif/yoserver/config/world_1.xml

# ── 8. Back to root so entrypoint can do setup, then drop privileges ──────────
USER root

# ── 9. Copy entrypoint & config templates ─────────────────────────────────────
COPY entrypoint.sh /entrypoint.sh
COPY config_local.cs.template /home/lif/yoserver/config_local.cs.template
COPY world_1.xml.template /home/lif/yoserver/world_1.xml.template
RUN chmod +x /entrypoint.sh && chown -R lif:lif /home/lif

# ── 10. Ports ─────────────────────────────────────────────────────────────────
#   28000     — Game traffic (default)
#   28001/2   — Steam query + additional game traffic
EXPOSE 28000/udp 28000/tcp 28001/udp 28001/tcp 28002/udp 28002/tcp

# ── 11. Volumes ───────────────────────────────────────────────────────────────
#   /home/lif/yoserver/config   — world_*.xml configs (mount to customise)
#   /home/lif/yoserver/Logs     — server logs
VOLUME ["/home/lif/yoserver/config", "/home/lif/yoserver/Logs"]

# ── 12. Go ────────────────────────────────────────────────────────────────────
# tini as PID 1 ensures proper signal handling and zombie reaping.
# xvfb-run provides a virtual display so Wine doesn't hang.
ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]