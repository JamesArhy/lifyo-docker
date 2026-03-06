#!/usr/bin/env bash
set -euo pipefail

# ══════════════════════════════════════════════════════════════════════════════
# Life is Feudal: Your Own — Docker Entrypoint
# Generates config_local.cs and world_N.xml from environment variables,
# waits for MariaDB, then launches the server via Wine + Xvfb.
# ══════════════════════════════════════════════════════════════════════════════

# ── Database defaults ─────────────────────────────────────────────────────────
: "${DB_HOST:=mariadb}"
: "${DB_PORT:=3306}"
: "${DB_USER:=lif}"
: "${DB_PASSWORD:=changeme}"
: "${DB_NAME:=lif_1}"

# ── Server defaults ──────────────────────────────────────────────────────────
: "${GAME_PORT:=28000}"
: "${WORLD_ID:=1}"
: "${UPDATE_ON_START:=false}"

# ── World config defaults ────────────────────────────────────────────────────
: "${SERVER_NAME:=Life is Feudal Docker Server}"
: "${SERVER_PASSWORD:=}"
: "${ADMIN_PASSWORD:=}"
: "${GAME_MODE:=Sandbox}"
: "${IS_PRIVATE:=0}"

# Skills & progression
: "${SKILLS_MULTIPLIER:=10}"
: "${CRAFTING_SKILLCAP:=600}"
: "${COMBAT_SKILLCAP:=400}"
: "${MINOR_SKILLCAP:=400}"

# World simulation
: "${OBJECT_DECAY_RATE:=0}"
: "${TERRAFORMING_SPEED:=4}"
: "${CRAFTING_PERIOD:=60}"
: "${ANIMAL_BREED_PERIOD:=60}"
: "${DAY_CYCLE:=3}"
: "${ANIMALS_COUNT:=100}"

# Server limits
: "${MAX_PLAYERS:=64}"

# Miscellaneous
: "${MOVABLE_MAX_DROP_HEIGHT:=5}"
: "${RANDOM_EVENT_CHANCE_WALKING:=0.03}"
: "${RANDOM_EVENT_CHANCE_ABILITY:=0.02}"
: "${HORSE_DECAY:=90.00}"
: "${DROP_ON_PRAY:=0}"

# Judgement Hour
: "${JH_ENABLED:=0}"
: "${JH_START_TIME:=18:00}"
: "${JH_MON:=0}"
: "${JH_TUE:=0}"
: "${JH_WED:=0}"
: "${JH_THU:=0}"
: "${JH_FRI:=0}"
: "${JH_SAT:=0}"
: "${JH_SUN:=0}"

SERVER_DIR="/home/lif/yoserver"
STEAMCMD="/home/lif/steamcmd/steamcmd.sh"

echo "========================================="
echo "  Life is Feudal: Your Own — Docker"
echo "========================================="
echo ""
echo "  Server name : ${SERVER_NAME}"
echo "  World ID    : ${WORLD_ID}"
echo "  Game port   : ${GAME_PORT}"
echo "  Max players : ${MAX_PLAYERS}"
echo "  Skills mult : ${SKILLS_MULTIPLIER}x"
echo "  Game mode   : ${GAME_MODE}"
echo ""

# ── Optional: update server files on start ────────────────────────────────────
if [ "${UPDATE_ON_START}" = "true" ]; then
    echo "[*] Updating game server via SteamCMD ..."
    su - lif -c "${STEAMCMD} \
        +@sSteamCmdForcePlatformType windows \
        +login anonymous \
        +force_install_dir ${SERVER_DIR} \
        +app_update 320850 validate \
        +quit"
fi

# ── Generate config_local.cs from environment variables ───────────────────────
echo "[*] Generating config_local.cs ..."
export DB_HOST DB_PORT DB_USER DB_PASSWORD DB_NAME GAME_PORT
envsubst < "${SERVER_DIR}/config_local.cs.template" > "${SERVER_DIR}/config_local.cs"
chown lif:lif "${SERVER_DIR}/config_local.cs"

# ── Generate world_N.xml from environment variables ───────────────────────────
WORLD_CONFIG="${SERVER_DIR}/config/world_${WORLD_ID}.xml"
echo "[*] Generating ${WORLD_CONFIG} ..."

# Export ALL variables that the template references
export WORLD_ID SERVER_NAME SERVER_PASSWORD ADMIN_PASSWORD GAME_MODE IS_PRIVATE
export SKILLS_MULTIPLIER CRAFTING_SKILLCAP COMBAT_SKILLCAP MINOR_SKILLCAP
export OBJECT_DECAY_RATE TERRAFORMING_SPEED CRAFTING_PERIOD ANIMAL_BREED_PERIOD
export DAY_CYCLE ANIMALS_COUNT MAX_PLAYERS GAME_PORT
export MOVABLE_MAX_DROP_HEIGHT RANDOM_EVENT_CHANCE_WALKING RANDOM_EVENT_CHANCE_ABILITY
export HORSE_DECAY DROP_ON_PRAY
export JH_ENABLED JH_START_TIME JH_MON JH_TUE JH_WED JH_THU JH_FRI JH_SAT JH_SUN

envsubst < "${SERVER_DIR}/world_1.xml.template" > "${WORLD_CONFIG}"
chown lif:lif "${WORLD_CONFIG}"

echo "[*] Config files generated."

# ── Wait for MariaDB to be reachable ─────────────────────────────────────────
echo "[*] Waiting for MariaDB at ${DB_HOST}:${DB_PORT} ..."
MAX_WAIT=120
ELAPSED=0
until su - lif -c "bash -c 'echo > /dev/tcp/${DB_HOST}/${DB_PORT}'" 2>/dev/null; do
    sleep 2
    ELAPSED=$((ELAPSED + 2))
    if [ "${ELAPSED}" -ge "${MAX_WAIT}" ]; then
        echo "[!] Timed out waiting for MariaDB after ${MAX_WAIT}s. Exiting."
        exit 1
    fi
done
echo "[*] MariaDB is reachable."

# ── Launch the server via Wine + Xvfb (as unprivileged user) ─────────────────
echo "[*] Starting LiF:YO server (World ${WORLD_ID}) ..."
exec su - lif -c "cd ${SERVER_DIR} && xvfb-run wine ddctd_cm_yo_server.exe -worldId ${WORLD_ID}"
