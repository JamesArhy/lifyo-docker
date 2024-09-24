#!/bin/bash

# Start MariaDB
echo "Starting MariaDB..."
service mysql start

# Check for available storage before downloading the game
cd /data

STORAGEAVAILABLE=$(stat -f -c "%a*%S" .)
STORAGEAVAILABLE=$((STORAGEAVAILABLE/1024/1024/1024))
printf "Checking available storage: %sGB detected\\n" "$STORAGEAVAILABLE"

if [[ "$STORAGEAVAILABLE" -lt 8 ]]; then
    printf "You have less than 8GB (%sGB detected) of available storage to download the game.\\nIf this is a fresh install, it will probably fail.\\n" "$STORAGEAVAILABLE"
fi

# Download the latest version of the game using SteamCMD
echo "Downloading the latest version of the game..."
STEAMAPPID="320850"  # Replace this with the correct app ID for Life is Feudal: Your Own
STEAMBETAFLAG="public"  # Modify this if you are using a different beta branch

steamcmd +force_install_dir /data/gamefiles +login anonymous +app_update "$STEAMAPPID" -beta "$STEAMBETAFLAG" validate +quit

# Store Steam logs
cp -r /home/steam/.steam/steam/logs/* "/data/logs/steam" || printf "Failed to store Steam logs\\n"

# Start the Life is Feudal server
echo "Starting Life is Feudal: Your Own server..."
cd /data/gamefiles

# Run the server in Wine using xvfb to run it in a virtual display (needed for Wine in headless mode)
xvfb-run --auto-servernum --server-args="-screen 0 1024x768x16" wine LIF_YourOwnServer.exe -worldid $WORLDID -port $LISTENPORT
