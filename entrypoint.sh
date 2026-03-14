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

# ── Ensure steamclient.so is available for Steam authentication ──────────
# The game server's steam_api64.dll (running under Wine) needs the native
# Linux steamclient.so to initialize the Steamworks API and validate player
# authentication tickets. Without it, players get CR_STEAM_INVALID_TICKET.
STEAM_SDK64="/home/lif/.steam/sdk64"
STEAMCLIENT_SO="${STEAM_SDK64}/steamclient.so"

if [ ! -f "${STEAMCLIENT_SO}" ]; then
    echo "[*] Setting up steamclient.so for Steam authentication ..."

    # Check if SteamCMD already has it from the game download
    if [ -f "/home/lif/steamcmd/linux64/steamclient.so" ]; then
        echo "[*] Found steamclient.so in SteamCMD linux64/, creating symlink ..."
        mkdir -p "${STEAM_SDK64}"
        ln -sf /home/lif/steamcmd/linux64/steamclient.so "${STEAMCLIENT_SO}"
    else
        # Download Steamworks SDK Redistributable (AppID 1007) — tiny download
        echo "[*] Downloading Steamworks SDK Redist (AppID 1007) for steamclient.so ..."
        su - lif -c "${STEAMCMD} \
            +force_install_dir /home/lif/steamworks_sdk \
            +login anonymous \
            +app_update 1007 validate \
            +quit" || true

        mkdir -p "${STEAM_SDK64}"
        if [ -f "/home/lif/steamworks_sdk/linux64/steamclient.so" ]; then
            cp /home/lif/steamworks_sdk/linux64/steamclient.so "${STEAMCLIENT_SO}"
            echo "[*] steamclient.so installed from Steamworks SDK Redist."
        elif [ -f "/home/lif/steamcmd/linux64/steamclient.so" ]; then
            # SteamCMD may have populated its own copy after running
            ln -sf /home/lif/steamcmd/linux64/steamclient.so "${STEAMCLIENT_SO}"
            echo "[*] steamclient.so symlinked from SteamCMD (appeared after SDK download)."
        else
            echo "[!] WARNING: steamclient.so not found after SDK download."
            echo "[!] Players will get CR_STEAM_INVALID_TICKET errors."
            echo "[!] Searching for any steamclient.so on the system ..."
            FOUND_SO=$(find /home/lif -name "steamclient.so" -type f 2>/dev/null | head -1)
            if [ -n "${FOUND_SO}" ]; then
                echo "[*] Found steamclient.so at ${FOUND_SO}, copying ..."
                cp "${FOUND_SO}" "${STEAMCLIENT_SO}"
            fi
        fi
    fi

    # Also set up 32-bit variant (some Steam internals check both)
    mkdir -p /home/lif/.steam/sdk32
    if [ -f "/home/lif/steamcmd/linux32/steamclient.so" ] && [ ! -f "/home/lif/.steam/sdk32/steamclient.so" ]; then
        ln -sf /home/lif/steamcmd/linux32/steamclient.so /home/lif/.steam/sdk32/steamclient.so
    fi

    chown -R lif:lif /home/lif/.steam
else
    echo "[*] steamclient.so already present at ${STEAMCLIENT_SO}"
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

    if not in_routine:
        if re.search(r'\bCREATE\s+(PROCEDURE|FUNCTION|TRIGGER)\b', stripped, re.IGNORECASE):
            in_routine = True
            depth = 0
            routine_lines = [line]
            # BEGIN may be on the same line as CREATE (e.g. after closing paren)
            if re.search(r'\bBEGIN\b', stripped, re.IGNORECASE):
                depth += 1
        elif re.match(r'DROP\s+(PROCEDURE|FUNCTION|TRIGGER)\s+', stripped, re.IGNORECASE):
            output.append(line)
        else:
            output.append(line)
    else:
        routine_lines.append(line)

        # Count all BEGIN keywords on this line (but skip 'BEGIN' after CREATE on first line)
        begin_count = len(re.findall(r'\bBEGIN\b', stripped, re.IGNORECASE))
        if begin_count > 0:
            depth += begin_count

        # Count END variants — skip END IF/LOOP/WHILE/CASE/REPEAT (control flow, not routine end)
        # Also skip END followed by a word that isn't a semicolon (e.g. END label_name)
        end_count = len(re.findall(r'\bEND\s*;', stripped, re.IGNORECASE))
        control_ends = len(re.findall(r'\bEND\s+(?:IF|LOOP|WHILE|CASE|REPEAT)\b', stripped, re.IGNORECASE))
        real_ends = end_count - control_ends

        if real_ends > 0:
            depth -= real_ends
            if depth <= 0:
                flush_routine()
                in_routine = False
                depth = 0

