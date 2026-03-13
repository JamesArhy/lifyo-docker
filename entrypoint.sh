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
: "${BACKUP_ENABLED:=true}"
: "${BACKUP_INTERVAL:=3600}"
: "${BACKUP_KEEP:=5}"

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
TEMPLATE_DIR="/opt/lif-templates"

# Ensure server directory structure exists (may be an empty volume mount)
mkdir -p "${SERVER_DIR}/config" "${SERVER_DIR}/Logs"
chown -R lif:lif "${SERVER_DIR}"

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

# ── Download / update game server via SteamCMD ────────────────────────────────
# On first run the server binary won't exist yet — download it.
# On subsequent runs, only update if UPDATE_ON_START=true.
GAME_EXE="${SERVER_DIR}/ddctd_cm_yo_server.exe"

if [ ! -f "${GAME_EXE}" ] || [ "${UPDATE_ON_START}" = "true" ]; then
    if [ ! -f "${GAME_EXE}" ]; then
        echo "[*] First run — downloading game server via SteamCMD (this takes a few minutes) ..."
    else
        echo "[*] Updating game server via SteamCMD ..."
    fi

    for i in 1 2 3 4 5; do
        su - lif -c "${STEAMCMD} \
            +@sSteamCmdForcePlatformType windows \
            +force_install_dir ${SERVER_DIR} \
            +login anonymous \
            +app_update 320850 validate \
            +quit" && break \
        || { echo "[!] SteamCMD attempt $i/5 failed, retrying in 30s..."; sleep 30; }
    done

    if [ ! -f "${GAME_EXE}" ]; then
        echo "[!] FATAL: Game server binary not found after SteamCMD download. Exiting."
        exit 1
    fi

    # Copy default config templates from the game's docs on first download
    if [ ! -f "${SERVER_DIR}/config_local.cs.bak" ]; then
        cp "${SERVER_DIR}/docs/config_local.cs" "${SERVER_DIR}/config_local.cs.bak" 2>/dev/null || true
    fi
    echo "[*] Game server ready."
fi

# ── Generate config_local.cs from environment variables ───────────────────────
echo "[*] Generating config_local.cs ..."
export DB_HOST DB_PORT DB_USER DB_PASSWORD DB_NAME
envsubst '${DB_HOST} ${DB_USER} ${DB_PASSWORD}' < "${TEMPLATE_DIR}/config_local.cs.template" > "${SERVER_DIR}/config_local.cs"
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

envsubst < "${TEMPLATE_DIR}/world_1.xml.template" > "${WORLD_CONFIG}"
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

