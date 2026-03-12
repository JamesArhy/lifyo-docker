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
: "${HORSE_DECAY_MINUTES:=0}"
: "${DROP_ON_PRAY:=0}"

# Judgement Hour
: "${JH_ENABLED:=0}"
: "${JH_START_TIME:=00:00}"
: "${JH_MON:=0}"
: "${JH_TUE:=0}"
: "${JH_WED:=0}"
: "${JH_THU:=0}"
: "${JH_FRI:=0}"
: "${JH_SAT:=0}"
: "${JH_SUN:=0}"
: "${JH_DURATION:=0}"

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
        +force_install_dir ${SERVER_DIR} \
        +login anonymous \
        +app_update 320850 validate \
        +quit"
fi

# ── Generate config_local.cs from environment variables ───────────────────────
echo "[*] Generating config_local.cs ..."
export DB_HOST DB_PORT DB_USER DB_PASSWORD DB_NAME
envsubst '${DB_HOST} ${DB_USER} ${DB_PASSWORD}' < "${SERVER_DIR}/config_local.cs.template" > "${SERVER_DIR}/config_local.cs"
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
export HORSE_DECAY_MINUTES DROP_ON_PRAY
export JH_ENABLED JH_START_TIME JH_MON JH_TUE JH_WED JH_THU JH_FRI JH_SAT JH_SUN JH_DURATION

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

# ── Helper: import SQL with DELIMITER support ────────────────────────────────
# The shipped SQL files contain CREATE PROCEDURE/FUNCTION with BEGIN...END
# blocks but no DELIMITER statements. The mysql CLI can't parse these without
# DELIMITER, so we preprocess: add DELIMITER // before each CREATE PROCEDURE/
# FUNCTION and replace the closing END; with END //.
import_sql_with_delimiters() {
    local sql_file="$1"
    echo "[*]   Importing ${sql_file} (with DELIMITER preprocessing) ..."

    python3 -c "
import re, sys

with open(sys.argv[1], 'r') as f:
    lines = f.read().split('\n')

output = []
in_routine = False

for line in lines:
    # CREATE PROCEDURE/FUNCTION at column 0 starts a routine
    if not in_routine and re.match(r'^CREATE\s+(PROCEDURE|FUNCTION)\s+', line, re.IGNORECASE):
        output.append('DELIMITER //')
        in_routine = True
        output.append(line)
    # END; at column 0 (with optional comment) ends a routine
    elif in_routine and re.match(r'^END;\s*(/\*.*\*/)?\s*$', line):
        out = re.sub(r';(\s*(/\*.*\*/)?\s*)$', r'//\1', line.rstrip())
        output.append(out)
        output.append('DELIMITER ;')
        in_routine = False
    else:
        output.append(line)

print('\n'.join(output))
" "${sql_file}" | \
    mysql --force -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" -p"${DB_PASSWORD}" "${DB_NAME}"
}

# ── Initialize database schema on first run ─────────────────────────────────
# Check both table count AND stored procedure count. The server needs stored
# procedures from patch.sql to function (e.g., CmServerInfoManager uses them).
TABLE_COUNT=$(mysql -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" -p"${DB_PASSWORD}" \
    -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}';" 2>/dev/null || echo "0")

