#!/bin/bash

SERVER_EXE="/home/lifuser/yoserver/ddctd_cm_yo_server.exe"

if [ -f "$SERVER_EXE" ]; then
    echo "Server executable found at $SERVER_EXE."
    echo "Skipping SteamCMD update/install. To force update, delete the executable or set FORCE_UPDATE=true."
else
    echo "Server executable NOT found. Starting installation via SteamCMD..."
    # SteamCMD setup and server update
    steamcmd +@sSteamCmdForcePlatformType windows +login anonymous \
        +force_install_dir /home/lifuser/yoserver +app_update 320850 validate +quit
fi

# Start Life is Feudal server using Wine and xvfb
echo "Starting Life is Feudal server..."
# We are likely running as lifuser now because of the su in init.sh
# xvfb-run might need a display number or auto-find one.
xvfb-run --auto-servernum --server-args='-screen 0 1024x768x24' wine "$SERVER_EXE" -worldid 1