# ── Helper: import SQL file ──────────────────────────────────────────────────
# The game's SQL files contain CREATE PROCEDURE/FUNCTION with BEGIN...END blocks
# but explicitly NO DELIMITER statements (patch.sql says "do not use DELIMITER").
# The mysql CLI needs DELIMITER to parse multi-statement routines, so we
# preprocess with Python to add them. The preprocessor:
#   - Detects CREATE PROCEDURE/FUNCTION/TRIGGER (any indentation)
#   - Tracks BEGIN/END nesting depth to find the outermost END
#   - Wraps each routine in DELIMITER // ... END // ... DELIMITER ;
#   - Passes through files that already have DELIMITER statements
import_sql() {
    local sql_file="$1"
    echo "[*]   Importing ${sql_file} ..."
    echo "[debug] File size: $(wc -c < "${sql_file}") bytes, $(wc -l < "${sql_file}") lines"
    echo "[debug] CREATE PROCEDURE/FUNCTION/TRIGGER count: $(grep -ciE 'CREATE\s+(PROCEDURE|FUNCTION|TRIGGER)' "${sql_file}" || echo 0)"

    python3 -c "
import re, sys

with open(sys.argv[1], 'r', errors='replace') as f:
    content = f.read()

# If the file already has DELIMITER statements, pass through as-is
if re.search(r'^\s*DELIMITER\s', content, re.MULTILINE | re.IGNORECASE):
    print(content)
    sys.exit(0)

lines = content.split('\n')
output = []
in_routine = False
depth = 0
routine_lines = []

def flush_routine():
    # Join all buffered routine lines into one block and emit with DELIMITER
    global routine_lines
    output.append('DELIMITER //')
    for rl in routine_lines:
        output.append(rl)
    # The last line should be END; — replace the trailing ; with //
    if output and re.match(r'\s*END\s*;\s*$', output[-1], re.IGNORECASE):
        output[-1] = re.sub(r';\s*$', ' //', output[-1])
    output.append('DELIMITER ;')
    routine_lines = []

for line in lines:
    stripped = line.strip()
    upper = stripped.upper()

    if not in_routine:
        # Detect start of a routine (handles any whitespace, optional DEFINER)
        if re.search(r'\bCREATE\s+(PROCEDURE|FUNCTION|TRIGGER)\b', stripped, re.IGNORECASE):
            in_routine = True
            depth = 0
            routine_lines = [line]
        elif re.match(r'DROP\s+(PROCEDURE|FUNCTION|TRIGGER)\s+', stripped, re.IGNORECASE):
            # DROP statements before CREATE — emit directly
            output.append(line)
        else:
            output.append(line)
    else:
        routine_lines.append(line)

        # Count BEGIN (but not BEGIN inside comments or strings — good enough)
        if re.match(r'\s*BEGIN\s*$', stripped, re.IGNORECASE):
            depth += 1

        # Count END variants
        if re.match(r'\s*END\s+(IF|LOOP|WHILE|CASE|REPEAT)\s*;', stripped, re.IGNORECASE):
            pass  # these don't affect routine depth
        elif re.match(r'\s*END\s*;\s*$', stripped, re.IGNORECASE):
            depth -= 1
            if depth <= 0:
                flush_routine()
                in_routine = False
                depth = 0

# If we ended mid-routine, flush what we have
if in_routine and routine_lines:
    flush_routine()

print('\n'.join(output))
" "${sql_file}" | \
    mysql -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" -p"${DB_PASSWORD}" "${DB_NAME}" 2>&1 | \
    while IFS= read -r err_line; do
        case "$err_line" in
            *ERROR*) echo "[!]   SQL: $err_line" ;;
        esac
    done

    echo "[*]   Done importing ${sql_file}"
}

# ── Initialize database schema on first run ─────────────────────────────────
# Use a marker table to track whether the schema has been imported. This avoids
# reimporting on every restart (which causes duplicate data and crash loops).
SCHEMA_IMPORTED=$(mysql -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" -p"${DB_PASSWORD}" \
    -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}' AND table_name='_docker_schema_imported';" 2>/dev/null || echo "0")

TABLE_COUNT=$(mysql -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" -p"${DB_PASSWORD}" \
    -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}';" 2>/dev/null || echo "0")

if [ "${SCHEMA_IMPORTED}" -eq 1 ] 2>/dev/null; then
    echo "[*] Database schema already imported (${TABLE_COUNT} tables), skipping."