PROC_COUNT=$(mysql -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" -p"${DB_PASSWORD}" \
    -N -e "SELECT COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA='${DB_NAME}';" 2>/dev/null || echo "0")

if [ "${TABLE_COUNT}" -eq 0 ] 2>/dev/null; then
    echo "[*] Empty database detected — importing schema ..."
    import_sql_with_delimiters "${SERVER_DIR}/sql/new.sql"
    import_sql_with_delimiters "${SERVER_DIR}/sql/patch.sql"
    import_sql_with_delimiters "${SERVER_DIR}/sql/dump.sql"
    echo "[*] Database schema imported."
elif [ "${PROC_COUNT}" -lt 50 ] 2>/dev/null; then
    echo "[*] Database has ${TABLE_COUNT} tables but only ${PROC_COUNT} stored procedures — reimporting ..."
    import_sql_with_delimiters "${SERVER_DIR}/sql/new.sql"
    import_sql_with_delimiters "${SERVER_DIR}/sql/patch.sql"
    import_sql_with_delimiters "${SERVER_DIR}/sql/dump.sql"
    echo "[*] Schema reimport complete."
else
    echo "[*] Database has ${TABLE_COUNT} tables and ${PROC_COUNT} stored procedures, skipping import."
fi

# ── Fix volume permissions ────────────────────────────────────────────────────
# Docker named volumes may be created as root; ensure lif user can write.
chown -R lif:lif "${SERVER_DIR}/Logs" "${SERVER_DIR}/config" 2>/dev/null || true
chown -R lif:lif /home/lif/.wine 2>/dev/null || true

# ── Launch the server via Wine + Xvfb (as unprivileged user) ─────────────────
echo "[*] Starting LiF:YO server (World ${WORLD_ID}) ..."

# Start a persistent Xvfb. xvfb-run tears down the X server when the wrapped
# command exits, which kills Wine prematurely. A persistent Xvfb stays up for
# the lifetime of the container.
rm -f /tmp/.X99-lock /tmp/.X11-unix/X99
Xvfb :99 -screen 0 1024x768x16 &
sleep 2

# Write a launcher script to avoid env-var and quoting issues with su -c.
rm -f /tmp/launch-lif.sh
cat > /tmp/launch-lif.sh <<'LAUNCHER'
#!/bin/bash
export HOME=/home/lif
export WINEPREFIX=/home/lif/.wine
export DISPLAY=:99
# Show errors only — switch to +loaddll,err+all for debugging DLL issues
export WINEDEBUG=err+all

# Ensure native VC++ runtime DLLs take priority over Wine builtins
export WINEDLLOVERRIDES="msvcp140=n,b;vcruntime140=n,b;ucrtbase=n,b"

echo "[*] Wine version: $(wine --version)"

# ── First-run: create Wine prefix + install VC++ 2015 runtime ──────────────
# This MUST happen at runtime (not docker build) because wineboot needs
# full kernel capabilities (personality syscall, /proc, etc.) that are
# unavailable or restricted during image build.
WINE_READY_MARKER="$WINEPREFIX/.wine_ready"

if [ ! -f "$WINE_READY_MARKER" ]; then
    echo "[*] First run detected — initializing Wine prefix (this takes a minute)..."
    # Clear contents (can't rm -rf a mounted volume, so remove contents instead)
    rm -rf "$WINEPREFIX"/* "$WINEPREFIX"/.[!.]* 2>/dev/null || true

    echo "[*] Running wineboot --init ..."
    wine wineboot --init
    wineserver -w

    echo "[*] Installing VC++ 2015 runtime via winetricks ..."
    /home/lif/winetricks -q vcrun2015
    wineserver -w

    touch "$WINE_READY_MARKER"
    echo "[*] Wine prefix initialized successfully."
else
    echo "[*] Wine prefix already initialized, skipping wineboot."
fi

cd /home/lif/yoserver

echo "[*] config_local.cs contents:"
cat config_local.cs 2>/dev/null || echo "[!] config_local.cs NOT FOUND"
echo ""
echo "[*] config/world_WORLD_ID_PLACEHOLDER.xml contents:"
cat config/world_WORLD_ID_PLACEHOLDER.xml 2>/dev/null || echo "[!] world config NOT FOUND"
echo ""

echo "[*] Launching ddctd_cm_yo_server.exe -worldid WORLD_ID_PLACEHOLDER ..."
wine ddctd_cm_yo_server.exe -worldid WORLD_ID_PLACEHOLDER
EXIT_CODE=$?

echo "[!] Server exited with code $EXIT_CODE"
echo ""
echo "[*] Checking Logs directory..."
ls -la Logs/ 2>/dev/null || echo "[!] Logs directory empty or missing"

# Show latest log file
LATEST_LOG=$(find Logs/ -name '*.log' -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
if [ -n "${LATEST_LOG:-}" ] && [ -f "$LATEST_LOG" ]; then
    echo "--- $LATEST_LOG ---"
    tail -50 "$LATEST_LOG"
    echo ""
fi

exit $EXIT_CODE
LAUNCHER

# Inject the actual world ID and make executable
sed -i "s/WORLD_ID_PLACEHOLDER/${WORLD_ID}/" /tmp/launch-lif.sh
chmod +x /tmp/launch-lif.sh
chown lif:lif /tmp/launch-lif.sh

exec su lif -s /bin/bash /tmp/launch-lif.sh