# If we ended mid-routine, flush what we have
if in_routine and routine_lines:
    flush_routine()

print('\n'.join(output))
" "${sql_file}" > /tmp/_preprocessed.sql

    # Normalize any explicit utf8mb4 references to utf8mb3 — the game only needs
    # 3-byte UTF-8 and MariaDB 10.6 rejects mixing utf8mb4 charset with utf8mb3 collations.
    sed -i 's/utf8mb4/utf8mb3/g' /tmp/_preprocessed.sql

    local import_errors
    import_errors=$(mysql --default-character-set=utf8mb3 \
        -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" -p"${DB_PASSWORD}" "${DB_NAME}" \
        < /tmp/_preprocessed.sql 2>&1 | grep -i 'ERROR' || true)

    if [ -n "${import_errors}" ]; then
        echo "[!]   SQL errors during import of ${sql_file}:"
        echo "${import_errors}" | while IFS= read -r err_line; do
            echo "[!]   $err_line"
        done
        IMPORT_FAILED=1
    fi

    rm -f /tmp/_preprocessed.sql
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
    IMPORT_FAILED=0
    import_sql "${SERVER_DIR}/sql/new.sql"
    import_sql "${SERVER_DIR}/sql/patch.sql"
    import_sql "${SERVER_DIR}/sql/dump.sql"

    # Debug: check what was actually created
    POST_TABLES=$(mysql -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" -p"${DB_PASSWORD}" \
        -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}';" 2>/dev/null || echo "0")
    POST_PROCS=$(mysql -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" -p"${DB_PASSWORD}" \
        -N -e "SELECT COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA='${DB_NAME}';" 2>/dev/null || echo "0")
    PATCH_STATUS=$(mysql -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" -p"${DB_PASSWORD}" \
        -N -e "SELECT Value FROM ${DB_NAME}._patch_execute_status LIMIT 1;" 2>/dev/null || echo "TABLE NOT FOUND")
    echo "[debug] Post-import: ${POST_TABLES} tables, ${POST_PROCS} stored procedures"
    echo "[debug] _patch_execute_status value: ${PATCH_STATUS}"

    if [ "${IMPORT_FAILED}" -eq 1 ]; then
        echo "[!] SQL import had errors — NOT creating import marker so it will retry on next restart."
        echo "[!] You may need to drop the database and restart: DROP DATABASE ${DB_NAME}; CREATE DATABASE ${DB_NAME};"
    else
        # Mark schema as imported so we don't reimport on restart
        mysql -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" -p"${DB_PASSWORD}" "${DB_NAME}" \
            -e "CREATE TABLE IF NOT EXISTS _docker_schema_imported (imported_at DATETIME DEFAULT CURRENT_TIMESTAMP);" 2>/dev/null
        mysql -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" -p"${DB_PASSWORD}" "${DB_NAME}" \
            -e "INSERT IGNORE INTO _docker_schema_imported VALUES (NOW());" 2>/dev/null
        echo "[*] Database schema imported successfully."
    fi
else
    # Tables exist but no marker — could be a pre-existing database OR a failed partial import.
    # Check if stored procedures exist (they're created by patch.sql, which was failing before).
    PROC_COUNT=$(mysql -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" -p"${DB_PASSWORD}" \
        -N -e "SELECT COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA='${DB_NAME}';" 2>/dev/null || echo "0")
    PATCH_STATUS=$(mysql -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" -p"${DB_PASSWORD}" \
        -N -e "SELECT Value FROM ${DB_NAME}._patch_execute_status LIMIT 1;" 2>/dev/null || echo "MISSING")

    if [ "${PROC_COUNT}" -gt 0 ] && [ "${PATCH_STATUS}" != "MISSING" ]; then
        echo "[*] Database has ${TABLE_COUNT} tables, ${PROC_COUNT} procedures — looks healthy."
        mysql -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" -p"${DB_PASSWORD}" "${DB_NAME}" \
            -e "CREATE TABLE IF NOT EXISTS _docker_schema_imported (imported_at DATETIME DEFAULT CURRENT_TIMESTAMP);" 2>/dev/null
        mysql -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" -p"${DB_PASSWORD}" "${DB_NAME}" \
            -e "INSERT IGNORE INTO _docker_schema_imported VALUES (NOW());" 2>/dev/null
        echo "[*] Import marker created."
    else
        echo "[!] Database has ${TABLE_COUNT} tables but ${PROC_COUNT} procedures and patch status: ${PATCH_STATUS}"
        echo "[!] This looks like a failed partial import. Dropping and re-importing..."
        mysql -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" -p"${DB_PASSWORD}" \
            -e "DROP DATABASE IF EXISTS ${DB_NAME}; CREATE DATABASE ${DB_NAME};" 2>/dev/null
        IMPORT_FAILED=0
        import_sql "${SERVER_DIR}/sql/new.sql"
        import_sql "${SERVER_DIR}/sql/patch.sql"
        import_sql "${SERVER_DIR}/sql/dump.sql"
        if [ "${IMPORT_FAILED}" -eq 0 ]; then
            mysql -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" -p"${DB_PASSWORD}" "${DB_NAME}" \
                -e "CREATE TABLE IF NOT EXISTS _docker_schema_imported (imported_at DATETIME DEFAULT CURRENT_TIMESTAMP);" 2>/dev/null
            mysql -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" -p"${DB_PASSWORD}" "${DB_NAME}" \
                -e "INSERT IGNORE INTO _docker_schema_imported VALUES (NOW());" 2>/dev/null
            echo "[*] Database re-imported successfully."
        else
            echo "[!] Re-import also had errors. Check logs above."
        fi
    fi
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

# Point Steam runtime to native steamclient.so for authentication
export LD_LIBRARY_PATH="/home/lif/.steam/sdk64:${LD_LIBRARY_PATH:-}"

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

# ── Steam registry setup for Wine ──────────────────────────────────────
# steam_api64.dll reads HKCU\Software\Valve\Steam\ActiveProcess to find
# steamclient64.dll. Without these registry keys, it reports "no bootstrapper
# found" and the Steam Game Server API never initializes — causing
# CR_STEAM_INVALID_TICKET for all players.
STEAM_REG_MARKER="$WINEPREFIX/.steam_registry_configured"
if [ ! -f "$STEAM_REG_MARKER" ]; then
    echo "[*] Configuring Steam registry keys for Wine ..."
    cat > /tmp/steam_registry.reg <<'STEAMREG'
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\Software\Valve\Steam]
"SteamPath"="Z:\\home\\lif\\yoserver"
"SteamExe"=""
"Language"="english"

[HKEY_CURRENT_USER\Software\Valve\Steam\ActiveProcess]
"SteamClientDll"="Z:\\home\\lif\\yoserver\\steamclient.dll"
"SteamClientDll64"="Z:\\home\\lif\\yoserver\\steamclient64.dll"
"SteamPath"="Z:\\home\\lif\\yoserver"
"Universe"="Public"
"pid"=dword:0000fffe
"ActiveUser"=dword:00000000

[HKEY_LOCAL_MACHINE\Software\Wow6432Node\Valve\Steam]
"InstallPath"="Z:\\home\\lif\\yoserver"
STEAMREG

    wine regedit /tmp/steam_registry.reg
    wineserver -w
    rm -f /tmp/steam_registry.reg
    touch "$STEAM_REG_MARKER"
    echo "[*] Steam registry keys configured."
else
    echo "[*] Steam registry keys already configured."
fi

cd /home/lif/yoserver

echo "[*] config_local.cs exists: $(test -f config_local.cs && echo 'yes' || echo 'NO')"
echo "[*] config/world_WORLD_ID_PLACEHOLDER.xml exists: $(test -f config/world_WORLD_ID_PLACEHOLDER.xml && echo 'yes' || echo 'NO')"
echo "[debug] config/ directory listing:"
ls -la config/ 2>/dev/null || echo "[debug] config/ directory does not exist"

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
sed -i "s/WORLD_ID_PLACEHOLDER/${WORLD_ID}/g" /tmp/launch-lif.sh
chmod +x /tmp/launch-lif.sh
chown lif:lif /tmp/launch-lif.sh

exec su lif -s /bin/bash /tmp/launch-lif.sh