elif [ "${TABLE_COUNT}" -eq 0 ] 2>/dev/null; then
    echo "[*] Empty database detected — importing schema ..."
    import_sql "${SERVER_DIR}/sql/new.sql"
    import_sql "${SERVER_DIR}/sql/patch.sql"
    import_sql "${SERVER_DIR}/sql/dump.sql"
    # Mark schema as imported so we don't reimport on restart
    mysql -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" -p"${DB_PASSWORD}" "${DB_NAME}" \
        -e "CREATE TABLE IF NOT EXISTS _docker_schema_imported (imported_at DATETIME DEFAULT CURRENT_TIMESTAMP);" 2>/dev/null
    mysql -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" -p"${DB_PASSWORD}" "${DB_NAME}" \
        -e "INSERT IGNORE INTO _docker_schema_imported VALUES (NOW());" 2>/dev/null
    # Debug: check what was actually created
    POST_TABLES=$(mysql -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" -p"${DB_PASSWORD}" \
        -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}';" 2>/dev/null || echo "0")
    POST_PROCS=$(mysql -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" -p"${DB_PASSWORD}" \
        -N -e "SELECT COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA='${DB_NAME}';" 2>/dev/null || echo "0")
    PATCH_STATUS=$(mysql -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" -p"${DB_PASSWORD}" \
        -N -e "SELECT Value FROM ${DB_NAME}._patch_execute_status LIMIT 1;" 2>/dev/null || echo "TABLE NOT FOUND")
    echo "[debug] Post-import: ${POST_TABLES} tables, ${POST_PROCS} stored procedures"
    echo "[debug] _patch_execute_status value: ${PATCH_STATUS}"
    echo "[*] Database schema imported."
else
    echo "[*] Database has ${TABLE_COUNT} tables but no import marker — assuming pre-existing database."
    # Create the marker for existing databases so we don't hit this branch again
    mysql -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" -p"${DB_PASSWORD}" "${DB_NAME}" \
        -e "CREATE TABLE IF NOT EXISTS _docker_schema_imported (imported_at DATETIME DEFAULT CURRENT_TIMESTAMP);" 2>/dev/null
    mysql -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" -p"${DB_PASSWORD}" "${DB_NAME}" \
        -e "INSERT IGNORE INTO _docker_schema_imported VALUES (NOW());" 2>/dev/null
    echo "[*] Import marker created. Skipping schema import."
fi

# ── Fix volume permissions ────────────────────────────────────────────────────
# Docker named volumes may be created as root; ensure lif user can write.
chown -R lif:lif "${SERVER_DIR}/Logs" "${SERVER_DIR}/config" 2>/dev/null || true
chown -R lif:lif /home/lif/.wine 2>/dev/null || true

# ── Backup loop (runs in background) ─────────────────────────────────────────
BACKUP_DIR="/home/lif/backups"
mkdir -p "${BACKUP_DIR}"
chown lif:lif "${BACKUP_DIR}"

if [ "${BACKUP_ENABLED}" = "true" ]; then
    echo "[*] Backups enabled — every ${BACKUP_INTERVAL}s, keeping last ${BACKUP_KEEP}"
    (
        while true; do
            sleep "${BACKUP_INTERVAL}"
            TIMESTAMP=$(date +%Y%m%d_%H%M%S)
            BACKUP_FILE="${BACKUP_DIR}/lif_backup_${TIMESTAMP}.tar.gz"

            echo "[backup] Starting backup ${TIMESTAMP} ..."

            # Dump database
            mysqldump -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" -p"${DB_PASSWORD}" \
                --routines --triggers "${DB_NAME}" > "${BACKUP_DIR}/db_dump.sql" 2>/dev/null

            # Create compressed archive: DB dump + world configs
            tar czf "${BACKUP_FILE}" \
                -C "${BACKUP_DIR}" db_dump.sql \
                -C "${SERVER_DIR}" config/ 2>/dev/null

            rm -f "${BACKUP_DIR}/db_dump.sql"

            # Prune old backups, keeping only the newest BACKUP_KEEP
            ls -1t "${BACKUP_DIR}"/lif_backup_*.tar.gz 2>/dev/null | tail -n +$((BACKUP_KEEP + 1)) | xargs rm -f 2>/dev/null

            SIZE=$(du -h "${BACKUP_FILE}" 2>/dev/null | cut -f1)
            COUNT=$(ls -1 "${BACKUP_DIR}"/lif_backup_*.tar.gz 2>/dev/null | wc -l)
            echo "[backup] Saved ${BACKUP_FILE} (${SIZE}), ${COUNT} backups retained"
        done
    ) &
    BACKUP_PID=$!
    echo "[*] Backup loop running (PID ${BACKUP_PID})"
else
    echo "[*] Backups disabled (BACKUP_ENABLED=false)"
fi

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

echo "[*] config_local.cs exists: $(test -f config_local.cs && echo 'yes' || echo 'NO')"
echo "[*] config/world_WORLD_ID_PLACEHOLDER.xml exists: $(test -f config/world_WORLD_ID_PLACEHOLDER.xml && echo 'yes' || echo 'NO')"

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

# Keep container alive for 10 minutes after crash so logs can be read in Portainer
# TODO: Remove this sleep after debugging is complete
if [ $EXIT_CODE -ne 0 ]; then
    echo "[debug] Server crashed — keeping container alive for 10 minutes for log inspection."
    echo "[debug] You can exec into this container from Portainer during this window."
    sleep 600
fi
exit $EXIT_CODE
LAUNCHER

# Inject the actual world ID and make executable
sed -i "s/WORLD_ID_PLACEHOLDER/${WORLD_ID}/" /tmp/launch-lif.sh
chmod +x /tmp/launch-lif.sh
chown lif:lif /tmp/launch-lif.sh

exec su lif -s /bin/bash /tmp/launch-lif.sh
